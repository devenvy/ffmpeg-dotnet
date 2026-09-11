#!/bin/sh
set -eu

# ==============================================================================
# run-smoke-test.sh <rid> <feed-dir>
#
# Restores tests/SmokeTest against a local feed and runs it for one RID.
#
# POSIX sh on purpose, not bash: this runs on Alpine (no bash in the dotnet SDK
# image), on macOS (bash 3.2, no associative arrays), and under Git Bash on the
# Windows runners.
# ==============================================================================

RID="${1:?Usage: run-smoke-test.sh <rid> <feed-dir>}"
FEED="${2:?Usage: run-smoke-test.sh <rid> <feed-dir>}"

FEED_ABS=$(cd "${FEED}" && pwd)
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="${REPO_ROOT}/.smoke/${RID}"

echo "RID:  ${RID}"
echo "Feed: ${FEED_ABS}"
find "${FEED_ABS}" -name '*.nupkg' -exec basename {} \; | sed 's/^/  /'
echo

rm -rf "${WORK}"
mkdir -p "${WORK}"
cp "${REPO_ROOT}/tests/SmokeTest/SmokeTest.csproj" "${WORK}/"
cp "${REPO_ROOT}/tests/SmokeTest/Program.cs" "${WORK}/"

# Everything DevEnvy.* must come from the local feed, so a stale package on
# nuget.org can never silently satisfy the restore and make this test pass
# against binaries the run did not build.
cat > "${WORK}/nuget.config" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="${FEED_ABS}" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <packageSourceMapping>
    <clear />
    <packageSource key="local"><package pattern="DevEnvy.*" /></packageSource>
    <packageSource key="nuget.org"><package pattern="*" /></packageSource>
  </packageSourceMapping>
</configuration>
EOF

PKG_CELL="${PKG_CELL:-LGPLv2}"
PKG_VERSION="${PKG_VERSION:-0.0.0-ci}"

cd "${WORK}"
exec dotnet run -c Release \
  -r "${RID}" --self-contained false \
  -p:FFmpegPackage="DevEnvy.FFmpeg.Binaries.${PKG_CELL}.Rid" \
  -p:FFmpegPackageVersion="${PKG_VERSION}"
