#!/usr/bin/env bash
set -euo pipefail
: "${TAG:?}" "${GH_REPO:?}" "${PUBLISH:?}"
python3 tool/release/version.py --tag "$TAG"

if gh release view "$TAG" --json isDraft > "$RUNNER_TEMP/vela-release-state.json" 2>/dev/null; then
  python3 - "$RUNNER_TEMP/vela-release-state.json" <<'PY'
import json, sys
if not json.load(open(sys.argv[1]))['isDraft']:
    raise SystemExit('Refusing to replace assets of an already published version; use a new version tag.')
PY
else
  flags=(--draft --verify-tag --title "Vela ${TAG#v}" --generate-notes)
  if [[ "$TAG" == *-* ]]; then flags+=(--prerelease); fi
  gh release create "$TAG" "${flags[@]}"
fi
gh release upload "$TAG" dist/* --clobber
gh release upload "$TAG" feeds/* --clobber

if [[ "$PUBLISH" == true ]]; then
  gh release edit "$TAG" --draft=false
  if ! gh release view updates >/dev/null 2>&1; then
    gh release create updates --target "$(git rev-parse HEAD)" --prerelease --latest=false \
      --title 'Vela update feeds' --notes 'Machine-readable update feeds. Download installers from a versioned Vela release.'
  fi
  # Versioned installers are public before any feed can advertise them.
  gh release upload updates feeds/* --clobber
fi
