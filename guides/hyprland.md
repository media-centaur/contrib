# Hyprland Window Rules

Media Centaur and mpv use different fullscreen strategies to coexist (`~/.config/hypr/rules.conf`):

- **Media Centaur** uses fake fullscreen (`float` + `size` + `move`) — sized to the display without claiming Hyprland's exclusive fullscreen slot.
- **mpv** uses `fullscreen = on` — standard WM fullscreen that renders on top.

When mpv closes, Media Centaur is still covering the full screen because it never used the fullscreen slot at all.

```
# Media Center — fake fullscreen (sized to display) avoids the fullscreen slot
windowrule {
    name = media-centaur
    match:class = Media Centaur
    float = on
    size = 3840 2160
    move = 0 0
    workspace = 5
}

# mpv — float fullscreen so it doesn't disrupt media center layout
windowrule {
    name = mpv-fullscreen
    match:class = mpv
    float = on
    fullscreen = on
    workspace = 5
}
```

> **Why not `fullscreen = on` for both?** Hyprland enforces one fullscreen window per workspace. When mpv claims the fullscreen slot, the frontend loses it and can't recover when mpv exits — it shrinks to a small floating window.

> **Why not `fullscreen_state = 0 2`?** Tested — it still conflicts with mpv's fullscreen. The frontend loses its fullscreen state when mpv closes.
