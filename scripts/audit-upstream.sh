#!/usr/bin/env bash
set -uo pipefail

# ==============================================================================
# audit-upstream.sh [tag...]
#
# Downloads every runtime artifact of each release, audits it, and writes one
# JSON line per artifact to audit-<tag>.jsonl. Artifacts are deleted as it goes,
# so peak disk stays at one artifact rather than the ~3 GB the full set weighs.
#
# Must run on Linux: tar on Windows cannot create symlinks, which would make
# every artifact look like it ships duplicate real files.
# ==============================================================================

TAGS=("${@:-9.0.1.5 8.1.2.5}")
read -ra TAGS <<< "${TAGS[*]}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${REPO_ROOT}/.audit"
EXTRACT="${EXTRACT_DIR:-/tmp/ffaudit}"   # must be a native filesystem: DrvFs reports 0777 for everything
mkdir -p "${EXTRACT}"
mkdir -p "${WORK}"

# Overridable so a partial re-run can fill gaps without refetching everything.
read -ra PLATFORMS <<< "${PLATFORMS:-win-x64 win-arm64 linux-x64 linux-arm64 linux-armhf linux-musl-x64 linux-musl-arm64 osx-x64 osx-arm64 android-arm64 android-x64 ios}"
CELLS=(lgplv2 lgplv3 gplv2 gplv3)

for tag in "${TAGS[@]}"; do
  ffmpeg_version="${tag%.*}"
  base="https://github.com/devenvy/ffmpeg/releases/download/${tag}"
  out="${WORK}/audit-${tag}.jsonl"
  [[ "${APPEND:-0}" == "1" ]] || : > "${out}"

  echo "==> ${tag}: fetching SHA256SUMS"
  curl -fsSL --retry 10 --retry-delay 15 --retry-max-time 900 --retry-all-errors --connect-timeout 30 "${base}/SHA256SUMS" -o "${WORK}/SHA256SUMS-${tag}"

  total=$(( ${#PLATFORMS[@]} * ${#CELLS[@]} ))
  n=0
  for platform in "${PLATFORMS[@]}"; do
    for cell in "${CELLS[@]}"; do
      n=$(( n + 1 ))
      name="ffmpeg-${ffmpeg_version}-${platform}-${cell}.tar.gz"
      printf '  [%2d/%2d] %-40s' "${n}" "${total}" "${platform}-${cell}"

      if ! curl -fsSL --retry 10 --retry-delay 15 --retry-max-time 900 --retry-all-errors --connect-timeout 30 "${base}/${name}" -o "${WORK}/a.tar.gz"; then
        echo "DOWNLOAD FAILED"
        printf '{"artifact":"%s-%s","tag":"%s","issues":[{"kind":"missing-asset","detail":"%s","file":""}]}\n' \
          "${platform}" "${cell}" "${tag}" "${name}" >> "${out}"
        continue
      fi

      # Every byte we audit is the byte upstream published.
      want=$(awk -v n="${name}" '$2==n{print $1}' "${WORK}/SHA256SUMS-${tag}")
      got=$(sha256sum "${WORK}/a.tar.gz" | cut -d' ' -f1)
      if [[ -z "${want}" ]]; then
        printf '{"artifact":"%s-%s","tag":"%s","issues":[{"kind":"missing-checksum","detail":"%s not in SHA256SUMS","file":""}]}\n' \
          "${platform}" "${cell}" "${tag}" "${name}" >> "${out}"
      elif [[ "${want}" != "${got}" ]]; then
        printf '{"artifact":"%s-%s","tag":"%s","issues":[{"kind":"checksum-mismatch","detail":"%s","file":""}]}\n' \
          "${platform}" "${cell}" "${tag}" "${name}" >> "${out}"
        echo "CHECKSUM MISMATCH"
        continue
      fi

      rm -rf "${EXTRACT}/x" && mkdir -p "${EXTRACT}/x"
      tar -xzf "${WORK}/a.tar.gz" -C "${EXTRACT}/x" 2>/dev/null

      python3 "${REPO_ROOT}/scripts/audit-upstream.py" "${EXTRACT}/x" "${platform}-${cell}" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); d['tag']='${tag}'; print(json.dumps(d))" \
        >> "${out}"

      issues=$(tail -1 "${out}" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['issues']))" 2>/dev/null || echo '?')
      echo "${issues} issue(s)"
      rm -rf "${EXTRACT}/x" "${WORK}/a.tar.gz"
    done
  done
  echo "==> wrote ${out}"
done
