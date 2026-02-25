#!/usr/bin/env bash
set -euo pipefail

# FFmpeg version (override by setting FFMPEG_VERSION)
FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"

# Target RID
RID="win-x64"

# Resolve repo root (works in GitHub Actions + local)
RAW_ROOT_DIR="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ "${RAW_ROOT_DIR}" =~ ^[A-Za-z]:[\\/] ]]; then
  ROOT_DIR="$(cygpath -u "${RAW_ROOT_DIR}")"
else
  ROOT_DIR="${RAW_ROOT_DIR}"
fi

# IMPORTANT: Build under MSYS2 MINGW64 to avoid UCRT entry-point issues (e.g. clock_gettime64)
if [[ "${MSYSTEM:-}" != "MINGW64" ]]; then
  echo "ERROR: This script must run under MSYSTEM=MINGW64 (got: ${MSYSTEM:-unset})" >&2
  echo "Hint: In GitHub Actions, set msys2/setup-msys2 msystem: MINGW64" >&2
  exit 1
fi

# Force the MINGW64 toolchain
export PATH="/mingw64/bin:$PATH"

WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

cd "${WORK_DIR}"
rm -rf "${SRC_DIR}" "${PREFIX_DIR}"
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o ffmpeg.tar.xz
mkdir -p "${SRC_DIR}"
tar -xf ffmpeg.tar.xz -C "${SRC_DIR}" --strip-components=1

cd "${SRC_DIR}"

# LGPL-safe defaults:
# - --disable-gpl and --disable-nonfree keep the build GPL/nonfree free
# - --disable-autodetect prevents pulling in optional external libs accidentally
./configure \
  --prefix="${PREFIX_DIR}" \
  --target-os=mingw32 \
  --arch=x86_64 \
  --enable-ffmpeg \
  --enable-ffprobe \
  --disable-ffplay \
  --disable-doc \
  --disable-debug \
  --enable-shared \
  --disable-static \
  --disable-gpl \
  --disable-nonfree \
  --disable-autodetect \
  --extra-ldflags="-static-libgcc"

make -j"$(nproc)"
make install

# Ensure the resulting artifacts run on a normal Windows machine (no MSYS2 installed)
# by bundling MinGW runtime DLLs next to ffmpeg.exe.
TOOLCHAIN_BIN="$(dirname "$(command -v gcc)")"
for dll in libwinpthread-1.dll libgcc_s_seh-1.dll libstdc++-6.dll; do
  if [[ -f "${TOOLCHAIN_BIN}/${dll}" ]]; then
    cp -a "${TOOLCHAIN_BIN}/${dll}" "${PREFIX_DIR}/bin/" || true
  fi
done

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cp -a "${PREFIX_DIR}/bin/"*.dll "${OUT_DIR}/" || true
cp -a "${PREFIX_DIR}/bin/ffmpeg.exe" "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffprobe.exe" "${OUT_DIR}/"

cat > "${ROOT_DIR}/artifacts/${RID}/build-info.txt" <<EOF
FFmpeg version: ${FFMPEG_VERSION}
RID: ${RID}
MSYSTEM: ${MSYSTEM:-}
Configure flags:
--target-os=mingw32 --arch=x86_64 --enable-ffmpeg --enable-ffprobe --disable-ffplay --disable-doc --disable-debug --enable-shared --disable-static --disable-gpl --disable-nonfree --disable-autodetect --extra-ldflags=-static-libgcc
EOF