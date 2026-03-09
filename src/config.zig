// config.zig — JSON-based configuration (replaces Go YAML config)
const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const fs = std.fs;

pub const MAX_PORTS = 16;

pub const PortMeta = struct {
    name: []const u8 = "",
    icon: []const u8 = "",
};

pub const Config = struct {
    ip: [64]u8 = undefined,
    ip_len: usize = 0,
    port: u16 = 5000,

    poll_interval_ms: u32 = 1000,
    fast_mode: bool = false,
    get_timeout_ms: u32 = 600,
    set_timeout_ms: u32 = 450,
    verify_after_set: bool = true,
    switch_suppress_ms: u32 = 800,
    setup_completed: bool = false,
    buzzer_enabled: bool = true,
    hide_inactive: bool = false,

    // Port metadata — fixed-size arrays for names (no allocator needed at runtime)
    port_names: [MAX_PORTS][64]u8 = undefined,
    port_name_lens: [MAX_PORTS]usize = [_]usize{0} ** MAX_PORTS,
    port_icons: [MAX_PORTS][256]u8 = undefined,
    port_icon_lens: [MAX_PORTS]usize = [_]usize{0} ** MAX_PORTS,
    port_icon_scales: [MAX_PORTS]f32 = [_]f32{1.0} ** MAX_PORTS,
    port_active: [MAX_PORTS]bool = [_]bool{true} ** MAX_PORTS,

    // File paths
    config_dir: [512]u8 = undefined,
    config_dir_len: usize = 0,
    config_path: [512]u8 = undefined,
    config_path_len: usize = 0,
    was_created: bool = false,

    pub fn ipSlice(self: *const Config) []const u8 {
        return self.ip[0..self.ip_len];
    }

    pub fn portName(self: *const Config, port: usize) []const u8 {
        if (port == 0 or port > MAX_PORTS) return "?";
        const idx = port - 1;
        if (self.port_name_lens[idx] == 0) return "?";
        return self.port_names[idx][0..self.port_name_lens[idx]];
    }

    pub fn setPortName(self: *Config, port: usize, name: []const u8) void {
        if (port == 0 or port > MAX_PORTS) return;
        const idx = port - 1;
        const n = @min(name.len, self.port_names[idx].len);
        @memcpy(self.port_names[idx][0..n], name[0..n]);
        self.port_name_lens[idx] = n;
    }

    pub fn portIcon(self: *const Config, port: usize) []const u8 {
        if (port == 0 or port > MAX_PORTS) return "";
        const idx = port - 1;
        return self.port_icons[idx][0..self.port_icon_lens[idx]];
    }

    pub fn setPortIcon(self: *Config, port: usize, icon: []const u8) void {
        if (port == 0 or port > MAX_PORTS) return;
        const idx = port - 1;
        const n = @min(icon.len, self.port_icons[idx].len);
        @memcpy(self.port_icons[idx][0..n], icon[0..n]);
        self.port_icon_lens[idx] = n;
    }

    pub fn portIconScale(self: *const Config, port: usize) f32 {
        if (port == 0 or port > MAX_PORTS) return 1.0;
        return self.port_icon_scales[port - 1];
    }

    pub fn setPortIconScale(self: *Config, port: usize, scale: f32) void {
        if (port == 0 or port > MAX_PORTS) return;
        self.port_icon_scales[port - 1] = @max(0.25, @min(scale, 4.0));
    }

    pub fn isPortActive(self: *const Config, port: usize) bool {
        if (port == 0 or port > MAX_PORTS) return true;
        return self.port_active[port - 1];
    }

    pub fn setPortActive(self: *Config, port: usize, active: bool) void {
        if (port == 0 or port > MAX_PORTS) return;
        self.port_active[port - 1] = active;
    }

    pub fn dirSlice(self: *const Config) []const u8 {
        return self.config_dir[0..self.config_dir_len];
    }

    pub fn pathSlice(self: *const Config) []const u8 {
        return self.config_path[0..self.config_path_len];
    }
};

