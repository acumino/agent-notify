#!/usr/bin/env bash
#
# agent-notify: Get desktop notifications when Claude Code asks for permission.
# Works on macOS, Linux, and Windows (WSL/Git Bash).
#
# Install:   curl -fsSL https://raw.githubusercontent.com/acumino/agent-notify/main/install.sh | bash
# Uninstall: curl -fsSL https://raw.githubusercontent.com/acumino/agent-notify/main/install.sh | bash -s -- --uninstall
#

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[agent-notify]${NC} $1"; }
warn()  { echo -e "${YELLOW}[agent-notify]${NC} $1"; }
error() { echo -e "${RED}[agent-notify]${NC} $1"; exit 1; }

detect_platform() {
    local os
    os="$(uname -s)"
    case "$os" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            error "Unsupported platform: $os"
            ;;
    esac
}

get_notify_command() {
    local platform="$1"
    case "$platform" in
        macos)
            echo "osascript -e 'display notification \"Claude Code needs your permission\" with title \"Claude Code\" sound name \"Ping\"'"
            ;;
        linux)
            echo "notify-send -u critical -a 'Claude Code' 'Claude Code' 'Claude Code needs your permission'"
            ;;
        wsl)
            # Use powershell.exe to show a Windows toast notification from WSL
            echo "powershell.exe -Command \"[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null; [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null; \\\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument; \\\$xml.LoadXml('<toast><visual><binding template=\\\"ToastText02\\\"><text id=\\\"1\\\">Claude Code</text><text id=\\\"2\\\">Claude Code needs your permission</text></binding></visual></toast>'); [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show(\\\$xml)\""
            ;;
        windows)
            # Git Bash / MSYS2 — use powershell
            echo "powershell -Command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Claude Code needs your permission','Claude Code','OK','Information')\" > /dev/null 2>&1"
            ;;
    esac
}

get_setup_instructions() {
    local platform="$1"
    case "$platform" in
        macos)
            info "Make sure notifications are enabled:"
            info "  System Settings > Notifications > Script Editor > Allow Notifications"
            ;;
        linux)
            if ! command -v notify-send &>/dev/null; then
                warn "notify-send not found. Install it:"
                warn "  Ubuntu/Debian: sudo apt install libnotify-bin"
                warn "  Fedora:        sudo dnf install libnotify"
                warn "  Arch:          sudo pacman -S libnotify"
            fi
            ;;
        wsl)
            info "Notifications will appear as Windows toast notifications."
            ;;
        windows)
            info "Notifications will appear as Windows message boxes."
            ;;
    esac
}

check_deps() {
    if ! command -v jq &>/dev/null; then
        local hint="Install jq:"
        case "$(detect_platform)" in
            macos)   hint="$hint brew install jq" ;;
            linux)   hint="$hint sudo apt install jq  (or your package manager)" ;;
            wsl)     hint="$hint sudo apt install jq" ;;
            windows) hint="$hint choco install jq  (or scoop install jq)" ;;
        esac
        error "jq is required. $hint"
    fi
}

ensure_settings_file() {
    mkdir -p "$HOME/.claude"
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo '{}' > "$SETTINGS_FILE"
        info "Created $SETTINGS_FILE"
    fi
}

install_hook() {
    local platform
    platform="$(detect_platform)"

    check_deps
    ensure_settings_file

    # Check if PermissionRequest hook already exists
    if jq -e '.hooks.PermissionRequest' "$SETTINGS_FILE" &>/dev/null; then
        warn "PermissionRequest hook already exists in $SETTINGS_FILE"
        warn "Skipping install to avoid overwriting your existing hook."
        warn "To reinstall, run with --uninstall first."
        exit 0
    fi

    local notify_cmd
    notify_cmd="$(get_notify_command "$platform")"

    # Add the PermissionRequest hook
    local tmp
    tmp=$(mktemp)
    jq --arg cmd "$notify_cmd" '
        .hooks = (.hooks // {}) |
        .hooks.PermissionRequest = [
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": $cmd
                    }
                ]
            }
        ]
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"

    info "Installed PermissionRequest hook (platform: $platform)."
    info ""
    info "You'll now get a desktop notification whenever Claude Code asks for permission."
    info "Works in both the CLI and VS Code extension."
    info ""
    get_setup_instructions "$platform"
    info ""
    info "To uninstall: curl -fsSL https://raw.githubusercontent.com/acumino/agent-notify/main/install.sh | bash -s -- --uninstall"
}

uninstall_hook() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        info "Nothing to uninstall — $SETTINGS_FILE not found."
        exit 0
    fi

    if ! jq -e '.hooks.PermissionRequest' "$SETTINGS_FILE" &>/dev/null; then
        info "No PermissionRequest hook found. Nothing to remove."
        exit 0
    fi

    local tmp
    tmp=$(mktemp)
    jq '
        del(.hooks.PermissionRequest) |
        if .hooks == {} then del(.hooks) else . end
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"

    info "Removed PermissionRequest hook."
}

# Main
case "${1:-}" in
    --uninstall)
        uninstall_hook
        ;;
    *)
        install_hook
        ;;
esac
