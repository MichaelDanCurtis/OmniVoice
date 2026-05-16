#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title OmniVoice Status
# @raycast.mode compact
# @raycast.packageName OmniVoice

set -euo pipefail

curl -fsS "http://127.0.0.1:8765/api/status" \
  | /usr/bin/python3 -c 'import json,sys; data=json.load(sys.stdin); print("OmniVoice {}: {} transcripts, {} events".format(data["status"], data["transcript_count"], data["event_count"]))'
