#!/usr/bin/env bash
# Safe user-scoped installer. A dry run is the default; this script is never
# invoked automatically by the session or by development checks.
set -euo pipefail

mode=dry-run
register=false
remove_session=false
restore=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) mode=dry-run ;;
        --install) mode=install ;;
        --uninstall) mode=uninstall ;;
        --register-session) register=true ;;
        --remove-session) remove_session=true ;;
        --restore) restore=true ;;
        -h|--help)
            cat <<'HELP'
Usage: scripts/install.sh [--dry-run|--install|--uninstall] [--register-session|--remove-session] [--restore]

Default: show a dry run. --install writes only Corvantium-owned files under
XDG_CONFIG_HOME/corvantium and XDG_DATA_HOME/../bin. Session registration is
separate, system-level, and always asks for confirmation.
HELP
            exit 0 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd -- "$script_dir/.." && pwd -P)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
if [[ -r "$config_home/hyprland/main.lua" ]]; then
    config_root="$config_home"
else
    config_root="$config_home/corvantium"
fi
bin_root="${XDG_BIN_HOME:-$HOME/.local/bin}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/corvantium"
manifest="$state_root/managed-files"
session_dest=/usr/share/wayland-sessions/hyprland-corvantium.desktop
session_template="$source_root/session/corvantium.desktop"

sources=(
    hyprland/main.lua
    shell/shell.qml
    shell/components/FluidPanel.qml
    shell/settings.json
    shell/services/weather.py
    shell/services/lyrics.py
    scripts/corvantium-session
    scripts/corvantium-launch
    scripts/corvantium-hardware
    scripts/corvantium-music-recognize
)
destinations=(
    "$config_root/hyprland/main.lua"
    "$config_root/shell/shell.qml"
    "$config_root/shell/components/FluidPanel.qml"
    "$config_root/shell/settings.json"
    "$config_root/shell/services/weather.py"
    "$config_root/shell/services/lyrics.py"
    "$config_root/scripts/corvantium-session"
    "$config_root/scripts/corvantium-launch"
    "$config_root/scripts/corvantium-hardware"
    "$config_root/scripts/corvantium-music-recognize"
)
binaries=(corvantium-session corvantium-launch corvantium-hardware corvantium-music-recognize)

