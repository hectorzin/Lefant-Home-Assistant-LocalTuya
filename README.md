# Lefant Home Assistant LocalTuya

🌐 [English](README.md) | [Español](README.es.md)

[![Platform](https://img.shields.io/badge/platform-Windows-0078D4)](https://www.microsoft.com/windows) [![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)](https://www.python.org/)

> Extract Lefant Device ID and Local Key for Home Assistant LocalTuya integration.

This community tool helps owners of selected Lefant robots obtain the local connection details needed for Home Assistant while leaving the robot paired with the official Lefant app. It does not distribute, replace, or modify the Lefant APK.

## Table of Contents

- [Quick Start](#quick-start)
- [What this project does](#what-this-project-does)
- [Validated setup](#validated-setup)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation](#installation)
- [Installing the Lefant app](#installing-the-lefant-app)
- [Frida Server](#frida-server)
- [Usage](#usage)
- [devices.json](#devicesjson)
- [Home Assistant and LocalTuya](#home-assistant-and-localtuya)
- [Ready-to-use LocalTuya templates](#ready-to-use-localtuya-templates)
- [Lefant M210 Pro Omni](#lefant-m210-pro-omni)
- [Contributing a Lefant model template](#contributing-a-lefant-model-template)
- [Troubleshooting](#troubleshooting)
- [Security and privacy](#security-and-privacy)
- [Legal and disclaimer](#legal-and-disclaimer)

## Quick Start

1. Install Python, Node.js/npm, Android Studio/ADB, and Frida.
2. Create or use an Android emulator that supports the `adb root` workflow required by the launcher.
3. Install the official Lefant app: preferably from Google Play when it is available in that emulator, or optionally from local APK files that you supply.
4. Download and place a matching `frida-server` binary locally.
5. Run:

   ```powershell
   .\lefant_launcher.ps1
   ```

6. Log in to Lefant manually if required and load the device list.
7. Press ENTER when prompted.
8. Use the extracted Device ID and Local Key in LocalTuya.

APK files are optional; see [Installing the Lefant app](#installing-the-lefant-app) for the supported local paths.

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

## Installing the Lefant app

Supplying APK files is **optional**. If the emulator has Google Play available, the easiest route is to install the official Lefant app directly from Google Play, then launch it and log in normally.

If Google Play is not available, or you prefer a local installation, the launcher supports APK files that you supply. The Lefant app and APK files are not included in this repository. Google Play availability alone is not enough: the emulator must still support the `adb root` workflow required by the launcher.

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

The launcher detects `split_config*.apk` files and uses `adb install-multiple`. These files are optional, ignored by Git, and supplied by you. This repository does not distribute APKs and does not link to unofficial APK download sites.

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
    "local_key": "xxxxxxxxxxxxxxxx",
    "mac": "e82f126407d4",
    "ip": "192.168.1.123"
  }
]
```

- Device ID comes from the Lefant/ThingClips `DeviceBean`.
- Local Key is sensitive local authentication material.
- MAC address is exported from `DeviceBean` when that value is available. It is written exactly as returned and may be empty on some models.
- IP is exported from `DeviceBean.getIp()` when that value is available. It is written exactly as returned and may be empty or stale; it is not assumed to be a reliable LAN address. If it is missing or outdated, the IP can be obtained from the router/DHCP leases, LocalTuya discovery, or TinyTuya.
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

## Ready-to-use LocalTuya templates

This repository includes reusable LocalTuya templates for these Lefant models:

- `Lefant_A1_Pro.yaml`
- `Lefant_M210_Pro_Omni.yaml`

Detailed M210 Pro Omni documentation appears below. The other included templates can be used directly even though they do not yet have their own dedicated section.

Copy the relevant file from this repository's `templates/` directory into the LocalTuya templates directory in your Home Assistant configuration:

```text
/config/custom_components/localtuya/templates/
```

When working relative to the Home Assistant configuration directory, the same location is:

```text
custom_components/localtuya/templates/
```

Then add the device in LocalTuya. During the **Add new device** flow, select **Use saved template**; LocalTuya lists the templates stored in that directory at that step. Restart Home Assistant after copying a template if it is not listed.

Templates are model-specific. Verify the available DPs before applying one to a different model, and select the protocol version that matches the device: Tuya protocol versions are not universal across Lefant models.

## Lefant M210 Pro Omni

The following setup is validated for the Lefant M210 Pro Omni using Tuya protocol `3.5`. It is model-specific and should not be treated as a universal Lefant mapping.

Configure the vacuum entity with:

- Power DP: `1`
- Pause DP: `2`
- Mode DP: `4`
- Status DP: `5`
- Fan speed DP: `9`
- Clean time DP: `16`
- Clean area DP: `17`
- Locate DP: `27`

Validated mode values are `smart`, `chargego`, `zone`, and `pose`. Validated fan speed values are `gentle`, `normal`, and `strong`.

Use these state groups for the vacuum entity:

| State | Values |
| --- | --- |
| Idle | `standby`, `sleep`, `charge_done` |
| Docked | `charging`, `charge_done`, `sleep` |
| Returning | `goto_charge` |
| Paused | `paused` |

| DP | Known name | Suggested LocalTuya use |
| --- | --- | --- |
| 1 | `power_go` | Vacuum power |
| 2 | `pause` | Vacuum pause |
| 3 | `switch_charge` | Separate **Return to dock** button; set `true` |
| 4 | `mode` | Vacuum mode |
| 5 | `status` | Read-only vacuum status; may report `goto_charge` |
| 9 | `suction` | Vacuum fan speed |
| 10 | `water_output` | Known DP; behavior not documented here |
| 14 | `auto_boost` | Separate switch |
| 15 | `break_clean` | Separate entity; the included template uses a switch. Validate its behavior before representing it as a diagnostic or binary sensor |
| 16 | `clean_time` | Sensor: clean time |
| 17 | `clean_area` | Sensor: clean area |
| 23 | `battery_percentage` | Separate battery sensor (`%`) |
| 27 | `seek` | Vacuum locate |

For this model, use DP 3 (`switch_charge = true`) for the normal Home Assistant **Return to dock** action. Do not substitute `mode=chargego` for that action. DP 5 is status/read-only and can report `goto_charge` while the robot returns to its dock.

## Contributing a Lefant model template

If another Lefant model works with LocalTuya, you can export or prepare its configuration, remove sensitive information, add a template under `templates/`, and open a Pull Request.

Please include the exact Lefant model, tested Tuya protocol version, tested Lefant app version (if known), DP mapping, confirmation that basic controls work, and any model-specific caveats.

Do not include a `local_key`, real `device_id`, private IP address, account data, or other personal data in a template, example, issue, or Pull Request.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| ADB was not found | Install Platform Tools, add it to `PATH`, or use `-Adb`. |
| No emulator detected | Check the AVD name, use `-Avd`, and wait for `adb devices` to show `device`. |
| `adb root` is unsupported | Use an emulator/system image that allows `adb root`; the launcher cannot deploy the server otherwise. |
| Lefant is not installed | Install it from Google Play if it is available in the emulator, install it manually, or use optional local APK files in a supported location. |
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
