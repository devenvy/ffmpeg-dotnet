#!/usr/bin/env bash
set -euo pipefail

# Cross-compile FFmpeg for Windows from Linux using mingw-w64
# Based on BtbN/FFmpeg-Builds approach

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
RID="win-x64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${ROOT_DIR}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

# Cross-compile toolchain
CROSS_PREFIX="x86_64-w64-mingw32"
export CC="${CROSS_PREFIX}-gcc"
export CXX="${CROSS_PREFIX}-g++"
export AR="${CROSS_PREFIX}-ar"
export RANLIB="${CROSS_PREFIX}-ranlib"
export NM="${CROSS_PREFIX}-nm"
export STRIP="${CROSS_PREFIX}-strip"

# Static link gcc/stdc++ runtime to avoid DLL dependencies and clock_gettime64 issues
export CFLAGS="-static-libgcc -static-libstdc++ -O2 -pipe"
export CXXFLAGS="-static-libgcc -static-libstdc++ -O2 -pipe"
export LDFLAGS="-static-libgcc -static-libstdc++"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

DEPS_DIR="${WORK_DIR}/deps"
mkdir -p "${DEPS_DIR}"

# ── Hardware acceleration headers ──────────────────────────────────────────────

# nv-codec-headers (MIT – compile-time headers for NVENC/NVDEC/CUDA)
echo "Building nv-codec-headers..."
cd "${WORK_DIR}"
rm -rf nv-codec-headers
git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git
cd nv-codec-headers
make install PREFIX="${DEPS_DIR}"

# AMF headers (MIT – compile-time headers for AMD hardware encoding)
echo "Installing AMF headers..."
cd "${WORK_DIR}"
rm -rf AMF
git clone --depth 1 https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git
mkdir -p "${DEPS_DIR}/include/AMF"
cp -r AMF/amf/public/include/* "${DEPS_DIR}/include/AMF/"

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
  --cross-prefix="${CROSS_PREFIX}-" \
  --arch=x86_64 \
  --target-os=mingw32 \
  --enable-cross-compile \
  --enable-ffmpeg \
  --enable-ffprobe \
  --disable-ffplay \
  --enable-shared \
  --disable-static \
  --disable-doc \
  --disable-debug \
  --enable-version3 \
  --disable-gpl \
  --disable-nonfree \
  --disable-autodetect \
  --enable-cuda \
  --enable-cuvid \
  --enable-nvenc \
  --enable-nvdec \
  --enable-ffnvcodec \
  --enable-d3d11va \
  --enable-dxva2 \
  --enable-amf \
  --enable-mediafoundation \
  --extra-cflags="${CFLAGS} -I${DEPS_DIR}/include" \
  --extra-cxxflags="${CXXFLAGS}" \
  --extra-ldflags="${LDFLAGS}"

echo "Building FFmpeg..."
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
Toolchain: ${CROSS_PREFIX}
Build type: Cross-compiled from Linux (LGPL shared)
Hardware acceleration: CUDA NVENC NVDEC D3D11VA DXVA2 AMF MediaFoundation
Configure flags:
--cross-prefix=${CROSS_PREFIX}- --arch=x86_64 --target-os=mingw32 --enable-cross-compile --enable-ffmpeg --enable-ffprobe --disable-ffplay --enable-shared --disable-static --disable-doc --disable-debug --enable-version3 --disable-gpl --disable-nonfree --disable-autodetect --enable-cuda --enable-cuvid --enable-nvenc --enable-nvdec --enable-ffnvcodec --enable-d3d11va --enable-dxva2 --enable-amf --enable-mediafoundation
CFLAGS: ${CFLAGS}
LDFLAGS: ${LDFLAGS}
EOF

echo "Done! FFmpeg binaries in ${OUT_DIR}"
