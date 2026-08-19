-- next-episode.lua — Chapter-based "Next Episode" button + auto-play countdown
-- Shows a "Next Episode" pill during a credits/outro chapter when the
-- playlist has a queued successor (Media Centaur appends it — ADR-062).
-- ENTER or a click advances with playlist-next; end-of-file advances on
-- its own, so the pill only ever *shortens* the credits, never skips
-- content automatically.
--
-- In the final seconds of the file the pill switches to countdown mode —
-- "Next episode in Ns" — regardless of chapters, so auto-play never
-- lands unannounced. ESC cancels: the queued entry is
-- removed and `user-data/media-centaur/auto-advance-cancelled` is set,
-- which the backend observes to stop re-appending (its queue check is
-- otherwise self-stabilizing).
--
-- Logging: run mpv with --msg-level=next_episode=trace to see all debug output

local msg = mp.msg
local assdraw = require("mp.assdraw")

msg.info("next-episode.lua loaded")

-- ── Config ──────────────────────────────────────────────────────────
-- Base sizes at 1080p — all scaled by osd_height / 1080 at render time
local cfg = {
    pill_w        = 330,
    countdown_w   = 380,   -- countdown pill: sized to its content, same
                           -- density as skip-intro's 300 — no dead middle
    pill_h        = 56,
    margin_right  = 48,
    margin_bottom = 120,   -- clears the default OSC bar
    corner_r      = 8,
    border_width  = 2,
    label_size    = 30,
    hint_size     = 22,
    -- Colors (ASS BGR format) — matches track-menu.lua / skip-intro.lua
    bg_color      = "40302A",  bg_alpha      = "00",  -- fully opaque
    text_color    = "ECE8E8",                          -- normal text
    bright_color  = "FFFFFF",                          -- label text
    header_color  = "FF9F4B",                          -- accent (arrow, bar)
    border_color  = "ECE8E8",  border_alpha  = "40",  -- ~75% opaque
    dim_color     = "808080",                          -- key hint text
    -- Timing
    delay         = 1.0,       -- seconds after chapter change before showing (skip mode)
    fade_in       = 0.3,       -- fade-in duration in seconds
    fade_out      = 0.2,       -- fade-out duration in seconds
    countdown_window = 20,     -- seconds before EOF the countdown mode begins
    -- A credits chapter must start at or after this fraction of the
    -- runtime — mirrors the backend's ChapterCompletion floor, and keeps
    -- an "Opening Credits" chapter at t=0 from triggering the pill.
    outro_floor   = 0.80,
}

-- Chapter title patterns that mark rolling credits (matched
-- case-insensitive, whole-word via %f frontiers). Mirrors the backend's
-- ChapterCompletion: `credits` covers "End Credits" / "Closing Credits" /
-- "Credits"; `outro` covers "Outro". Bare "Ending" is deliberately
-- excluded (often the story climax).
local credits_patterns = {
    "%f[%a]credits%f[%A]",
    "%f[%a]outro%f[%A]",
}

-- ── State ───────────────────────────────────────────────────────────
local state = {
    visible     = false,
    mode        = nil,     -- "skip" (credits pill) | "countdown" (final seconds)
    cancelled   = false,   -- viewer cancelled auto-advance — pill stays away
    remaining   = nil,     -- last observed time-remaining (seconds)
    last_second = nil,     -- last rendered whole second (repaint throttle)
    overlay     = nil,
    fade        = 0,       -- current fade level (0 = invisible, 1 = fully visible)
    fade_target = 0,       -- target fade level
    fade_timer  = nil,     -- periodic timer for fade animation
    delay_timer = nil,     -- one-shot timer for initial delay
    rect        = nil,     -- last-rendered pill bounds {x1,y1,x2,y2} for hit-testing
    hover       = false,   -- cursor is currently over the pill
    mouse_bound = false,   -- MBTN_LEFT forced binding is active (only while hovering)
}

local bindings = {}

-- ── Helpers ─────────────────────────────────────────────────────────

local function ass_color(bgr)
    return "\\1c&H" .. bgr .. "&"
end

local function ass_alpha(a)
    return "\\1a&H" .. a .. "&"
end

local function ass_border_color(bgr)
    return "\\3c&H" .. bgr .. "&"
end

local function ass_border_alpha(a)
    return "\\3a&H" .. a .. "&"
end

-- Interpolate alpha from fully transparent (FF) toward target based on fade
local function faded(target_hex)
    local target = tonumber(target_hex, 16)
    local alpha = math.floor(0xFF - (0xFF - target) * state.fade)
    return string.format("%02X", alpha)
end

-- ── Detection ───────────────────────────────────────────────────────

