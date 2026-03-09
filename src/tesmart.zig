//! TeSmart 16-Port HDMI/KVM Switch protocol implementation.
//!
//! Supports both TCP/IP (port 5000 by default) and RS-232 serial (9600 8N1)
//! communication methods used by the TeSmart switch family.
//!
//! Command frame format (6 bytes):
//!   0xAA  0xBB  0x03  <CMD>  <DATA>  0xEE

const std = @import("std");
const builtin = @import("builtin");

// ── POSIX / C headers for serial port support ─────────────────────────────────
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

// ── Protocol constants ─────────────────────────────────────────────────────────

/// Default TCP port used by TeSmart switches with Ethernet adapters.
pub const DEFAULT_TCP_PORT: u16 = 5000;

/// Number of input ports on the 16-port switch.
pub const MAX_PORTS: u8 = 16;

// Command frame structure
const HDR1: u8 = 0xAA;
const HDR2: u8 = 0xBB;
const FRAME_LEN: u8 = 0x03;
const TAIL: u8 = 0xEE;

// Command bytes
const CMD_SWITCH: u8 = 0x01; // Switch active port
const CMD_QUERY: u8 = 0x10; // Query active port
const CMD_RESP: u8 = 0x11; // Response to port query
const CMD_BEEP: u8 = 0x02; // Beeper on/off

const FRAME_SIZE: usize = 6;

// ── Public error set ───────────────────────────────────────────────────────────

pub const Error = error{
    NotConnected,
    InvalidPort,
    InvalidResponse,
    ConnectionFailed,
    WriteError,
    ReadError,
    SerialConfigError,
    UnsupportedPlatform,
};

// ── Connection type ────────────────────────────────────────────────────────────

/// Maximum length (including null) for a serial device path string.
const MAX_DEVICE_PATH_LEN: usize = 256;

pub const ConnectionType = enum { tcp, serial };

// ── Main TeSmart controller struct ────────────────────────────────────────────

