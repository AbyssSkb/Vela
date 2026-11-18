#!/usr/bin/env bash
set -euo pipefail
: "${TAG:?}" "${GH_REPO:?}" "${PUBLISH:?}"

case "$PUBLISH" in
  false) exec python3 tool/release/publication.py prepare "$TAG" ;;
  true) exec python3 tool/release/publication.py publish "$TAG" ;;
  *) echo 'PUBLISH must be true or false.' >&2; exit 1 ;;
esac
