#!/usr/bin/env python3
"""Read byte counters from the default-route interface for the status bar."""

import json
import sys
from pathlib import Path

VIRTUAL_PREFIXES = ("br-", "docker", "veth", "tailscale", "tun", "tap", "virbr", "wg")


def default_interface(preferred: str = "") -> str:
    preferred_stats = Path("/sys/class/net") / preferred / "statistics"
    if preferred and preferred != "lo" and preferred_stats.is_dir():
        return preferred

    try:
        with Path("/proc/net/route").open(encoding="ascii") as routes:
            next(routes, None)
            for row in routes:
                fields = row.split()
                if (
                    len(fields) >= 4
                    and fields[0] != "lo"
                    and fields[1] == "00000000"
                    and int(fields[3], 16) & 1
                ):
                    return fields[0]
    except (OSError, ValueError):
        pass

    try:
        for row in Path("/proc/net/ipv6_route").read_text(encoding="ascii").splitlines():
            fields = row.split()
            interface = fields[-1] if fields else ""
            if (
                len(fields) >= 10
                and fields[0] == "0" * 32
                and fields[1] == "00"
                and interface != "lo"
            ):
                return interface
    except OSError:
        pass

    interfaces = []
    try:
        for device in sorted(Path("/sys/class/net").iterdir()):
            if device.name == "lo" or device.name.startswith(VIRTUAL_PREFIXES):
                continue
            if (device / "device").exists() and (device / "statistics").is_dir():
                interfaces.append(device.name)
    except OSError:
        pass
    return ",".join(interfaces)


def main() -> None:
    interface = default_interface(sys.argv[1] if len(sys.argv) > 1 else "")
    rx = tx = 0
    valid_interfaces = []
    for name in interface.split(","):
        root = Path("/sys/class/net") / name / "statistics"
        try:
            rx += int((root / "rx_bytes").read_text(encoding="ascii").strip())
            tx += int((root / "tx_bytes").read_text(encoding="ascii").strip())
            valid_interfaces.append(name)
        except (OSError, ValueError):
            continue
    result = {
        "interface": ",".join(valid_interfaces),
        "rx": rx,
        "tx": tx,
    }
    print(json.dumps(result, separators=(",", ":")))


if __name__ == "__main__":
    main()
