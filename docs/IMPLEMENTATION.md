# Corvantium implementation notes

## Session boundary

Corvantium uses the installed Hyprland executable with a dedicated Lua profile passed as `--config`. Its shell, settings, and helper scripts are installed under `~/.config/corvantium`; launcher symlinks are under `~/.local/bin`. No files are written to the standard Hyprland, Waybar, or Quickshell configuration roots. SDDM registration is a separate opt-in operation that writes `/usr/share/wayland-sessions/hyprland-corvantium.desktop` with the visible name **Hyprland Corvantium** and never changes the default session or touches Serpantinum's entry.

## Components

- `hyprland/main.lua`: compositor options, keybindings, and Corvantium shell startup.
- `shell/shell.qml`: Quickshell's transparent per-monitor shell, full-feature capsule bar, per-monitor workspace indicators, audio mixer, media/lyrics panel, calendar/weather dashboard, and session/settings panel. `shell/components/FluidPanel.qml` draws the shared animated liquid panel and connector used by the feature popups.
- `shell/services/weather.py`: opt-in city geocoding and Open-Meteo cache/fallback.
- `shell/services/lyrics.py`: LRCLIB exact metadata lookup, LRC parsing, local cache, and browser search URL.
- `scripts/`: session/version guard, app detection, optional hardware controls, installer/uninstaller.

Quickshell's PipeWire API manages endpoints and streams. MPRIS player controls use the player capability flags. NetworkManager, BlueZ, and UPower status use Quickshell's built-in service modules where those daemons exist. Missing services leave explicit unavailable states.

## Validation

Run `python3 -m unittest discover -s tests -v`, `bash -n scripts/*.sh scripts/corvantium-*`, `python3 -m py_compile shell/services/*.py`, and `git diff --check`. Verify the compositor profile with `CORVANTIUM_CONFIG_CHECK=1 Hyprland --verify-config --config hyprland/main.lua`; the environment flag prevents shell autostart during verification. Run `qmllint shell/shell.qml` with the local Quickshell QML import paths when a compatible linter is available. Do not run `scripts/install.sh --install` as a development check.

In the current sandbox, the Hyprland config check passes. Python, shell syntax, and the service unit checks pass. The installed `qmllint` exits with status 255 without a diagnostic, and offscreen Quickshell parsing stops when it cannot load the `PanelWindow` backend. Starting a disposable Wayland compositor is blocked by the sandbox's socket restrictions, so full QML runtime behavior still needs validation in a separate test session. No install or active desktop session was started.

Hardware controls, playback behavior, external device selection, multiple physical monitors, and SDDM session switching require a real user session and are not mocked by the static checks. Weather is opt-in by city; the client uses [Open-Meteo](https://open-meteo.com/) and the shell provides an attribution link for its CC BY 4.0 data. Lyrics lookup uses [LRCLIB](https://lrclib.net/docs), observes a request gap and rate-limit responses, and caches results locally.
