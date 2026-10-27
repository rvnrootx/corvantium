-- Corvantium session profile for Hyprland 0.55+. This file is always passed
-- explicitly; it never lives in or writes to ~/.config/hypr.
local home = os.getenv("HOME") or ""
local xdg = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local root = os.getenv("CORVANTIUM_CONFIG_HOME")
if not root then
    root = xdg .. "/corvantium"
end

local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function command(text)
    return hl.dsp.exec_cmd(text)
end

hl.env("XDG_SESSION_DESKTOP", "Corvantium")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 9,
        border_size = 2,
        ["col.active_border"] = "rgb(d29363)",
        ["col.inactive_border"] = "rgb(293533)",
        layout = "dwindle",
    },
    decoration = {
        rounding = 9,
        active_opacity = 1.0,
        inactive_opacity = 0.96,
        shadow = { enabled = true, range = 14, render_power = 3, color = "rgba(07100dcc)" },
        blur = { enabled = true, size = 4, passes = 2, vibrancy = 0.08 },
    },
    -- Keep legacy XWayland surfaces crisp on this 1.5x display. This is scoped
    -- to Corvantium; the user's primary Hyprland profile is not modified.
    xwayland = { force_zero_scaling = true },
    animations = { enabled = false },
    dwindle = { preserve_split = true },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
    input = {
        kb_layout = os.getenv("CORVANTIUM_KB_LAYOUT") or "us",
        follow_mouse = 1,
        sensitivity = 0,
    },
    binds = { workspace_back_and_forth = true, allow_workspace_cycles = true },
})

-- Use the dedicated Quickshell tree. The shell itself has no permanent widgets.
-- Config verification skips autostart so the check does not launch a UI.
if os.getenv("CORVANTIUM_CONFIG_CHECK") ~= "1" then
    hl.on("hyprland.start", function()
        hl.exec_cmd("qs --no-duplicate --path " .. quote(root .. "/shell"))
    end)
end

-- Super tap has a reliable Super+Space fallback. Chord bindings stay separate.
hl.bind("SUPER + SUPER_L", command(root .. "/scripts/corvantium-launch search"), {
    release = true,
    description = "Corvantium: application search",
})
hl.bind("SUPER + SPACE", command(root .. "/scripts/corvantium-launch search"), {
    description = "Corvantium: application search fallback",
})
hl.bind("SUPER + G", command("qs --path " .. quote(root .. "/shell") .. " ipc call corvantium toggleOverlay"), {
    description = "Corvantium: toggle the quick overlay",
})
hl.bind("SUPER + SHIFT + A", command(root .. "/scripts/corvantium-launch screen-search"), {
    description = "Corvantium: select a screen region and search it",
})
hl.bind("SUPER + SHIFT + X", command(root .. "/scripts/corvantium-launch screen-ocr"), {
    description = "Corvantium: copy text from a selected screen region",
})
hl.bind("SUPER + SHIFT + G", command(root .. "/scripts/corvantium-launch music-identify"), {
    description = "Corvantium: recognize music playing on this device",
})
hl.bind("SUPER + SHIFT + S", command(root .. "/scripts/corvantium-launch screen-screenshot"), {
    description = "Corvantium: capture a selected screen region",
})
hl.bind("SUPER + SHIFT + W", command(root .. "/scripts/corvantium-launch wallpaper"), {
    description = "Corvantium: choose a wallpaper",
})
hl.bind("Print", command(root .. "/scripts/corvantium-launch screenshot"), {
    description = "Corvantium: open the screenshot tool",
})
hl.bind("SUPER + V", command(root .. "/scripts/corvantium-launch clipboard"), { description = "Corvantium: clipboard history" })
hl.bind("SUPER + SLASH", command(root .. "/scripts/corvantium-launch keybinds"), {
    description = "Corvantium: show keybindings",
})

for n = 1, 9 do
    hl.bind("SUPER + " .. n, hl.dsp.focus({ workspace = tostring(n) }), {
        description = "Corvantium: switch to workspace " .. n,
    })
    hl.bind("SUPER + SHIFT + " .. n, hl.dsp.window.move({ workspace = tostring(n), follow = false }), {
        description = "Corvantium: move window to workspace " .. n,
    })
