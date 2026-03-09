# tesmart-ui-zig

A graphical UI for [TeSmart 16-port HDMI/KVM Switches](https://www.tesmart.com/), written in [Zig](https://ziglang.org/) and [raylib](https://www.raylib.com/).

## Features

- **4 × 4 port grid** – click any button to instantly switch the active KVM input
- **TCP/IP connection** – connect to the switch's Ethernet adapter (default port 5000)
- **RS-232 serial connection** – connect via a USB-to-serial adapter (`/dev/ttyUSB0`, etc.)
- **Active-port indicator** – always shows which input is currently selected
- **Query button** – read the current active port directly from the switch
- Dark UI theme with live status messages

## Protocol

TeSmart switches use a simple 6-byte command frame over both TCP and RS-232:

| Byte | Value | Description |
|------|-------|-------------|
| 0    | `0xAA` | Header 1 |
| 1    | `0xBB` | Header 2 |
| 2    | `0x03` | Length |
| 3    | Command | `0x01` switch, `0x10` query, `0x02` beeper |
| 4    | Data | Port index (0-based) or beeper flag |
| 5    | `0xEE` | Tail |

**Serial settings:** 9600 baud, 8-N-1, no flow control.

## Requirements

| Dependency | Version |
|------------|---------|
| [Zig](https://ziglang.org/download/) | ≥ 0.14.0 |
| raylib-zig (fetched automatically) | devel |

## Building

### 1 – Fetch the raylib-zig dependency

```sh
zig fetch --save https://github.com/Not-Nik/raylib-zig/archive/devel.tar.gz
```

This command downloads the package and updates `build.zig.zon` with the correct hash.

### 2 – Build & run

```sh
zig build run
```

Or build only:

```sh
zig build
# Binary is placed at:  zig-out/bin/tesmart-ui
```

### Cross-compiling

```sh
# Example: build for Linux x86-64 on any host
zig build -Dtarget=x86_64-linux-gnu
```

## Usage

1. Enter the **IP address** and **port** (default `5000`) of your switch's Ethernet adapter, then click **Connect TCP**, _or_
2. Enter the serial device path (e.g. `/dev/ttyUSB0`) and click **Connect RS232**.
3. Click any port button to switch the KVM to that input.
4. Use **Query Port** to read the currently active input from the switch.
5. Click **Disconnect** when done.

## License

MIT – see [LICENSE](LICENSE).