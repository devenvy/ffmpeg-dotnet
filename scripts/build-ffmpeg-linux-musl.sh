#!/bin/sh
set -eu

FFMPEG_VERSION="${FFMPEG_VERSION:-7.1.1}"
RID="linux-musl-x64"
WORKSPACE="${WORKSPACE:-/work}"
WORK_DIR="${WORKSPACE}/.build/${RID}"
SRC_DIR="${WORK_DIR}/src"
PREFIX_DIR="${WORK_DIR}/install"
OUT_DIR="${WORKSPACE}/artifacts/${RID}/native"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

apk add --no-cache \
  bash \
  build-base \
  curl \
  nasm \
  tar \
  xz \
  yasm

cd "${WORK_DIR}"
rm -rf "${SRC_DIR}" "${PREFIX_DIR}"
curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o ffmpeg.tar.xz
mkdir -p "${SRC_DIR}"
tar -xf ffmpeg.tar.xz -C "${SRC_DIR}" --strip-components=1

cd "${SRC_DIR}"
./configure \
  --prefix="${PREFIX_DIR}" \
  --enable-ffmpeg \
  --enable-ffprobe \
  --disable-ffplay \
  --disable-doc \
  --disable-debug \
  --enable-pic \
  --enable-shared \
  --disable-static \
  --disable-gpl \
  --disable-nonfree

make -j"$(getconf _NPROCESSORS_ONLN)"
make install

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cp -a "${PREFIX_DIR}/lib/libavcodec.so"* "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/lib/libavformat.so"* "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/lib/libavutil.so"* "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/lib/libswresample.so"* "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/lib/libswscale.so"* "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffmpeg" "${OUT_DIR}/"
cp -a "${PREFIX_DIR}/bin/ffprobe" "${OUT_DIR}/"

cat > "${WORKSPACE}/artifacts/${RID}/build-info.txt" <<EOF
FFmpeg version: ${FFMPEG_VERSION}
RID: ${RID}
Configure flags:
--enable-ffmpeg --enable-ffprobe --disable-ffplay --disable-doc --disable-debug --enable-pic --enable-shared --disable-static --disable-gpl --disable-nonfree
EOF
