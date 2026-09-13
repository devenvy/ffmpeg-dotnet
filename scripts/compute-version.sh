#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# compute-version.sh <upstream-tag>
#
# Prints the NuGet package version for an upstream release tag.
#
#   z = (upstream_z * 100) + our_build
#
# Upstream's fourth component is a GLOBAL build counter shared across series:
# 8.1.2.5 and 9.0.1.5 were published at the same instant. Per series it
# therefore has gaps (9.0.1 went .0 .1 .2 .4 .5). Giving our own counter its own
# digit range keeps the two from drifting into each other and makes the mapping
# reversible: upstream_z = z / 100, our_build = z % 100.
#
# our_build counts packaging-only releases against one upstream build, read from
# the v* tags already pushed.
# ==============================================================================

UPSTREAM_TAG="${1:?Usage: compute-version.sh <upstream-tag> [--force-rebuild]}"
FORCE_REBUILD="${2:-}"

if ! [[ "${UPSTREAM_TAG}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)$ ]]; then
  echo "ERROR: '${UPSTREAM_TAG}' is not a 4-part upstream tag (e.g. 9.0.1.5)" >&2
  exit 1
fi

FFMPEG="${BASH_REMATCH[1]}"
UPSTREAM_Z="${BASH_REMATCH[2]}"
BASE=$(( UPSTREAM_Z * 100 ))

# Highest our_build already published against this exact upstream build.
HIGHEST=-1
while read -r tag; do
  [[ -z "${tag}" ]] && continue
  z="${tag##*.}"
  (( z / 100 == UPSTREAM_Z )) || continue
  (( z % 100 > HIGHEST )) && HIGHEST=$(( z % 100 ))
done < <(git tag --list "v${FFMPEG}.*" | sed 's/^v//')

# Releasing is not the same as computing the next version. Without this, a
# caller asking "is a release warranted?" always got a fresh, untagged version
# back and concluded yes - so any commit touching the packaging published all
# 53 packages again and burned a version number.
#
# A new upstream build is always worth releasing. Re-releasing the same upstream
# build is a deliberate act and has to be asked for.
if [[ "${HIGHEST}" -ge 0 && "${FORCE_REBUILD}" != "--force-rebuild" ]]; then
  echo "ERROR: upstream ${UPSTREAM_TAG} is already released as v${FFMPEG}.$(( BASE + HIGHEST ))." >&2
  echo "       Pass --force-rebuild to publish another packaging-only build." >&2
  exit 3
fi

OUR_BUILD=$(( HIGHEST + 1 ))

# Two counters share one integer only because our_build stays inside its own
# range. At 100 it would carry into upstream's digits and claim to come from a
# build that does not exist.
if (( OUR_BUILD > 99 )); then
  echo "ERROR: our_build would be ${OUR_BUILD} for upstream ${UPSTREAM_TAG}." >&2
  echo "       Only 00-99 packaging releases fit per upstream build." >&2
  exit 1
fi

printf '%s.%d\n' "${FFMPEG}" $(( BASE + OUR_BUILD ))
