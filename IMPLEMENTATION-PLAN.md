# two-phone-ds-emu simulator prototype

- [x] Copy the existing local source into an independent project and generate a separate app identity.
- [x] Implement bounded, length-framed local TCP transport (simulator substitute for Bluetooth) with framing tests.
- [x] Add a deterministic bridge: frame-boundary inputs, shared starting snapshot, deterministic fingerprints, and safe state handling.
- [x] Add controller and display roles, bottom controls, top-only display, handshake, checksums, failure handling, and diagnostics.
- [x] Create a repeatable two-simulator HeartGold test with scripted button and touch inputs, matching state/frame hashes, and screenshots.
- [x] Build, run the real simulator test, and document what it does and does not prove.
- [ ] Add an intentional divergence hook and assert that the end-to-end harness detects it.
- [ ] Replace local TCP with a Bluetooth LE transport for physical-device testing.

ROM remains local and excluded from source control. Original ds-emu remains unchanged.
