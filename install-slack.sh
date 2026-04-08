#!/usr/bin/env bash
#
# install-slack.sh: Send Claude Code notifications to Slack.
# Installs a hook that fires on PermissionRequest and Stop events.
#
# Install:   bash install-slack.sh --slack-webhook https://hooks.slack.com/...
# Uninstall: bash install-slack.sh --uninstall
#

set -euo pipefail

INSTALL_DIR="$HOME/.claude/remote-notify"
CONFIG_FILE="$INSTALL_DIR/config"
NOTIFY_SCRIPT="$INSTALL_DIR/notify-slack.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_CMD="$NOTIFY_SCRIPT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[slack-notify]${NC} $1"; }
warn()  { echo -e "${YELLOW}[slack-notify]${NC} $1"; }
error() { echo -e "${RED}[slack-notify]${NC} $1"; exit 1; }

check_deps() {
    for cmd in jq curl; do
        command -v "$cmd" &>/dev/null || error "$cmd is required but not found. Install it and retry."
    done
}

ensure_settings_file() {
    mkdir -p "$HOME/.claude"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
        info "Created $SETTINGS_FILE"
    fi
}

write_notify_script() {
    mkdir -p "$INSTALL_DIR"
    cat > "$NOTIFY_SCRIPT" << 'NOTIFY_EOF'
#!/usr/bin/env bash
#
# notify-slack.sh — called by Claude Code hooks, do not run directly
#

CONFIG_FILE="$HOME/.claude/remote-notify/config"

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
NOTIFY_EOF
    chmod +x "$NOTIFY_SCRIPT"
    info "Installed notification script to $NOTIFY_SCRIPT"
}

save_config() {
    local webhook_url="$1"
    cat > "$CONFIG_FILE" << EOF
SLACK_WEBHOOK_URL="$webhook_url"
EOF
    chmod 600 "$CONFIG_FILE"
    info "Saved config to $CONFIG_FILE"
}

already_installed() {
    jq -e '
        (.hooks.PermissionRequest // []) + (.hooks.Stop // []) |
        any(.hooks[]?.command // "" | test("remote-notify"))
    ' "$SETTINGS_FILE" &>/dev/null
}

install_hooks() {
    local tmp
    tmp=$(mktemp)
    jq --arg cmd "$HOOK_CMD" '
        .hooks = (.hooks // {}) |
        .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) + [
            {"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}
        ]) |
        .hooks.Stop = ((.hooks.Stop // []) + [
            {"matcher": "", "hooks": [{"type": "command", "command": $cmd}]}
        ])
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    info "Added PermissionRequest and Stop hooks to $SETTINGS_FILE"
}

install() {
    local webhook_url="${SLACK_WEBHOOK:-}"

    if [[ -z "$webhook_url" ]]; then
        read -r -p "Slack webhook URL: " webhook_url
    fi

    [[ -n "$webhook_url" ]] || error "Slack webhook URL is required."

    check_deps
    ensure_settings_file

    if already_installed; then
        warn "Slack hooks already installed in $SETTINGS_FILE"
        warn "To reinstall, run with --uninstall first."
        exit 0
    fi

    write_notify_script
    save_config "$webhook_url"
    install_hooks

    info ""
    info "Done! You'll get a Slack message when Claude Code needs permission or finishes."
    info ""
    info "Test it:"
    info "  echo '{\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\"}' | $NOTIFY_SCRIPT"
    info ""
    info "To uninstall: bash install-slack.sh --uninstall"
}

uninstall() {
    if [[ -f "$SETTINGS_FILE" ]]; then
        local tmp
        tmp=$(mktemp)
        jq '
            def remove_remote_notify:
                map(select((.hooks[]?.command // "") | test("remote-notify") | not));

            .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) | remove_remote_notify) |
            .hooks.Stop = ((.hooks.Stop // []) | remove_remote_notify) |
            if .hooks.PermissionRequest == [] then del(.hooks.PermissionRequest) else . end |
            if .hooks.Stop == [] then del(.hooks.Stop) else . end |
            if .hooks == {} then del(.hooks) else . end
        ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
        info "Removed Slack hooks from $SETTINGS_FILE"
    fi

    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        info "Removed $INSTALL_DIR"
    fi

    info "Uninstalled."
}

# Parse args
SLACK_WEBHOOK=""
for arg in "$@"; do
    case "$arg" in
        --uninstall) uninstall; exit 0 ;;
        --slack-webhook=*) SLACK_WEBHOOK="${arg#*=}" ;;
        --slack-webhook) shift; SLACK_WEBHOOK="${1:-}" ;;
    esac
done

install
