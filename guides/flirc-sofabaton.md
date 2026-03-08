# FLIRC USB + Sofabaton X1S

Use a Sofabaton X1S universal remote to control the media center PC via a FLIRC USB IR receiver.

## Approach

Sofabaton's app only exposes a fixed set of device profiles with predetermined commands — you can't define arbitrary IR codes. The workaround is to let FLIRC do the mapping:

1. Pick any device profile in Sofabaton that has enough buttons.
2. Use FLIRC to learn each button press and map it to the desired keyboard key.

The Sofabaton is just an IR emitter; FLIRC is the smart part that translates each IR code to a keystroke.

## Setup

### 1. Choose a Sofabaton device profile

In the Sofabaton app, add a device. The brand/model doesn't matter since FLIRC will learn whatever codes it sends — pick one with many buttons, including color keys (red/green/blue/yellow), navigation, and transport controls.

**Recommended default:** Search for **Motorola**, model **DCT-603x** (a cable STB with a rich button set).

Avoid picking a device you actually own — the IR codes would conflict. If you need more buttons than one profile provides, add a second "device" and learn those codes too.

### 2. Pair buttons in FLIRC

Install `flirc_util` (AUR: `flirc-bin`) and plug in the FLIRC USB receiver.

For each button:

```sh
# Start recording — FLIRC waits for an IR signal
flirc_util record <key>

# Then press the corresponding button on the Sofabaton
```

Where `<key>` is any key name FLIRC recognizes: `up`, `down`, `left`, `right`, `enter`, `escape`, `space`, `play_pause`, `media_stop`, `media_next`, `media_prev`, `vol_up`, `vol_down`, `mute`, `a`-`z`, `f1`-`f12`, etc.

Example mapping:

```sh
flirc_util record up           # D-pad up
flirc_util record down         # D-pad down
flirc_util record left         # D-pad left
flirc_util record right        # D-pad right
flirc_util record enter        # OK/Select
flirc_util record escape       # Back
flirc_util record space        # Play/Pause
flirc_util record media_stop   # Stop
```

### 3. Verify

```sh
# List all recorded keys
flirc_util settings

# Delete a single key to re-record it
flirc_util delete <key>

# Erase all mappings and start over
flirc_util format
```

## Tips

- FLIRC mappings are stored on the device itself — they persist across machines without any software running.
- Point the Sofabaton at the FLIRC receiver (small IR window on the USB dongle). Line of sight is required.
- If a button sends a repeated IR code that FLIRC already knows, it will reject the recording. Use `flirc_util delete` to clear the conflict first.
- The `flirc_util` GUI (`flirc`) is available but the CLI is faster for bulk setup.
