# Lefant Home Assistant LocalTuya

[![Platform](https://img.shields.io/badge/platform-Windows-0078D4)](https://www.microsoft.com/windows) [![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)](https://www.python.org/)

> Extract Lefant Device ID and Local Key for Home Assistant LocalTuya integration.

This community tool helps owners of selected Lefant robots obtain the local connection details needed for Home Assistant while leaving the robot paired with the official Lefant app. It does not distribute, replace, or modify the Lefant APK.

## Table of Contents

- [What this project does](#what-this-project-does)
- [Validated setup](#validated-setup)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Lefant APK](#lefant-apk)
- [Frida Server](#frida-server)
- [Usage](#usage)
- [devices.json](#devicesjson)
- [Home Assistant and LocalTuya](#home-assistant-and-localtuya)
- [Lefant M210 Pro Omni](#lefant-m210-pro-omni)
- [Troubleshooting](#troubleshooting)
- [Security and privacy](#security-and-privacy)
- [Legal and disclaimer](#legal-and-disclaimer)

## What this project does

Some Lefant robots are based on Tuya/ThingClips components. To configure a device locally, Home Assistant LocalTuya generally needs its Device ID, Local Key, LAN IP address, and Tuya protocol version.

After a robot is paired in the Lefant app, its Local Key may not be available from a normal Tuya IoT Cloud project. This project reads `DeviceBean` objects already loaded by the authenticated official Lefant app in an Android environment controlled by the owner. It exports the Device ID and Local Key without moving the robot away from Lefant.

This is not a compatibility claim for every Lefant model. Protocol version and datapoints are device-specific. The extractor deliberately exports only values it actually reads; it does not assume a protocol version.

## Validated setup

The following setup has been validated:

- Lefant M210 Pro Omni
- Lefant app `3.3.25`
- Tuya protocol `3.5` for that model
- Windows host
- Android emulator with `adb root` support

## Architecture

```text
Windows PC
  └─ lefant_launcher.ps1
       └─ Android Emulator
            └─ Official Lefant app (manual owner login)
                 └─ frida-server
                      └─ DeviceBean extraction
                           └─ devices.json
                                └─ LocalTuya
                                     └─ Home Assistant
```

- The PowerShell launcher starts or reuses an Android emulator and prepares Frida.
- The official Lefant app is where the owner signs in and loads their own device list.
- `frida-server` allows the local Windows Frida client to attach to that controlled emulator.
- The TypeScript agent enumerates loaded `DeviceBean` instances.
- The Python exporter deduplicates by Device ID and writes `devices.json`.
- LocalTuya uses those values together with the robot's IP address and applicable protocol version.

## Requirements

- [Python 3.10+](https://www.python.org/downloads/)
- [Node.js and npm](https://nodejs.org/)
- [Android Studio](https://developer.android.com/studio), including an Android Emulator AVD
- [Android SDK Platform Tools / ADB](https://developer.android.com/tools/releases/platform-tools)
- [Frida](https://frida.re/) and a matching [`frida-server` release](https://github.com/frida/frida/releases)
- [HACS](https://www.hacs.xyz/) for Home Assistant
- [xZetsubou/hass-localtuya](https://github.com/xZetsubou/hass-localtuya), the LocalTuya fork intended by this project

The current xZetsubou LocalTuya code lists protocol `3.5` among its supported protocol versions. This repository is intended for that fork, not the older upstream `rospogrigio/localtuya` repository. It remains your responsibility to select the protocol that matches your device.

The emulator must support `adb root`, because the launcher places and starts `frida-server` at `/data/local/tmp/frida-server`. Google APIs system images are generally more suitable than Google Play images here because `adb root` availability matters.

## Installation

1. Clone the repository:

   ```powershell
   git clone https://github.com/hectorzin/Lefant-Home-Assistant-LocalTuya.git
   cd Lefant-Home-Assistant-LocalTuya
   ```

2. Install Python dependencies:

   ```powershell
   py -m pip install -r requirements.txt
   ```

3. Install Node dependencies:

   ```powershell
   npm install
   ```

   The Python exporter can run `npm install` automatically if `frida-java-bridge` is missing, but installing dependencies beforehand is recommended.

4. Create or choose an Android Emulator AVD that supports `adb root`. The default AVD name used by the launcher is `Pixel_6`.

5. Download a `frida-server` matching both the installed Frida client version and the emulator ABI. Do not add it to Git.

## Lefant APK

The Lefant APK is **not** included in this repository. You may install the official Lefant app manually in the emulator, or supply APK files locally for the launcher.

The launcher checks these base APK locations:

```text
./lefant.apk
./apk/lefant.apk
```

If the app uses split APKs, place the splits beside the base APK:

```text
apk/
  lefant.apk
  split_config.arm64_v8a.apk
  split_config.es.apk
  split_config.xxhdpi.apk
```

The launcher detects `split_config*.apk` files and uses `adb install-multiple`. APK files are ignored by Git and must be supplied by you. This project does not link to unofficial APK download sites.

## Frida Server

The Frida client and `frida-server` versions must match. The launcher detects the installed Frida client version and the emulator ABI, then expects a matching server binary.

Supported local locations are:

```text
./frida-server
./frida/frida-server
./frida/frida-server-VERSION-android-x86_64
```

Use `-FridaServerPath` to provide an explicit path:

```powershell
.\lefant_launcher.ps1 `
  -FridaServerPath .\frida\frida-server-17.17.0-android-x86_64
```

The launcher pushes a compatible binary to `/data/local/tmp/frida-server`, sets its permissions, starts it through `adb root`, and verifies it from Windows. Do not commit the binary.

## Usage

Start the normal workflow:

```powershell
.\lefant_launcher.ps1
```

The launcher automatically:

1. Finds ADB.
2. Reuses a running Android emulator when possible, or starts the configured AVD.
3. Waits for Android boot completion.
4. Checks whether Lefant is installed and optionally installs a user-supplied APK.
5. Launches the official Lefant app.
6. Lets you sign in manually if required and wait for the device list to load.
7. Prepares and verifies `frida-server`.
8. Attaches Frida to Lefant, extracts `DeviceBean` data, and writes `devices.json`.

The Local Key is masked in terminal output by default. Show it explicitly with:

```powershell
.\lefant_launcher.ps1 -ShowKey
```

`devices.json` always contains the complete Local Key, so treat it as sensitive.

### Useful launcher parameters

| Parameter | Purpose | Example |
| --- | --- | --- |
| `-Serial` | Reuse a specific ADB emulator | `-Serial emulator-5554` |
| `-Adb` | Use an explicit ADB executable | `-Adb C:\Android\Sdk\platform-tools\adb.exe` |
| `-Avd` | AVD to start when no emulator is online | `-Avd Pixel_6` |
| `-EmulatorPath` | Explicit Android Emulator executable | `-EmulatorPath C:\Android\Sdk\emulator\emulator.exe` |
| `-FridaServerPath` | Explicit matching `frida-server` binary | `-FridaServerPath .\frida\frida-server-17.17.0-android-x86_64` |
| `-FridaAddress` | Authorized remote Frida endpoint | `-FridaAddress 127.0.0.1:27042` |
| `-Output` | JSON output file | `-Output .\devices.json` |
| `-ShowKey` | Show the complete Local Key in the terminal | `-ShowKey` |

## devices.json

Example with safe placeholder values:

```json
[
  {
    "name": "Robot Vacuum",
    "device_id": "xxxxxxxxxxxxxxxxxxxxxx",
    "local_key": "xxxxxxxxxxxxxxxx"
  }
]
```

- Device ID comes from the Lefant/ThingClips `DeviceBean`.
- Local Key is sensitive local authentication material.
- `devices.json` is ignored by Git.
- Never publish Local Keys or private Device IDs unnecessarily.

## Home Assistant and LocalTuya

Install [xZetsubou/hass-localtuya](https://github.com/xZetsubou/hass-localtuya) through HACS:

1. Open **HACS** → **Integrations**.
2. Open the menu → **Custom repositories**.
3. Add `https://github.com/xZetsubou/hass-localtuya`.
4. Select category **Integration**.
5. Install **LocalTuya** and restart Home Assistant if prompted.
6. Open **Settings** → **Devices & services** → **Add integration** → **LocalTuya**.

Provide the values appropriate to your robot:

- Host / IP address
- Device ID
- Local Key
- Protocol version

Find the IP address through router DHCP leases, LocalTuya discovery, or optional [TinyTuya discovery](https://github.com/jasonacox/tinytuya). TinyTuya is not required.

## Lefant M210 Pro Omni

The following datapoints are known from the validated M210 Pro Omni setup. They are model-specific and should not be treated as a universal Lefant mapping.

| DP | Known name | Suggested LocalTuya use |
| --- | --- | --- |
| 1 | `power_go` | Vacuum power |
| 2 | `pause` | Vacuum pause |
| 3 | `switch_charge` | Separate **Return to dock** button; set `true` |
| 4 | `mode` | Vacuum mode |
| 5 | `status` | Read-only vacuum status; may report `goto_charge` |
| 9 | `suction` | Vacuum fan speed |
| 10 | `water_output` | Known DP; behavior not documented here |
| 14 | `auto_boost` | Switch: Auto Boost |
| 15 | `break_clean` | Sensor or binary sensor: cleaning interruption |
| 16 | `clean_time` | Sensor: clean time |
| 17 | `clean_area` | Sensor: clean area |
| 23 | `battery_percentage` | Sensor: battery |
| 27 | `seek` | Vacuum locate |

For this model, use DP 3 (`switch_charge = true`) for the normal Home Assistant **Return to dock** action. Do not substitute `mode=chargego` for that action. DP 5 is status/read-only and can report `goto_charge` while the robot returns to its dock.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| ADB was not found | Install Platform Tools, add it to `PATH`, or use `-Adb`. |
| No emulator detected | Check the AVD name, use `-Avd`, and wait for `adb devices` to show `device`. |
| `adb root` is unsupported | Use an emulator/system image that allows `adb root`; the launcher cannot deploy the server otherwise. |
| Lefant APK was not found | Provide `lefant.apk` in a supported location or install the official app manually. |
| Split installation fails | Keep the base APK and all available `split_config*.apk` files together. |
| Frida client/server mismatch | Download the server matching the Frida client version and emulator ABI. |
| `frida-server` is not running | Check `adb root`, the binary path, ABI, and version. |
| Cannot attach to Lefant | Open the official app, ensure it is running, and confirm Frida verification completed. |
| No `DeviceBean` found | Load the Lefant device list fully, then retry. |
| Multiple ADB devices | Use `-Serial emulator-XXXX`. |
| `devices.json` is missing | Extraction did not find a complete DeviceBean; check the device list and errors above. |
| Lefant version warning | The validated app version is `3.3.25`; other versions may still work but are unvalidated. |

## Security and privacy

- Local Keys authenticate local device communication. Keep them private.
- Never publish `devices.json` or commit Local Keys.
- Avoid publishing private Device IDs unnecessarily.
- This project only targets an Android environment controlled by the user.
- You sign in to Lefant manually; the project does not collect or transmit credentials.

## Legal and disclaimer

This is an unofficial community project. It is not affiliated with Lefant, Tuya, ThingClips, or Home Assistant. Lefant, Tuya, ThingClips, and Home Assistant are trademarks of their respective owners.

The project is intended for interoperability with devices owned by the user. No Lefant APKs, `frida-server` binaries, or other proprietary binaries are distributed.
