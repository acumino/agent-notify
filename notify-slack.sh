#!/usr/bin/env bash
#
# notify-slack.sh — Claude Code Slack notifier (installed by install-slack.sh)
# Do not run this directly. It is called by Claude Code hooks via stdin JSON.
#

CONFIG_FILE="$HOME/.claude/remote-notify/config"

# Silently exit if not configured
[[ -f "$CONFIG_FILE" ]] || exit 0

# shellcheck source=/dev/null
source "$CONFIG_FILE"

[[ -n "${SLACK_WEBHOOK_URL:-}" ]] || exit 0

INPUT=$(cat 2>/dev/null || true)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null || true)

send_slack() {
    local text="$1"
    jq -n --arg t "$text" '{"text": $t}' | \
        curl -s -X POST "$SLACK_WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d @- > /dev/null 2>&1 || true
}

case "$EVENT" in
    PermissionRequest)
        TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
        send_slack ":bell: *Claude Code needs your permission* | Tool: \`$TOOL\`"
        ;;
    Stop|SubagentStop)
        send_slack ":white_check_mark: *Claude Code* session ended"
        ;;
esac
