#!/usr/bin/env bash
set -euo pipefail

# Build FFmpeg for macOS - LGPL shared libraries

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_VERSION="${FFMPEG_VERSION:-$(cat "${ROOT_DIR}/FFMPEG_VERSION" | tr -d '[:space:]')}"
RID="${RID:-osx-x64}"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

# Install build dependencies via Homebrew
brew install nasm yasm pkg-config || true

echo "Installing Vulkan-Headers..."
cd "${WORK_DIR}"
rm -rf Vulkan-Headers
git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git
mkdir -p "${WORK_DIR}/deps/include" "${WORK_DIR}/deps/lib/pkgconfig"
cp -r Vulkan-Headers/include/vulkan "${WORK_DIR}/deps/include/"

VULKAN_HEADER_FILE="${WORK_DIR}/deps/include/vulkan/vulkan_core.h"
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
cat > "${WORK_DIR}/deps/lib/pkgconfig/vulkan.pc" <<PKGCONFIG
prefix=${WORK_DIR}/deps
includedir=\${prefix}/include

Name: Vulkan-Headers
Description: Vulkan header-only SDK for FFmpeg configure checks
Version: ${VULKAN_PC_VERSION}
Cflags: -I\${includedir}
PKGCONFIG

export PKG_CONFIG_PATH="${WORK_DIR}/deps/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

VULKAN_FLAGS=()
HWACCEL_FEATURES="VideoToolbox AudioToolbox"
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
  --enable-pthreads \
  --disable-gpl \
  --disable-nonfree \
  --disable-autodetect \
  --enable-videotoolbox \
  --enable-audiotoolbox \
  "${VULKAN_FLAGS[@]}" \
  --extra-cflags="-I${WORK_DIR}/deps/include"

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
Hardware acceleration: ${HWACCEL_FEATURES}
Vulkan: ${VULKAN_STATUS}
Configure flags:
--enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-pic --enable-pthreads --disable-gpl --disable-nonfree --disable-autodetect --enable-videotoolbox --enable-audiotoolbox ${VULKAN_FLAGS[*]}
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