// ── Default config JSON ──
const default_json =
    \\{
    \\  "ip": "192.168.1.10",
    \\  "port": 5000,
    \\  "poll_interval_ms": 1000,
    \\  "fast_mode": false,
    \\  "get_timeout_ms": 600,
    \\  "set_timeout_ms": 450,
    \\  "verify_after_set": true,
    \\  "switch_suppress_ms": 800,
    \\  "setup_completed": false,
    \\  "ports": {
    \\    "1":  { "name": "HDMI Port 1",  "icon": "" },
    \\    "2":  { "name": "HDMI Port 2",  "icon": "" },
    \\    "3":  { "name": "HDMI Port 3",  "icon": "" },
    \\    "4":  { "name": "HDMI Port 4",  "icon": "" },
    \\    "5":  { "name": "HDMI Port 5",  "icon": "" },
    \\    "6":  { "name": "HDMI Port 6",  "icon": "" },
    \\    "7":  { "name": "HDMI Port 7",  "icon": "" },
    \\    "8":  { "name": "HDMI Port 8",  "icon": "" },
    \\    "9":  { "name": "HDMI Port 9",  "icon": "" },
    \\    "10": { "name": "HDMI Port 10", "icon": "" },
    \\    "11": { "name": "HDMI Port 11", "icon": "" },
    \\    "12": { "name": "HDMI Port 12", "icon": "" },
    \\    "13": { "name": "HDMI Port 13", "icon": "" },
    \\    "14": { "name": "HDMI Port 14", "icon": "" },
    \\    "15": { "name": "HDMI Port 15", "icon": "" },
    \\    "16": { "name": "HDMI Port 16", "icon": "" }
    \\  }
    \\}
;

/// Determine the platform-specific config directory.
fn configDir(buf: []u8) !usize {
    switch (builtin.os.tag) {
        .macos => {
            const home = std.posix.getenv("HOME") orelse return error.NoHome;
            const suffix = "/Library/Application Support/tesmart-ui";
            const total = home.len + suffix.len;
            if (total > buf.len) return error.BufferTooSmall;
            @memcpy(buf[0..home.len], home);
            @memcpy(buf[home.len..][0..suffix.len], suffix);
            return total;
        },
        .windows => {
            const appdata = std.posix.getenv("APPDATA") orelse return error.NoAppData;
            const suffix = "\\tesmart-ui";
            const total = appdata.len + suffix.len;
            if (total > buf.len) return error.BufferTooSmall;
            @memcpy(buf[0..appdata.len], appdata);
            @memcpy(buf[appdata.len..][0..suffix.len], suffix);
            return total;
        },
        else => {
            // Linux / other: XDG_CONFIG_HOME or ~/.config
            const base = std.posix.getenv("XDG_CONFIG_HOME") orelse blk: {
                const home = std.posix.getenv("HOME") orelse return error.NoHome;
                const cfg_suffix = "/.config";
                if (home.len + cfg_suffix.len > buf.len) return error.BufferTooSmall;
                @memcpy(buf[0..home.len], home);
                @memcpy(buf[home.len..][0..cfg_suffix.len], cfg_suffix);
                break :blk buf[0 .. home.len + cfg_suffix.len];
            };
            const suffix = "/tesmart-ui";
            const total = base.len + suffix.len;
            if (total > buf.len) return error.BufferTooSmall;
            // If base came from env (not buf), copy it
            if (base.ptr != buf.ptr) {
                @memcpy(buf[0..base.len], base);
            }
            @memcpy(buf[base.len..][0..suffix.len], suffix);
            return total;
        },
    }
}

