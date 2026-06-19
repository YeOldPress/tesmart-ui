// tray.zig — Zig wrapper for native system-tray integration
const std = @import("std");
const builtin = @import("builtin");

const config = @import("config.zig");

const has_tray = switch (builtin.os.tag) {
    .macos, .linux, .windows => true,
    else => false,
};

// ── Public action type returned by pollAction() ──

pub const Action = union(enum) {
    none,
    switch_port: u8,
    toggle_buzzer,
    show_window,
    quit,
};

// ── Atomic action slot (written by C callback, read by Zig main thread) ──
var g_action: std.atomic.Value(i32) = std.atomic.Value(i32).init(0);

fn trayCallback(menu_id: c_int) callconv(.c) void {
    g_action.store(@intCast(menu_id), .release);
}

// ── C extern declarations ──
extern fn tray_init(cb: *const fn (c_int) callconv(.c) void, port: c_int, buz: c_int, names: *const [16][*:0]const u8, visible: *const [16]c_int, icon_path: [*:0]const u8) void;
extern fn tray_update(port: c_int, buz: c_int, names: *const [16][*:0]const u8, visible: *const [16]c_int) void;
extern fn tray_poll_events() void;
extern fn tray_cleanup() void;

// ── Name buffer (null-terminated copies for C) ──
var name_bufs: [16][65]u8 = undefined;
var name_ptrs: [16][*:0]const u8 = undefined;
var vis_mask: [16]c_int = .{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 };

fn fileExists(path: []const u8) bool {
    const f = std.fs.cwd().openFile(path, .{}) catch return false;
    f.close();
    return true;
}

fn tryPath(out: []u8, path: []const u8) ?[]const u8 {
    if (path.len == 0 or path.len > out.len) return null;
    if (!fileExists(path)) return null;
    @memcpy(out[0..path.len], path);
    return out[0..path.len];
}

fn resolveTrayIconPath(out: []u8) ?[]const u8 {
    switch (builtin.os.tag) {
        .linux => {
            if (std.posix.getenv("APPDIR")) |appdir| {
                var p: [1024]u8 = undefined;
                const c1 = std.fmt.bufPrint(&p, "{s}/tesmart-ui.png", .{appdir}) catch "";
                if (tryPath(out, c1)) |ok| return ok;
                const c2 = std.fmt.bufPrint(&p, "{s}/usr/share/icons/hicolor/256x256/apps/tesmart-ui.png", .{appdir}) catch "";
                if (tryPath(out, c2)) |ok| return ok;
            }

            var exe_dir_buf: [1024]u8 = undefined;
            const exe_dir = std.fs.selfExeDirPath(&exe_dir_buf) catch "";
            if (exe_dir.len > 0) {
                var p: [1024]u8 = undefined;
                const c1 = std.fmt.bufPrint(&p, "{s}/AppIcon.png", .{exe_dir}) catch "";
                if (tryPath(out, c1)) |ok| return ok;
                const c2 = std.fmt.bufPrint(&p, "{s}/../AppIcon.png", .{exe_dir}) catch "";
                if (tryPath(out, c2)) |ok| return ok;
                const c3 = std.fmt.bufPrint(&p, "{s}/../../tesmart-ui.png", .{exe_dir}) catch "";
                if (tryPath(out, c3)) |ok| return ok;
            }
        },
        .macos => {
            var exe_dir_buf: [1024]u8 = undefined;
            const exe_dir = std.fs.selfExeDirPath(&exe_dir_buf) catch "";
            if (exe_dir.len > 0) {
                var p: [1024]u8 = undefined;
                const c1 = std.fmt.bufPrint(&p, "{s}/../Resources/AppIcon.icns", .{exe_dir}) catch "";
                if (tryPath(out, c1)) |ok| return ok;
                const c2 = std.fmt.bufPrint(&p, "{s}/../Resources/AppIcon.png", .{exe_dir}) catch "";
                if (tryPath(out, c2)) |ok| return ok;
            }
        },
        .windows => {
            var exe_dir_buf: [1024]u8 = undefined;
            const exe_dir = std.fs.selfExeDirPath(&exe_dir_buf) catch "";
            if (exe_dir.len > 0) {
                var p: [1024]u8 = undefined;
                const c1 = std.fmt.bufPrint(&p, "{s}/AppIcon.ico", .{exe_dir}) catch "";
                if (tryPath(out, c1)) |ok| return ok;
                const c2 = std.fmt.bufPrint(&p, "{s}/AppIcon.png", .{exe_dir}) catch "";
                if (tryPath(out, c2)) |ok| return ok;
            }
        },
        else => {},
    }
    if (tryPath(out, "./AppIcon.ico")) |ok| return ok;
    if (tryPath(out, "./AppIcon.png")) |ok| return ok;
    return null;
}