local function is_credits(title)
    if not title or title == "" then return false end
    local lower = title:lower()
    for _, pattern in ipairs(credits_patterns) do
        if lower:match(pattern) then
            msg.debug("is_credits: matched '" .. title .. "' with pattern '" .. pattern .. "'")
            return true
        end
    end
    return false
end

local function has_next_playlist_entry()
    local count = mp.get_property_number("playlist-count", 1)
    local pos = mp.get_property_number("playlist-pos", 0)
    local has_next = count - pos > 1
    msg.trace("has_next_playlist_entry: count=" .. count .. " pos=" .. pos)
    return has_next
end

-- The current chapter counts as rolling credits when its title names it
-- so AND it starts in the back stretch of the file.
local function in_credits_chapter()
    local chapter = mp.get_property_number("chapter", -1)
    if chapter < 0 then return false end

    local chapters = mp.get_property_native("chapter-list", {})
    local current = chapters[chapter + 1]  -- 0-based → 1-based
    if not current or not is_credits(current.title) then return false end

    local duration = mp.get_property_number("duration")
    if not duration or duration <= 0 then return false end

    if (current.time or 0) < duration * cfg.outro_floor then
        msg.debug("in_credits_chapter: '" .. tostring(current.title) ..
            "' starts before the outro floor, ignoring")
        return false
    end

    return true
end

-- The countdown window is open: a successor is queued and the file ends
-- within cfg.countdown_window seconds. Pausing pauses the countdown too —
-- honest, since the advance happens at EOF and EOF isn't approaching.
local function in_countdown_window()
    return state.remaining ~= nil
        and state.remaining > 0
        and state.remaining <= cfg.countdown_window
end

-- ── Render ──────────────────────────────────────────────────────────

local function render()
    msg.trace("render: called, visible=" .. tostring(state.visible) ..
        " mode=" .. tostring(state.mode) .. " fade=" .. string.format("%.2f", state.fade))
    if not state.visible or state.fade <= 0 then return end

    local w, h = mp.get_osd_size()
    msg.trace("render: osd size " .. tostring(w) .. "x" .. tostring(h))
    if not w or w == 0 then
        msg.warn("render: osd size is 0, aborting")
        return
    end

    local countdown = state.mode == "countdown"

    local scale = h / 1080
    local pill_w    = math.floor((countdown and cfg.countdown_w or cfg.pill_w) * scale)
    local pill_h    = math.floor(cfg.pill_h * scale)
    local margin_r  = math.floor(cfg.margin_right * scale)
    local margin_b  = math.floor(cfg.margin_bottom * scale)
    local corner_r  = math.floor(cfg.corner_r * scale)
    local border_w  = math.max(1, math.floor(cfg.border_width * scale))
    local label_sz  = math.floor(cfg.label_size * scale)
    local hint_sz   = math.floor(cfg.hint_size * scale)

    -- Pill position (bottom-right)
    local px = w - pill_w - margin_r
    local py = h - pill_h - margin_b
    local center_y = py + pill_h / 2

    -- Record bounds so the mouse observer can hit-test clicks/hover
    state.rect = { x1 = px, y1 = py, x2 = px + pill_w, y2 = py + pill_h }

    -- Fade-adjusted alphas
    local bg_a = faded(cfg.bg_alpha)
    local text_a = faded("00")

    -- Hover brightens the border to the accent color for a clickable affordance
    local border_c = state.hover and cfg.header_color or cfg.border_color
    local border_a = state.hover and faded("00") or faded(cfg.border_alpha)

    local ass = assdraw.ass_new()

    -- Background pill
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord0\\shad0" ..
        ass_color(cfg.bg_color) .. ass_alpha(bg_a) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + pill_w, py + pill_h, corner_r)
    ass:draw_stop()

    -- Border
    ass:new_event()
    ass:pos(0, 0)
    ass:append("{\\an7\\bord" .. border_w .. "\\shad0" ..
        "\\1a&HFF&" ..
        ass_border_color(border_c) .. ass_border_alpha(border_a) ..
        "\\p1}")
    ass:draw_start()
    ass:round_rect_cw(px, py, px + pill_w, py + pill_h, corner_r)
    ass:draw_stop()

    local pad = math.floor(16 * scale)
    local gap = math.floor(10 * scale)

    if countdown then
        -- Layout: [ ENTER  Next episode in 12s  ESC Cancel ]
        -- Same single-row density as skip-intro — no bar, no dead space;
        -- the ticking seconds are the countdown.
        local seconds = math.max(1, math.ceil(state.remaining or 0))

        -- "ENTER" hint (dim, small)
        ass:new_event()
        ass:pos(px + pad, center_y)
        ass:append("{\\an4\\bord0\\shad0\\fs" .. hint_sz ..
            "\\fnsans-serif" ..
            ass_color(cfg.dim_color) .. ass_alpha(text_a) .. "}ENTER")

        -- "Next episode in Ns" label (bright, bold)
        local hint_width = math.floor(58 * scale)
        ass:new_event()
        ass:pos(px + pad + hint_width + gap, center_y)
        ass:append("{\\an4\\bord0\\shad0\\fs" .. label_sz ..
            "\\fnsans-serif\\b1" ..
            ass_color(cfg.bright_color) .. ass_alpha(text_a) ..
            "}Next episode in " .. seconds .. "s")

        -- "ESC Cancel" hint (dim, right-aligned)
        ass:new_event()
        ass:pos(px + pill_w - pad, center_y)
        ass:append("{\\an6\\bord0\\shad0\\fs" .. hint_sz ..
            "\\fnsans-serif" ..
            ass_color(cfg.dim_color) .. ass_alpha(text_a) .. "}ESC Cancel")
    else
        -- Layout: [  ENTER   Next Episode  ▶▶  ]

        -- "ENTER" hint (dim, small)
        ass:new_event()
        ass:pos(px + pad, center_y)
        ass:append("{\\an4\\bord0\\shad0\\fs" .. hint_sz ..
            "\\fnsans-serif" ..
            ass_color(cfg.dim_color) .. ass_alpha(text_a) .. "}ENTER")

        -- "Next Episode" label (bright, bold)
        local hint_width = math.floor(58 * scale)
        ass:new_event()
        ass:pos(px + pad + hint_width + gap, center_y)
        ass:append("{\\an4\\bord0\\shad0\\fs" .. label_sz ..
            "\\fnsans-serif\\b1" ..
            ass_color(cfg.bright_color) .. ass_alpha(text_a) .. "}Next Episode")

        -- "▶▶" arrow (accent color)
        local arrow_pad = math.floor(14 * scale)
        ass:new_event()
        ass:pos(px + pill_w - pad - arrow_pad, center_y)
        ass:append("{\\an6\\bord0\\shad0\\fs" .. label_sz ..
            "\\fnsans-serif" ..
            ass_color(cfg.header_color) .. ass_alpha(text_a) .. "}\226\150\182\226\150\182")
    end

    -- Apply overlay
    if not state.overlay then
        state.overlay = mp.create_osd_overlay("ass-events")
        msg.trace("render: created new overlay object")
    end
    state.overlay.res_x = w
    state.overlay.res_y = h
    state.overlay.data = ass.text
    state.overlay:update()
