#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# wait-for-index.sh <version> <nupkg-dir>
#
# Blocks until nuget.org actually serves every payload package of this version.
#
# The meta packages depend on the payloads by exact version. Upload acceptance
# is not availability: nuget.org validates and indexes asynchronously, usually
# within minutes. Pushing the metas before that leaves a window where a consumer
# resolves a meta whose dependencies cannot be found.
# ==============================================================================

VERSION="${1:?Usage: wait-for-index.sh <version> <nupkg-dir>}"
DIR="${2:?Usage: wait-for-index.sh <version> <nupkg-dir>}"

DEADLINE=$(( $(date +%s) + ${INDEX_TIMEOUT_SECONDS:-1800} ))
INTERVAL="${INDEX_POLL_SECONDS:-20}"

ids=()
for f in "${DIR}"/*.nupkg; do
  base="$(basename "$f" ".${VERSION}.nupkg")"
  [[ "${base}" == "$(basename "$f")" ]] && continue    # different version, skip
  [[ "${base}" == *.Runtime.All ]] && continue          # the metas are what wait
  ids+=("${base}")
done

echo "Waiting for ${#ids[@]} package(s) at version ${VERSION} to be indexed."

pending=("${ids[@]}")
while [[ ${#pending[@]} -gt 0 ]]; do
  still=()
  for id in "${pending[@]}"; do
    lower="$(echo "${id}" | tr '[:upper:]' '[:lower:]')"
    # The flat container does not answer HEAD, so ask for the version list and
    # look for ours in it. That is also the endpoint restore consults.
    url="https://api.nuget.org/v3-flatcontainer/${lower}/index.json"
    if curl -fsS --max-time 30 "${url}" 2>/dev/null | grep -q "\"${VERSION}\""; then
      echo "  indexed: ${id}"
    else
      still+=("${id}")
    fi
  done
  pending=("${still[@]+"${still[@]}"}")

  [[ ${#pending[@]} -eq 0 ]] && break

  if [[ $(date +%s) -ge ${DEADLINE} ]]; then
    echo "ERROR: timed out with ${#pending[@]} package(s) still unindexed:" >&2
    printf '  %s\n' "${pending[@]}" >&2
    echo "The payloads are pushed; rerun this workflow to finish publishing the metas." >&2
    exit 1
  fi

  echo "  ${#pending[@]} still pending, sleeping ${INTERVAL}s"
  sleep "${INTERVAL}"
done

echo "All payload packages are serving from nuget.org."
