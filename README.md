# TeSmart UI (Zig)

A cross-platform GUI for controlling **TESmart 16-port HDMI/KVM switches**.

Ported from the original [Go/Fyne version](https://github.com/SiirRandall/tesmart-ui) to **Zig + raylib**.

---

## Features

- **16-Port Grid** — click to switch inputs; active port highlighted with animated glow effects
- **Per-Port Customization** — custom names, icons (PNG), per-port icon scaling
- **Port Filtering** — mark ports active/inactive, toggle filter to hide unused ports with animated transitions
- **System Tray** — native tray icon on macOS (Cocoa), Linux (AppIndicator), and Windows (Shell_NotifyIcon) with port switching, buzzer toggle, and quit
- **Polling** — background thread polls the active input (configurable interval)
- **Device Controls** — buzzer mute/unmute, LED timeout, ping
- **Network Configuration** — read/set switch IP, netmask, gateway, port (ASCII protocol)
- **First-Run Setup** — guided connection dialog on first launch
- **macOS App Bundle** — `bundle_macos.sh` builds a signed `.app` with icon
- **JSON Config** — auto-created on first run, persists all settings

---

## Architecture Changes from Go

| Go (original) | Zig (this port) |
|---|---|
| Fyne (retained-mode GUI) | raylib (immediate-mode) |
| YAML config (`gopkg.in/yaml.v3`) | JSON config (hand-rolled) |
| `goroutine` + `channel` | `std.Thread` + `std.atomic` |
| System tray (fyne/systray) | Native tray (Cocoa / AppIndicator / Win32) |
| `net.Dialer` | `std.net.tcpConnectToAddress` |

---

## Requirements

- **Zig 0.15.0+**
- **raylib-zig** (fetched automatically via `zig fetch`)
- A TESmart HDMI/KVM switch (default IP `192.168.1.10`, port `5000`)

### Platform-specific (for system tray)

| Platform | Extra dependencies |
|---|---|
| macOS | None (Cocoa is built-in) |
| Linux | `libayatana-appindicator3-dev`, `libgtk-3-dev` |
| Windows | None (Win32 APIs are built-in) |

## Quick Start

```bash
# 1. Clone
git clone <your-repo-url>
cd tesmart-ui-zig

# 2. Fetch the raylib-zig dependency (populates the hash in build.zig.zon)
zig fetch --save git+https://github.com/raylib-zig/raylib-zig#devel

# 3. Build & run
zig build run
```

### Build a release binary

```bash
zig build -Doptimize=ReleaseFast
# Binary at: zig-out/bin/tesmart-ui
```

### macOS App Bundle

```bash
# Place an optional AppIcon.png or AppIcon.icns in the project root, then:
./bundle_macos.sh

# Output: zig-out/TeSmart UI.app
# Install: cp -r "zig-out/TeSmart UI.app" /Applications/
```

---

## Configuration

On first run, a JSON config is created at:

| OS | Path |
|---|---|
| macOS | `~/Library/Application Support/tesmart-ui/config.json` |
| Linux | `~/.config/tesmart-ui/config.json` |
| Windows | `%APPDATA%\tesmart-ui\config.json` |

Example:

```json
{
  "ip": "192.168.1.10",
  "port": 5000,
  "poll_interval_ms": 1000,
  "fast_mode": false,
  "get_timeout_ms": 600,
  "set_timeout_ms": 450,
  "verify_after_set": true,
  "switch_suppress_ms": 800,
  "setup_completed": false,
  "buzzer_enabled": true,
  "hide_inactive": false,
  "ports": {
    "1":  { "name": "HDMI Port 1", "icon": "", "icon_scale": 1.0, "active": true },
    "2":  { "name": "HDMI Port 2", "icon": "", "icon_scale": 1.0, "active": true },
    ...
    "16": { "name": "HDMI Port 16", "icon": "", "icon_scale": 1.0, "active": true }
  }
}
```

---

## Usage

- **Left-click** a tile to switch to that port
- **Right-click** a tile to open the edit dialog for that port
- **Toolbar buttons**: Connect, Edit, Network, Ping, Buzzer, Filter, About
- **Filter**: hides inactive ports from the grid and system tray (with animated resize)
- **System tray**: switch ports, toggle buzzer, show window, or quit

---

## Protocol Notes

- Input switching & status use **binary frames**: `AA BB 03 <cmd> <arg> EE`
- Network configuration uses **ASCII** commands: `IP?`, `IP:x.x.x.x;`, etc.
- Many models require a **power cycle** for new IP/port to take effect

---

## Project Structure

```
tesmart-ui-zig/
├── build.zig          # Build script (links raylib + platform tray)
├── build.zig.zon      # Package manifest
├── bundle_macos.sh    # macOS .app bundle script
├── README.md
└── src/
    ├── main.zig       # Entry point
    ├── client.zig     # TCP client (binary + ASCII protocol)
    ├── config.zig     # JSON config load/save
    ├── gui.zig        # raylib GUI (grid, toolbar, dialogs, polling)
    ├── native.zig     # OS-native helpers (file picker, icon paths)
    ├── protocol.zig   # Binary frame constants, parsing, hex helpers
    ├── tray.zig       # Zig tray wrapper (cross-platform)
    ├── tray_macos.m   # macOS tray (NSStatusItem / Cocoa)
    ├── tray_linux.c   # Linux tray (AppIndicator3 / GTK)
    └── tray_windows.c # Windows tray (Shell_NotifyIcon / Win32)
```

---

## License

MIT — see [LICENSE](LICENSE).

---

## Credits

- Original Go/Fyne app: [SiirRandall/tesmart-ui](https://github.com/SiirRandall/tesmart-ui)
- Protocol docs: [Kreeblah/TESmartSwitchAPI-macOS](https://github.com/Kreeblah/TESmartSwitchAPI-macOS)
- CLI inspiration: [mirceanton/tesmartctl](https://github.com/mirceanton/tesmartctl)
