# 🐔 Chicken Neck

A macOS menu-bar app that watches your posture through the Mac's webcam and calls you out — like a tiny orthopaedic chicken on your shoulder — the moment your neck starts craning toward the screen.

Everything runs **on-device** with Apple's Vision framework. No video is recorded, saved, or sent anywhere.

## What it tracks

Designed around the neck problems a camera can actually measure reliably:

- **Forward head posture** ("tech neck") — graded **green → orange → red** as your head drifts in front of your shoulders. Red gives you a nudge.
- **Lateral neck tilt** — leaning your head toward a shoulder (asymmetric muscle loading) gets highlighted.
- **Cervical rotation** — craning to a side monitor gets highlighted.
- **Screen proximity** — leaning in too far.
- **Sit time** — how long you've been *on the perch* continuously, plus total seated today.
- **Coop breaks** — get nudged to stand and stretch every N minutes (movement matters even with perfect posture).
- **Lunch reminder** — a friendly "feed the chicken" between 1–2pm.
- **History** — daily good-vs-slouch minutes, good-posture %, and slouch (peck) counts.

## Build & run

Requires macOS 14+ and the Swift toolchain.

```bash
make run          # build + launch
make install      # copy to /Applications
swift scripts/make_icon.swift   # regenerate the app icon
```

On first launch, grant **camera access** when prompted. Then:

1. **Start monitoring**
2. Sit tall → **Calibrate**
3. Slouch / crane / tilt and watch the chicken react.

The menu-bar chicken turns **green / orange / red** with your posture. Toggle it off in Settings if you prefer the window only. If alerts fire when you sit up instead of slouching, flip **Reverse forward detection**.

## Settings

Forward & side-tilt sensitivity · hold time · alert cooldown · coop-break interval · lunch reminder · sound / spoken / notification cues · show menu-bar chicken · start at login.

---

Built by Sumanth Raj Urs + Claude.
