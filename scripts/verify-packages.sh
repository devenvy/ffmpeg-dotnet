#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# verify-packages.sh <nupkg-dir> [--expect-complete [--cells LGPLv2,...]]
#
# --expect-complete additionally asserts every shipped package is present: the
# helper, and every cell's .All and per-platform packages (only the cells
# named by --cells, when given).
# The release workflow passes it for every cell; CI narrows it to the one cell
# it packs in full.
#
# Thin wrapper around verify-packages.py. The checks live in a real file, not a
# heredoc: `python3 - <<EOF` throws away the interpreter's exit status, so a
# heredoc version printed FAILURES and still exited 0, which made every green
# CI run meaningless.
# ==============================================================================

DIR="${1:?Usage: verify-packages.sh <nupkg-dir> [--expect-complete [--cells LGPLv2,...]]}"
shift
exec python3 "$(dirname "${BASH_SOURCE[0]}")/verify-packages.py" "${DIR}" "$@"
