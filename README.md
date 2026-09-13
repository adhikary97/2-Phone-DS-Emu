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
3. The display acknowledges the completed frame.
4. At configured checkpoints, both hash their complete savestate and both
   framebuffers. Any difference fails the session.

The lockstep acknowledgement is deliberately strict for the proof. A hardware
version will likely use a small frame window to trade alignment for lower input
latency.

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

To change a phone's role or ROM, tap **Setup** in the status bar, choose **Reset
Setup**, then force-quit and reopen the app.

The launch-argument interface remains available for repeatable simulator and
diagnostic runs, but it is no longer required for ordinary phone use.

## Current boundary

This validates deterministic dual emulation, shared snapshot loading, framed
input transport, Bonjour discovery, persistent on-device setup, and
role-specific rendering. The strict physical proof did not sustain 60 fps. It
does **not** validate long-run determinism, background behavior, reconnection,
or audio synchronization. Those remain the next hardware milestones.