confirm() {
    local prompt="$1" answer
    [[ -t 0 ]] || { printf 'Refusing interactive change without a terminal.\n' >&2; return 1; }
    read -r -p "$prompt [y/N] " answer
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

backup_exact() {
    local target="$1" rel="$2" bucket="$3"
    [[ -e "$target" || -L "$target" ]] || return 0
    mkdir -p "$bucket/$(dirname -- "$rel")"
    cp -a -- "$target" "$bucket/$rel"
}

is_managed() {
    [[ -f "$manifest" ]] && grep -Fxq -- "$1" "$manifest"
}

preflight() {
    local missing=0 version qs_version
    local compositor
    compositor="$(command -v Hyprland || command -v hyprland || true)"
    for binary in qs python3; do
        if ! command -v "$binary" >/dev/null 2>&1; then
            printf 'Missing required program: %s\n' "$binary" >&2
            missing=1
        fi
    done
    if [[ -z "$compositor" ]]; then
        printf 'Missing required program: Hyprland or hyprland\n' >&2
        missing=1
    fi
    (( missing == 0 )) || { printf '%s\n' 'Install the listed runtime dependencies, then retry.' >&2; return 1; }
    version="$("$compositor" --version 2>/dev/null | head -n 1 | sed -nE 's/.*([0-9]+)\.([0-9]+)\.([0-9]+).*/\1.\2.\3/p')"
    [[ -n "$version" ]] || { echo 'Could not determine Hyprland version.' >&2; return 1; }
    local major="${version%%.*}" minor="${version#*.}"; minor="${minor%%.*}"
    if (( major == 0 && minor < 55 )); then
        printf 'Hyprland %s is too old; Corvantium needs 0.55 or newer.\n' "$version" >&2
        return 1
    fi
    qs_version="$(qs --version 2>/dev/null | sed -nE 's/.*Quickshell ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
    [[ -n "$qs_version" ]] || { echo 'Could not determine Quickshell version.' >&2; return 1; }
    local qs_major qs_rest qs_minor
    qs_major="${qs_version%%.*}"
    qs_rest="${qs_version#*.}"
    qs_minor="${qs_rest%%.*}"
    if (( qs_major == 0 && qs_minor < 3 )); then
        printf 'Quickshell %s is too old; Corvantium needs 0.3 or newer.\n' "$qs_version" >&2
        return 1
    fi
    printf 'Preflight passed: Hyprland %s, Quickshell %s, Python %s.\n' "$version" "$qs_version" "$(python3 --version 2>&1)"
    for binary in wpctl playerctl brightnessctl v4l2-ctl fuzzel wofi songrec pactl slurp grim tesseract wl-copy; do
        command -v "$binary" >/dev/null 2>&1 || printf 'Optional capability not found: %s\n' "$binary"
    done
}

install_user_files() {
    local original="$state_root/original" snapshot="$state_root/snapshots/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$config_root" "$bin_root" "$state_root"
    touch "$manifest"
    for i in "${!sources[@]}"; do
        local src="$source_root/${sources[$i]}" dest="${destinations[$i]}" rel="${destinations[$i]#"$config_root"/}"
        if [[ "$dest" == "$config_root/"* ]]; then rel="config/$rel"; else rel="$(basename -- "$dest")"; fi
        if [[ "${sources[$i]}" == "shell/settings.json" ]] && is_managed "$dest" && [[ -f "$dest" ]]; then
            printf 'Preserving user settings: %s\n' "$dest"
            continue
        fi
        if [[ -e "$dest" || -L "$dest" ]]; then
            if is_managed "$dest"; then backup_exact "$dest" "$rel" "$snapshot";
            elif [[ ! -e "$original/$rel" && ! -L "$original/$rel" ]]; then backup_exact "$dest" "$rel" "$original"; fi
        fi
        install -D -m 0644 -- "$src" "$dest"
        case "$(basename -- "$dest")" in corvantium-session|corvantium-launch|corvantium-hardware|corvantium-music-recognize) chmod 0755 "$dest" ;; esac
        grep -Fxq -- "$dest" "$manifest" || printf '%s\n' "$dest" >> "$manifest"
    done
    for name in "${binaries[@]}"; do
        local dest="$bin_root/$name" target="$config_root/scripts/$name" rel="bin/$name"
        if [[ -e "$dest" || -L "$dest" ]]; then
            if is_managed "$dest"; then backup_exact "$dest" "$rel" "$snapshot";
            elif [[ ! -e "$original/$rel" && ! -L "$original/$rel" ]]; then backup_exact "$dest" "$rel" "$original"; fi
            rm -f -- "$dest"
        fi
        ln -s -- "$target" "$dest"
        grep -Fxq -- "$dest" "$manifest" || printf '%s\n' "$dest" >> "$manifest"
    done
    printf 'Installed Corvantium user files under %s\n' "$config_root"
    printf 'Added launch commands under %s\n' "$bin_root"
}

desktop_exec_value() {
    local executable="$bin_root/corvantium-session"
    if [[ "$executable" == *[[:space:]]* ]]; then
        printf 'Session executable path contains whitespace, which this SDDM entry cannot safely launch: %s\n' "$executable" >&2
        return 1
    fi
    printf '%s\n' "$executable"
}

register_session_now() {
    [[ -x "$bin_root/corvantium-session" ]] || { printf 'Install user files first (--install).\n' >&2; return 1; }
    [[ -r "$config_root/hyprland/main.lua" && -r "$config_root/shell/shell.qml" ]] || {
        printf 'Corvantium config is incomplete under %s. Run --install before registering the session.\n' "$config_root" >&2
        return 1
    }
    local temp desktop_exec backup
    temp="$(mktemp)"
    desktop_exec="$(desktop_exec_value)"
    sed "s|^Exec=.*|Exec=$desktop_exec|" "$session_template" > "$temp"
    printf 'Will install only: %s\n' "$session_dest"
    printf 'The entry will not become the default and will not change Serpantinum.\n'
    confirm 'Register the Hyprland Corvantium session with SDDM?' || { rm -f "$temp"; echo 'Session registration cancelled.'; return 0; }
    if [[ -e "$session_dest" ]]; then
        backup="${XDG_STATE_HOME:-$HOME/.local/state}/corvantium/session-backup-$(date +%Y%m%d-%H%M%S).desktop"
        mkdir -p "$(dirname -- "$backup")"
        sudo install -D -m 0600 "$session_dest" "$backup"
        sudo chown "$(id -u):$(id -g)" "$backup"
        echo "Backed up existing Corvantium session entry to $backup"
    fi
    sudo install -D -m 0644 "$temp" "$session_dest"
    rm -f "$temp"
    echo "Registered $session_dest"
}

