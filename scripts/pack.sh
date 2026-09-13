#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# pack.sh — download upstream FFmpeg release assets and pack NuGet packages
#
# Usage:
#   ./scripts/pack.sh <upstream-tag> <nuget-version> [--output <dir>] [--phase all|base|meta]
#
# Example:
#   ./scripts/pack.sh 9.0.1.5 9.0.1.500 --output ./nupkgs
#
# This repository does not build FFmpeg. It repackages the prebuilt assets from
# devenvy/ffmpeg releases. See docs/superpowers/specs/ for the design.
#
# Overridable for local runs, so one package can be packed instead of all 57:
#   RIDS="linux-musl-x64" CELLS="gplv2" ./scripts/pack.sh 9.0.1.5 0.0.0-local
#
# Requires: bash 4+, curl, tar, jq, sha256sum, dotnet
# ==============================================================================

UPSTREAM_TAG="${1:?Usage: pack.sh <upstream-tag> <nuget-version> [--output <dir>]}"
NUGET_VERSION="${2:?Usage: pack.sh <upstream-tag> <nuget-version> [--output <dir>]}"
shift 2

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/nupkgs"
PHASE="all"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_DIR="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2 ;;
    --phase)  PHASE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "${PHASE}" in
  all|base|meta) ;;
  *) echo "Unknown phase: ${PHASE} (expected all, base or meta)" >&2; exit 1 ;;
esac

UPSTREAM_REPO="devenvy/ffmpeg"
FFMPEG_VERSION="${UPSTREAM_TAG%.*}"          # 9.0.1.5 -> 9.0.1
DOWNLOAD_DIR="${REPO_ROOT}/.downloads/${UPSTREAM_TAG}"
STAGING_DIR="${REPO_ROOT}/staging"
NUSPEC_DIR="${REPO_ROOT}/.nuspec-gen"
STUB_CSPROJ="${REPO_ROOT}/src/Packaging/Packaging.csproj"

# Upstream artifact name -> .NET RID. Upstream calls 32-bit ARM "armhf"; .NET calls it linux-arm.
declare -A RID_FOR_ARTIFACT=(
  [win-x64]=win-x64
  [win-arm64]=win-arm64
  [linux-x64]=linux-x64
  [linux-arm64]=linux-arm64
  [linux-armhf]=linux-arm
  [linux-musl-x64]=linux-musl-x64
  [linux-musl-arm64]=linux-musl-arm64
  [osx-x64]=osx-x64
  [osx-arm64]=osx-arm64
  [android-arm64]=android-arm64
  [android-x64]=android-x64
)

# Package cell -> SPDX license expression. Upstream's "v2" cells are 2.1/2.0.
declare -A CELL_LICENSE=(
  [LGPLv2]="LGPL-2.1-or-later"
  [LGPLv3]="LGPL-3.0-or-later"
  [GPLv2]="GPL-2.0-or-later"
  [GPLv3]="GPL-3.0-or-later"
)

# Upstream license cell -> NuGet package-id segment.
declare -A PACKAGE_CELL=(
  [lgplv2]=LGPLv2
  [lgplv3]=LGPLv3
  [gplv2]=GPLv2
  [gplv3]=GPLv3
)

# RIDS="" is meaningful: pack iOS on its own, without dragging in a RID-native
# platform just to satisfy the loop.
if [[ -n "${RIDS+set}" && -z "${RIDS// /}" ]]; then
  ARTIFACTS=()
else
  read -ra ARTIFACTS <<< "${RIDS:-win-x64 win-arm64 linux-x64 linux-arm64 linux-armhf linux-musl-x64 linux-musl-arm64 osx-x64 osx-arm64 android-arm64 android-x64}"
fi
read -ra CELL_LIST <<< "${CELLS:-lgplv2 lgplv3 gplv2 gplv3}"
PACK_IOS="${PACK_IOS:-1}"

mkdir -p "${DOWNLOAD_DIR}" "${OUTPUT_DIR}"

echo "Upstream tag:   ${UPSTREAM_TAG}"
echo "FFmpeg version: ${FFMPEG_VERSION}"
echo "NuGet version:  ${NUGET_VERSION}"
echo "Phase:          ${PHASE}"
echo ""

