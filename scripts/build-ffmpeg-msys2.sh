#!/usr/bin/env bash
set -euo pipefail

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.3}"
RID="win-x64"
RAW_ROOT_DIR="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ "${RAW_ROOT_DIR}" =~ ^[A-Za-z]:[\\/] ]]; then
  ROOT_DIR="$(cygpath -u "${RAW_ROOT_DIR}")"
else
  ROOT_DIR="${RAW_ROOT_DIR}"
fi
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
  --disable-nonfree

make -j"$(nproc)"
make install

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cp -a "${PREFIX_DIR}/bin/"*.dll "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffmpeg.exe" "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffprobe.exe" "${OUT_DIR}/"

cat > "${ROOT_DIR}/artifacts/${RID}/build-info.txt" <<EOF
FFmpeg version: ${FFMPEG_VERSION}
RID: ${RID}
Configure flags:
--target-os=mingw32 --arch=x86_64 --enable-ffmpeg --enable-ffprobe --disable-ffplay --disable-doc --disable-debug --enable-shared --disable-static --disable-gpl --disable-nonfree
EOF
