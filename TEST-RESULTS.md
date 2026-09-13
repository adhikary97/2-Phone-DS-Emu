# Test results

Verified on 2026-09-12 with Xcode's iOS 26.5 Simulator runtime.

## Protocol tests

`xcodebuild test` executed nine tests covering all wire-message round trips,
malformed trailing bytes, launch-argument parsing and override behavior, saved
on-device setup, the scripted key/touch sequence, Metal drawable resizing,
setup-screen controls, and Bonjour discovery plus bidirectional framed-message
exchange. Result: 9 passed, 0 failed.

The Bonjour integration test starts a real Network.framework listener and
browser, discovers the advertised `_twophonedsemu._tcp` service, connects, and
exchanges protocol messages in both directions. The on-device setup UI was also
rendered on the SE-sized simulator with an existing `TestROM.nds`; the captured
screen is `artifacts/on-device-setup.png`.

## Self-starting Bonjour proof

The dedicated controller and SE display simulators were then launched with
saved on-device roles and ROM names. The launches supplied only the automated
frame/checkpoint flags—no role, host, IP address, port, or ROM argument. The
display discovered the controller through Bonjour, both loaded the remembered
ROM, transferred the 19,760,184-byte snapshot, and passed 120 frames with two
matching checkpoints.

Reports and final screens:

- `artifacts/automatic-controller-report.json`
- `artifacts/automatic-display-report.json`
- `artifacts/automatic-controller.png`
- `artifacts/automatic-display.png`

The rotation regression test first failed with a `0×0` Metal drawable after a
simulated landscape transition. After `DSScreenView` began synchronizing the
drawable size to its bounds and native scale in `layoutSubviews`, the focused
test and complete suite passed. The physical SE was rebuilt, reinstalled, and
relaunched in landscape-right orientation with the corrected build.

## Two-process HeartGold proof

Command:

```bash
./scripts/run-simulator-proof.sh \
  '/Users/paras.adhikary/Downloads/Pokemon - HeartGold Version (USA).nds'
```

Environment:

- Controller: iPhone 15 Pro Max simulator
- Display: iPhone SE (3rd generation) simulator
- ROM SHA-256: `65f02a56842b75aa92d775d56d657a56fe3fa993550b04dc20704ab82d760105`
- Shared starting snapshot: 19,760,184 bytes
- Frames: 480
- Inputs exercised: A, Start, Right, and stylus down/up at (128, 96)
- Determinism checks: whole savestate, top framebuffer, and bottom framebuffer
  every 60 frames

Result: both processes passed all 8 checkpoints and produced this identical
final digest:

```text
state  = 7848267641777028573
top    = 13852291851001799461
bottom = 1949991421880254054
```

The repeatable run reported 53.14 fps for the controller and 51.88 fps for the
display, including per-frame TCP acknowledgement and checkpoint hashing.

This confirms short-run deterministic reproduction in two simulator processes.
It is not a Bluetooth or physical-device performance result.

## Two-phone hardware proof

On 2026-09-12, the same 480-frame proof ran over local-network TCP on:

- Controller: iPhone 15 Pro Max, iOS 27.0 beta
- Display: iPhone SE (3rd generation), iOS 18.1
- Controller and display connected over the same private Wi-Fi network

Both physical phones verified the same ROM SHA-256, transferred the same
19,760,184-byte snapshot, and matched all 8 savestate plus dual-framebuffer
checkpoints. Their final digest was identical to the simulator proof above.

The reports recorded 18.42 seconds / 26.06 fps for the controller and 13.17
seconds / 36.46 fps for the display. The controller timer includes roughly five
seconds spent waiting for the display process to be launched, so these totals
are useful proof-run timings rather than clean steady-state emulation
benchmarks. The strict per-frame acknowledgement path still needs performance
work before it can sustain a 60 fps hardware session.

Downloaded reports:

- `artifacts/physical-controller-report.json`
- `artifacts/physical-display-report.json`
