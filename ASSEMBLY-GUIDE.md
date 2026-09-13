# DS Handheld Assembly Guide

## Your Parts

| # | Item | Details |
|---|---|---|
| 1 | **Anker USB-C to HDMI adapter** | USB-C in → standard HDMI out, 4K@60Hz |
| 2 | **Waveshare 3.5" HDMI LCD** | 480x320 IPS, standard HDMI input, 5V power |
| 3 | **chenyang FPC flat HDMI cable** | Standard HDMI to standard HDMI, 50cm, 90-degree angled |
| 4 | **iPhone** | USB-C, running iOS 26, DSEmu app installed |

---

## Step 1: Bench Test — Verify the Signal Chain

Do this first before building anything. Confirm every component works together on a desk.

### 1a. Power the Waveshare display
- Connect the Waveshare display to any **USB phone charger or power bank** via its micro-USB/USB-C power port
- The display backlight should turn on (it will show a "No Signal" message or stay blue/black)

### 1b. Connect the HDMI chain
- Plug the **Anker USB-C to HDMI adapter** into your iPhone's USB-C port
- Connect one end of the **FPC flat HDMI cable** to the Anker adapter's HDMI output
- Connect the other end of the FPC flat cable to the **Waveshare display's HDMI input**

### 1c. Test with screen mirroring
- Your iPhone should automatically mirror its screen to the Waveshare display
- You should see your iPhone's home screen on the TFT
- If nothing shows: check that the FPC cable is fully seated on both ends, and try unplugging/replugging the Anker adapter

### 1d. Test with DSEmu
- Open the **DSEmu** app on your iPhone
- Load a ROM
- The **bottom DS screen** should appear on your iPhone
- The **top DS screen** should appear on the Waveshare display
- Verify touch input still works on the iPhone screen
- Check for latency: move something in-game and see if the top screen lags behind the bottom (should be minimal)

### What to check
- [ ] Waveshare powers on and shows backlight
- [ ] iPhone detects external display (screen mirrors or DSEmu sends top screen)
- [ ] Image appears on Waveshare (not cropped, not stretched badly)
- [ ] No visible latency between iPhone bottom screen and Waveshare top screen
- [ ] Audio plays from iPhone speakers
- [ ] FPC cable bends easily without losing signal

### Troubleshooting
| Problem | Fix |
|---|---|
| No image on display | Unplug/replug adapter. Try a different HDMI port on display if it has multiple. |
| Image is cropped or wrong aspect | Use the OSD buttons on the Waveshare to adjust scaling mode |
| Flickering | Power supply issue — use a stronger USB charger (2A) for the display |
| DSEmu shows both screens on iPhone | External display not detected — unplug and replug the adapter while the app is running |

---

## Step 2: Test Display Orientation and Scaling

The DS top screen is 256x192. The Waveshare is 480x320. The RTD controller auto-scales, but you should verify:

- Is the image centered with black bars (letterboxed)? This is correct.
- Is the pixel art crisp? Our Metal shader uses nearest-neighbor filtering, so it should look sharp.
- If the image is stretched, check the Waveshare OSD menu (small buttons on the PCB) and set scaling to "1:1" or "aspect ratio" mode instead of "full screen"

---

## Step 3: Measure for Enclosure Planning

Once the signal chain works, take measurements for your enclosure design:

### Measurements to take
- [ ] **Waveshare display dimensions**: width x height x depth of the PCB + screen assembly (mm)
- [ ] **Waveshare HDMI port position**: distance from edge of board to center of HDMI connector (mm)
- [ ] **Waveshare power port position**: distance from edge to center of power connector (mm)
- [ ] **Anker adapter dimensions**: length x width x height (mm)
- [ ] **iPhone dimensions** with and without case (mm)
- [ ] **FPC cable bend radius**: how tight can it fold without losing signal? Test by bending it in a U-shape
- [ ] **FPC cable width**: measure the flat ribbon section (mm)

### Sketch the layout
Draw two rectangles (top half and bottom half of clamshell):

**Bottom half (iPhone cradle):**
```
┌──────────────────────────┐
│                          │
│   ┌──────────────────┐   │
│   │                  │   │
│   │     iPhone       │   │
│   │   (screen up)    │   │
│   │                  │   │
│   └──────┬───────────┘   │
│          │USB-C          │
│   ┌──────┴───────────┐   │
│   │  Anker adapter   │   │
│   └──────┬───────────┘   │
│          │HDMI           │
│          │(FPC cable     │
│          │ exits through │
│          │ hinge)        │
└──────────┼───────────────┘
           │
      ─────┼───── HINGE
           │
┌──────────┼───────────────┐
│          │FPC cable      │
│          │enters from    │
│          │hinge          │
│   ┌──────┴───────────┐   │
│   │ Waveshare board  │   │
│   │ (HDMI in, power) │   │
│   └──────────────────┘   │
│   ┌──────────────────┐   │
│   │                  │   │
│   │  3.5" TFT screen │   │
│   │  (faces user)    │   │
│   │                  │   │
│   └──────────────────┘   │
│                          │
│   [5V battery + boost]   │
└──────────────────────────┘
```

---

## Step 4: Enclosure Design (Future)

Once measurements are confirmed, design a 3D-printed clamshell enclosure:

- **Bottom half**: Recessed slot for iPhone, cavity for Anker adapter, FPC cable exit channel
- **Top half**: Waveshare display mounted flush, HDMI cable entry, power system cavity
- **Hinge**: Route FPC flat cable through — the cable is thin enough to pass through a laptop-style hinge barrel
- **Material**: PLA for prototyping, PETG for final version
- **Tools**: Fusion 360 or Onshape for CAD, Cura/PrusaSlicer for printing

---

## Step 5: Power System (Future)

For untethered use (no USB cable to display):

1. **LiPo battery** (3.7V, 1000-2000mAh) → **power switch** → **boost converter** (3.7V→5V) → Waveshare 5V power input
2. **TP4056 USB-C charger module** → LiPo (for recharging the battery)
3. Mount in the top half of the enclosure near the Waveshare board

---

## Step 6: Optional Physical Controls (Future)

Replace on-screen buttons with real tactile switches:

1. Wire 12 tactile buttons to an **ESP32-S3** dev board
2. Flash Bluetooth HID gamepad firmware
3. iPhone auto-detects it as a game controller via GCController framework
4. Mount buttons in the bottom half of the enclosure around the iPhone
5. DSEmu's ControllerManager.swift already handles GCController input

---

## Quick Reference: What Plugs Into What

```
iPhone USB-C port
    └─→ Anker USB-C to HDMI adapter
            └─→ FPC flat HDMI cable (standard HDMI both ends)
                    └─→ Waveshare 3.5" HDMI LCD (standard HDMI input)
                            └─→ USB phone charger (5V power for display)
```
