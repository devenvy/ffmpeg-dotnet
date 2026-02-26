#!/usr/bin/env bash
set -euo pipefail

# Build FFmpeg for Linux ARM64 (glibc) - LGPL shared libraries
# Native build on ARM64 runner
# Targets: NVIDIA Jetson, Rockchip SoCs (RK3588 etc.), Raspberry Pi, generic ARM64 servers

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
RID="linux-arm64"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

# ── System packages ───────────────────────────────────────────────────────────

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  autoconf \
  automake \
  build-essential \
  cmake \
  curl \
  git \
  libdrm-dev \
  libtool \
  libva-dev \
  nasm \
  pkg-config \
  xz-utils

DEPS_DIR="${WORK_DIR}/deps"
mkdir -p "${DEPS_DIR}"

# ── Hardware acceleration dependencies ─────────────────────────────────────────

# nv-codec-headers (MIT – compile-time headers for NVENC/NVDEC/CUDA on Jetson)
echo "Building nv-codec-headers..."
cd "${WORK_DIR}"
rm -rf nv-codec-headers
git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX="${DEPS_DIR}"

# Rockchip MPP (Apache 2.0 – hardware codec for Rockchip SoCs)
# Built as a static library with -fPIC so it gets baked into FFmpeg shared libs.
# This avoids a hard runtime dependency on librockchip_mpp.so for non-Rockchip
# ARM64 systems while still registering the rkmpp encoders/decoders.
echo "Building Rockchip MPP (static)..."
cd "${WORK_DIR}"
rm -rf mpp
git clone --depth 1 https://github.com/rockchip-linux/mpp.git
cd mpp
cmake -B build \
  -DCMAKE_INSTALL_PREFIX="${DEPS_DIR}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DCMAKE_CXX_FLAGS="-fPIC" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TEST=OFF
cmake --build build -j"$(nproc)"
cmake --install build

export PKG_CONFIG_PATH="${DEPS_DIR}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# ── FFmpeg ─────────────────────────────────────────────────────────────────────

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
  --enable-libdrm \
  --enable-rkmpp \
  --enable-v4l2-m2m \
  --extra-cflags="-I${DEPS_DIR}/include" \
  --extra-ldflags="-L${DEPS_DIR}/lib"

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
Build type: Native Linux ARM64 glibc (LGPL shared)
Hardware acceleration: CUDA NVENC NVDEC VAAPI libdrm RKMPP(static) V4L2-M2M
Configure flags:
--enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-pic --disable-gpl --disable-nonfree --disable-autodetect --enable-cuda --enable-cuvid --enable-nvenc --enable-nvdec --enable-ffnvcodec --enable-vaapi --enable-libdrm --enable-rkmpp --enable-v4l2-m2m
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
