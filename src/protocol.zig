// protocol.zig — TESmart binary-frame + ASCII helpers
const std = @import("std");

// Binary frame format:  AA BB 03 <cmd> <arg> EE
pub const FRAME_HEAD_0: u8 = 0xAA;
pub const FRAME_HEAD_1: u8 = 0xBB;
pub const FRAME_LEN: u8 = 0x03;
pub const FRAME_TAIL: u8 = 0xEE;
pub const FRAME_SIZE: usize = 6;

// Command bytes
pub const CMD_GET_ACTIVE: u8 = 0x10;
pub const CMD_SET_INPUT_ALT: u8 = 0x11; // arg = port-1 (0-indexed)
pub const CMD_SET_INPUT: u8 = 0x01; // arg = port (1-indexed)
pub const CMD_BUZZER: u8 = 0x02;
pub const CMD_LED_TIMEOUT: u8 = 0x03;

// LED timeout argument values
pub const LED_OFF: u8 = 0x00; // always-on
pub const LED_10S: u8 = 0x0A;
pub const LED_30S: u8 = 0x1E;

// Reply discriminator
pub const REPLY_ACTIVE: u8 = 0x11;

pub const Frame = [FRAME_SIZE]u8;

/// Build a 6-byte binary frame.
pub fn makeFrame(cmd: u8, arg: u8) Frame {
    return .{ FRAME_HEAD_0, FRAME_HEAD_1, FRAME_LEN, cmd, arg, FRAME_TAIL };
}

/// Scan a buffer for valid 6-byte frames (AA BB 03 .. .. EE).
/// Returns a slice of frame start offsets.
pub fn findFrames(buf: []const u8, offsets: []usize) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i + 5 < buf.len) : (i += 1) {
        if (buf[i] == FRAME_HEAD_0 and
            buf[i + 1] == FRAME_HEAD_1 and
            buf[i + 2] == FRAME_LEN and
            buf[i + 5] == FRAME_TAIL)
        {
            if (count < offsets.len) {
                offsets[count] = i;
                count += 1;
            }
            i += 4; // skip past this frame (loop will +1)
        }
    }
    return count;
}

/// Extract the active-input port (1-based) from a response buffer.
/// Looks for frames with cmd byte == 0x11, returns port = arg + 1.
pub fn scanActivePort(buf: []const u8) ?u8 {
    var off_buf: [64]usize = undefined;
    const n = findFrames(buf, &off_buf);
    for (off_buf[0..n]) |off| {
        if (buf[off + 3] == REPLY_ACTIVE) {
            return buf[off + 4] + 1;
        }
    }
    // Fallback: loose scan without tail byte
    var i: usize = 0;
    while (i + 4 < buf.len) : (i += 1) {
        if (buf[i] == FRAME_HEAD_0 and
            buf[i + 1] == FRAME_HEAD_1 and
            buf[i + 2] == FRAME_LEN and
            buf[i + 3] == REPLY_ACTIVE)
        {
            return buf[i + 4] + 1;
        }
    }
    return null;
}

// ── ASCII helpers ──

/// Keep only digits and dots from a string (for IP address cleaning).
pub fn keepDigitsDots(input: []const u8, out: []u8) usize {
    var len_out: usize = 0;
    for (input) |c| {
        if ((c >= '0' and c <= '9') or c == '.') {
            if (len_out < out.len) {
                out[len_out] = c;
                len_out += 1;
            }
        }
    }
    return len_out;
}

/// Keep only digits.
pub fn keepDigits(input: []const u8, out: []u8) usize {
    var len_out: usize = 0;
    for (input) |c| {
        if (c >= '0' and c <= '9') {
            if (len_out < out.len) {
                out[len_out] = c;
                len_out += 1;
            }
        }
    }
    return len_out;
}

/// Remove leading-zero padding from each dotted-decimal octet.
/// e.g. "192.168.001.010" → "192.168.1.10"
pub fn depadIP(input: []const u8, out: []u8) usize {
    var pos: usize = 0;
    var octet_start: usize = 0;

    var i: usize = 0;
    while (i <= input.len) : (i += 1) {
        const at_end = (i == input.len);
        const is_dot = if (!at_end) input[i] == '.' else false;

        if (at_end or is_dot) {
            const octet = input[octet_start..i];
            // Skip leading zeros
            var start: usize = 0;
            while (start + 1 < octet.len and octet[start] == '0') : (start += 1) {}
            const trimmed = octet[start..];
            if (pos + trimmed.len > out.len) break;
            @memcpy(out[pos..][0..trimmed.len], trimmed);
            pos += trimmed.len;
            if (is_dot and pos < out.len) {
                out[pos] = '.';
                pos += 1;
            }
            octet_start = i + 1;
        }
    }
    return pos;
}

/// Hex-encode a byte buffer into uppercase hex string.
pub fn hexEncode(data: []const u8, out: []u8) usize {
    const hex_chars = "0123456789ABCDEF";
    var pos: usize = 0;
    for (data) |b| {
        if (pos + 2 > out.len) break;
        out[pos] = hex_chars[b >> 4];
        out[pos + 1] = hex_chars[b & 0x0F];
        pos += 2;
    }
    return pos;
}

/// Decode a hex string into bytes. Returns number of bytes written, or error.
pub fn hexDecode(hex: []const u8, out: []u8) !usize {
    // Strip spaces
    var clean: [2048]u8 = undefined;
    var clen: usize = 0;
    for (hex) |c| {
        if (c != ' ') {
            if (clen < clean.len) {
                clean[clen] = c;
                clen += 1;
            }
        }
    }
    if (clen == 0) return error.EmptyHex;
    if (clen % 2 != 0) return error.OddLength;

    var pos: usize = 0;
    var i: usize = 0;
    while (i + 1 < clen) : (i += 2) {
        if (pos >= out.len) break;
        const hi = hexVal(clean[i]) orelse return error.InvalidHex;
        const lo = hexVal(clean[i + 1]) orelse return error.InvalidHex;
        out[pos] = (@as(u8, hi) << 4) | @as(u8, lo);
        pos += 1;
    }
    return pos;
}

fn hexVal(c: u8) ?u4 {
    if (c >= '0' and c <= '9') return @intCast(c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(c - 'a' + 10);
    if (c >= 'A' and c <= 'F') return @intCast(c - 'A' + 10);
    return null;
}

// ── tests ──

test "makeFrame round-trip" {
    const f = makeFrame(CMD_GET_ACTIVE, 0x00);
    try std.testing.expectEqualSlices(u8, &.{ 0xAA, 0xBB, 0x03, 0x10, 0x00, 0xEE }, &f);
}

test "scanActivePort" {
    const buf = [_]u8{ 0xAA, 0xBB, 0x03, 0x11, 0x02, 0xEE };
    const port = scanActivePort(&buf);
    try std.testing.expectEqual(@as(?u8, 3), port); // 0x02 + 1
}

test "depadIP" {
    var out: [64]u8 = undefined;
    const n = depadIP("192.168.001.010", &out);
    try std.testing.expectEqualStrings("192.168.1.10", out[0..n]);
}