# MSBuild needs a normalized, platform-native absolute path for the staging
# globs. Two distinct reasons: %(RecursiveDir) miscomputes when the glob's fixed
# portion contains ".." segments, silently packing the staging tree into the
# target path; and Git Bash rewrites a bare /d/... into D:\d\... on the way to
# dotnet. cygpath exists only on Windows; elsewhere the path passes through.
to_native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

AUTH=()
[[ -n "${GH_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")

###############################################################################
# download_and_verify — fetch one asset and check it against the release's
# aggregate SHA256SUMS. Upstream publishes that manifest per release, so every
# byte we pack is verified before it is extracted.
###############################################################################
BASE_URL="https://github.com/${UPSTREAM_REPO}/releases/download/${UPSTREAM_TAG}"

fetch_checksums() {
  local dest="${DOWNLOAD_DIR}/SHA256SUMS"
  [[ -f "${dest}" ]] && return 0
  echo "==> Fetching SHA256SUMS for ${UPSTREAM_TAG}"
  curl -fsSL "${AUTH[@]}" "${BASE_URL}/SHA256SUMS" -o "${dest}"
}

download_and_verify() {
  local name="$1" dest="${DOWNLOAD_DIR}/$1"

  if [[ ! -f "${dest}" ]]; then
    echo "  downloading ${name}"
    curl -fSL --retry 3 "${AUTH[@]}" "${BASE_URL}/${name}" -o "${dest}"
  fi

  local expected
  expected="$(awk -v n="${name}" '$2 == n { print $1 }' "${DOWNLOAD_DIR}/SHA256SUMS")"
  if [[ -z "${expected}" ]]; then
    echo "ERROR: ${name} is not listed in SHA256SUMS" >&2
    return 1
  fi

  local actual
  actual="$(sha256sum "${dest}" | cut -d' ' -f1)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERROR: checksum mismatch for ${name}" >&2
    echo "  expected ${expected}" >&2
    echo "  actual   ${actual}" >&2
    rm -f "${dest}"
    return 1
  fi
}

###############################################################################
# normalize_desktop — keep exactly one real file per shared library.
#
# A .nupkg is a zip written by NuGet, and NuGet has no symlink representation:
# a link left in staging is packed as a full byte copy of its target. Upstream
# ships three names per library and only one of them is ever loaded:
#
#   libavcodec.so             symlink, link-time only
#   libavcodec.so.63          symlink  <- SONAME, the loaded name
#   libavcodec.so.63.1.101    real file
#
# "The loaded name" is not a guess: the ffmpeg binary's DT_NEEDED entries name
# libavcodec.so.63, and FFmpeg.AutoGen's dynamic loader builds lib{0}.so.{1} on
# Linux and lib{0}.{1}.dylib on macOS.
#
# The tradeoff, verified rather than assumed: .NET's default P/Invoke probing
# tries avcodec, libavcodec, avcodec.so, libavcodec.so and never appends a
# version suffix, so [DllImport("avcodec")] fails without the unversioned name.
# Nothing we ship uses that path. Do not "fix" it by restoring the unversioned
# names; that costs a full extra copy of every library.
###############################################################################
normalize_desktop() {
  local dir="$1" f target base keep

  # ${dir:?} so an empty argument can never turn this into rm -rf /
  rm -rf "${dir:?}/include" "${dir:?}/lib"

  # Resolve the SONAME to a real file; drop the link-time bare names. A dangling
  # link is left alone so packing fails loudly rather than shipping a package
  # with a library missing.
  for f in "${dir}"/*; do
    [[ -L "${f}" ]] || continue
    if [[ "${f}" =~ \.so\.[0-9]+$ || "${f}" =~ \.[0-9]+\.dylib$ ]]; then
      target="$(readlink -f "${f}")"
      if [[ -e "${target}" ]]; then
        rm -f "${f}"
        mv "${target}" "${f}"
      fi
    else
      rm -f "${f}"
    fi
  done

  # Whatever fully versioned copies remain now duplicate the SONAME. Only
  # removed when that name is present, so an unexpected layout is kept rather
  # than silently emptied.
  for f in "${dir}"/*; do
    [[ -f "${f}" && ! -L "${f}" ]] || continue
    base="$(basename "${f}")"
    # shellcheck disable=SC2001  # capture-group rewrites; ${var//x/y} cannot express these
    case "${base}" in
      *.so.*.*.*)    keep="$(sed 's/\(\.so\.[0-9]*\)\..*/\1/' <<< "${base}")" ;;
      *.*.*.*.dylib) keep="$(sed 's/\.\([0-9]*\)\.[0-9]*\.[0-9]*\.dylib$/.\1.dylib/' <<< "${base}")" ;;
      *) continue ;;
    esac
    [[ "${keep}" != "${base}" && -f "${dir}/${keep}" ]] && rm -f "${f}"
  done

  return 0
}

