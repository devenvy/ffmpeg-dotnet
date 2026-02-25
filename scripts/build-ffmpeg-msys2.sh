#!/usr/bin/env bash
set -euo pipefail

# Download pre-built FFmpeg LGPL shared binaries from BtbN (trusted source)
# This avoids MinGW clock_gettime64 compatibility issues

RID="win-x64"
RAW_ROOT_DIR="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ "${RAW_ROOT_DIR}" =~ ^[A-Za-z]:[\\/] ]]; then
  ROOT_DIR="$(cygpath -u "${RAW_ROOT_DIR}")"
else
  ROOT_DIR="${RAW_ROOT_DIR}"
fi

WORK_DIR="${ROOT_DIR}/.build/${RID}"
OUT_DIR="${ROOT_DIR}/artifacts/${RID}/native"

mkdir -p "${WORK_DIR}" "${OUT_DIR}"
cd "${WORK_DIR}"

# Download latest LGPL shared build from BtbN
BTBN_URL="https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl-shared.zip"
echo "Downloading FFmpeg LGPL shared build from BtbN..."
curl -fsSL "${BTBN_URL}" -o ffmpeg.zip

# Extract
rm -rf ffmpeg-extracted
unzip -q ffmpeg.zip -d ffmpeg-extracted
FFMPEG_DIR=$(find ffmpeg-extracted -maxdepth 1 -type d -name 'ffmpeg-*' | head -1)

# Copy binaries to output
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cp -a "${FFMPEG_DIR}/bin/"*.dll "${OUT_DIR}/"
cp -a "${FFMPEG_DIR}/bin/ffmpeg.exe" "${OUT_DIR}/"
cp -a "${FFMPEG_DIR}/bin/ffprobe.exe" "${OUT_DIR}/"

# Get version from ffmpeg
FFMPEG_VERSION=$("${OUT_DIR}/ffmpeg.exe" -version 2>/dev/null | head -1 | awk '{print $3}' || echo "unknown")

cat > "${ROOT_DIR}/artifacts/${RID}/build-info.txt" <<EOF
FFmpeg version: ${FFMPEG_VERSION}
RID: ${RID}
Source: BtbN FFmpeg-Builds (LGPL shared)
URL: ${BTBN_URL}
EOF

echo "Done! FFmpeg binaries copied to ${OUT_DIR}"