-- skip-intro.lua — Chapter-based intro skip button overlay
-- Shows a "Skip Intro" pill when playback enters an intro/opening chapter.
--
-- Logging: run mpv with --msg-level=skip_intro=trace to see all debug output

local msg = mp.msg
local assdraw = require("mp.assdraw")

msg.info("skip-intro.lua loaded")

-- ── Config ──────────────────────────────────────────────────────────
-- Base sizes at 1080p — all scaled by osd_height / 1080 at render time
local cfg = {
    pill_w        = 300,
    pill_h        = 56,
    margin_right  = 48,
    margin_bottom = 120,   -- clears the default OSC bar
    corner_r      = 8,
    border_width  = 2,
    label_size    = 30,
    hint_size     = 22,
    -- Colors (ASS BGR format) — matches track-menu.lua
    bg_color      = "40302A",  bg_alpha      = "00",  -- fully opaque
    text_color    = "ECE8E8",                          -- normal text
    bright_color  = "FFFFFF",                          -- label text
    header_color  = "FF9F4B",                          -- accent (arrow)
    border_color  = "ECE8E8",  border_alpha  = "40",  -- ~75% opaque
    dim_color     = "808080",                          -- key hint text
    -- Timing
    delay         = 1.0,       -- seconds after chapter change before showing
    fade_in       = 0.3,       -- fade-in duration in seconds
    fade_out      = 0.2,       -- fade-out duration in seconds
}

-- Chapter title patterns that trigger the skip button (matched case-insensitive)
local intro_patterns = {
    "^intro$",     "^intro%s",
    "^opening$",   "^opening%s",
    "^op$",        "^op%s",    "^op%d",
    "^prologue$",
}