/// Load config from disk (creates default if missing).
pub fn load() !Config {
    var cfg = Config{};

    // Determine paths
    cfg.config_dir_len = try configDir(&cfg.config_dir);
    const dir_str = cfg.config_dir[0..cfg.config_dir_len];

    const file_name = "/config.json";
    @memcpy(cfg.config_path[0..cfg.config_dir_len], dir_str);
    @memcpy(cfg.config_path[cfg.config_dir_len..][0..file_name.len], file_name);
    cfg.config_path_len = cfg.config_dir_len + file_name.len;

    const path_str = cfg.config_path[0..cfg.config_path_len];

    // Try to open existing file
    const file = std.fs.cwd().openFile(path_str, .{}) catch |err| {
        if (err == error.FileNotFound) {
            // Create directory and default file
            std.fs.cwd().makePath(dir_str) catch {};
            const f = try std.fs.cwd().createFile(path_str, .{});
            defer f.close();
            try f.writeAll(default_json);
            cfg.was_created = true;
            setDefaults(&cfg);
            return cfg;
        }
        return err;
    };
    defer file.close();

    // Read and parse
    var buf: [8192]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    try parseJson(&cfg, buf[0..bytes_read]);

    return cfg;
}

/// Save config to disk as JSON.
pub fn save(cfg: *const Config) !void {
    const path_str = cfg.config_path[0..cfg.config_path_len];
    const file = try std.fs.cwd().createFile(path_str, .{});
    defer file.close();

    // Build JSON in a stack buffer, then write all at once.
    var out: [8192]u8 = undefined;
    var pos: usize = 0;

    const header = try std.fmt.bufPrint(out[pos..], "{s}" ++
        "  \"ip\": \"{s}\",\n" ++
        "  \"port\": {d},\n" ++
        "  \"poll_interval_ms\": {d},\n" ++
        "  \"fast_mode\": {s},\n" ++
        "  \"get_timeout_ms\": {d},\n" ++
        "  \"set_timeout_ms\": {d},\n" ++
        "  \"verify_after_set\": {s},\n" ++
        "  \"switch_suppress_ms\": {d},\n" ++
        "  \"setup_completed\": {s},\n" ++
        "  \"buzzer_enabled\": {s},\n" ++
        "  \"hide_inactive\": {s},\n" ++
        "  \"ports\": {{\n", .{
        "{\n",
        cfg.ip[0..cfg.ip_len],
        cfg.port,
        cfg.poll_interval_ms,
        if (cfg.fast_mode) "true" else "false",
        cfg.get_timeout_ms,
        cfg.set_timeout_ms,
        if (cfg.verify_after_set) "true" else "false",
        cfg.switch_suppress_ms,
        if (cfg.setup_completed) "true" else "false",
        if (cfg.buzzer_enabled) "true" else "false",
        if (cfg.hide_inactive) "true" else "false",
    });
    pos += header.len;

    for (0..MAX_PORTS) |i| {
        const port_num = i + 1;
        const name = cfg.port_names[i][0..cfg.port_name_lens[i]];
        const icon = cfg.port_icons[i][0..cfg.port_icon_lens[i]];
        const sep: []const u8 = if (i < MAX_PORTS - 1) ",\n" else "\n";
        // Format scale with 2 decimal places
        var scale_buf: [8]u8 = undefined;
        const scale_str = std.fmt.bufPrint(&scale_buf, "{d:.2}", .{cfg.port_icon_scales[i]}) catch "1.00";
        const active_str: []const u8 = if (cfg.port_active[i]) "true" else "false";
        const line = try std.fmt.bufPrint(out[pos..], "    \"{d}\": {{ \"name\": \"{s}\", \"icon\": \"{s}\", \"icon_scale\": {s}, \"active\": {s} }}{s}", .{ port_num, name, icon, scale_str, active_str, sep });
        pos += line.len;
    }

    const footer = "  }\n}\n";
    @memcpy(out[pos..][0..footer.len], footer);
    pos += footer.len;

    try file.writeAll(out[0..pos]);
}

// ── Parsing ──

