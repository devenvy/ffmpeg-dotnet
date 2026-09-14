#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-packages.sh <nupkg-dir> [--expect-complete]
#
# --expect-complete additionally asserts every shipped platform is present.
# The release workflow passes it; CI does not, because CI packs a deliberate
# subset of representative RIDs.
#
# Thin wrapper around verify-packages.py. The checks live in a real file, not a
# heredoc: `python3 - <<EOF` throws away the interpreter's exit status, so a
# heredoc version printed FAILURES and still exited 0, which made every green
# CI run meaningless.
# ==============================================================================

DIR="${1:?Usage: verify-packages.sh <nupkg-dir> [--expect-complete]}"
shift
exec python3 "$(dirname "${BASH_SOURCE[0]}")/verify-packages.py" "${DIR}" "$@"
