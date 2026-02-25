#!/usr/bin/env bash
set -euo pipefail

# Cross-compile FFmpeg for Linux musl from Ubuntu using musl-tools

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
RID="linux-musl-x64"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

# Use musl cross-compiler (no static-pie for shared libs)
export CC="musl-gcc"
export CFLAGS="-O2 -pipe -fPIC"
export LDFLAGS=""

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

cd "${WORK_DIR}"
rm -rf "${SRC_DIR}" "${PREFIX_DIR}"

echo "Downloading FFmpeg ${FFMPEG_VERSION}..."
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o ffmpeg.tar.xz
mkdir -p "${SRC_DIR}"
tar -xf ffmpeg.tar.xz -C "${SRC_DIR}" --strip-components=1

cd "${SRC_DIR}"

echo "Configuring FFmpeg..."
./configure \
  --prefix="${PREFIX_DIR}" \
  --cc="${CC}" \
  --enable-ffmpeg \
  --enable-ffprobe \
  --disable-ffplay \
  --enable-shared \
  --disable-static \
  --disable-doc \
  --disable-debug \
  --enable-pic \
  --enable-version3 \
  --disable-gpl \
  --disable-nonfree \
  --disable-autodetect \
  --extra-cflags="${CFLAGS}"

echo "Building FFmpeg..."
make -j"$(nproc)"
make install

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cp -a "${PREFIX_DIR}/lib/"*.so* "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffmpeg" "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffprobe" "${OUT_DIR}/"

cat > "${ROOT_DIR}/artifacts/${RID}/build-info.txt" <<EOF
FFmpeg version: ${FFMPEG_VERSION}
RID: ${RID}
Build type: Linux musl (cross-compiled, LGPL shared)
Compiler: ${CC}
Configure flags:
--enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-pic --enable-version3 --disable-gpl --disable-nonfree --disable-autodetect
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