fn buildNamePtrs(cfg: *const config.Config) void {
    for (0..16) |i| {
        const name = cfg.portName(i + 1);
        const n = @min(name.len, 64);
        @memcpy(name_bufs[i][0..n], name[0..n]);
        name_bufs[i][n] = 0;
        name_ptrs[i] = @ptrCast(&name_bufs[i]);
    }
}

fn buildVisMask(cfg: *const config.Config, hide_inactive: bool) void {
    for (0..16) |i| {
        vis_mask[i] = if (hide_inactive and !cfg.port_active[i]) 0 else 1;
    }
}

// ── State tracking (avoid redundant menu rebuilds) ──
var last_port: u8 = 0;
var last_buzzer: bool = false;
var last_hide: bool = false;
var last_force: bool = false;

// ── Public API ──

pub fn init(active_port: u8, buzzer_on: bool, hide_inactive: bool, cfg: *const config.Config) void {
    if (comptime !has_tray) return;
    last_port = active_port;
    last_buzzer = buzzer_on;
    last_hide = hide_inactive;
    buildNamePtrs(cfg);
    buildVisMask(cfg, hide_inactive);

    var icon_path_buf: [1024]u8 = undefined;
    var icon_path_z: [1025:0]u8 = std.mem.zeroes([1025:0]u8);
    const icon_path = resolveTrayIconPath(&icon_path_buf);
    const icon_len: usize = if (icon_path) |p| p.len else 0;
    if (icon_len > 0) {
        @memcpy(icon_path_z[0..icon_len], icon_path.?);
    }

    tray_init(
        &trayCallback,
        @intCast(active_port),
        @as(c_int, if (buzzer_on) 1 else 0),
        &name_ptrs,
        &vis_mask,
        @ptrCast(&icon_path_z),
    );
}

pub fn updateIfChanged(active_port: u8, buzzer_on: bool, hide_inactive: bool, cfg: *const config.Config) void {
    if (comptime !has_tray) return;
    const changed = (active_port != last_port or buzzer_on != last_buzzer or hide_inactive != last_hide or last_force);
    if (!changed) return;
    last_port = active_port;
    last_buzzer = buzzer_on;
    last_hide = hide_inactive;
    last_force = false;
    buildNamePtrs(cfg);
    buildVisMask(cfg, hide_inactive);
    tray_update(@intCast(active_port), @as(c_int, if (buzzer_on) 1 else 0), &name_ptrs, &vis_mask);
}

pub fn forceUpdate() void {
    last_force = true;
}

pub fn cleanup() void {
    if (comptime !has_tray) return;
    tray_cleanup();
}

pub fn pumpEvents() void {
    if (comptime !has_tray) return;
    if (comptime builtin.os.tag == .linux) {
        tray_poll_events();
    }
}

pub fn pollAction() Action {
    if (comptime !has_tray) return .none;
    const id = g_action.swap(0, .acquire);
    if (id >= 1 and id <= 16) return .{ .switch_port = @as(u8, @intCast(id)) };
    return switch (id) {
        100 => .toggle_buzzer,
        200 => .show_window,
        201 => .quit,
        else => .none,
    };
}
