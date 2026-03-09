// client.zig — TCP client for TESmart binary + ASCII protocol
const std = @import("std");
const proto = @import("protocol.zig");
const posix = std.posix;

const Allocator = std.mem.Allocator;
const net = std.net;

pub const KVMNetConfig = struct {
    ip: [64]u8 = undefined,
    ip_len: usize = 0,
    port: u16 = 5000,
    mask: [64]u8 = undefined,
    mask_len: usize = 0,
    gw: [64]u8 = undefined,
    gw_len: usize = 0,

    pub fn ipSlice(self: *const KVMNetConfig) []const u8 {
        return self.ip[0..self.ip_len];
    }
    pub fn maskSlice(self: *const KVMNetConfig) []const u8 {
        return self.mask[0..self.mask_len];
    }
    pub fn gwSlice(self: *const KVMNetConfig) []const u8 {
        return self.gw[0..self.gw_len];
    }
};

pub const Client = struct {
    ip: [64]u8 = undefined,
    ip_len: usize = 0,
    port: u16 = 5000,
    get_timeout_ms: u64 = 600,
    set_timeout_ms: u64 = 450,
    mutex: std.Thread.Mutex = .{},
    stream: ?net.Stream = null,

    pub fn init(ip: []const u8, port: u16, get_to_ms: u64, set_to_ms: u64) Client {
        var c = Client{};
        c.setTarget(ip, port, get_to_ms, set_to_ms);
        return c;
    }

    pub fn setTarget(self: *Client, ip: []const u8, port: u16, get_to_ms: u64, set_to_ms: u64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.disconnectLocked();
        const len = @min(ip.len, self.ip.len);
        @memcpy(self.ip[0..len], ip[0..len]);
        self.ip_len = len;
        self.port = port;
        self.get_timeout_ms = get_to_ms;
        self.set_timeout_ms = set_to_ms;
    }

    /// Close the persistent connection (call when done).
    pub fn close(self: *Client) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.disconnectLocked();
    }

    /// Close connection (caller must hold mutex).
    fn disconnectLocked(self: *Client) void {
        if (self.stream) |s| {
            s.close();
            self.stream = null;
        }
    }

    /// Return existing stream or open a new persistent connection (caller must hold mutex).
    fn ensureConnectedLocked(self: *Client) !net.Stream {
        if (self.stream) |s| return s;
        const addr = try self.resolveAddr();
        const s = try net.tcpConnectToAddress(addr);
        // Set receive timeout so read() doesn't block forever
        const tv = posix.timeval{ .sec = 0, .usec = 200_000 }; // 200ms
        posix.setsockopt(s.handle, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(tv)) catch {};
        self.stream = s;
        return s;
    }

    // ── Binary protocol ──

    const TxRxResult = struct { buf: [4096]u8, len: usize };

    /// Send a binary frame and collect the response (persistent connection with retry).
    fn txrx(self: *Client, cmd: u8, arg: u8, timeout_ms: u64) !TxRxResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.txrxLocked(cmd, arg, timeout_ms, true);
    }

    /// Inner txrx that assumes mutex is held. retry=true allows one reconnect attempt.
    fn txrxLocked(self: *Client, cmd: u8, arg: u8, timeout_ms: u64, retry: bool) !TxRxResult {
        const stream = self.ensureConnectedLocked() catch |err| {
            if (retry) {
                self.disconnectLocked();
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.txrxLocked(cmd, arg, timeout_ms, false);
            }
            return err;
        };

        const frame = proto.makeFrame(cmd, arg);
        stream.writeAll(&frame) catch |err| {
            self.disconnectLocked();
            if (retry) {
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.txrxLocked(cmd, arg, timeout_ms, false);
            }
            return err;
        };

        const deadline_ns: i128 = std.time.nanoTimestamp() + @as(i128, timeout_ms) * std.time.ns_per_ms;
        var result: TxRxResult = .{ .buf = undefined, .len = 0 };

        while (true) {
            if (std.time.nanoTimestamp() >= deadline_ns) break;

            var read_buf: [256]u8 = undefined;
            const n = stream.read(&read_buf) catch |err| {
                if (err == error.WouldBlock) {
                    std.Thread.sleep(15 * std.time.ns_per_ms);
                    continue;
                }
                self.disconnectLocked();
                if (retry and result.len == 0) {
                    std.Thread.sleep(50 * std.time.ns_per_ms);
                    return self.txrxLocked(cmd, arg, timeout_ms, false);
                }
                break;
            };
            if (n == 0) {
                // EOF — peer closed connection
                self.disconnectLocked();
                if (retry and result.len == 0) {
                    std.Thread.sleep(50 * std.time.ns_per_ms);
                    return self.txrxLocked(cmd, arg, timeout_ms, false);
                }
                break;
            }

            const space = result.buf.len - result.len;
            const copy_n = @min(n, space);
            @memcpy(result.buf[result.len..][0..copy_n], read_buf[0..copy_n]);
            result.len += copy_n;

            // Check for a complete frame
            var off_buf: [64]usize = undefined;
            if (proto.findFrames(result.buf[0..result.len], &off_buf) > 0) {
                return result;
            }
            if (result.len >= result.buf.len) break;
        }
        return result;
    }

    /// Get currently active input (1-based port number).
    pub fn getActiveInput(self: *Client) !u8 {
        const resp = try self.txrx(proto.CMD_GET_ACTIVE, 0x00, self.get_timeout_ms);
        if (proto.scanActivePort(resp.buf[0..resp.len])) |port| {
            return port;
        }
        // Retry once
        const resp2 = self.txrx(proto.CMD_GET_ACTIVE, 0x00, self.get_timeout_ms) catch return error.NoReply;
        if (proto.scanActivePort(resp2.buf[0..resp2.len])) |port| {
            return port;
        }
        return error.NoReply;
    }

    /// Switch to a specific input (1-16).
    pub fn setInput(self: *Client, port: u8) !void {
        if (port < 1 or port > 16) return error.PortOutOfRange;
        // Try CMD_SET_INPUT first (1-indexed)
        _ = self.txrx(proto.CMD_SET_INPUT, port, self.set_timeout_ms) catch {
            // Fallback to CMD_SET_INPUT_ALT (0-indexed)
            _ = try self.txrx(proto.CMD_SET_INPUT_ALT, port - 1, self.set_timeout_ms);
            return;
        };
    }

    /// Mute or unmute buzzer.
    pub fn setBuzzer(self: *Client, enabled: bool) !void {
        const v: u8 = if (enabled) 0x01 else 0x00;
        _ = try self.txrx(proto.CMD_BUZZER, v, self.set_timeout_ms);
    }

    pub fn setLEDTimeoutOff(self: *Client) !void {
        _ = try self.txrx(proto.CMD_LED_TIMEOUT, proto.LED_OFF, self.set_timeout_ms);
    }
    pub fn setLEDTimeout10s(self: *Client) !void {
        _ = try self.txrx(proto.CMD_LED_TIMEOUT, proto.LED_10S, self.set_timeout_ms);
    }
    pub fn setLEDTimeout30s(self: *Client) !void {
        _ = try self.txrx(proto.CMD_LED_TIMEOUT, proto.LED_30S, self.set_timeout_ms);
    }

    pub fn ping(self: *Client) !void {
        _ = try self.getActiveInput();
    }

    // ── Raw hex sender ──

    pub fn rawHexSend(self: *Client, hex_str: []const u8, timeout_ms: u64, out: []u8) !usize {
        var payload: [2048]u8 = undefined;
        const payload_len = try proto.hexDecode(hex_str, &payload);

        self.mutex.lock();
        defer self.mutex.unlock();

        return self.rawHexSendLocked(payload[0..payload_len], timeout_ms, out, true);
    }

    fn rawHexSendLocked(self: *Client, payload: []const u8, timeout_ms: u64, out: []u8, retry: bool) !usize {
        const stream = self.ensureConnectedLocked() catch |err| {
            if (retry) {
                self.disconnectLocked();
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.rawHexSendLocked(payload, timeout_ms, out, false);
            }
            return err;
        };

        stream.writeAll(payload) catch |err| {
            self.disconnectLocked();
            if (retry) {
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.rawHexSendLocked(payload, timeout_ms, out, false);
            }
            return err;
        };

        const deadline_ns: i128 = std.time.nanoTimestamp() + @as(i128, timeout_ms) * std.time.ns_per_ms;
        var result_buf: [4096]u8 = undefined;
        var result_len: usize = 0;

        while (true) {
            if (std.time.nanoTimestamp() >= deadline_ns) break;
            var tmp: [256]u8 = undefined;
            const n = stream.read(&tmp) catch |err| {
                if (err == error.WouldBlock) {
                    std.Thread.sleep(15 * std.time.ns_per_ms);
                    continue;
                }
                self.disconnectLocked();
                break;
            };
            if (n == 0) {
                self.disconnectLocked();
                break;
            }
            const space = result_buf.len - result_len;
            const cn = @min(n, space);
            @memcpy(result_buf[result_len..][0..cn], tmp[0..cn]);
            result_len += cn;
            if (result_len >= result_buf.len) break;
        }

        return proto.hexEncode(result_buf[0..result_len], out);
    }

    // ── ASCII network config ──

    fn sendAscii(self: *Client, pkt: []const u8, timeout_ms: u64, out: []u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.sendAsciiLocked(pkt, timeout_ms, out, true);
    }

    fn sendAsciiLocked(self: *Client, pkt: []const u8, timeout_ms: u64, out: []u8, retry: bool) !usize {
        const stream = self.ensureConnectedLocked() catch |err| {
            if (retry) {
                self.disconnectLocked();
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.sendAsciiLocked(pkt, timeout_ms, out, false);
            }
            return err;
        };

        stream.writeAll(pkt) catch |err| {
            self.disconnectLocked();
            if (retry) {
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.sendAsciiLocked(pkt, timeout_ms, out, false);
            }
            return err;
        };

        const deadline_ns: i128 = std.time.nanoTimestamp() + @as(i128, timeout_ms) * std.time.ns_per_ms;
        var result_len: usize = 0;

        while (true) {
            if (std.time.nanoTimestamp() >= deadline_ns) break;
            var tmp: [256]u8 = undefined;
            const n = stream.read(&tmp) catch |err| {
                if (err == error.WouldBlock) {
                    std.Thread.sleep(15 * std.time.ns_per_ms);
                    continue;
                }
                self.disconnectLocked();
                break;
            };
            if (n == 0) {
                self.disconnectLocked();
                break;
            }
            const space = out.len - result_len;
            const cn = @min(n, space);
            @memcpy(out[result_len..][0..cn], tmp[0..cn]);
            result_len += cn;
            if (result_len >= out.len) break;
        }
        return result_len;
    }

    fn sendAsciiUntilTerm(self: *Client, pkt: []const u8, timeout_ms: u64, term: u8, out: []u8) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.sendAsciiUntilTermLocked(pkt, timeout_ms, term, out, true);
    }

    fn sendAsciiUntilTermLocked(self: *Client, pkt: []const u8, timeout_ms: u64, term: u8, out: []u8, retry: bool) !usize {
        const stream = self.ensureConnectedLocked() catch |err| {
            if (retry) {
                self.disconnectLocked();
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.sendAsciiUntilTermLocked(pkt, timeout_ms, term, out, false);
            }
            return err;
        };

        stream.writeAll(pkt) catch |err| {
            self.disconnectLocked();
            if (retry) {
                std.Thread.sleep(50 * std.time.ns_per_ms);
                return self.sendAsciiUntilTermLocked(pkt, timeout_ms, term, out, false);
            }
            return err;
        };

        const deadline_ns: i128 = std.time.nanoTimestamp() + @as(i128, timeout_ms) * std.time.ns_per_ms;
        var result_len: usize = 0;

        while (true) {
            if (std.time.nanoTimestamp() >= deadline_ns) break;
            var tmp: [256]u8 = undefined;
            const n = stream.read(&tmp) catch |err| {
                if (err == error.WouldBlock) {
                    std.Thread.sleep(20 * std.time.ns_per_ms);
                    continue;
                }
                self.disconnectLocked();
                break;
            };
            if (n == 0) {
                self.disconnectLocked();
                break;
            }
            const space = out.len - result_len;
            const cn = @min(n, space);
            @memcpy(out[result_len..][0..cn], tmp[0..cn]);
            result_len += cn;

            // Check for terminator
            if (std.mem.indexOfScalar(u8, out[0..result_len], term) != null) break;
            if (result_len >= out.len) break;
        }

        // Clean: remove nulls, \r, \n and truncate at terminator
        return cleanAsciiResponse(out[0..result_len], out, term);
    }

    /// Read the switch's network configuration via ASCII commands.
    pub fn getNetworkConfigASCII(self: *Client) !KVMNetConfig {
        var cfg = KVMNetConfig{};

        // Read IP
        var ip_raw: [256]u8 = undefined;
        const ip_len = try self.sendAsciiUntilTerm("IP?", 2000, ';', &ip_raw);
        const ip_str = stripPrefixSuffix(ip_raw[0..ip_len], "IP:", ";");
        cfg.ip_len = proto.depadIP(ip_str, &cfg.ip);

        // Read Port
        var pt_raw: [256]u8 = undefined;
        const pt_len = try self.sendAsciiUntilTerm("PT?", 2000, ';', &pt_raw);
        const pt_str = stripPrefixSuffix(pt_raw[0..pt_len], "PT:", ";");
        var digits: [16]u8 = undefined;
        const dlen = proto.keepDigits(pt_str, &digits);
        if (dlen == 0) return error.BadPortReply;
        cfg.port = std.fmt.parseUnsigned(u16, digits[0..dlen], 10) catch return error.BadPortReply;
        if (cfg.port == 0 or cfg.port > 65535) return error.BadPortReply;

        // Read Mask
        var ma_raw: [256]u8 = undefined;
        const ma_len = try self.sendAsciiUntilTerm("MA?", 2000, ';', &ma_raw);
        const ma_str = stripPrefixSuffix(ma_raw[0..ma_len], "MA:", ";");
        cfg.mask_len = proto.depadIP(ma_str, &cfg.mask);

        // Read Gateway
        var gw_raw: [256]u8 = undefined;
        const gw_len = try self.sendAsciiUntilTerm("GW?", 2000, ';', &gw_raw);
        const gw_str = stripPrefixSuffix(gw_raw[0..gw_len], "GW:", ";");
        cfg.gw_len = proto.depadIP(gw_str, &cfg.gw);

        return cfg;
    }

    /// Set the switch's network configuration via ASCII commands.
    pub fn setNetworkConfigASCII(self: *Client, ip: []const u8, port: u16, mask: []const u8, gw: []const u8) !void {
        var cmd_buf: [128]u8 = undefined;

        const cmds = [_]struct { fmt_str: []const u8, arg: []const u8, port_val: ?u16 }{
            .{ .fmt_str = "IP:", .arg = ip, .port_val = null },
            .{ .fmt_str = "PT:", .arg = &.{}, .port_val = port },
            .{ .fmt_str = "MA:", .arg = mask, .port_val = null },
            .{ .fmt_str = "GW:", .arg = gw, .port_val = null },
        };

        for (cmds) |c| {
            var pos: usize = 0;
            @memcpy(cmd_buf[pos..][0..c.fmt_str.len], c.fmt_str);
            pos += c.fmt_str.len;

            if (c.port_val) |pv| {
                const port_str = std.fmt.bufPrint(cmd_buf[pos..], "{d}", .{pv}) catch return error.BufferOverflow;
                pos += port_str.len;
            } else {
                @memcpy(cmd_buf[pos..][0..c.arg.len], c.arg);
                pos += c.arg.len;
            }
            cmd_buf[pos] = ';';
            pos += 1;

            var resp: [256]u8 = undefined;
            const rlen = try self.sendAscii(cmd_buf[0..pos], 2000, &resp);

            // Check for "OK" in response (if any)
            if (rlen > 0) {
                const cleaned = stripNulls(resp[0..rlen]);
                if (cleaned.len > 0 and std.mem.indexOf(u8, cleaned, "OK") == null) {
                    return error.UnexpectedReply;
                }
            }
        }
    }

    // ── Internals ──

    fn resolveAddr(self: *const Client) !net.Address {
        const ip_slice = self.ip[0..self.ip_len];
        // Parse as IPv4
        return net.Address.parseIp4(ip_slice, self.port) catch return error.InvalidAddress;
    }
};

// ── String helpers ──

fn stripPrefixSuffix(s: []const u8, prefix: []const u8, suffix: []const u8) []const u8 {
    var result = s;
    if (std.mem.startsWith(u8, result, prefix)) {
        result = result[prefix.len..];
    }
    if (result.len > 0 and std.mem.endsWith(u8, result, suffix)) {
        result = result[0 .. result.len - suffix.len];
    }
    return std.mem.trim(u8, result, " \t");
}

fn cleanAsciiResponse(input: []const u8, out: []u8, term: u8) usize {
    var pos: usize = 0;
    for (input) |c| {
        if (c == 0 or c == '\r' or c == '\n') continue;
        if (pos < out.len) {
            out[pos] = c;
            pos += 1;
        }
        if (c == term) break;
    }
    return pos;
}

fn stripNulls(s: []const u8) []const u8 {
    // Find first non-null and last non-null
    var start: usize = 0;
    while (start < s.len and s[start] == 0) : (start += 1) {}
    var end: usize = s.len;
    while (end > start and s[end - 1] == 0) : (end -= 1) {}
    return std.mem.trim(u8, s[start..end], " \t\r\n");
}
