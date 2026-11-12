#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# test-install-apple-workload.sh
#
# Runs install-apple-workload.sh against stub `dotnet` and `xcodebuild` commands
# to pin down how it chooses a workload set. The stub lists workload sets the
# way the real CLI does, only the 5 newest unless --take asks for more, which
# is what broke the selection once: the one set the runners' Xcode could build
# with was sixth.
# ==============================================================================

here="$(cd "$(dirname "$0")" && pwd)"
script="${here}/install-apple-workload.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/bin"

# STUB_SETS: "set sdk" lines, newest first. STUB_FULL=1 lists exactly as many
# sets as --take asks for. STUB_LOG receives the install command.
cat > "${work}/bin/dotnet" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1 $2" = "workload install" ]; then
  echo "$*" > "${STUB_LOG}"
  exit 0
fi
[ "$1 $2 $3" = "workload search version" ] || { echo "stub dotnet: unexpected $*" >&2; exit 2; }
shift 3
take=5
one=""
while [ $# -gt 0 ]; do
  case "$1" in
    --take) take="$2"; shift 2 ;;
    --format) shift 2 ;;
    *) one="$1"; shift ;;
  esac
done
if [ -n "${one}" ]; then
  sdk="$(printf '%s\n' "${STUB_SETS}" | awk -v s="${one}" '$1 == s { print $2 }')"
  printf '{"manifestVersions":{"microsoft.net.sdk.ios":"%s.1000/10.0.100","microsoft.net.sdk.maccatalyst":"%s.1000/10.0.100"}}\n' \
    "${sdk}" "${sdk}"
elif [ "${STUB_FULL:-0}" = 1 ]; then
  seq 1 "${take}" | jq -R '{workloadVersion: ("10.0." + .)}' | jq -s -c .
else
  printf '%s\n' "${STUB_SETS}" | awk 'NF { print $1 }' | head -n "${take}" \
    | jq -R '{workloadVersion: .}' | jq -s -c .
fi
STUB
cat > "${work}/bin/xcodebuild" <<'STUB'
#!/usr/bin/env bash
printf 'Xcode %s\nBuild version 17A1\n' "${STUB_XCODE}"
STUB
chmod +x "${work}/bin/dotnet" "${work}/bin/xcodebuild"

# the band as it was when 10.0.404 shipped: only 10.0.401 and older target Xcode 26
band="10.0.404 27.2
10.0.403 27.1
10.0.402.1 27.1
10.0.402 27.0
10.0.401.1 27.0
10.0.401 26.5
10.0.400.1 26.0
10.0.400 26.0"

failures=0
# expect <name> <workload> <xcode> <expected set, or "fail">
expect() {
  local name="$1" workload="$2" xcode="$3" want="$4" got status
  : > "${work}/install.log"
  set +e
  STUB_SETS="${STUB_SETS:-${band}}" STUB_XCODE="${xcode}" STUB_LOG="${work}/install.log" \
    PATH="${work}/bin:${PATH}" bash "${script}" "${workload}" > "${work}/out.log" 2>&1
  status=$?
  set -e
  got="$(sed -n 's/.*--version \([^ ]*\).*/\1/p' "${work}/install.log")"
  if [ "${want}" = fail ]; then
    if [ "${status}" -ne 0 ] && [ -z "${got}" ]; then echo "ok   ${name}"; return; fi
  elif [ "${status}" -eq 0 ] && [ "${got}" = "${want}" ]; then
    echo "ok   ${name}"
    return
  fi
  echo "FAIL ${name}: wanted ${want}, got '${got}' (exit ${status})"
  sed 's/^/     /' "${work}/out.log"
  failures=$((failures + 1))
}

expect "the newest set Xcode supports, beyond the CLI's default 5" ios 26.6 10.0.401
expect "the same for Mac Catalyst" maccatalyst 26.6 10.0.401
expect "the newest set when Xcode supports it" ios 27.2 10.0.404
expect "an Xcode between two sets' SDKs takes the older set" ios 27.0 10.0.402
expect "no set for an Xcode older than every SDK" ios 25.4 fail
STUB_FULL=1 expect "a list as long as --take is refused as possibly cut short" ios 26.6 fail
STUB_SETS=" " expect "an empty list is refused" ios 26.6 fail

if [ "${failures}" -ne 0 ]; then
  echo "${failures} case(s) failed" >&2
  exit 1
fi
echo "PASS: install-apple-workload.sh picks the right workload set"
