#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-consumer.sh <nupkg-dir> <version>
#
# Builds throwaway projects against the freshly packed feed and asserts what a
# real consumer actually gets. Package contents alone do not prove this: NuGet
# RID resolution, SDK asset selection and the trim targets all sit between the
# package and the consumer's bin/, and each has surprised us at least once.
# ==============================================================================

FEED="$(cd "${1:?Usage: verify-consumer.sh <nupkg-dir> <version>}" && pwd)"
VERSION="${2:?Usage: verify-consumer.sh <nupkg-dir> <version>}"
CELL="${CELL:-LGPLv2}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

scaffold() {
  local dir="$1" package="$2"
  rm -rf "${dir}"
  dotnet new console -o "${dir}" >/dev/null
  cat > "${dir}/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="${FEED}" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <clear />
    <packageSource key="local"><package pattern="DevEnvy.*" /></packageSource>
    <packageSource key="nuget.org"><package pattern="*" /></packageSource>
  </packageSourceMapping>
</configuration>
EOF
  sed -i "s|</Project>|  <ItemGroup><PackageReference Include=\"${package}\" Version=\"${VERSION}\" /></ItemGroup>\n</Project>|" \
    "${dir}"/*.csproj
}

restored_rids() {
  grep -oE "\"DevEnvy\.FFmpeg\.Binaries\.${CELL}\.Runtime\.[a-z0-9-]+/" "$1/obj/project.assets.json" 2>/dev/null \
    | tr -d '"/' | sed "s/DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.//" | sort -u | tr '\n' ' ' || true
}

echo "=== .Rid meta restores exactly one platform ==="
scaffold "${WORK}/rid" "DevEnvy.FFmpeg.Binaries.${CELL}.Rid"
dotnet build "${WORK}/rid" -c Release -r linux-x64 --self-contained false >/dev/null 2>&1 \
  || fail "build with -r linux-x64 failed"

got="$(restored_rids "${WORK}/rid")"
[[ "${got}" == "linux-x64 " ]] || fail ".Rid with -r linux-x64 restored '${got}', expected only linux-x64"
find "${WORK}/rid/bin" -name 'libavcodec.so.*' | grep -q . \
  || fail "libavcodec did not reach bin/ for linux-x64"
echo "  linux-x64 only, libavcodec present"

echo "=== .Rid meta warns instead of silently shipping nothing ==="
scaffold "${WORK}/norid" "DevEnvy.FFmpeg.Binaries.${CELL}.Rid"
dotnet build "${WORK}/norid" -c Release 2>&1 | grep -q DEVFFM001 \
  || fail "a RID-less build of .Rid did not emit the DEVFFM001 warning"
echo "  DEVFFM001 emitted"

# Only meaningful when every runtime package for the cell is in the feed, which
# is true on a release run and not on a CI subset run.
_runtime_pkgs=("${FEED}"/*."${CELL}".Runtime.*.nupkg)
if [[ -e "${_runtime_pkgs[0]}" && "${#_runtime_pkgs[@]}" -ge 11 ]]; then
  echo "=== all-platform meta trims to FFmpegRuntimeIdentifiers ==="
  scaffold "${WORK}/trim" "DevEnvy.FFmpeg.Binaries.${CELL}"
  sed -i "s|<TargetFramework>|<FFmpegRuntimeIdentifiers>linux-x64</FFmpegRuntimeIdentifiers><TargetFramework>|" \
    "${WORK}/trim"/*.csproj
  dotnet publish "${WORK}/trim" -c Release >/dev/null 2>&1 || fail "trimmed publish failed"

  kept="$(find "${WORK}/trim/bin" -path '*publish*' -name 'runtimes' -type d -exec ls {} \; | sort -u | tr '\n' ' ')"
  [[ "${kept}" == "linux-x64 " ]] || fail "trim kept '${kept}', expected only linux-x64"
  echo "  publish output trimmed to linux-x64"
else
  echo "=== all-platform meta trim: skipped (feed has a RID subset) ==="
fi

echo ""
echo "Consumer verification passed."
