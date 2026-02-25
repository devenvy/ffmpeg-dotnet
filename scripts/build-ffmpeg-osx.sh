#!/usr/bin/env bash
set -euo pipefail

# Build FFmpeg for macOS - LGPL shared libraries

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
RID="${RID:-osx-x64}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

# Install build dependencies via Homebrew
brew install nasm yasm pkg-config || true

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
  --disable-autodetect

echo "Building FFmpeg..."
make -j"$(sysctl -n hw.ncpu)"
make install

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cp -a "${PREFIX_DIR}/lib/"*.dylib "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffmpeg" "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffprobe" "${OUT_DIR}/"

cat > "${ROOT_DIR}/artifacts/${RID}/build-info.txt" <<EOF
FFmpeg version: ${FFMPEG_VERSION}
RID: ${RID}
Build type: Native macOS (LGPL shared)
Configure flags:
--enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-pic --enable-version3 --disable-gpl --disable-nonfree --disable-autodetect
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