fn parseJson(cfg: *Config, data: []const u8) !void {
    setDefaults(cfg);

    const parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, data, .{}) catch return;
    defer parsed.deinit();

    const root = parsed.value.object;

    if (root.get("ip")) |v| {
        if (v == .string) {
            const s = v.string;
            const n = @min(s.len, cfg.ip.len);
            @memcpy(cfg.ip[0..n], s[0..n]);
            cfg.ip_len = n;
        }
    }
    if (root.get("port")) |v| {
        if (v == .integer) cfg.port = @intCast(@min(@max(v.integer, 1), 65535));
    }
    if (root.get("poll_interval_ms")) |v| {
        if (v == .integer) cfg.poll_interval_ms = @intCast(@max(v.integer, 100));
    }
    if (root.get("fast_mode")) |v| {
        if (v == .bool) cfg.fast_mode = v.bool;
    }
    if (root.get("get_timeout_ms")) |v| {
        if (v == .integer) cfg.get_timeout_ms = @intCast(@max(v.integer, 50));
    }
    if (root.get("set_timeout_ms")) |v| {
        if (v == .integer) cfg.set_timeout_ms = @intCast(@max(v.integer, 50));
    }
    if (root.get("verify_after_set")) |v| {
        if (v == .bool) cfg.verify_after_set = v.bool;
    }
    if (root.get("switch_suppress_ms")) |v| {
        if (v == .integer) cfg.switch_suppress_ms = @intCast(@max(v.integer, 0));
    }
    if (root.get("setup_completed")) |v| {
        if (v == .bool) cfg.setup_completed = v.bool;
    }
    if (root.get("buzzer_enabled")) |v| {
        if (v == .bool) cfg.buzzer_enabled = v.bool;
    }
    if (root.get("hide_inactive")) |v| {
        if (v == .bool) cfg.hide_inactive = v.bool;
    }

    if (root.get("ports")) |ports_val| {
        if (ports_val == .object) {
            var iter = ports_val.object.iterator();
            while (iter.next()) |entry| {
                const key = entry.key_ptr.*;
                const port_num = std.fmt.parseUnsigned(usize, key, 10) catch continue;
                if (port_num < 1 or port_num > MAX_PORTS) continue;
                const idx = port_num - 1;

                if (entry.value_ptr.* == .object) {
                    const obj = entry.value_ptr.object;
                    if (obj.get("name")) |name_v| {
                        if (name_v == .string) {
                            const s = name_v.string;
                            const n = @min(s.len, cfg.port_names[idx].len);
                            @memcpy(cfg.port_names[idx][0..n], s[0..n]);
                            cfg.port_name_lens[idx] = n;
                        }
                    }
                    if (obj.get("icon")) |icon_v| {
                        if (icon_v == .string) {
                            const s = icon_v.string;
                            const n = @min(s.len, cfg.port_icons[idx].len);
                            @memcpy(cfg.port_icons[idx][0..n], s[0..n]);
                            cfg.port_icon_lens[idx] = n;
                        }
                    }
                    if (obj.get("icon_scale")) |scale_v| {
                        if (scale_v == .float) {
                            cfg.port_icon_scales[idx] = @max(0.25, @min(@as(f32, @floatCast(scale_v.float)), 4.0));
                        } else if (scale_v == .integer) {
                            cfg.port_icon_scales[idx] = @max(0.25, @min(@as(f32, @floatFromInt(scale_v.integer)), 4.0));
                        }
                    }
                    if (obj.get("active")) |active_v| {
                        if (active_v == .bool) cfg.port_active[idx] = active_v.bool;
                    }
                }
            }
        }
    }
}

fn setDefaults(cfg: *Config) void {
    // IP
    const default_ip = "192.168.1.10";
    @memcpy(cfg.ip[0..default_ip.len], default_ip);
    cfg.ip_len = default_ip.len;

    cfg.port = 5000;
    cfg.poll_interval_ms = 1000;
    cfg.fast_mode = false;
    cfg.get_timeout_ms = 600;
    cfg.set_timeout_ms = 450;
    cfg.verify_after_set = true;
    cfg.switch_suppress_ms = 800;

    // Default port names
    for (0..MAX_PORTS) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "HDMI Port {d}", .{i + 1}) catch "Port";
        @memcpy(cfg.port_names[i][0..name.len], name);
        cfg.port_name_lens[i] = name.len;
        cfg.port_icon_lens[i] = 0;
        cfg.port_icon_scales[i] = 1.0;
        cfg.port_active[i] = true;
    }
}
