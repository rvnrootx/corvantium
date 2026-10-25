-- Corvantium session profile for Hyprland 0.55+. This file is always passed
-- explicitly; it never lives in or writes to ~/.config/hypr.
local home = os.getenv("HOME") or ""
local xdg = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local root = os.getenv("CORVANTIUM_CONFIG_HOME") or (xdg .. "/corvantium")

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
    animations = { enabled = true },
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
    hl.exec_cmd("qs --no-duplicate --path " .. quote(root .. "/shell"))
end

-- Super tap has a reliable Super+Space fallback. Chord bindings stay separate.
hl.bind("SUPER + SUPER_L", command(root .. "/scripts/corvantium-launch search"), {
    release = true,
    description = "Corvantium: application search",
})
hl.bind("SUPER + SPACE", command(root .. "/scripts/corvantium-launch search"), {
    description = "Corvantium: application search fallback",
})

for n = 1, 9 do
    hl.bind("SUPER + " .. n, command("hyprctl dispatch workspace " .. n), {
        description = "Corvantium: switch to workspace " .. n,
    })
end

hl.bind("SUPER + E", command(root .. "/scripts/corvantium-launch files"), { description = "Corvantium: file manager" })
hl.bind("SUPER + T", command(root .. "/scripts/corvantium-launch terminal"), { description = "Corvantium: terminal" })
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Corvantium: close focused window" })
hl.bind("SUPER + D", hl.dsp.window.float({ action = "toggle" }), { description = "Corvantium: toggle floating" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ action = "toggle" }), { description = "Corvantium: toggle fullscreen" })
hl.bind("SUPER + SHIFT + M", command(root .. "/scripts/corvantium-launch logout"), {
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