-- ── State ───────────────────────────────────────────────────────────
local state = {
    visible     = false,
    overlay     = nil,
    skip_time   = nil,     -- absolute time to seek to (start of next chapter)
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

-- ── Chapter Detection ───────────────────────────────────────────────

local function is_intro(title)
    if not title or title == "" then return false end
    local lower = title:lower()
    for _, pattern in ipairs(intro_patterns) do
        if lower:match(pattern) then
            msg.debug("is_intro: matched '" .. title .. "' with pattern '" .. pattern .. "'")
            return true
        end
    end
    return false
end

local function get_next_chapter_time()
    local chapter = mp.get_property_number("chapter", -1)
    if chapter < 0 then return nil end

    local chapters = mp.get_property_native("chapter-list", {})
    local next_idx = chapter + 2  -- chapter is 0-based, Lua table is 1-based
    if next_idx > #chapters then
        msg.trace("get_next_chapter_time: intro is last chapter, no skip target")
        return nil
    end

    local next_time = chapters[next_idx].time
    msg.trace("get_next_chapter_time: next chapter at " .. tostring(next_time) .. "s")
    return next_time
end

-- ── Render ──────────────────────────────────────────────────────────

local function render()
    msg.trace("render: called, visible=" .. tostring(state.visible) .. " fade=" .. string.format("%.2f", state.fade))
    if not state.visible or state.fade <= 0 then return end

    local w, h = mp.get_osd_size()
    msg.trace("render: osd size " .. tostring(w) .. "x" .. tostring(h))
    if not w or w == 0 then
        msg.warn("render: osd size is 0, aborting")
        return
    end

    local scale = h / 1080
    local pill_w    = math.floor(cfg.pill_w * scale)
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

    -- Layout: [  ENTER   Skip Intro  ▶▶  ]
    local pad = math.floor(16 * scale)
    local gap = math.floor(10 * scale)

    -- "ENTER" hint (dim, small)
    ass:new_event()
    ass:pos(px + pad, center_y)
    ass:append("{\\an4\\bord0\\shad0\\fs" .. hint_sz ..
        "\\fnsans-serif" ..
        ass_color(cfg.dim_color) .. ass_alpha(text_a) .. "}ENTER")

    -- "Skip Intro" label (bright, bold)
    local hint_width = math.floor(58 * scale)
    ass:new_event()
    ass:pos(px + pad + hint_width + gap, center_y)
    ass:append("{\\an4\\bord0\\shad0\\fs" .. label_sz ..
        "\\fnsans-serif\\b1" ..
        ass_color(cfg.bright_color) .. ass_alpha(text_a) .. "}Skip Intro")

    -- "▶▶" arrow (accent color)
    local arrow_pad = math.floor(14 * scale)
    ass:new_event()
    ass:pos(px + pill_w - pad - arrow_pad, center_y)
    ass:append("{\\an6\\bord0\\shad0\\fs" .. label_sz ..
        "\\fnsans-serif" ..
        ass_color(cfg.header_color) .. ass_alpha(text_a) .. "}\226\150\182\226\150\182")

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

-- ── Skip Action ─────────────────────────────────────────────────────

local function skip()
    if not state.skip_time then return end
    msg.info("skip: seeking to " .. tostring(state.skip_time) .. "s")
    mp.commandv("seek", tostring(state.skip_time), "absolute")
end

-- ── Mouse Interaction ───────────────────────────────────────────────
-- The pill is clickable. To avoid swallowing clicks meant for the OSC /
-- seek bar, MBTN_LEFT is only captured while the cursor is over the pill
-- (gated by the mouse-pos observer below) — same pattern mpv's own OSC uses.

local function point_in_rect(x, y, r)
    return r and x and y and x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2
end

local function bind_click()
    if state.mouse_bound then return end
    state.mouse_bound = true
    mp.add_forced_key_binding("MBTN_LEFT", "skip-intro-click", skip)
    msg.trace("bind_click: MBTN_LEFT captured")
end

local function unbind_click()
    if not state.mouse_bound then return end
    state.mouse_bound = false
    mp.remove_key_binding("skip-intro-click")
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
    state.skip_time = nil
    state.fade = 0
    state.fade_target = 0
    state.rect = nil
    state.hover = false

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

local function begin_show()
    state.delay_timer = nil
    msg.info("show: skip target=" .. tostring(state.skip_time) .. "s")
    state.visible = true
    bind("enter", "skip-intro-enter", skip)
    animate_to(1)
end

local function schedule_show(next_time)
    cancel_delay()
    state.skip_time = next_time

    if state.visible then
        animate_to(1)
        return
    end

    state.delay_timer = mp.add_timeout(cfg.delay, begin_show)
    msg.debug("schedule_show: delay timer started (" .. cfg.delay .. "s)")
end

local function hide()
    cancel_delay()
    if not state.visible then return end
    msg.info("hide: fading out")
    animate_to(0)
end

local function force_hide()
    cancel_delay()
    if state.fade_timer then
        state.fade_timer:kill()
        state.fade_timer = nil
    end
    cleanup_overlay()
end

-- ── Chapter Change Observer ─────────────────────────────────────────

local function on_chapter_change(_, chapter)
    msg.trace("on_chapter_change: chapter=" .. tostring(chapter))

    if not chapter or chapter < 0 then
        hide()
        return
    end

    local chapters = mp.get_property_native("chapter-list", {})
    local current = chapters[chapter + 1]  -- 0-based → 1-based
    if not current then
        msg.trace("on_chapter_change: no chapter metadata")
        hide()
        return
    end

    local title = current.title
    msg.trace("on_chapter_change: title='" .. tostring(title) .. "'")

    if is_intro(title) then
        local next_time = get_next_chapter_time()
        if next_time then
            schedule_show(next_time)
        else
            hide()  -- intro is last chapter, nowhere to skip
        end
    else
        hide()
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

mp.register_event("end-file", function()
    msg.trace("end-file: cleaning up")
    force_hide()
end)

-- ── Register ───────────────────────────────────────────────────────

mp.observe_property("chapter", "number", on_chapter_change)
msg.info("skip-intro.lua: chapter observer registered")