pub const TeSmart = struct {
    allocator: std.mem.Allocator,
    conn_type: ?ConnectionType = null,
    tcp_stream: ?std.net.Stream = null,
    /// File descriptor for an open serial port, or null when not connected.
    serial_fd: ?c_int = null,
    /// 1-16; 0 means unknown.
    current_port: u8 = 0,

    pub fn init(allocator: std.mem.Allocator) TeSmart {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TeSmart) void {
        self.disconnect();
    }

    // ── Connection management ──────────────────────────────────────────────────

    /// Open a TCP connection to the TeSmart switch.
    pub fn connectTcp(self: *TeSmart, host: []const u8, port: u16) !void {
        self.disconnect();
        const stream = try std.net.tcpConnectToHost(self.allocator, host, port);
        self.tcp_stream = stream;
        self.conn_type = .tcp;
    }

    /// Open an RS-232 serial connection to the TeSmart switch.
    /// `device` is the path to the serial device, e.g. "/dev/ttyUSB0".
    pub fn connectSerial(self: *TeSmart, device: []const u8) !void {
        if (builtin.os.tag == .windows) return Error.UnsupportedPlatform;
        self.disconnect();

        // Build a null-terminated copy of the device path.
        var dev: [MAX_DEVICE_PATH_LEN]u8 = undefined;
        if (device.len >= dev.len) return Error.ConnectionFailed;
        @memcpy(dev[0..device.len], device);
        dev[device.len] = 0;

        const fd = c.open(&dev, c.O_RDWR | c.O_NOCTTY | c.O_SYNC);
        if (fd < 0) return Error.ConnectionFailed;
        errdefer _ = c.close(fd);

        try configureSerial(fd);

        self.serial_fd = fd;
        self.conn_type = .serial;
    }

    /// Close any open connection and reset state.
    pub fn disconnect(self: *TeSmart) void {
        if (self.tcp_stream) |*s| {
            s.close();
            self.tcp_stream = null;
        }
        if (self.serial_fd) |fd| {
            _ = c.close(fd);
            self.serial_fd = null;
        }
        self.conn_type = null;
        self.current_port = 0;
    }

    /// Returns true when a connection is open.
    pub fn isConnected(self: *const TeSmart) bool {
        return self.conn_type != null;
    }

    // ── Switch commands ────────────────────────────────────────────────────────

    /// Switch the KVM to `port` (1 – 16).
    pub fn switchToPort(self: *TeSmart, port: u8) !void {
        if (port < 1 or port > MAX_PORTS) return Error.InvalidPort;
        const cmd = buildFrame(CMD_SWITCH, port - 1); // switch uses 0-indexed port
        try self.sendFrame(&cmd);
        self.current_port = port;
    }

    /// Query the currently active port and return it (1 – 16).
    pub fn queryCurrentPort(self: *TeSmart) !u8 {
        const cmd = buildFrame(CMD_QUERY, 0x00);
        try self.sendFrame(&cmd);

        var resp: [FRAME_SIZE]u8 = undefined;
        const n = try self.recvFrame(&resp);
        if (n == FRAME_SIZE and
            resp[0] == HDR1 and resp[1] == HDR2 and
            resp[2] == FRAME_LEN and resp[3] == CMD_RESP and
            resp[5] == TAIL)
        {
            self.current_port = resp[4] + 1; // response is 0-indexed
            return self.current_port;
        }
        return Error.InvalidResponse;
    }

    /// Enable (`true`) or disable (`false`) the audible beeper.
    pub fn setBeeper(self: *TeSmart, on: bool) !void {
        const cmd = buildFrame(CMD_BEEP, if (on) @as(u8, 0x01) else @as(u8, 0x00));
        try self.sendFrame(&cmd);
    }

    // ── Internal helpers ───────────────────────────────────────────────────────

    fn buildFrame(cmd: u8, data: u8) [FRAME_SIZE]u8 {
        return .{ HDR1, HDR2, FRAME_LEN, cmd, data, TAIL };
    }

    fn sendFrame(self: *TeSmart, frame: []const u8) !void {
        switch (self.conn_type orelse return Error.NotConnected) {
            .tcp => {
                const s = self.tcp_stream orelse return Error.NotConnected;
                try s.writeAll(frame);
            },
            .serial => {
                const fd = self.serial_fd orelse return Error.NotConnected;
                const n = c.write(fd, frame.ptr, frame.len);
                if (n < 0 or @as(usize, @intCast(n)) != frame.len)
                    return Error.WriteError;
            },
        }
    }

    fn recvFrame(self: *TeSmart, buf: []u8) !usize {
        switch (self.conn_type orelse return Error.NotConnected) {
            .tcp => {
                const s = self.tcp_stream orelse return Error.NotConnected;
                return try s.read(buf);
            },
            .serial => {
                const fd = self.serial_fd orelse return Error.NotConnected;
                const n = c.read(fd, buf.ptr, buf.len);
                if (n < 0) return Error.ReadError;
                return @intCast(n);
            },
        }
    }
};

// ── Serial port helper (POSIX only) ───────────────────────────────────────────

/// Configure a serial port file descriptor for 9600-8N1 communication.
fn configureSerial(fd: c_int) Error!void {
    var tty: c.struct_termios = std.mem.zeroes(c.struct_termios);
    if (c.tcgetattr(fd, &tty) != 0) return Error.SerialConfigError;

    _ = c.cfsetospeed(&tty, c.B9600);
    _ = c.cfsetispeed(&tty, c.B9600);

    // 8 data bits, no parity, 1 stop bit
    tty.c_cflag = (tty.c_cflag & ~@as(c_uint, c.CSIZE)) | c.CS8;
    tty.c_cflag &= ~@as(c_uint, c.PARENB | c.CSTOPB);
    // Disable hardware flow control; enable receiver + local mode
    tty.c_cflag &= ~@as(c_uint, c.CRTSCTS);
    tty.c_cflag |= @as(c_uint, c.CLOCAL | c.CREAD);

    // Raw input: no line discipline, no echo, no signals
    tty.c_lflag &= ~@as(c_uint, c.ICANON | c.ECHO | c.ECHOE | c.ISIG);
    // Disable software flow control and input processing
    tty.c_iflag &= ~@as(c_uint, c.IXON | c.IXOFF | c.IXANY | c.ICRNL);
    // Raw output
    tty.c_oflag &= ~@as(c_uint, c.OPOST);

    // Non-blocking read; 1-second timeout
    tty.c_cc[c.VMIN] = 0;
    tty.c_cc[c.VTIME] = 10;

    if (c.tcsetattr(fd, c.TCSANOW, &tty) != 0) return Error.SerialConfigError;
}
