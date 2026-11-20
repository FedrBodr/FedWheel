Project: FedWheel
Document: design

# FedWheel: Fenix 8 support (design)

## Intent
The owner rides an InMotion V8 and wears a Garmin Fenix 8 (51 mm). The V8 cannot talk to Garmin watches directly
(Garmin limits BLE packets to 20 bytes; pre-V11 InMotion wheels refuse a smaller MTU — see WheelDash
`source/BLE/frameDecoder.mc`). The working path is: wheel → WheelLog (Android, open source, supports V8) → watch.
WheelLog's watch companion (`Wheellog/Companion.Garmin`, GPL-3.0) was abandoned in 2022 and does not list Fenix 8
("app is not compatible with your fenix 8 51mm" in the Connect IQ Store). FedWheel is our fork that continues it.

## Goals
- The companion builds with the current Connect IQ SDK using the standard toolchain.
- It runs on every Fenix 8 variant (AMOLED 43/47/51 mm, Pro, Solar 47/51 mm).
- Stock WheelLog on the phone (Play Store / GitHub APK) sends data to it with no phone-side changes.
- It can be sideloaded onto the owner's watch over USB.

## Non-goals
- Publishing to the Connect IQ Store.
- New features or UI redesign.
- Changes to the WheelLog phone app.

## Constraints
- Keep the app UUID WheelLog expects. WheelLog (`GarminConnectIQ.kt`) only talks to
  `487e6172-972c-4f93-a4db-26fd689f935a` (stable) or `433c30dc-f316-4d11-a16e-de153d297705` (beta).
- License stays GPL-3.0; keep upstream attribution.
- Connect IQ SDK Manager requires the owner's Garmin account login (owner's step).

## Approaches
- **A. Install the stock companion from the store** — rejected: store refuses Fenix 8.
- **B. Revive this companion (chosen)** — smallest change; phone side already works with it.
- **C. Make WheelLog expose an EUC World–compatible API so WheelDash works** — nicer watch UI, but requires
  building and maintaining a custom phone APK. Kept as fallback if B's sideload/messaging fails.

## Decided
- Name shown on the watch: **FedWheel**. Internal UUID unchanged (see Constraints).
- Replace the kumitateru build (`package.toml`) with `manifest.xml` + `monkey.jungle`.
- Add all Fenix 8 product IDs; keep existing devices where the current SDK still ships them.
- Fix whatever breaks under the new SDK; check layouts in the simulator at 454×454 and 280×280.
- Deliver a signed `.prg` to `GARMIN/APPS` via USB (OpenMTP on macOS).

## Left to the builder
- Which UUID (stable vs beta) to use — whichever the owner's WheelLog version picks up; start with stable.
- Exact SDK version (latest available in SDK Manager).

## Main risk
Whether WheelLog's Connect IQ mobile SDK messaging reaches a sideloaded (non-store) app with the same UUID.
Verified at the sideload step; if it fails, fall back to approach C.
