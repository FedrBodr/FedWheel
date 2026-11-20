Project: FedWheel
Document: implementation-plan

# FedWheel Fenix 8 Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the abandoned WheelLog Garmin companion with the current Connect IQ SDK, add Fenix 8, and sideload it as "FedWheel".

**Architecture:** Unchanged Monkey C watch-app. The phone (stock WheelLog, `GarminConnectIQ.kt`) opens a local NanoHTTPD server and sends its port to the watch app via Connect IQ messaging; the watch polls `http://127.0.0.1:<port>/data/main|details|alarms` (`src/comm/DataServer.mc`). We only replace the build system, rename, add devices, and fix compile/layout issues.

**Tech Stack:** Monkey C, Connect IQ SDK (latest from SDK Manager), `monkeyc`/`monkeydo`, CIQVec 1.1.0 barrel (`dependencies/`), OpenMTP for sideload.

**Spec:** `docs/superpowers/specs/2026-11-20-fenix8-support-design.md`

## Global Constraints

- App UUID: `487e6172-972c-4f93-a4db-26fd689f935a` (WheelLog "stable" ID; WheelLog uses it unless its beta toggle is on).
- Display name: `FedWheel` in all languages (eng, rus, ukr).
- License GPL-3.0; keep upstream credit in README.
- Fenix 8 product IDs (verify exact names in `~/Library/Application Support/Garmin/ConnectIQ/Devices/` before use): `fenix843mm`, `fenix847mm`, `fenix8pro47mm`, `fenix8solar47mm`, `fenix8solar51mm`. Drop any old device the current SDK no longer ships.
- Signing key `developer_key.der` is never committed (add to `.gitignore`).
- No phone-side changes, no store publishing, no UI redesign.

## Review Focus

- Phone unreachable (Garmin Connect closed / Bluetooth off; responseCode −104, −300, 404): app must stay on the waiting screen, not crash. → test in Task 2.
- Wheel disconnects mid-ride (`connectedToWheel` = false while phone is reachable): show "not connected", keep last values, no crash. → test in Task 2.
- WheelLog sends `speed`, `pwm`, `maxPwm`, `topSpeed` as **strings** (e.g. `"12.3"`, `"07"`), `battery` as int: parser and renderer must accept strings. → test in Task 2.
- `useMph` = true: speed labels switch units. → test in Task 2.
- Round 454×454 (AMOLED) and 280×280 (Solar MIP) screens: arcs and text fit, nothing clipped. → Task 3.

---

### Task 0 (owner): Toolchain

- [ ] Install Connect IQ SDK Manager (developer.garmin.com/connect-iq/sdk), log in with Garmin account, download the latest SDK and device files for all Fenix 8 models.
- [ ] Install OpenMTP (for copying files to the watch).
- [ ] Verify: `ls ~/Library/Application\ Support/Garmin/ConnectIQ/Devices | grep fenix8` lists Fenix 8 IDs, and the SDK `bin/monkeyc` exists.

### Task 1: Standard build, rename, Fenix 8 devices

**Files:**
- Create: `manifest.xml`, `monkey.jungle`
- Modify: `resources/strings/{main,rus,ukr}/strings.xml` (AppName → `FedWheel`), `.gitignore` (+ `developer_key.der`, `bin/`)
- Delete: `package.toml`

**Interfaces:**
- Produces: build command used by all later tasks:
  `monkeyc -f monkey.jungle -d <device> -y developer_key.der -o bin/FedWheel.prg`

- [ ] **Step 1:** Generate key: `openssl genrsa -out /tmp/k.pem 4096 && openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/k.pem -out developer_key.der -nocrypt`
- [ ] **Step 2:** Write `manifest.xml` from `package.toml`: watch-app, entry `WheelLogCompanionApp`, launcher icon `@Drawables.LauncherIcon`, name `@Strings.AppName`, UUID from Global Constraints, permission `Communications`, languages eng/rus/ukr, devices = still-shipped old IDs + Fenix 8 IDs, minApiLevel `1.2.0`.
- [ ] **Step 3:** Write `monkey.jungle`: `project.manifest = manifest.xml` and `base.barrelPath = dependencies/CIQVec-1.1.0.barrel`.
- [ ] **Step 4:** Build for `fenix847mm`. Expected: `BUILD SUCCESSFUL`. Fix compile errors in `src/` minimally (no behaviour change) until it passes.
- [ ] **Step 5:** Build loop over every Fenix 8 ID. Expected: all succeed.
- [ ] **Step 6:** Commit `build: switch to standard Connect IQ build, rename to FedWheel, add Fenix 8`.