end

-- ── Actions ─────────────────────────────────────────────────────────

local function advance()
    if not state.visible then return end
    msg.info("advance: playlist-next")
    mp.commandv("playlist-next")
end

-- Cancel auto-advance: drop the queued successor and tell the backend so
-- its self-stabilizing queue check doesn't append it right back
-- (MpvSession observes the user-data property and sets chain_cancelled).
local function cancel()
    if not state.visible or state.mode ~= "countdown" then return end

    local count = mp.get_property_number("playlist-count", 1)
    if count > 1 then
        msg.info("cancel: removing queued playlist entry " .. (count - 1))
        mp.commandv("playlist-remove", tostring(count - 1))
    end

    mp.set_property_native("user-data/media-centaur/auto-advance-cancelled", true)
    state.cancelled = true
    -- The ESC binding hides the pill right after cancelling
end

-- ── Mouse Interaction ───────────────────────────────────────────────
-- The pill is clickable. To avoid swallowing clicks meant for the OSC /
-- seek bar, MBTN_LEFT is only captured while the cursor is over the pill
-- (gated by the mouse-pos observer below) — same pattern skip-intro uses.

local function point_in_rect(x, y, r)
    return r and x and y and x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2
end

local function bind_click()
    if state.mouse_bound then return end
    state.mouse_bound = true
    mp.add_forced_key_binding("MBTN_LEFT", "next-episode-click", advance)
    msg.trace("bind_click: MBTN_LEFT captured")
end

local function unbind_click()
    if not state.mouse_bound then return end
    state.mouse_bound = false
    mp.remove_key_binding("next-episode-click")
    msg.trace("unbind_click: MBTN_LEFT released")
end

local function on_mouse_move(_, pos)
    local inside = state.visible and point_in_rect(pos and pos.x, pos and pos.y, state.rect)
    if inside == state.hover then return end

    state.hover = inside
    if inside then bind_click() else unbind_click() end
    render()  -- repaint border in hover/non-hover style
end

-- ── Overlay Cleanup ────────────────────────────────────────────────

local function cleanup_overlay()
    msg.debug("cleanup_overlay")
    state.visible = false
    state.mode = nil
    state.fade = 0
    state.fade_target = 0
    state.rect = nil
    state.hover = false
    state.last_second = nil

    unbind_click()
    for _, name in ipairs(bindings) do
        mp.remove_key_binding(name)
    end
    bindings = {}

    if state.overlay then
        state.overlay:remove()
        state.overlay = nil
    end
