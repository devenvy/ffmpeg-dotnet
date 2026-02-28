#!/usr/bin/env bash
set -euo pipefail

# Build FFmpeg for Linux (glibc) - LGPL shared libraries

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.3}"
RID="linux-x64"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  autoconf \
  automake \
  build-essential \
  curl \
  git \
  libdrm-dev \
  libtool \
  libva-dev \
  libvdpau-dev \
  libvpl-dev \
  nasm \
  pkg-config \
  xz-utils \
  yasm

DEPS_DIR="${WORK_DIR}/deps"
mkdir -p "${DEPS_DIR}"

# ?? Hardware acceleration headers ??????????????????????????????????????????????

# nv-codec-headers (MIT – compile-time headers for NVENC/NVDEC/CUDA)
echo "Building nv-codec-headers..."
cd "${WORK_DIR}"
rm -rf nv-codec-headers
git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX="${DEPS_DIR}"

export PKG_CONFIG_PATH="${DEPS_DIR}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# ?? FFmpeg ?????????????????????????????????????????????????????????????????????

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
  --disable-gpl \
  --disable-nonfree \
  --disable-autodetect \
  --enable-cuda \
  --enable-cuvid \
  --enable-nvenc \
  --enable-nvdec \
  --enable-ffnvcodec \
  --enable-vaapi \
  --enable-vdpau \
  --enable-libdrm \
  --enable-libvpl \
  --enable-v4l2-m2m \
  --extra-cflags="-I${DEPS_DIR}/include"

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
Build type: Native Linux glibc (LGPL shared)
Hardware acceleration: CUDA NVENC NVDEC VAAPI VDPAU libdrm QSV V4L2-M2M
Configure flags:
--enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-pic --disable-gpl --disable-nonfree --disable-autodetect --enable-cuda --enable-cuvid --enable-nvenc --enable-nvdec --enable-ffnvcodec --enable-vaapi --enable-vdpau --enable-libdrm --enable-libvpl --enable-v4l2-m2m
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
