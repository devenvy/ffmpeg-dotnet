#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-consumer.sh <nupkg-dir> <version>
#
# Builds throwaway projects against the freshly packed feed and asserts what a
# real consumer gets. Package contents alone do not prove this: NuGet RID
# resolution, SDK asset selection and the trim targets all sit between the
# package and the consumer's bin/, and each has surprised us at least once.
#
# The pattern under test is the one the README documents:
#
#   <ItemGroup Condition="'$(RuntimeIdentifier)' == ''">
#     <PackageReference Include="...Runtime.All" />
#   </ItemGroup>
#   <ItemGroup Condition="'$(RuntimeIdentifier)' != ''">
#     <PackageReference Include="...Runtime.$(RuntimeIdentifier)" />
#   </ItemGroup>
# ==============================================================================

FEED="$(cd "${1:?Usage: verify-consumer.sh <nupkg-dir> <version>}" && pwd)"
VERSION="${2:?Usage: verify-consumer.sh <nupkg-dir> <version>}"
CELL="${CELL:-LGPLv2}"
RID_UNDER_TEST="${RID_UNDER_TEST:-linux-x64}"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

scaffold() {
  local dir="$1"
  rm -rf "${dir}"
  dotnet new console -o "${dir}" >/dev/null
  cat > "${dir}/nuget.config" <<EOF
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
  # The documented two-branch pattern, verbatim.
  python3 - "${dir}" "${CELL}" "${VERSION}" <<'PY'
import sys, pathlib
d, cell, ver = sys.argv[1], sys.argv[2], sys.argv[3]
p = next(pathlib.Path(d).glob('*.csproj'))
s = p.read_text(encoding='utf-8-sig')
s = s.replace('</Project>', f'''  <ItemGroup Condition="'$(RuntimeIdentifier)' == ''">
    <PackageReference Include="DevEnvy.FFmpeg.Binaries.{cell}.Runtime.All" Version="{ver}" />
  </ItemGroup>
  <ItemGroup Condition="'$(RuntimeIdentifier)' != ''">
    <PackageReference Include="DevEnvy.FFmpeg.Binaries.{cell}.Runtime.$(RuntimeIdentifier)" Version="{ver}" />
  </ItemGroup>
</Project>''')
p.write_text(s, encoding='utf-8')
PY
}

restored_platforms() {
  grep -oE "\"DevEnvy\.FFmpeg\.Binaries\.${CELL}\.Runtime\.[A-Za-z0-9-]+/" "$1/obj/project.assets.json" 2>/dev/null \
    | tr -d '"/' | sed "s/DevEnvy.FFmpeg.Binaries.${CELL}.Runtime.//" | sort -u | tr '\n' ' ' || true
}

echo "=== a RID-specific build restores exactly that platform ==="
scaffold "${WORK}/rid"
dotnet build "${WORK}/rid" -c Release -r "${RID_UNDER_TEST}" --self-contained false >/dev/null 2>&1 \
  || fail "build with -r ${RID_UNDER_TEST} failed"
got="$(restored_platforms "${WORK}/rid")"
[[ "${got}" == "${RID_UNDER_TEST} " ]] \
  || fail "expected only ${RID_UNDER_TEST}, restored '${got}'"
find "${WORK}/rid/bin" -name 'libavcodec.so.*' -o -name 'avcodec-*.dll' | grep -q . \
  || fail "no avcodec reached bin/ for ${RID_UNDER_TEST}"
echo "  ${RID_UNDER_TEST} only, avcodec present"

# Only meaningful when the whole platform set is in the feed, which is true on a
# release run and not on a CI subset run.
count=$(find "${FEED}" -name "*.${CELL}.Runtime.*.nupkg" | wc -l)
if [[ "${count}" -ge 13 ]]; then
  echo "=== a RID-less build falls back to Runtime.All and gets every platform ==="
  scaffold "${WORK}/norid"
  dotnet build "${WORK}/norid" -c Release >/dev/null 2>&1 || fail "RID-less build failed"
  got="$(restored_platforms "${WORK}/norid")"
  [[ "${got}" == *"All"* ]] || fail "RID-less build did not resolve Runtime.All, got '${got}'"
  for want in win-x64 linux-x64 osx-arm64 ios; do
    [[ "${got}" == *"${want}"* ]] || fail "Runtime.All did not bring ${want}"
  done
  echo "  Runtime.All resolved, pulling every platform"

  echo "=== FFmpegRuntimeIdentifiers trims the RID-less output ==="
  scaffold "${WORK}/trim"
  python3 - "${WORK}/trim" <<'PY'
import sys, pathlib
p = next(pathlib.Path(sys.argv[1]).glob('*.csproj'))
s = p.read_text(encoding='utf-8-sig').replace(
    '<TargetFramework>', '<FFmpegRuntimeIdentifiers>linux-x64</FFmpegRuntimeIdentifiers><TargetFramework>')
p.write_text(s, encoding='utf-8')
PY
  dotnet publish "${WORK}/trim" -c Release >/dev/null 2>&1 || fail "trimmed publish failed"
  kept="$(find "${WORK}/trim/bin" -path '*publish/runtimes/*' -maxdepth 4 -mindepth 2 -type d -exec basename {} \; | sort -u | tr '\n' ' ')"
  [[ "${kept}" == "linux-x64 " ]] || fail "trim kept '${kept}', expected only linux-x64"
  echo "  publish output trimmed to linux-x64"
else
  echo "=== Runtime.All and trim checks: skipped (feed holds ${count} platform packages, need 13) ==="
fi

echo ""
echo "Consumer verification passed."