end
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = "10" }), { description = "Corvantium: switch to workspace 10" })
hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = "10", follow = false }), { description = "Corvantium: move window to workspace 10" })
for key, direction in pairs({ LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d" }) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = direction }), { description = "Corvantium: focus window " .. direction })
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = direction }), { description = "Corvantium: move window " .. direction })
end
hl.bind("SUPER + CTRL + LEFT", hl.dsp.focus({ workspace = "r-1" }), { description = "Corvantium: previous workspace" })
hl.bind("SUPER + CTRL + RIGHT", hl.dsp.focus({ workspace = "r+1" }), { description = "Corvantium: next workspace" })

hl.bind("SUPER + E", command(root .. "/scripts/corvantium-launch files"), { description = "Corvantium: file manager" })
hl.bind("SUPER + T", command(root .. "/scripts/corvantium-launch terminal"), { description = "Corvantium: terminal" })
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Corvantium: close focused window" })
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }), { description = "Corvantium: toggle maximize" })
hl.bind("SUPER + ALT + SPACE", hl.dsp.window.float({ action = "toggle" }), { description = "Corvantium: toggle floating" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ action = "toggle" }), { description = "Corvantium: toggle fullscreen" })
hl.bind("SUPER + P", hl.dsp.window.pin(), { description = "Corvantium: pin focused window" })
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special(""), { description = "Corvantium: toggle scratch workspace" })
hl.bind("SUPER + TAB", command("qs --path " .. quote(root .. "/shell") .. " ipc call corvantium toggleOverlay"), { description = "Corvantium: open workspace and controls overlay" })
hl.bind("SUPER + J", command("qs --path " .. quote(root .. "/shell") .. " ipc call corvantium toggleBar"), { description = "Corvantium: show or hide the top bar" })
hl.bind("SUPER + M", command("qs --path " .. quote(root .. "/shell") .. " ipc call corvantium toggleMedia"), { description = "Corvantium: toggle media controls" })
hl.bind("SUPER + RETURN", command(root .. "/scripts/corvantium-launch terminal"), { description = "Corvantium: terminal" })
hl.bind("SUPER + W", command(root .. "/scripts/corvantium-launch browser"), { description = "Corvantium: browser" })
hl.bind("SUPER + SHIFT + M", command("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { description = "Corvantium: toggle audio mute" })
hl.bind("SUPER + SHIFT + L", command("loginctl suspend"), { description = "Corvantium: suspend system" })
hl.bind("SUPER + L", command("loginctl lock-session"), { description = "Corvantium: lock session" })
hl.bind("SUPER + SHIFT + B", command("playerctl previous"), { description = "Corvantium: previous track" })
hl.bind("SUPER + SHIFT + N", command("playerctl next"), { description = "Corvantium: next track" })
hl.bind("SUPER + SHIFT + P", command("playerctl play-pause"), { description = "Corvantium: toggle playback" })
hl.bind("CTRL + ALT + DELETE", command(root .. "/scripts/corvantium-launch logout"), {
    description = "Corvantium: log out to the session selector",
})

hl.bind("XF86AudioRaiseVolume", command("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true })
hl.bind("XF86AudioLowerVolume", command("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true })
hl.bind("XF86AudioMute", command("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute", command("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))
hl.bind("XF86AudioPlay", command("playerctl play-pause"))
hl.bind("XF86AudioNext", command("playerctl next"))
hl.bind("XF86AudioPrev", command("playerctl previous"))
hl.bind("XF86MonBrightnessUp", command(root .. "/scripts/corvantium-hardware brightness-up"), { repeating = true })
hl.bind("XF86MonBrightnessDown", command(root .. "/scripts/corvantium-hardware brightness-down"), { repeating = true })
hl.bind("SUPER + SHIFT + C", command(root .. "/scripts/corvantium-hardware camera-toggle"), {
    description = "Corvantium: toggle supported V4L2 privacy control",
})
