#!/usr/bin/env bash
set -euo pipefail

# Build FFmpeg for Linux musl from Ubuntu using musl-tools

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_VERSION="${FFMPEG_VERSION:-$(cat "${ROOT_DIR}/FFMPEG_VERSION" | tr -d '[:space:]')}"
RID="linux-musl-x64"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

# Use musl cross-compiler (no static-pie for shared libs)
export CC="musl-gcc"
export CFLAGS="-O2 -pipe -fPIC"
export LDFLAGS=""

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

DEPS_DIR="${WORK_DIR}/deps"
mkdir -p "${DEPS_DIR}"

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  git \
  pkg-config \
  xz-utils

# ?? Hardware acceleration headers ??????????????????????????????????????????????

# nv-codec-headers (MIT � compile-time headers for NVENC/NVDEC/CUDA)
echo "Building nv-codec-headers..."
cd "${WORK_DIR}"
rm -rf nv-codec-headers
git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX="${DEPS_DIR}"

# Vulkan-Headers (Apache-2.0 – compile-time headers for Vulkan hwcontext/video)
echo "Installing Vulkan-Headers..."
cd "${WORK_DIR}"
rm -rf Vulkan-Headers
git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git
mkdir -p "${DEPS_DIR}/include" "${DEPS_DIR}/lib/pkgconfig"
cp -r Vulkan-Headers/include/vulkan "${DEPS_DIR}/include/"
cp -r Vulkan-Headers/include/vk_video "${DEPS_DIR}/include/"

VULKAN_HEADER_FILE="${DEPS_DIR}/include/vulkan/vulkan_core.h"
VULKAN_HEADER_REV="$(awk '/^#define VK_HEADER_VERSION / { print $3; exit }' "${VULKAN_HEADER_FILE}")"
if grep -q '^#define VK_API_VERSION_1_4 ' "${VULKAN_HEADER_FILE}"; then
  VULKAN_API_VERSION="1.4"
elif grep -q '^#define VK_API_VERSION_1_3 ' "${VULKAN_HEADER_FILE}"; then
  VULKAN_API_VERSION="1.3"
else
  echo "Vulkan support requires Vulkan 1.3+ headers." >&2
  exit 1
fi
VULKAN_PC_VERSION="${VULKAN_API_VERSION}.${VULKAN_HEADER_REV}"
cat > "${DEPS_DIR}/lib/pkgconfig/vulkan.pc" <<PKGCONFIG
prefix=${DEPS_DIR}
includedir=\${prefix}/include

Name: Vulkan-Headers
Description: Vulkan header-only SDK for FFmpeg configure checks
Version: ${VULKAN_PC_VERSION}
Cflags: -I\${includedir}
PKGCONFIG

export PKG_CONFIG_PATH="${DEPS_DIR}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

VULKAN_FLAGS=()
HWACCEL_FEATURES="CUDA NVENC NVDEC"
if pkg-config --exists vulkan; then
  VULKAN_VERSION="$(pkg-config --modversion vulkan || echo unknown)"
  VULKAN_FLAGS+=(--enable-vulkan)
  VULKAN_STATUS="required and enabled (headers ${VULKAN_VERSION})"
  HWACCEL_FEATURES="${HWACCEL_FEATURES} Vulkan"
  echo "Vulkan support enabled (${VULKAN_VERSION})"
else
  echo "Vulkan support is required, but compatible Vulkan headers were not detected." >&2
  exit 1
fi

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
  --cc="${CC}" \
  --enable-ffmpeg \
  --enable-ffprobe \
  --disable-ffplay \
  --enable-shared \
  --disable-static \
  --disable-doc \
  --disable-debug \
  --enable-pic \
  --enable-pthreads \
  --disable-gpl \
  --disable-nonfree \
  --disable-autodetect \
  --enable-cuda \
  --enable-cuvid \
  --enable-nvenc \
  --enable-nvdec \
  --enable-ffnvcodec \
  "${VULKAN_FLAGS[@]}" \
  --extra-cflags="${CFLAGS} -I${DEPS_DIR}/include"

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
Hardware acceleration: ${HWACCEL_FEATURES}
Vulkan: ${VULKAN_STATUS}
Configure flags:
--enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-pic --enable-pthreads --disable-gpl --disable-nonfree --disable-autodetect --enable-cuda --enable-cuvid --enable-nvenc --enable-nvdec --enable-ffnvcodec ${VULKAN_FLAGS[*]}
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
