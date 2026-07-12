-- hdr-display.lua — flip the Hyprland output into HDR mode while HDR
-- content plays, and restore SDR when it ends. The desktop stays SDR
-- (where it looks right); the TV gets a real PQ signal only for HDR
-- films, doing its own tone mapping (requires target-colorspace-hint=yes
-- in mpv.conf). Debug: mpv --msg-level=hdr_display=debug <file>
--
-- Expect a few seconds of black when playback starts/stops an HDR file:
-- the TV re-locks the HDMI link on the mode change. Same as a console.

local msg = require("mp.msg")

local cfg = {
    -- Must mirror the monitor line in ~/.config/hypr/hyprland.conf so the
    -- revert lands back on the compositor's steady state.
    sdr_monitor = "HDMI-A-1,3840x2160@120,0x0,1.0",
    hdr_monitor = "HDMI-A-1,3840x2160@120,0x0,1.0, bitdepth, 10, cm, hdr, sdrbrightness, 3.0, sdrsaturation, 1.0",
}

local state = {
    engaged = false, -- true while we have switched the output to HDR
}

local function set_monitor(line)
    local res = mp.command_native({
        name = "subprocess",
        args = { "hyprctl", "keyword", "monitor", line },
        playback_only = false,
        capture_stdout = true,
    })
    if res and res.status == 0 then
        return true
    end
    msg.warn("hyprctl keyword monitor failed: " .. ((res and res.stdout) or "no result"))
    return false
end

local function engage()
    if state.engaged then
        return
    end
    msg.info("HDR content detected — switching display to HDR mode")
    if set_monitor(cfg.hdr_monitor) then
        state.engaged = true
    end
end

local function revert()
    if not state.engaged then
        return
    end
    msg.info("restoring display to SDR mode")
    if set_monitor(cfg.sdr_monitor) then
        state.engaged = false
    end
end

-- gamma is the video's transfer function: "pq"/"hlg" mean HDR. It is nil
-- briefly between playlist entries — only a definite SDR value reverts,
-- so an HDR → HDR playlist transition doesn't bounce the TV twice.
mp.observe_property("video-params/gamma", "string", function(_, gamma)
    msg.debug("video-params/gamma = " .. (gamma or "nil"))
    if gamma == "pq" or gamma == "hlg" then
        engage()
    elseif gamma ~= nil then
        revert()
    end
end)

mp.register_event("shutdown", revert)
