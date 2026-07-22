#!/usr/bin/env bash
set -euo pipefail

# Smoke test for agent task capture + sound alert pipeline.
# Sends synthetic hook payloads through AgentStickHooks CLI.
# Requires: macOS app running with agentCaptureEnabled=true.

cd "$(dirname "$0")/.."

echo "=== Building AgentStickHooks ==="
cd desktop/macos
swift build --product AgentStickHooks 2>&1 | tail -3

HOOK=".build/debug/AgentStickHooks"

echo ""
echo "=== Test 1: Claude Code Stop (task completed) ==="
printf '%s\n' '{"hook_event_name":"Stop","session_id":"test-codex-1","turn_id":"turn-1","cwd":"/tmp","last_assistant_message":"All tests pass"}' \
  | "$HOOK" --source codex
echo "  -> Expected: app logs decoded event, device receives task_done sound"

echo ""
echo "=== Test 2: Claude Code StopFailure (task failed) ==="
printf '%s\n' '{"hook_event_name":"StopFailure","session_id":"test-claude-1","cwd":"/tmp","error":"Build failed"}' \
  | "$HOOK" --source claude
echo "  -> Expected: app logs decoded event, device receives task_failed sound"

echo ""
echo "=== Test 3: UserPromptSubmit (task running) ==="
printf '%s\n' '{"hook_event_name":"UserPromptSubmit","session_id":"test-codex-2","cwd":"/tmp"}' \
  | "$HOOK" --source codex
echo "  -> Expected: app logs running state, no sound"

echo ""
echo "=== Test 4: SessionStart (session started) ==="
printf '%s\n' '{"hook_event_name":"SessionStart","session_id":"test-claude-2","cwd":"/tmp"}' \
  | "$HOOK" --source claude
echo "  -> Expected: app logs session start, no sound"

echo ""
echo "=== Test 5: Malformed JSON (fail-open) ==="
printf 'not json\n' | "$HOOK" --source codex || true
echo "  -> Expected: hook exits 0 (fail-open), no crash"

echo ""
echo "=== All synthetic tests sent ==="
echo "Check the AgentStick app logs for decoded events."
echo "If a device is connected, listen for task_done / task_failed tones."
