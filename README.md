# TeSmart UI

A lightweight, cross-platform desktop GUI for controlling **TeSmart 16-port HDMI/KVM switches** over the network.

Built with **Zig** and **raylib** for fast startup, low memory usage, and native performance on macOS, Linux, and Windows.

![License](https://img.shields.io/badge/license-MIT-blue)

---

## Features

### Switch Control
- **16-Port Grid** — click any tile to switch inputs instantly
- **Active Port Highlight** — animated glow, bounce, and neon border effects on the active port
- **Buzzer Control** — mute/unmute the switch buzzer
- **Ping** — test connectivity to the switch with round-trip timing
- **LED Timeout** — configure the switch front-panel LED timeout

### Customization
- **Custom Port Names** — label each port (e.g. "Gaming PC", "Mac Studio")
- **Custom Icons** — assign a PNG icon to any port
- **Per-Port Icon Scaling** — adjust icon size per port
- **Active/Inactive Ports** — mark ports as inactive to declutter the grid
- **Port Filtering** — toggle to hide inactive ports with smooth animated transitions

### Network Configuration
- **Read/Write Network Settings** — view and change the switch IP, netmask, gateway, and TCP port using the ASCII protocol
- **Raw Hex Commands** — send arbitrary hex frames for advanced users

### System Tray
- **macOS** — native Cocoa `NSStatusItem`
- **Linux** — AppIndicator3 + GTK3 (KDE & GNOME compatible)
- **Windows** — Win32 `Shell_NotifyIcon`
- Switch ports, toggle buzzer, and quit — all from the tray menu

### Connection
- **Persistent TCP Connection** — maintains a single connection to the switch with automatic reconnection on error
- **Background Polling** — dedicated thread polls the active input at a configurable interval
- **Switch Suppression** — prevents stale poll reads from overriding a pending switch command
- **First-Run Setup** — guided connection dialog on first launch

### Text Editing
- Full cursor support in all input fields
- Arrow keys, Home/End, click-to-position, Delete/Backspace

### Performance
- **Dynamic FPS** — 60 FPS during animations, 30 FPS on input, 15 FPS idle, 1 FPS unfocused
- **Dirty-Flag Rendering** — only elevates frame rate when state actually changes
- **Low Idle CPU** — ~5% focused idle on Apple M2 Pro

### Packaging
- **macOS App Bundle** — signed `.app` with custom icon via `bundle_macos.sh`
- **Linux AppImage** — portable single-file executable via `bundle_linux.sh`

### Configuration
- **JSON Config** — auto-created on first run, persists all settings
- **Verbose Mode** — console logging disabled by default, enable with `-Dverbose=true`

---

## Screenshots

<!-- Add screenshots here -->

---

## Requirements

- **Zig 0.15.0+**
- A TeSmart HDMI/KVM switch (default: `192.168.1.10:5000`)

raylib-zig is fetched automatically during the build.

### Platform Dependencies (System Tray)

| Platform | Dependencies |
|---|---|
| macOS | None (Cocoa is built-in) |
| Debian / Ubuntu | `libayatana-appindicator3-dev libgtk-3-dev` |
| Fedora / RHEL | `libayatana-appindicator-gtk3-devel gtk3-devel` |
| Arch | `libayatana-appindicator gtk3` |
| openSUSE | `libayatana-appindicator3-devel gtk3-devel` |
| Windows | None (Win32 APIs are built-in) |

---

## Quick Start

```bash
git clone https://github.com/SiirRandall/tesmart-ui-zig.git
cd tesmart-ui-zig
zig build run
```

On first launch, a setup dialog will ask for your switch's IP address and port.

### Build Options

```bash
# Release build
zig build -Doptimize=ReleaseFast

# Enable console logging
zig build run -Dverbose=true

# Output binary: zig-out/bin/tesmart-ui
```

### macOS App Bundle

```bash
./bundle_macos.sh
# Output: zig-out/TeSmart UI.app
cp -r "zig-out/TeSmart UI.app" /Applications/
```

Place an `AppIcon.png` or `AppIcon.icns` in the project root before bundling to use a custom icon.

### Linux AppImage

```bash
./bundle_linux.sh
# Output: zig-out/TeSmart_UI-x86_64.AppImage
chmod +x zig-out/TeSmart_UI-x86_64.AppImage
./zig-out/TeSmart_UI-x86_64.AppImage
```

---

## Configuration

A JSON config file is auto-created on first run:

| OS | Path |
|---|---|
| macOS | `~/Library/Application Support/tesmart-ui/config.json` |
| Linux | `~/.config/tesmart-ui/config.json` |
| Windows | `%APPDATA%\tesmart-ui\config.json` |

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
  "buzzer_enabled": true,
  "hide_inactive": false,
  "ports": {
    "1":  { "name": "HDMI Port 1", "icon": "", "icon_scale": 1.0, "active": true },
    "2":  { "name": "HDMI Port 2", "icon": "", "icon_scale": 1.0, "active": true }
  }
}
```

---

## Usage

| Action | How |
|---|---|
| Switch port | Left-click a tile |
| Edit port | Right-click a tile |
| Toggle buzzer | Toolbar button or tray menu |
| Filter inactive ports | Toolbar "Filter" button |
| Network settings | Toolbar "Network" button |
| Ping switch | Toolbar "Ping" button |

### Toolbar

`Connect` · `Edit` · `Network` · `Ping` · `Buzzer` · `Filter` · `About`

---

## Protocol

TeSmart switches use two protocols over TCP:

**Binary** (input switching & status):
```
Request:  AA BB 03 <cmd> <arg> EE
Response: AA BB 03 <cmd> <arg> EE
```

**ASCII** (network configuration):
```
IP?         → returns current IP
IP:x.x.x.x;  → sets IP (requires power cycle)
```

See [TESmartSwitchAPI-macOS](https://github.com/Kreeblah/TESmartSwitchAPI-macOS) for full protocol documentation.

---

## Project Structure

```
tesmart-ui-zig/
├── build.zig          Build configuration
├── build.zig.zon      Package manifest (raylib-zig dependency)
├── bundle_macos.sh    macOS .app bundle script
├── bundle_linux.sh    Linux AppImage bundle script
├── AppIcon.png        Application icon
└── src/
    ├── main.zig       Entry point
    ├── gui.zig        GUI — grid, toolbar, dialogs, animations, polling
    ├── client.zig     TCP client — persistent connection, binary + ASCII protocol
    ├── config.zig     JSON config — load, save, defaults
    ├── protocol.zig   Binary frame constants and hex helpers
    ├── native.zig     OS-native helpers (file picker, font paths)
    ├── tray.zig       Cross-platform tray wrapper
    ├── tray_macos.m   macOS tray (Cocoa NSStatusItem)
    ├── tray_linux.c   Linux tray (AppIndicator3 / GTK3)
    └── tray_windows.c Windows tray (Shell_NotifyIcon)
```

---

## License

MIT — see [LICENSE](LICENSE).

---

## Acknowledgments

- Protocol documentation: [Kreeblah/TESmartSwitchAPI-macOS](https://github.com/Kreeblah/TESmartSwitchAPI-macOS)
- GUI framework: [raylib](https://www.raylib.com/) via [raylib-zig](https://github.com/raylib-zig/raylib-zig)
