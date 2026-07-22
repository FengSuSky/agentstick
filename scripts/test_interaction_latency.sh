#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rg -q 'private let audioEndTimeout: TimeInterval = 0\.25' \
  "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -q 'if config\.autoEnter \{' \
  "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -q 'completePendingPaste\(text: text\)' \
  "$root/desktop/macos/Sources/AgentStickApp/VoiceStickCoordinator.swift"
rg -q '#define TX_DRAIN_TIMEOUT_MS 150' \
  "$root/firmware/components/audio_pipeline/audio_pipeline.c"
rg -q 'xQueueSend\(s_tx_queue, &sentinel, portMAX_DELAY\);' \
  "$root/firmware/components/audio_pipeline/audio_pipeline.c"
if awk '/esp_err_t audio_pipeline_stop\\(void\\)/,/^}/ { if ($0 ~ /xQueueReset\\(s_tx_queue\\);/) found=1 } END { exit(found ? 0 : 1) }' \
  "$root/firmware/components/audio_pipeline/audio_pipeline.c"; then
  echo "audio_pipeline_stop must not clear queued audio before END" >&2
  exit 1
fi