uninstall_user_files() {
    [[ -f "$manifest" ]] || { echo 'No Corvantium install manifest was found.'; return 0; }
    confirm 'Remove only files listed in the Corvantium install manifest?' || { echo 'Uninstall cancelled.'; return 0; }
    local preserve_settings=false
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        if [[ "$path" == "$config_root/shell/settings.json" && -f "$path" ]] && ! cmp -s -- "$path" "$source_root/shell/settings.json"; then
            preserve_settings=true
            printf 'Keeping modified user settings: %s\n' "$path"
            continue
        fi
        if [[ -e "$path" || -L "$path" ]]; then rm -f -- "$path"; fi
    done < "$manifest"
    if [[ "$restore" == true ]]; then
        local original="$state_root/original"
        if [[ -d "$original" ]]; then
            while IFS= read -r -d '' file; do
                local rel="${file#"$original"/}" target
                case "$rel" in
                    config/*) target="$config_root/${rel#config/}" ;;
                    bin/*) target="$bin_root/${rel#bin/}" ;;
                    *) continue ;;
                esac
                if [[ "$preserve_settings" == true && "$rel" == config/shell/settings.json ]]; then
                    printf 'Keeping modified settings in place; the previous file remains backed up at %s\n' "$file"
                    continue
                fi
                install -D -m "$(stat -c '%a' "$file")" "$file" "$target"
            done < <(find "$original" -type f -print0)
            while IFS= read -r -d '' file; do
                local rel="${file#"$original"/}" target
                case "$rel" in bin/*) target="$bin_root/${rel#bin/}" ;; *) continue ;; esac
                rm -f -- "$target"; ln -s -- "$(readlink "$file")" "$target"
            done < <(find "$original" -type l -print0)
            echo 'Restored backed-up original Corvantium-path files.'
        fi
    fi
    rm -f -- "$manifest"
    rmdir "$config_root/hyprland" "$config_root/shell/services" "$config_root/shell/components" "$config_root/shell" "$config_root/scripts" "$config_root" 2>/dev/null || true
    echo 'Removed manifest-managed Corvantium files.'
}

remove_session_now() {
    [[ -e "$session_dest" ]] || { echo 'No Hyprland Corvantium SDDM entry exists.'; return 0; }
    printf 'Will remove only: %s\n' "$session_dest"
    confirm 'Remove the Corvantium SDDM entry?' || { echo 'Session removal cancelled.'; return 0; }
    if [[ "$restore" == true ]]; then
        local backup
        backup="$(find "$state_root" -maxdepth 1 -type f -name 'session-backup-*.desktop' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
        if [[ -n "$backup" && -f "$backup" ]]; then
            sudo install -D -m 0644 "$backup" "$session_dest"
            echo "Restored previous session entry from $backup"
            return 0
        fi
    fi
    sudo rm -- "$session_dest"
    echo 'Removed Corvantium SDDM entry.'
}

case "$mode" in
    dry-run)
        printf 'Dry run: no files will be changed.\n'
        for i in "${!sources[@]}"; do printf '  %s -> %s\n' "$source_root/${sources[$i]}" "${destinations[$i]}"; done
        for name in "${binaries[@]}"; do printf '  symlink %s -> %s/scripts/%s\n' "$bin_root/$name" "$config_root" "$name"; done
        if [[ "$register" == true ]]; then printf '  optional system file: %s (requires separate confirmation)\n' "$session_dest"; fi
        if [[ "$remove_session" == true ]]; then printf '  optional system file removal: %s (requires separate confirmation)\n' "$session_dest"; fi
        ;;
    install)
        preflight
        printf 'Files will be installed under %s and %s.\n' "$config_root" "$bin_root"
        printf 'Existing files at those exact destinations are backed up; other desktop trees are not targets.\n'
        confirm 'Install Corvantium user files?' || { echo 'Install cancelled.'; exit 0; }
        install_user_files
        if [[ "$register" == true ]]; then register_session_now; fi
        ;;
    uninstall)
        uninstall_user_files
        if [[ "$remove_session" == true ]]; then remove_session_now; fi
        ;;
esac
