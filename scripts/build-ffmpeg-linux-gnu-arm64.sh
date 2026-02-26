#!/usr/bin/env bash
set -euo pipefail

# Cross-compile FFmpeg for Linux ARM64 (glibc) - LGPL shared libraries
# Targets: NVIDIA Jetson, Rockchip SoCs (RK3588 etc.), Raspberry Pi, generic ARM64 servers

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
RID="linux-arm64"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

CROSS_PREFIX="aarch64-linux-gnu"
export CC="${CROSS_PREFIX}-gcc"
export CXX="${CROSS_PREFIX}-g++"
export AR="${CROSS_PREFIX}-ar"
export RANLIB="${CROSS_PREFIX}-ranlib"
export NM="${CROSS_PREFIX}-nm"
export STRIP="${CROSS_PREFIX}-strip"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

# ── System packages (multiarch for ARM64 dev libraries) ───────────────────────

sudo dpkg --add-architecture arm64

CODENAME="$(lsb_release -cs)"
sudo tee /etc/apt/sources.list.d/arm64-ports.list > /dev/null <<SOURCES
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ ${CODENAME} main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ ${CODENAME}-updates main restricted universe multiverse
SOURCES

# Pin existing sources to amd64 to prevent multiarch conflicts
if [ -f /etc/apt/sources.list ]; then
  sudo sed -i '/^deb \[/!s/^deb /deb [arch=amd64] /' /etc/apt/sources.list
fi

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  cmake \
  curl \
  g++-aarch64-linux-gnu \
  gcc-aarch64-linux-gnu \
  git \
  libdrm-dev:arm64 \
  libva-dev:arm64 \
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
echo "Cross-compiling Rockchip MPP (static)..."
cd "${WORK_DIR}"
rm -rf mpp
git clone --depth 1 https://github.com/rockchip-linux/mpp.git
cd mpp
cmake -B build \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER="${CC}" \
  -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_INSTALL_PREFIX="${DEPS_DIR}" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DCMAKE_CXX_FLAGS="-fPIC" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TEST=OFF
cmake --build build -j"$(nproc)"
cmake --install build

# pkg-config: local deps first, then ARM64 system libraries
export PKG_CONFIG_PATH="${DEPS_DIR}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${DEPS_DIR}/lib/pkgconfig:/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig"

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
  --cross-prefix="${CROSS_PREFIX}-" \
  --arch=aarch64 \
  --target-os=linux \
  --enable-cross-compile \
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
Toolchain: ${CROSS_PREFIX}
Build type: Cross-compiled from x64 Linux (LGPL shared)
Hardware acceleration: CUDA NVENC NVDEC VAAPI libdrm RKMPP(static) V4L2-M2M
Configure flags:
--cross-prefix=${CROSS_PREFIX}- --arch=aarch64 --target-os=linux --enable-cross-compile --enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-pic --disable-gpl --disable-nonfree --disable-autodetect --enable-cuda --enable-cuvid --enable-nvenc --enable-nvdec --enable-ffnvcodec --enable-vaapi --enable-libdrm --enable-rkmpp --enable-v4l2-m2m
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
