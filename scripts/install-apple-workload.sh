#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# install-apple-workload.sh <workload>   (ios | maccatalyst)
#
# Installs the newest workload set whose Apple SDK the selected Xcode can build
# with, so the .NET workloads and Xcode move forward together without pinning
# either.
#
# Each iOS/Mac Catalyst SDK's version names the Xcode it needs (SDK 27.0 needs
# Xcode 27.0, SDK 26.5 needs Xcode 26.5), and a plain `dotnet workload install`
# takes the newest workload set whatever Xcode the runner has: when .NET shipped
# SDK 27.0 before GitHub's macOS images had Xcode 27, every Apple build failed
# with "requires Xcode 27.0". This lists the workload sets for the installed
# .NET SDK band (newest first) and takes the first whose Apple SDK is no newer
# than `xcodebuild -version`. When the images get a newer Xcode, the newer
# workloads follow on their own.
# ==============================================================================

WORKLOAD="${1:?Usage: install-apple-workload.sh <ios|maccatalyst>}"
case "${WORKLOAD}" in
  ios|maccatalyst) ;;
  *) echo "FAIL: unknown workload ${WORKLOAD} (ios or maccatalyst)" >&2; exit 1 ;;
esac

xcode="$(xcodebuild -version | sed -n 's/^Xcode \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')"
test -n "${xcode}" || { echo "FAIL: couldn't read the Xcode version" >&2; exit 1; }
echo "Xcode ${xcode}"

# major.minor of a manifest version like "26.5.10318/10.0.100"
sdk_of() {
  dotnet workload search version "$1" --format json \
    | jq -r --arg m "microsoft.net.sdk.${WORKLOAD}" '.manifestVersions[$m] // empty' | tr -d '\r' \
    | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\)\..*/\1/p'
}

# Every workload set in this SDK band, newest first. The CLI lists only the 5
# newest unless --take says otherwise, and the set a lagging Xcode can build
# with may be further back: SDK 10.0.404 pushed 10.0.401, the last set with an
# Xcode 26 SDK, off the default list, and every Apple build failed. Ask for far
# more than a band holds, and treat a full page as possibly cut short rather
# than silently missing the set needed. scripts/test-install-apple-workload.sh
# covers the selection.
TAKE=1000
sets="$(dotnet workload search version --take "${TAKE}" --format json | jq -r '.[].workloadVersion' | tr -d '\r')"
count="$(printf '%s\n' "${sets}" | grep -c . || true)"
test "${count}" -gt 0 || { echo "FAIL: dotnet listed no workload sets for this SDK band" >&2; exit 1; }
test "${count}" -lt "${TAKE}" \
  || { echo "FAIL: dotnet listed ${count} workload sets, the most asked for; the list may be cut short" >&2; exit 1; }
echo "${count} workload sets in this SDK band"

for set in ${sets}; do
  sdk="$(sdk_of "${set}")"
  [ -n "${sdk}" ] || continue
  # this set's Apple SDK is no newer than Xcode: the lower of the two is the SDK
  if [ "$(printf '%s\n%s\n' "${sdk}" "${xcode}" | sort -V | head -n 1)" = "${sdk}" ]; then
    echo "workload set ${set}: ${WORKLOAD} SDK ${sdk}, which Xcode ${xcode} builds"
    dotnet workload install "${WORKLOAD}" --version "${set}" --skip-sign-check
    exit 0
  fi
  echo "skipping workload set ${set}: ${WORKLOAD} SDK ${sdk} needs a newer Xcode than ${xcode}"
done

echo "FAIL: no workload set for this .NET SDK has a ${WORKLOAD} SDK that Xcode ${xcode} supports" >&2
exit 1
