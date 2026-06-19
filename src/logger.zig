const std = @import("std");

var g_file: ?std.fs.File = null;
var g_mutex: std.Thread.Mutex = .{};

pub fn init(config_dir: []const u8) !void {
    g_mutex.lock();
    defer g_mutex.unlock();

    if (g_file != null) return;

    try std.fs.cwd().makePath(config_dir);

    var path_buf: [1024]u8 = undefined;
    const suffix = "/tesmart-ui.log";
    if (config_dir.len + suffix.len > path_buf.len) return error.BufferTooSmall;

    @memcpy(path_buf[0..config_dir.len], config_dir);
    @memcpy(path_buf[config_dir.len..][0..suffix.len], suffix);
    const path = path_buf[0 .. config_dir.len + suffix.len];

    const f = try std.fs.cwd().createFile(path, .{ .truncate = false, .read = true });
    try f.seekFromEnd(0);
    g_file = f;
}

pub fn deinit() void {
    g_mutex.lock();
    defer g_mutex.unlock();

    if (g_file) |f| {
        f.close();
        g_file = null;
    }
}

fn writeLine(comptime level: []const u8, comptime fmt: []const u8, args: anytype) void {
    g_mutex.lock();
    defer g_mutex.unlock();

    const f = g_file orelse return;

    var msg_buf: [1536]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, fmt, args) catch return;

    var line_buf: [1800]u8 = undefined;
    const ts = std.time.timestamp();
    const line = std.fmt.bufPrint(&line_buf, "[{d}] {s}: {s}\n", .{ ts, level, msg }) catch return;

    _ = f.writeAll(line) catch return;
    _ = f.sync() catch {};
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    writeLine("INFO", fmt, args);
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    writeLine("WARN", fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    writeLine("ERROR", fmt, args);
}
