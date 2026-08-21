#!/usr/bin/env python3
"""Export DeviceBean objects already loaded by the owner's official Lefant app."""

from __future__ import annotations

import argparse
import ipaddress
import json
import shutil
import subprocess
import sys
import threading
from pathlib import Path
from threading import Event
from typing import Any

PACKAGE = "com.yunshi.robotlife"
ROOT = Path(__file__).resolve().parent
AGENT_PATH = ROOT / "agent" / "devicebean_agent.ts"


class ToolError(RuntimeError):
    pass


def run(command: list[str], timeout: float = 15) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    except FileNotFoundError as exc:
        raise ToolError(f"Executable not found: {command[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise ToolError(f"Timed out: {' '.join(command[:3])}") from exc
    if result.returncode:
        raise ToolError((result.stderr or result.stdout or "Command failed").strip())
    return result.stdout.strip()


def locate_adb(explicit: str | None) -> str:
    if explicit:
        path = Path(explicit)
        if not path.is_file():
            raise ToolError(f"ADB does not exist: {path}")
        return str(path)
    found = shutil.which("adb")
    if found:
        return found
    bundled = Path(__file__).resolve().parent.parent / "adb.exe"
    if bundled.is_file():
        return str(bundled)
    raise ToolError("ADB was not found. Install Android Platform Tools or use --adb PATH.")


def adb_prefix(adb: str, serial: str | None) -> list[str]:
    return [adb, *(["-s", serial] if serial else [])]


def select_serial(adb: str, requested: str | None) -> str:
    rows = run([adb, "devices"]).splitlines()[1:]
    devices = [(r.split()[0], r.split()[1]) for r in rows if len(r.split()) >= 2]
    if requested:
        state = next((state for serial, state in devices if serial == requested), None)
        if state != "device":
            raise ToolError(f"ADB {requested!r} is not authorized/online (state: {state or 'missing'}).")
        return requested
    ready = [serial for serial, state in devices if state == "device"]
    if len(ready) == 1:
        return ready[0]
    if not ready:
        raise ToolError("No authorized ADB device is available. Connect or start the emulator and accept USB debugging.")
    raise ToolError("Multiple ADB devices are available. Use --serial: " + ", ".join(ready))


def app_pid(adb: str, serial: str, package: str) -> int:
    prefix = adb_prefix(adb, serial)
    if not run([*prefix, "shell", "pm", "path", package]).startswith("package:"):
        raise ToolError(f"{package} is not installed on {serial}.")
    pids = run([*prefix, "shell", "pidof", package]).split()
    if not pids:
        raise ToolError(f"{package} is not running. Open it, sign in normally, and load your devices.")
    if len(pids) > 1:
        raise ToolError(f"Multiple PIDs were found for {package}: {', '.join(pids)}")
    try:
        return int(pids[0])
    except ValueError as exc:
        raise ToolError(f"ADB returned an invalid PID: {pids[0]!r}") from exc


def build_java_agent() -> tuple[Any, str]:
    """Bundle the TypeScript agent with Frida's compiler and Java bridge."""
    try:
        import frida  # type: ignore
    except ImportError as exc:
        raise ToolError("The Frida Python module is missing. Run: py -m pip install -r requirements.txt") from exc
    if not AGENT_PATH.is_file():
        raise ToolError(f"Frida Java bridge is unavailable: agent is missing: {AGENT_PATH}.")

    bridge = ROOT / "node_modules" / "frida-java-bridge"
    if not bridge.is_dir():
        npm = shutil.which("npm.cmd") or shutil.which("npm")
        if not npm:
            raise ToolError(
                "Frida Java bridge is unavailable: frida-java-bridge is missing and npm was not found. "
                "Install Node.js/npm and run npm install in this directory."
            )
        print("Preparing frida-java-bridge (npm install)...")
        try:
            result = subprocess.run(
                [npm, "install", "--no-audit", "--no-fund"],
                cwd=ROOT,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=180,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ToolError(f"Frida Java bridge is unavailable: npm install could not complete ({exc}).") from exc
        if result.returncode or not bridge.is_dir():
            detail = (result.stderr or result.stdout or "no details").strip()
            raise ToolError(f"Frida Java bridge is unavailable: npm install failed: {detail}")

    diagnostics: list[str] = []
    try:
        compiler = frida.Compiler()
        compiler.on("diagnostics", lambda diagnostic: diagnostics.append(str(diagnostic)))
        bundle = compiler.build(str(AGENT_PATH), project_root=str(ROOT))
    except Exception as exc:
        detail = "\n".join(diagnostics)
        suffix = f"\n{detail}" if detail else ""
        raise ToolError(f"Frida Java bridge is unavailable: the agent could not be compiled.{suffix}\n{exc}") from exc
    return frida, bundle


def get_frida_device(serial: str, address: str | None) -> Any:
    try:
        import frida  # type: ignore
    except ImportError as exc:
        raise ToolError("The Frida Python module is missing. Run: py -m pip install -r requirements.txt") from exc
    try:
        if address:
            return frida.get_device_manager().add_remote_device(address)
        manager = frida.get_device_manager()
        return next((d for d in manager.enumerate_devices() if d.id == serial), None) or frida.get_usb_device(timeout=5000)
    except Exception as exc:
        raise ToolError("Could not connect to Frida on the authorized device. Verify a compatible frida-server or use --frida-address. Details: " + str(exc)) from exc


def extract(serial: str, pid: int, address: str | None, timeout: float) -> list[dict[str, str]]:
    _, bundle = build_java_agent()
    device = get_frida_device(serial, address)
    records: dict[str, dict[str, str]] = {}
    complete, errors = Event(), []
    try:
        session = device.attach(pid)
        script = session.create_script(bundle)
        def on_message(message: dict[str, Any], data: Any) -> None:
            if message.get("type") == "send":
                payload = message.get("payload", {})
                if payload.get("type") == "device" and payload.get("device_id"):
                    did = str(payload["device_id"])
                    records[did] = {
                        "name": str(payload.get("name", "")),
                        "device_id": did,
                        "local_key": str(payload.get("local_key", "")),
                        "mac": normalize_mac(payload.get("mac", "")),
                        "lan_ip": "",
                    }
                elif payload.get("type") == "error":
                    errors.append(str(payload.get("error")))
                    complete.set()
                elif payload.get("type") == "complete": complete.set()
            elif message.get("type") == "error":
                errors.append(str(message.get("stack") or message.get("description") or "Frida script error")); complete.set()
        script.on("message", on_message)
        script.load()
        if not complete.wait(timeout): raise ToolError(f"Enumeration did not finish within {timeout:g} s.")
        if errors: raise ToolError("Frida could not enumerate DeviceBean: " + errors[0])
        script.unload(); session.detach()
    except ToolError: raise
    except Exception as exc: raise ToolError(f"Could not attach Frida to PID {pid}: {exc}") from exc
    return sorted(records.values(), key=lambda item: (item["name"].casefold(), item["device_id"]))


def normalize_mac(value: Any) -> str:
    """Normalize a DeviceBean MAC to AA:BB:CC:DD:EE:FF when the value is recognizable."""
    try:
        raw = str(value or "").strip()
        if not raw:
            return ""
        cleaned = "".join(ch for ch in raw if ch not in ":-")
        if len(cleaned) == 12 and all(ch in "0123456789abcdefABCDEF" for ch in cleaned):
            hexed = cleaned.upper()
            return ":".join(hexed[i : i + 2] for i in range(0, 12, 2))
        return raw
    except Exception:
        return ""


NEIGHBOR_STATE_PRIORITY = {
    "reachable": 0,
    "stale": 1,
    "delay": 2,
    "probe": 3,
    "permanent": 4,
}
SKIPPED_NEIGHBOR_STATES = {"incomplete", "unreachable"}
POWERSHELL_NEIGHBORS = (
    "Get-NetNeighbor -AddressFamily IPv4 | "
    "Select-Object IPAddress, LinkLayerAddress, @{n='State';e={$_.State.ToString()}} | "
    "ConvertTo-Json -Compress"
)


def mac_lookup_key(value: Any) -> str:
    """Normalize a MAC so ':' and '-' compare as the same 12-character hex key."""
    cleaned = "".join(ch for ch in str(value or "") if ch not in ":-").upper()
    if len(cleaned) == 12 and all(ch in "0123456789ABCDEF" for ch in cleaned):
        return cleaned
    return ""


def is_usable_lan_ipv4(value: str) -> bool:
    try:
        addr = ipaddress.IPv4Address(value)
    except ValueError:
        return False
    if addr.is_unspecified or addr.is_multicast or addr.is_loopback or addr.is_link_local or addr.is_reserved:
        return False
    return value != "255.255.255.255"


def _neighbor_field(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, dict):
        for key in ("IPAddress", "value", "Address"):
            if key in value:
                return str(value[key]).strip()
        return ""
    return str(value).strip()


def read_windows_ipv4_neighbors() -> list[dict[str, str]] | None:
    """Read the local IPv4 neighbor/ARP table. Returns None if the lookup itself failed."""
    if sys.platform != "win32":
        return []
    powershell = shutil.which("powershell.exe") or shutil.which("powershell")
    if not powershell:
        print("Warning: PowerShell was not found; Windows neighbor fallback for lan_ip was skipped.", file=sys.stderr)
        return None
    try:
        result = subprocess.run(
            [powershell, "-NoProfile", "-NonInteractive", "-Command", POWERSHELL_NEIGHBORS],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=15,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"Warning: Windows neighbor table lookup failed; lan_ip may stay empty. ({exc})", file=sys.stderr)
        return None
    if result.returncode:
        detail = (result.stderr or result.stdout or "Get-NetNeighbor failed").strip()
        print(f"Warning: Windows neighbor table lookup failed; lan_ip may stay empty. ({detail})", file=sys.stderr)
        return None
    raw = (result.stdout or "").strip().lstrip("\ufeff")
    if not raw or raw in {"null", "[]"}:
        return []
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        print("Warning: Windows neighbor table lookup returned unreadable data; lan_ip may stay empty.", file=sys.stderr)
        return None
    if isinstance(parsed, dict):
        parsed = [parsed]
    if not isinstance(parsed, list):
        return []
    neighbors: list[dict[str, str]] = []
    for entry in parsed:
        if not isinstance(entry, dict):
            continue
        ip = _neighbor_field(entry.get("IPAddress"))
        mac = mac_lookup_key(entry.get("LinkLayerAddress"))
        state = _neighbor_field(entry.get("State"))
        if ip and mac and mac != "000000000000":
            neighbors.append({"ip": ip, "mac": mac, "state": state})
    return neighbors


def match_neighbor_ip(mac: str, neighbors: list[dict[str, str]]) -> str:
    wanted = mac_lookup_key(mac)
    if not wanted:
        return ""
    ranked: list[tuple[int, str]] = []
    for entry in neighbors:
        if entry["mac"] != wanted:
            continue
        if not is_usable_lan_ipv4(entry["ip"]):
            continue
        state = entry["state"].casefold()
        if state in SKIPPED_NEIGHBOR_STATES:
            continue
        ranked.append((NEIGHBOR_STATE_PRIORITY.get(state, 50), entry["ip"]))
    if not ranked:
        return ""
    ranked.sort(key=lambda item: item[0])
    return ranked[0][1]


def discover_lan_ips(device_ids: list[str]) -> dict[str, str]:
    """Fill LAN IPs from a TinyTuya UDP broadcast scan when the optional module is installed."""
    ips = {device_id: "" for device_id in device_ids}
    if not device_ids:
        return ips
    try:
        import tinytuya  # type: ignore
    except ImportError:
        print(
            "Warning: TinyTuya is not installed; skipping Tuya LAN broadcast. Optional: py -m pip install tinytuya",
            file=sys.stderr,
        )
        return ips

    result: dict[str, Any] = {"found": None, "error": None}

    def run_scan() -> None:
        try:
            result["found"] = tinytuya.deviceScan(
                verbose=False, maxretry=15, color=False, poll=False, forcescan=False
            )
        except TypeError:
            try:
                result["found"] = tinytuya.deviceScan(False, 15, False, False, False)
            except Exception as exc:
                result["error"] = exc
        except Exception as exc:
            result["error"] = exc

    worker = threading.Thread(target=run_scan, daemon=True)
    worker.start()
    worker.join(20)
    if worker.is_alive():
        print("Warning: TinyTuya LAN discovery timed out; skipping Tuya LAN broadcast.", file=sys.stderr)
        return ips
    if result["error"] is not None:
        print(
            f"Warning: TinyTuya LAN discovery failed; skipping Tuya LAN broadcast. ({result['error']})",
            file=sys.stderr,
        )
        return ips
    found = result["found"]
    if not isinstance(found, dict):
        print("Warning: TinyTuya LAN discovery returned no usable results; skipping Tuya LAN broadcast.", file=sys.stderr)
        return ips

    by_id: dict[str, str] = {}
    for ip, info in found.items():
        if not isinstance(info, dict):
            continue
        gw_id = str(info.get("gwId") or info.get("id") or "")
        lan_ip = str(info.get("ip") or ip or "").strip()
        if gw_id and lan_ip:
            by_id[gw_id] = lan_ip
    for device_id in device_ids:
        ips[device_id] = by_id.get(device_id, "")
    return ips


def fill_lan_ips(records: list[dict[str, str]]) -> None:
    """Prefer TinyTuya Device ID matches, then Windows IPv4 neighbor/ARP lookup by MAC."""
    by_id = discover_lan_ips([item["device_id"] for item in records])
    for item in records:
        item["lan_ip"] = by_id.get(item["device_id"], "")
    missing = [item for item in records if not item.get("lan_ip") and item.get("mac")]
    if not missing:
        return
    neighbors = read_windows_ipv4_neighbors()
    if not neighbors:
        return
    for item in missing:
        item["lan_ip"] = match_neighbor_ip(item["mac"], neighbors)


def masked(key: str) -> str:
    return "*" * max(0, len(key) - 4) + key[-4:]


def main() -> int:
    parser = argparse.ArgumentParser(description="Export DeviceBean data from the owner's authenticated official Lefant session.")
    parser.add_argument("--serial", help="ADB serial when more than one device is connected")
    parser.add_argument("--adb", help="Path to adb.exe")
    parser.add_argument("--package", default=PACKAGE, help=f"Official package (default: {PACKAGE})")
    parser.add_argument("--frida-address", help="Authorized remote Frida endpoint, e.g. 127.0.0.1:27042")
    parser.add_argument("--timeout", type=float, default=15, help="Maximum enumeration wait in seconds (15)")
    parser.add_argument("--output", default="devices.json", help="Output JSON file (devices.json)")
    parser.add_argument("--show-key", action="store_true", help="Show complete local_key values in the console")
    args = parser.parse_args()
    if args.timeout <= 0: parser.error("--timeout must be greater than zero")
    try:
        adb, serial = locate_adb(args.adb), None
        serial = select_serial(adb, args.serial)
        pid = app_pid(adb, serial, args.package)
        print(f"Connected to {serial}; official Lefant is running (PID {pid}).")
        records = extract(serial, pid, args.frida_address, args.timeout)
        if not records: raise ToolError("No DeviceBean with device_id and local_key was found. Open your device list and try again.")
        fill_lan_ips(records)
        output = Path(args.output).resolve(); output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(records, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"Exported {len(records)} owned device(s) to {output}")
        for item in records:
            key = item["local_key"] if args.show_key else masked(item["local_key"])
            lan_ip = item.get("lan_ip") or "(none)"
            print(f"- {item['name'] or '(unnamed)'} | {item['device_id']} | key={key} | lan_ip={lan_ip}")
        return 0
    except ToolError as exc:
        print(f"Error: {exc}", file=sys.stderr); return 1


if __name__ == "__main__": raise SystemExit(main())
