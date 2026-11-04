#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title Start OmniSpeak App
# @raycast.mode compact
# @raycast.packageName OmniSpeak

set -euo pipefail

curl -fsS -X POST "http://127.0.0.1:8765/api/desktop-app/start" \
  | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("message", "OmniSpeak app launch requested"))'