###############################################################################
# normalize_android — flatten the NDK ABI directory and drop the headers.
#
# Upstream bundles include/ in mobile tarballs deliberately ("those builds exist
# only to be linked"), which is right for Gradle and wrong here: a RID-specific
# .NET publish flattens everything under native/ into the publish root, so the
# per-library version.h files collide and the build fails with NETSDK1152.
#
# libc++_shared.so is kept. libavcodec and libavfilter are built from C++ and
# linked against c++_shared; the app crashes on load without it.
###############################################################################
normalize_android() {
  local dir="$1" abi

  rm -rf "${dir:?}/include"

  for abi in arm64-v8a x86_64 armeabi-v7a x86; do
    if [[ -d "${dir}/lib/${abi}" ]]; then
      mv "${dir}/lib/${abi}"/* "${dir}/"
      break
    fi
  done
  rm -rf "${dir:?}/lib"

  return 0
}

###############################################################################
# Phase: base — the per-platform payload packages and the helper
###############################################################################
if [[ "${PHASE}" == "all" || "${PHASE}" == "base" ]]; then
  fetch_checksums

  echo "==> Staging native payloads"
  rm -rf "${STAGING_DIR}"

  for artifact in "${ARTIFACTS[@]}"; do
    rid="${RID_FOR_ARTIFACT[${artifact}]:?unknown upstream artifact ${artifact}}"
    for cell in "${CELL_LIST[@]}"; do
      tarball="ffmpeg-${FFMPEG_VERSION}-${artifact}-${cell}.tar.gz"
      download_and_verify "${tarball}"

      stage="${STAGING_DIR}/${PACKAGE_CELL[${cell}]}/${rid}"
      work="${stage}/native"
      mkdir -p "${work}"
      tar -xzf "${DOWNLOAD_DIR}/${tarball}" -C "${work}"

      case "${artifact}" in
        android-*) normalize_android "${work}" ;;
        win-*)     ;;   # flat DLLs, nothing to do
        *)         normalize_desktop "${work}" ;;
      esac

      # legal/ is packed at the package root, never under runtimes/{rid}/native/.
      # Anything beneath native/ is a native asset to NuGet, so license text left
      # there is copied into every consumer's build and publish output, and the
      # per-dependency notices collide across packages on a flattened publish.
      if [[ -d "${work}/legal" ]]; then
        mkdir -p "${stage}/legal"
        mv "${work}/legal"/* "${stage}/legal/"
        rmdir "${work}/legal"
      fi

      echo "  staged ${PACKAGE_CELL[${cell}]}/${rid}"
    done
  done

  if [[ "${PACK_IOS}" == "1" ]]; then
    for cell in "${CELL_LIST[@]}"; do
      tarball="ffmpeg-${FFMPEG_VERSION}-ios-${cell}.tar.gz"
      download_and_verify "${tarball}"
      stage="${STAGING_DIR}/${PACKAGE_CELL[${cell}]}/ios"
      mkdir -p "${stage}"
      tar -xzf "${DOWNLOAD_DIR}/${tarball}" -C "${stage}"
      echo "  staged ${PACKAGE_CELL[${cell}]}/ios (xcframeworks, no normalization)"
    done
  fi

  echo ""
  echo "==> Packing helper"
  dotnet pack "${REPO_ROOT}/src/DevEnvy.FFmpeg.Binaries/DevEnvy.FFmpeg.Binaries.csproj" \
    -c Release -p:Version="${NUGET_VERSION}" -o "${OUTPUT_DIR}" --nologo -v quiet

  echo "==> Packing runtime packages"
  for artifact in "${ARTIFACTS[@]}"; do
    rid="${RID_FOR_ARTIFACT[${artifact}]}"
    for cell in "${CELL_LIST[@]}"; do
      pc="${PACKAGE_CELL[${cell}]}"
      bash "${REPO_ROOT}/scripts/gen-nuspec.sh" runtime "${pc}" "${rid}" "${NUGET_VERSION}" "${FFMPEG_VERSION}"
      dotnet pack "${REPO_ROOT}/src/Packaging/Runtime.csproj" \
        -p:Cell="${pc}" -p:Rid="${rid}" -p:CellLicense="${CELL_LICENSE[${pc}]}" \
        -p:StagingDir="$(to_native_path "${STAGING_DIR}/${pc}/${rid}")/" \
        -p:TargetsFile="$(to_native_path "${NUSPEC_DIR}/DevEnvy.FFmpeg.Binaries.${pc}.Runtime.${rid}.targets")" \
        -p:FFmpegVersion="${FFMPEG_VERSION}" -p:Version="${NUGET_VERSION}" \
        -p:RestoreAdditionalProjectSources="$(to_native_path "${OUTPUT_DIR}")" \
        -o "${OUTPUT_DIR}" --nologo -v quiet
      echo "  packed DevEnvy.FFmpeg.Binaries.${pc}.Runtime.${rid}"
    done
  done

  if [[ "${PACK_IOS}" == "1" ]]; then
    echo "==> Packing iOS packages"
    for cell in "${CELL_LIST[@]}"; do
      pc="${PACKAGE_CELL[${cell}]}"
      bash "${REPO_ROOT}/scripts/gen-nuspec.sh" ios "${pc}" "" "${NUGET_VERSION}" "${FFMPEG_VERSION}"
      dotnet pack "${REPO_ROOT}/src/Packaging/Apple.csproj" \
        -p:Cell="${pc}" -p:CellLicense="${CELL_LICENSE[${pc}]}" \
        -p:StagingDir="$(to_native_path "${STAGING_DIR}/${pc}/ios")/" \
        -p:TargetsFile="$(to_native_path "${NUSPEC_DIR}/DevEnvy.FFmpeg.Binaries.${pc}.Runtime.ios.targets")" \
        -p:FFmpegVersion="${FFMPEG_VERSION}" -p:Version="${NUGET_VERSION}" \
        -p:RestoreAdditionalProjectSources="$(to_native_path "${OUTPUT_DIR}")" \
        -o "${OUTPUT_DIR}" --nologo -v quiet
      echo "  packed DevEnvy.FFmpeg.Binaries.${pc}.Runtime.ios"
    done
  fi
fi

###############################################################################
# Phase: meta — the two metas per cell
#
# Packed separately because they only carry dependencies: on a release run the
# base packages must be indexed by the feed before these can restore.
###############################################################################
if [[ "${PHASE}" == "all" || "${PHASE}" == "meta" ]]; then
  echo ""
  echo "==> Packing meta packages"
  for cell in "${CELL_LIST[@]}"; do
    pc="${PACKAGE_CELL[${cell}]}"
    bash "${REPO_ROOT}/scripts/gen-nuspec.sh" all "${pc}" "" "${NUGET_VERSION}" "${FFMPEG_VERSION}"
    dotnet pack "${STUB_CSPROJ}" \
      -p:NuspecBasePath=../.. -p:NuspecFile="${NUSPEC_DIR}/DevEnvy.FFmpeg.Binaries.${pc}.Runtime.All.nuspec" \
      -o "${OUTPUT_DIR}" --nologo -v quiet
    echo "  packed DevEnvy.FFmpeg.Binaries.${pc}.Runtime.All"
  done
fi

echo ""
echo "Done. Packages in ${OUTPUT_DIR}"
_packed=("${OUTPUT_DIR}"/*.nupkg)
printf '  %s package(s)\n' "${#_packed[@]}"
