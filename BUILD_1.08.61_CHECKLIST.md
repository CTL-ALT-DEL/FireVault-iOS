# Build 1.08.61 — GPS Deep Dive

## Scope

- [x] Use one shared Nearby GPS manager for the handset and CarPlay.
- [x] Keep Trip Log as the sole high-accuracy owner while recording.
- [x] Publish one validated live-speed value to iPhone and CarPlay.
- [x] Reject stale and poor-accuracy fixes from live MPH.
- [x] Keep route archive sampling independent from live telemetry.
- [x] Refresh CarPlay GPS Diagnostics while the page is open.
- [x] Reuse Trip Log GPS in iPhone Diagnostics during recording.
- [x] Preserve CarPlay ownership when the handset enters the background.
- [x] Preserve handset ownership when CarPlay disconnects.
- [x] Do not change stop-detection timing or account matching.
- [x] Do not bump the visible version or build number.
- [x] Do not merge into `main`.

## Automated validation

- [x] Fresh measured speed is displayed.
- [x] Live speed expires when movement evidence becomes stale.
- [x] Poor-accuracy fixes cannot produce MPH.
- [x] Cached fixes cannot produce MPH after signal loss.
- [x] Live motion remains independent from 75-meter archive spacing.
- [x] Speed returns after reliable movement resumes.
- [x] Complete unit-test suite passes.
- [x] Generic physical-iPhone target compiles without signing.

## Required physical road test

- [ ] Install the branch on the test iPhone.
- [ ] Connect to physical CarPlay.
- [ ] Before recording, compare GPS accuracy on iPhone and CarPlay.
- [ ] Start Trip Log from CarPlay and confirm both show the same status.
- [ ] Drive above 10 mph and compare iPhone/CarPlay MPH.
- [ ] Stop safely and confirm MPH returns to zero within approximately 8 seconds.
- [ ] Resume driving and confirm MPH recovers without restarting Trip Log.
- [ ] Open CarPlay GPS Diagnostics and verify Last Update advances live.
- [ ] Background and reopen the iPhone app while CarPlay remains connected.
- [ ] Disconnect and reconnect CarPlay during the active Trip Log.
- [ ] Drive through a weak-signal area and confirm stale speed is not frozen.
- [ ] Confirm distance, stops, elapsed time, elevation, and accuracy stay synchronized.
- [ ] Complete an all-day battery comparison against Build 1.08.60.

## Expected behavior

During an active Trip Log, iPhone and CarPlay consume the same shared Trip Log
location and validated speed. Before recording, both scenes share the same
Nearby location service. Screen rendering may differ by one refresh cycle, but
the underlying telemetry values are identical.