### Task 2: Protocol parsing tests

**Files:**
- Create: `test/DataServerTest.mc`
- Modify: `monkey.jungle` (add `test` to sourcePath for unit-test builds), `src/comm/DataServer.mc` only if a test fails

**Interfaces:**
- Consumes: `DataServer.parseOldProtocolData(dataType as Symbol, message as Dictionary)`, `DataServer.updateUsingOldProtocol_main(responseCode, data)`, `WheelData.*` fields.

- [ ] **Step 1: Write tests** (`(:test)` functions, `Toybox.Test`):
  - `parsesMainFromWheelLog`: message `{"speed"=>"12.3","topSpeed"=>"25.1","speedLimit"=>30,"useMph"=>false,"battery"=>80,"temp"=>35,"pwm"=>"07","maxPwm"=>"40","connectedToWheel"=>true,"wheelModel"=>"V8"}` → `WheelData.currentSpeed.equals("12.3")`, `batteryPercentage == 80`, `isWheelConnected == true`, `wheelModel.equals("V8")`.
  - `wheelDisconnectedKeepsRunning`: same message with `connectedToWheel=>false` → `isWheelConnected == false`, no exception.
  - `phoneUnreachableDoesNotParse`: `updateUsingOldProtocol_main(-104, null)` → no exception, `AppStorage.runtimeDb["comm_lastResponseCode"] == -104`.
  - `mphFlagStored`: `useMph=>true` → `WheelData.useMph == true`.
- [ ] **Step 2:** Run: `monkeyc -f monkey.jungle -d fenix847mm -y developer_key.der --unit-test -o bin/test.prg && monkeydo bin/test.prg fenix847mm -t` (simulator running). Expected: all PASS (fix `DataServer.mc` if any fails).
- [ ] **Step 3:** Commit `test: pin WheelLog protocol parsing`.

### Task 3: Layout check on Fenix 8 screens

**Files:**
- Modify (only if clipped): `resources/layouts/home_layout.xml`, `src/view/homeView/components/ArcRenderer.mc`, `src/view/detailView/components/PageArcRenderer.mc`; device-specific overrides go in `resources-<deviceId>/` per standard jungle rules.

- [ ] **Step 1:** Run in simulator on `fenix847mm` and `fenix8solar51mm` with fake data (temporarily set `WheelData` values in a debug-only `(:debug)` block, not committed if invasive). Screenshot home and detail views.
- [ ] **Step 2:** Expected: arcs centred, text fully visible on both. Fix if not.
- [ ] **Step 3:** Commit `fix: layout on Fenix 8` (skip if no change).

### Task 4: Sideload and end-to-end (owner + agent)

- [ ] **Step 1:** Build release `.prg` for the owner's model (51 mm: `fenix847mm` if AMOLED shares that ID, else `fenix8solar51mm` — confirm with owner).
- [ ] **Step 2:** Owner: connect watch via USB, OpenMTP → copy `bin/FedWheel.prg` to `GARMIN/APPS/`, disconnect.
- [ ] **Step 3:** Owner: WheelLog → Settings → Watch → enable Garmin Connect IQ, beta **off**; wheel connected in WheelLog; start FedWheel on watch.
- [ ] **Step 4:** Expected: speed and battery on the watch match WheelLog. If the watch stays on "waiting": try UUID `433c30dc-f316-4d11-a16e-de153d297705` with WheelLog beta **on**; if still nothing, stop and switch to spec approach C.

### Task 5: README and push

- [ ] **Step 1:** README: fork notice + upstream credit (ggoraa, Wheellog/Companion.Garmin), supported devices, build and sideload instructions (commands from Task 1 and Task 4), "Decisions" section (UUID kept and why; kumitateru dropped and why).
- [ ] **Step 2:** Commit and `git push origin master`.
