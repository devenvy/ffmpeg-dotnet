#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-packages.sh <nupkg-dir>
#
# Thin wrapper around verify-packages.py. The checks live in a real file, not a
# heredoc: `python3 - <<EOF` throws away the interpreter's exit status, so a
# heredoc version printed FAILURES and still exited 0, which made every green
# CI run meaningless.
# ==============================================================================

DIR="${1:?Usage: verify-packages.sh <nupkg-dir>}"
exec python3 "$(dirname "${BASH_SOURCE[0]}")/verify-packages.py" "${DIR}"