end

-- ── Fade Animation ─────────────────────────────────────────────────

local function ensure_fade_timer()
    if state.fade_timer then return end
    if state.fade == state.fade_target then return end

    state.fade_timer = mp.add_periodic_timer(1 / 60, function()
        local dt = 1 / 60
        if state.fade < state.fade_target then
            state.fade = math.min(state.fade + dt / cfg.fade_in, state.fade_target)
        elseif state.fade > state.fade_target then
            state.fade = math.max(state.fade - dt / cfg.fade_out, state.fade_target)
        end

        render()

        if state.fade == state.fade_target then
            state.fade_timer:kill()
            state.fade_timer = nil
            if state.fade <= 0 then
                cleanup_overlay()
            end
        end
    end)
end

local function animate_to(target)
    state.fade_target = target
    ensure_fade_timer()
end

-- ── Show / Hide Lifecycle ───────────────────────────────────────────

local function cancel_delay()
    if state.delay_timer then
        state.delay_timer:kill()
        state.delay_timer = nil
    end
end

local function bind(key, name, fn)
    bindings[#bindings + 1] = name
    mp.add_forced_key_binding(key, name, fn)
end

local function hide()
    cancel_delay()
    if not state.visible then return end
    msg.info("hide: fading out")
    animate_to(0)
end

-- Countdown mode additionally captures ESC for cancel; skip mode only
-- ENTER. Rebound whenever the mode changes while visible.
local function bind_for_mode()
    for _, name in ipairs(bindings) do
        mp.remove_key_binding(name)
    end
    bindings = {}

    bind("enter", "next-episode-enter", advance)
    if state.mode == "countdown" then
        bind("ESC", "next-episode-cancel", function()
            cancel()
            hide()
        end)
    end
end

local function begin_show(mode)
    state.delay_timer = nil
    msg.info("show: next-episode pill (" .. mode .. ")")
    state.visible = true
    state.mode = mode
    bind_for_mode()
    animate_to(1)
end

local function set_mode(mode)
    if state.visible then
        if state.mode ~= mode then
            msg.debug("set_mode: " .. tostring(state.mode) .. " → " .. mode)
            state.mode = mode
            bind_for_mode()
            render()
        end
        cancel_delay()
        animate_to(1)
        return
    end

    if mode == "countdown" then
        -- No courtesy delay when the file is about to end
        cancel_delay()
        begin_show(mode)
        return
    end

    if state.delay_timer then return end
    state.delay_timer = mp.add_timeout(cfg.delay, function() begin_show(mode) end)
    msg.debug("set_mode: delay timer started (" .. cfg.delay .. "s)")
end

local function force_hide()
    cancel_delay()
    if state.fade_timer then
        state.fade_timer:kill()
        state.fade_timer = nil
    end
    cleanup_overlay()
end

-- ── Evaluation ──────────────────────────────────────────────────────
-- Re-run on chapter changes, playlist-count changes AND time-remaining
-- ticks: the successor is appended by the backend shortly after file
-- load, and the countdown window opens purely on remaining time —
-- chapters or not, auto-play never lands unannounced.

local function evaluate()
    if state.cancelled then
        hide()
        return
    end

    if not has_next_playlist_entry() then
        hide()
        return
    end

    if in_countdown_window() then
        set_mode("countdown")
    elseif in_credits_chapter() then
        set_mode("skip")
    else
        hide()
    end
end

local function on_time_remaining(_, remaining)
    state.remaining = remaining
    evaluate()

    -- Repaint at whole-second granularity while the countdown shows
    if state.visible and state.mode == "countdown" then
        local second = remaining and math.ceil(remaining) or nil
        if second ~= state.last_second then
            state.last_second = second
            render()
        end
    end
end

-- ── Re-render on OSD resize ────────────────────────────────────────

mp.observe_property("osd-width", "number", function()
    if state.visible then render() end
end)
mp.observe_property("osd-height", "number", function()
    if state.visible then render() end
end)

-- ── Track cursor for clickable pill (hover + click hit-testing) ────
mp.observe_property("mouse-pos", "native", on_mouse_move)

-- ── Cleanup on file end ────────────────────────────────────────────
-- `cancelled` deliberately survives: after a cancel the playlist ends at
-- this file, and the backend's chain_cancelled is sticky for the session.

mp.register_event("end-file", function()
    msg.trace("end-file: cleaning up")
    force_hide()
end)

-- ── Register ───────────────────────────────────────────────────────

mp.observe_property("chapter", "number", evaluate)
mp.observe_property("playlist-count", "number", evaluate)
mp.observe_property("time-remaining", "number", on_time_remaining)
msg.info("next-episode.lua: chapter + playlist + time-remaining observers registered")
