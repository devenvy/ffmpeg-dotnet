#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# publish-smoke-test.sh <rid> <feed-dir> <out-dir>
#
# Publishes tests/SmokeTest self-contained for one RID. Used where the target
# cannot run a .NET SDK at reasonable speed - currently linux-arm, which has no
# native runner and whose emulated SDK build took six hours. Building here and
# emulating only the finished binary reduces that to seconds.
# ==============================================================================

RID="${1:?Usage: publish-smoke-test.sh <rid> <feed-dir> <out-dir>}"
FEED="$(cd "${2:?feed dir}" && pwd)"
OUT="${3:?out dir}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${REPO_ROOT}/.smoke/publish-${RID}"
PKG_CELL="${PKG_CELL:-LGPLv2}"
PKG_VERSION="${PKG_VERSION:-0.0.0-ci}"

# NuGet caches by id+version and never re-extracts, so a repacked 0.0.0-* would
# otherwise be restored from a stale copy.
NUGET_CACHE="${NUGET_PACKAGES:-${HOME}/.nuget/packages}"
[ -d "${NUGET_CACHE}" ] && rm -rf "${NUGET_CACHE}"/devenvy.ffmpeg.binaries*

rm -rf "${WORK}" "${OUT}"
mkdir -p "${WORK}"
cp "${REPO_ROOT}/tests/SmokeTest/SmokeTest.csproj" "${REPO_ROOT}/tests/SmokeTest/Program.cs" "${WORK}/"

cat > "${WORK}/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="${FEED}" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <clear />
    <packageSource key="local"><package pattern="DevEnvy.*" /></packageSource>
    <packageSource key="nuget.org"><package pattern="*" /></packageSource>
  </packageSourceMapping>
</configuration>
EOF

dotnet publish "${WORK}" \
  -c Release -r "${RID}" --self-contained true \
  -p:FFmpegPackage="DevEnvy.FFmpeg.Binaries.${PKG_CELL}.Runtime.${RID}" \
  -p:FFmpegPackageVersion="${PKG_VERSION}" \
  -o "${OUT}"

# The apphost and ffmpeg/ffprobe must be executable: publishing preserves the
# apphost bit, but the natives came out of a .nupkg, which carries no modes.
chmod +x "${OUT}/SmokeTest" 2>/dev/null || true
find "${OUT}" \( -name ffmpeg -o -name ffprobe \) -exec chmod +x {} + 2>/dev/null || true

echo "Published ${RID} to ${OUT}"
