# two-phone-ds-emu

An experimental iOS melonDS fork that runs the same Nintendo DS game on two
phones. The controller phone renders the bottom screen and owns all touch/button
input; the display phone renders the top screen. Frames are reproduced locally
on each phone—no video is streamed.

The melonDS dependency is vendored under `melonDS/` so a normal clone contains
everything needed to generate and build the Xcode project.

## What this prototype proves

Normal two-phone play uses Network.framework and Bonjour to advertise and find
the controller automatically over the local network, including peer-to-peer
interfaces. The command-line simulator proof retains a fixed-address TCP mode
for repeatability.
At startup, both instances verify the ROM SHA-256. The controller then sends a
full melonDS snapshot so both emulators begin from identical CPU, memory, RTC,
GPU, SPU, cartridge, and save state.

For every subsequent frame:

1. The controller sends an absolute key/touch state tagged with a frame number.
2. Both instances apply it before running that frame.
3. A dedicated controller-side receiver collects display acknowledgements while
   the controller continues emulating at its 60 fps cadence.
4. The controller may lead by at most four unacknowledged frames. If the window
   fills, it waits for the oldest acknowledgement before advancing.
5. At configured checkpoints, both hash their complete savestate and both
   framebuffers. Any difference fails the session.

Checkpoint frames remain hard barriers: the controller drains the complete
window and does not send another input until the display's digest matches. The
default four-frame window can be overridden for diagnostics with
`--two-phone-frame-window`; values are clamped to 1–8. Protocol v3 also reports
the display's average and maximum per-frame emulation/render time at each
checkpoint.

### Latest verified run

On 2026-09-12, the supplied HeartGold ROM completed 480 frames both in dedicated
simulators and on a physical iPhone 15 Pro Max plus iPhone SE (3rd generation).
All eight periodic whole-state and dual-framebuffer checkpoints matched, and
the physical devices produced the same final digest as the simulators. The
physical run used fixed-address local-network TCP with strict per-frame
acknowledgement; see
`TEST-RESULTS.md` and the `physical-*-report.json` files under `artifacts/`.
The self-starting path was separately verified in two simulators with saved
roles and no role, host, IP address, port, or ROM launch arguments.

## Run the HeartGold simulator proof

Prerequisites: Xcode with an iOS Simulator runtime, `xcodegen`, and `jq`.

```bash
./scripts/run-simulator-proof.sh \
  '/Users/paras.adhikary/Downloads/Pokemon - HeartGold Version (USA).nds'
```

The script creates/reuses dedicated iPhone 15 Pro Max and iPhone SE (3rd
generation) simulators, copies the ROM only into their app containers, runs 480
frames with scripted A, Start, Right, and stylus states, and writes reports and
screenshots under `artifacts/`.

Override the run length with `TWO_PHONE_FRAMES=1200`. The ROM, save files, build
products, and generated artifacts are excluded from source control.

## Run on two physical iPhones

After the signed app has been installed on both phones, normal play does not
need a Mac, Terminal commands, a cable, or an IP address:

1. Keep Wi-Fi enabled on both phones and open **TwoPhone DS** on each one.
2. On each phone, choose the same `.nds` ROM. A ROM already stored in the app is
   selected automatically.
3. Tap **Controller** on the phone that will show the bottom screen and controls.
4. Tap **Top Display** on the other phone.
5. Tap **Allow** if iOS asks for Local Network access.

The role and ROM are remembered. On later sessions, just open the app on both
phones; either phone may be opened first, and they will wait for and discover
each other automatically. The status bar reports searching, connecting, ROM
validation, snapshot transfer, and lockstep play.

If either phone leaves the app, the live synchronization connection is closed
before iOS suspends it. Returning to the app automatically restarts discovery;
the controller sends a fresh snapshot of its current game state and lockstep
play resumes without setup or Mac commands.

To change a phone's role or ROM, tap **Setup** in the status bar, choose **Reset
Setup**, then force-quit and reopen the app.

The launch-argument interface remains available for repeatable simulator and
diagnostic runs, but it is no longer required for ordinary phone use.

## Current boundary

This validates deterministic dual emulation, shared snapshot loading, framed
input transport, Bonjour discovery, persistent on-device setup, foreground
reconnection, and role-specific rendering. Two physical leave-and-return
cycles each recovered with one verified snapshot and no failed determinism
checkpoint. Use an optimized Release build for physical play: the tested
Release build sustained roughly 54–56 fps after reconnect, compared with about
28–32 fps for an unoptimized Debug build. Physical tracing of the controller
showed ample CPU headroom and negligible send-completion cost; most blocked
time was in the display-acknowledgement receive. Protocol v3 moves those
receives off the emulation thread and uses a bounded four-frame window while
retaining hard checkpoint barriers. Longer determinism runs and audio
synchronization remain the next hardware milestones.
