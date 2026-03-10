// gui.zig — raylib-based GUI for TeSmart UI
const std = @import("std");
const rl = @import("raylib");
const build_options = @import("build_options");
const config = @import("config.zig");
const Client = @import("client.zig").Client;
const native = @import("native.zig");
const tray = @import("tray.zig");

const WINDOW_W = 720;
const WINDOW_H = 700;
const GRID_COLS = 4;
const GRID_ROWS = 4;
const TILE_W = 160;
const TILE_H = 130;
const TILE_PAD = 8;
const TOOLBAR_H = 40;
const STATUS_H = 30;
const FONT_SIZE: i32 = 18;
const SMALL_FONT: i32 = 14;
const FONT_SZ: f32 = 18.0;
const SMALL_SZ: f32 = 14.0;
const FONT_SPACING: f32 = 1.0;
const ICON_DISPLAY_SZ: f32 = 48.0;

// ── Colors ──
const BG = rl.Color{ .r = 18, .g = 18, .b = 24, .a = 255 };
const TILE_NORMAL = rl.Color{ .r = 32, .g = 34, .b = 42, .a = 255 };
const TILE_ACTIVE = rl.Color{ .r = 22, .g = 100, .b = 220, .a = 255 };
const TILE_HOVER = rl.Color{ .r = 42, .g = 44, .b = 56, .a = 255 };
const TEXT_WHITE = rl.Color{ .r = 230, .g = 232, .b = 240, .a = 255 };
const TEXT_DIM = rl.Color{ .r = 120, .g = 124, .b = 140, .a = 255 };
const TOOLBAR_BG = rl.Color{ .r = 22, .g = 22, .b = 30, .a = 255 };
const STATUS_BG = rl.Color{ .r = 16, .g = 16, .b = 22, .a = 255 };
const DIALOG_BG = rl.Color{ .r = 28, .g = 30, .b = 38, .a = 255 };
const DIALOG_OVERLAY = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 180 };
const BTN_NORMAL = rl.Color{ .r = 38, .g = 40, .b = 50, .a = 255 };
const BTN_HOVER = rl.Color{ .r = 52, .g = 54, .b = 68, .a = 255 };
const BTN_ACTIVE = rl.Color{ .r = 22, .g = 100, .b = 220, .a = 255 };
const INPUT_BG = rl.Color{ .r = 22, .g = 24, .b = 32, .a = 255 };
const INPUT_BORDER = rl.Color{ .r = 55, .g = 58, .b = 70, .a = 255 };
const INPUT_FOCUS = rl.Color{ .r = 60, .g = 130, .b = 255, .a = 255 };
const ACCENT = rl.Color{ .r = 60, .g = 130, .b = 255, .a = 255 };
const ICON_PLACEHOLDER = rl.Color{ .r = 55, .g = 58, .b = 70, .a = 255 };
const WHITE = rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 };
const GLOW_COLOR = rl.Color{ .r = 60, .g = 160, .b = 255, .a = 255 };
const NEON_COLOR = rl.Color{ .r = 60, .g = 180, .b = 255, .a = 255 };
const TILE_BORDER = rl.Color{ .r = 48, .g = 50, .b = 62, .a = 255 };
const TILE_ACTIVE_GLOW = rl.Color{ .r = 22, .g = 100, .b = 220, .a = 40 };
const SEPARATOR = rl.Color{ .r = 40, .g = 42, .b = 52, .a = 255 };
const NEON_CYCLE_NS: i128 = 2000 * std.time.ns_per_ms;
const NEON_SEG_FRAC: f32 = 0.25; // bright segment covers 25% of perimeter
const NEON_DURATION_NS: i128 = 3000 * std.time.ns_per_ms;

const ANIM_DURATION_NS: i128 = 500 * std.time.ns_per_ms;
const FILTER_ANIM_NS: i128 = 300 * std.time.ns_per_ms;

const Dialog = enum { none, connection, edit_port, network_config, raw_hex, about, first_setup };
const ToolbarAction = enum { none, connection, edit, network, ping, buzzer, filter, about };

// ── Module-level font (set once after initWindow) ──
var g_font: rl.Font = undefined;
var g_font_ok: bool = false;

fn drawTxt(text: [:0]const u8, x: i32, y: i32, size: f32, color: rl.Color) void {
    if (g_font_ok) {
        rl.drawTextEx(g_font, text, .{ .x = @floatFromInt(x), .y = @floatFromInt(y) }, size, FONT_SPACING, color);
    } else {
        rl.drawText(text, x, y, @intFromFloat(size), color);
    }
}

fn measureTxt(text: [:0]const u8, size: f32) i32 {
    if (g_font_ok) {
        return @intFromFloat(rl.measureTextEx(g_font, text, size, FONT_SPACING).x);
    } else {
        return rl.measureText(text, @intFromFloat(size));
    }
}

fn loadSystemFont() void {
    const paths = [_][:0]const u8{
        // macOS
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Verdana.ttf",
        "/System/Library/Fonts/Supplemental/Tahoma.ttf",
        "/Library/Fonts/Arial.ttf",
        // Linux — Fedora / RHEL
        "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans.ttf",
        "/usr/share/fonts/liberation-sans/LiberationSans-Regular.ttf",
        "/usr/share/fonts/google-noto/NotoSans-Regular.ttf",
        // Linux — Debian / Ubuntu
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
        // Linux — Arch
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/noto/NotoSans-Regular.ttf",
        // Linux — openSUSE
        "/usr/share/fonts/truetype/DejaVuSans.ttf",
        // Windows
        "C:\\Windows\\Fonts\\segoeui.ttf",
        "C:\\Windows\\Fonts\\arial.ttf",
    };
    for (paths) |path| {
        // Check file exists
        const f = std.fs.cwd().openFile(path, .{}) catch continue;
        f.close();
        g_font = rl.loadFontEx(path, 32, null) catch continue;
        // Smooth scaling
        rl.setTextureFilter(g_font.texture, .bilinear);
        g_font_ok = true;
        return;
    }
    // Fallback: keep default
    g_font_ok = false;
}

// ── Gui ──

pub const Gui = struct {
    cfg: *config.Config,
    cli: *Client,

    active_port: u8 = 0,
    status_text: [256]u8 = undefined,
    status_len: usize = 0,

    // Dialog state
    dialog: Dialog = .none,
    input_fields: [4]InputField = [_]InputField{InputField{}} ** 4,
    focused_field: ?usize = null,
    dialog_result: [256]u8 = undefined,
    dialog_result_len: usize = 0,
    selected_edit_port: u8 = 1,

    // Pending switch (flicker suppression)
    pending_port: u8 = 0,
    pending_until_ns: i128 = 0,
    poll_suppress_until: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    // Status hold (prevent poller from overwriting transient messages)
    status_hold_until: i128 = 0,

    // Tile switch animation
    anim_port: u8 = 0,
    anim_start_ns: i128 = 0,

    // Icon textures (per port)
    icon_textures: [config.MAX_PORTS]rl.Texture2D = undefined,
    icon_loaded: [config.MAX_PORTS]bool = [_]bool{false} ** config.MAX_PORTS,

    // Polling
    poll_thread: ?std.Thread = null,
    poll_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    polled_port: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
    poll_error: bool = false,

    // Buzzer state
    buzzer_enabled: bool = true,
    quit_requested: bool = false,
    edit_icon_scale: f32 = 1.0,
    edit_port_active: bool = true,
    hide_inactive: bool = false,

    // Filter animation
    filter_anim_start_ns: i128 = 0,
    filter_anim_from_h: i32 = 0,
    filter_anim_to_h: i32 = 0,

    // Dirty-flag rendering (skip redraws when idle)
    needs_redraw: bool = true,
    last_mouse_x: i32 = -1,
    last_mouse_y: i32 = -1,
    last_active_port: u8 = 0,

    pub fn init(cfg: *config.Config, cli: *Client) Gui {
        var g = Gui{ .cfg = cfg, .cli = cli };
        g.buzzer_enabled = cfg.buzzer_enabled;
        g.hide_inactive = cfg.hide_inactive;
        g.setStatus("Ready — {s}:{d}", .{ cfg.ip[0..cfg.ip_len], cfg.port });
        return g;
    }

    fn visiblePortCount(self: *const Gui) usize {
        if (!self.hide_inactive) return config.MAX_PORTS;
        var count: usize = 0;
        for (0..config.MAX_PORTS) |i| {
            if (self.cfg.port_active[i]) count += 1;
        }
        return if (count == 0) 1 else count;
    }

    fn targetWindowHeight(self: *const Gui) i32 {
        const count = self.visiblePortCount();
        const cols: usize = GRID_COLS;
        const rows = (count + cols - 1) / cols;
        return @intCast(TOOLBAR_H + 10 + rows * (TILE_H + TILE_PAD) + 10 + STATUS_H);
    }

    fn resizeForVisiblePorts(self: *Gui) void {
        rl.setWindowSize(WINDOW_W, self.targetWindowHeight());
    }

    fn startFilterAnim(self: *Gui) void {
        self.filter_anim_from_h = rl.getScreenHeight();
        self.filter_anim_to_h = self.targetWindowHeight();
        self.filter_anim_start_ns = std.time.nanoTimestamp();
    }

    fn filterAnimProgress(self: *const Gui) f32 {
        if (self.filter_anim_start_ns == 0) return 1.0;
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.filter_anim_start_ns;
        if (elapsed >= FILTER_ANIM_NS) return 1.0;
        const t: f32 = @as(f32, @floatFromInt(@as(i64, @intCast(elapsed)))) /
            @as(f32, @floatFromInt(@as(i64, @intCast(FILTER_ANIM_NS))));
        // Ease-out cubic
        const inv = 1.0 - t;
        return 1.0 - inv * inv * inv;
    }

    fn isAnimating(self: *const Gui) bool {
        const now = std.time.nanoTimestamp();
        // Port switch bounce/neon animation
        if (self.anim_start_ns > 0 and now < self.anim_start_ns + NEON_DURATION_NS) return true;
        // Filter resize animation
        if (self.filter_anim_start_ns > 0 and now < self.filter_anim_start_ns + FILTER_ANIM_NS) return true;
        // Dialog open (user is interacting)
        if (self.dialog != .none) return true;
        return false;
    }

    fn checkForInputChanges(self: *Gui) void {
        const mx = rl.getMouseX();
        const my = rl.getMouseY();
        if (mx != self.last_mouse_x or my != self.last_mouse_y) {
            self.needs_redraw = true;
            self.last_mouse_x = mx;
            self.last_mouse_y = my;
        }
        if (rl.isMouseButtonPressed(.left) or rl.isMouseButtonPressed(.right) or
            rl.isMouseButtonDown(.left) or rl.getMouseWheelMove() != 0)
            self.needs_redraw = true;
        if (rl.isWindowResized())
            self.needs_redraw = true;
        // Polled port changed
        const polled = self.polled_port.load(.monotonic);
        if (polled != self.last_active_port) {
            self.needs_redraw = true;
            self.last_active_port = polled;
        }
        // Tray action pending
        if (tray.hasPendingAction())
            self.needs_redraw = true;
    }

    fn setStatus(self: *Gui, comptime fmt: []const u8, args: anytype) void {
        const result = std.fmt.bufPrint(&self.status_text, fmt, args) catch {
            self.status_len = 0;
            return;
        };
        self.status_len = result.len;
        self.needs_redraw = true;
    }

    fn setStatusStr(self: *Gui, s: []const u8) void {
        const n = @min(s.len, self.status_text.len);
        @memcpy(self.status_text[0..n], s[0..n]);
        self.status_len = n;
        self.needs_redraw = true;
    }

    pub fn run(self: *Gui) void {
        if (!build_options.verbose) rl.setTraceLogLevel(.none);
        rl.initWindow(WINDOW_W, WINDOW_H, "TeSmart 16-Port HDMI Switch");
        defer rl.closeWindow();
        rl.setTargetFPS(60);

        // Resize for initial filter state
        self.resizeForVisiblePorts();

        // Load system font
        loadSystemFont();

        // Load icon textures from config directory
        self.loadAllIcons();

        // Start polling thread
        self.startPoller();
        defer self.stopPoller();

        // System tray
        tray.init(self.active_port, self.buzzer_enabled, self.hide_inactive, self.cfg);
        defer tray.cleanup();

        // Show first-setup if needed
        if (!self.cfg.setup_completed or self.cfg.was_created) {
            self.dialog = .first_setup;
            self.prepareConnectionFields();
        }

        // Start in event-waiting mode (idle, ~0% CPU)
        var event_waiting = true;
        rl.enableEventWaiting();

        while (!rl.windowShouldClose() and !self.quit_requested) {
            self.checkForInputChanges();

            const animating = self.isAnimating();

            // Switch between event-waiting (idle) and continuous (animating) modes
            if (animating and event_waiting) {
                rl.disableEventWaiting();
                event_waiting = false;
            } else if (!animating and !event_waiting) {
                rl.enableEventWaiting();
                event_waiting = true;
            }

            self.update();
            self.draw();
            self.needs_redraw = false;
        }

        // Unload icon textures
        for (0..config.MAX_PORTS) |i| {
            if (self.icon_loaded[i]) rl.unloadTexture(self.icon_textures[i]);
        }
        if (g_font_ok) rl.unloadFont(g_font);
    }

    // ── Icon loading ──

    fn loadAllIcons(self: *Gui) void {
        for (0..config.MAX_PORTS) |i| {
            self.loadIconForPort(i);
        }
    }

    fn loadIconForPort(self: *Gui, idx: usize) void {
        // Unload previous if any
        if (self.icon_loaded[idx]) {
            rl.unloadTexture(self.icon_textures[idx]);
            self.icon_loaded[idx] = false;
        }

        const icon_name = self.cfg.portIcon(idx + 1);
        if (icon_name.len == 0) return;

        var full_path: [1024]u8 = undefined;
        const path_len = native.iconFullPath(self.cfg.dirSlice(), icon_name, &full_path);
        if (path_len == 0) return;

        // Need null-terminated path for raylib
        var path_z: [1025:0]u8 = std.mem.zeroes([1025:0]u8);
        const pn = @min(path_len, 1024);
        @memcpy(path_z[0..pn], full_path[0..pn]);
        const path_slice: [:0]const u8 = path_z[0..pn :0];

        // Check file exists
        const f = std.fs.cwd().openFile(full_path[0..path_len], .{}) catch return;
        f.close();

        const tex = rl.loadTexture(path_slice) catch return;
        if (tex.width > 0 and tex.height > 0) {
            self.icon_textures[idx] = tex;
            self.icon_loaded[idx] = true;
        }
    }

    // ── Update ──

    fn update(self: *Gui) void {
        // Animate filter window resize
        if (self.filter_anim_start_ns > 0) {
            const now = std.time.nanoTimestamp();
            const elapsed = now - self.filter_anim_start_ns;
            if (elapsed >= FILTER_ANIM_NS) {
                rl.setWindowSize(WINDOW_W, self.filter_anim_to_h);
                self.filter_anim_start_ns = 0;
            } else {
                const t = self.filterAnimProgress();
                const from_f: f32 = @floatFromInt(self.filter_anim_from_h);
                const to_f: f32 = @floatFromInt(self.filter_anim_to_h);
                const h: i32 = @intFromFloat(from_f + (to_f - from_f) * t);
                rl.setWindowSize(WINDOW_W, h);
            }
        }

        // Only accept polled port after suppression window expires
        const now = std.time.nanoTimestamp();
        const suppressed = (self.pending_port > 0 and now < self.pending_until_ns);

        if (!suppressed) {
            const polled = self.polled_port.load(.monotonic);
            if (polled > 0 and polled != self.active_port) {
                self.anim_port = polled;
                self.anim_start_ns = now;
                self.active_port = polled;
                if (now >= self.status_hold_until) {
                    self.setStatus("Active: {d}", .{polled});
                }
            }
            // Clear pending state once suppression is over
            self.pending_port = 0;
        }

        // Process system-tray actions
        self.processTrayAction();
        tray.updateIfChanged(self.active_port, self.buzzer_enabled, self.hide_inactive, self.cfg);
        tray.pumpEvents();

        if (self.dialog != .none) {
            self.updateDialog();
            return;
        }

        self.updateGrid();
        self.updateToolbar();
    }

    fn updateGrid(self: *Gui) void {
        const left = rl.isMouseButtonPressed(.left);
        const right = rl.isMouseButtonPressed(.right);
        if (!left and !right) return;
        const mx: f32 = @floatFromInt(rl.getMouseX());
        const my: f32 = @floatFromInt(rl.getMouseY());

        // Build visible port list
        var visible: [config.MAX_PORTS]usize = undefined;
        var visible_count: usize = 0;
        for (0..config.MAX_PORTS) |pi| {
            if (self.hide_inactive and !self.cfg.port_active[pi]) continue;
            visible[visible_count] = pi;
            visible_count += 1;
        }

        for (0..visible_count) |vi| {
            const i = visible[vi];
            const rect = tileRect(vi);
            if (mx >= rect.x and mx < rect.x + rect.width and
                my >= rect.y and my < rect.y + rect.height)
            {
                const port: u8 = @intCast(i + 1);

                if (right) {
                    self.selected_edit_port = port;
                    self.dialog = .edit_port;
                    self.refreshEditFields();
                    self.input_fields[2].active = false;
                    self.input_fields[3].active = false;
                    self.focused_field = 0;
                    return;
                }

                self.active_port = port;
                self.anim_port = port;
                self.anim_start_ns = std.time.nanoTimestamp();
                self.pending_port = port;
                self.pending_until_ns = std.time.nanoTimestamp() +
                    5000 * std.time.ns_per_ms;
                // Clear stale polled value and suppress polling for 2s
                self.polled_port.store(port, .monotonic);
                self.poll_suppress_until.store(@intCast(@as(i64, @truncate(@divTrunc(std.time.nanoTimestamp(), std.time.ns_per_ms))) + 5000), .release);
                self.setStatus("Switching to {d}...", .{port});

                const thread = std.Thread.spawn(.{}, switchThread, .{ self, port }) catch {
                    self.setStatusStr("Failed to spawn switch thread");
                    return;
                };
                thread.detach();
                return;
            }
        }
    }

    fn switchThread(self: *Gui, port: u8) void {
        self.cli.setInput(port) catch {
            self.pending_port = 0;
            self.pending_until_ns = 0;
            self.setStatus("Switch to {d} failed", .{port});
            tray.wakeMainThread();
            return;
        };
        if (self.cfg.fast_mode) {
            self.setStatus("Switched (fast) → {d}", .{port});
            tray.wakeMainThread();
            return;
        }
        if (self.cfg.verify_after_set) {
            for (0..2) |_| {
                std.Thread.sleep(90 * std.time.ns_per_ms);
                if (self.cli.getActiveInput()) |cur| {
                    if (cur == port) {
                        self.clearPendingIfMatch(port);
                        self.setStatus("Switched to input {d}", .{port});
                        tray.wakeMainThread();
                        return;
                    }
                } else |_| {}
            }
            self.setStatusStr("Switched (unverified)");
            tray.wakeMainThread();
            return;
        }
        self.setStatus("Switched to input {d}", .{port});
        tray.wakeMainThread();
    }

    fn processTrayAction(self: *Gui) void {
        switch (tray.pollAction()) {
            .switch_port => |port| {
                self.active_port = port;
                self.anim_port = port;
                self.anim_start_ns = std.time.nanoTimestamp();
                self.pending_port = port;
                self.pending_until_ns = std.time.nanoTimestamp() + 5000 * std.time.ns_per_ms;
                self.polled_port.store(port, .monotonic);
                self.poll_suppress_until.store(@intCast(@as(i64, @truncate(@divTrunc(std.time.nanoTimestamp(), std.time.ns_per_ms))) + 5000), .release);
                self.setStatus("Switching to {d}...", .{port});
                const thread = std.Thread.spawn(.{}, switchThread, .{ self, port }) catch {
                    self.setStatusStr("Failed to spawn switch thread");
                    return;
                };
                thread.detach();
            },
            .toggle_buzzer => {
                self.buzzer_enabled = !self.buzzer_enabled;
                self.cli.setBuzzer(self.buzzer_enabled) catch {
                    self.setStatusStr(if (self.buzzer_enabled) "Failed to enable buzzer" else "Failed to disable buzzer");
                    self.status_hold_until = std.time.nanoTimestamp() + 3 * std.time.ns_per_s;
                    self.buzzer_enabled = !self.buzzer_enabled;
                    return;
                };
                self.cfg.buzzer_enabled = self.buzzer_enabled;
                config.save(self.cfg) catch {};
                self.setStatusStr(if (self.buzzer_enabled) "Buzzer enabled" else "Buzzer disabled");
                self.status_hold_until = std.time.nanoTimestamp() + 3 * std.time.ns_per_s;
            },
            .show_window => {},
            .quit => {
                self.quit_requested = true;
            },
            .none => {},
        }
    }

    fn updateToolbar(self: *Gui) void {
        if (!rl.isMouseButtonPressed(.left)) return;
        switch (self.getToolbarAction()) {
            .connection => {
                self.dialog = .connection;
                self.prepareConnectionFields();
            },
            .edit => {
                self.dialog = .edit_port;
                self.prepareEditFields();
            },
            .network => {
                self.dialog = .network_config;
                self.prepareNetworkFields();
            },
            .ping => {
                const t = std.Thread.spawn(.{}, pingThread, .{self}) catch return;
                t.detach();
            },
            .buzzer => {
                self.buzzer_enabled = !self.buzzer_enabled;
                self.cli.setBuzzer(self.buzzer_enabled) catch {
                    self.setStatusStr(if (self.buzzer_enabled) "Failed to enable buzzer" else "Failed to disable buzzer");
                    self.status_hold_until = std.time.nanoTimestamp() + 3 * std.time.ns_per_s;
                    self.buzzer_enabled = !self.buzzer_enabled; // revert
                    return;
                };
                self.cfg.buzzer_enabled = self.buzzer_enabled;
                config.save(self.cfg) catch {};
                self.setStatusStr(if (self.buzzer_enabled) "Buzzer enabled" else "Buzzer disabled");
                self.status_hold_until = std.time.nanoTimestamp() + 3 * std.time.ns_per_s;
            },
            .filter => {
                self.hide_inactive = !self.hide_inactive;
                self.cfg.hide_inactive = self.hide_inactive;
                config.save(self.cfg) catch {};
                self.startFilterAnim();
                tray.forceUpdate();
                self.setStatusStr(if (self.hide_inactive) "Hiding inactive ports" else "Showing all ports");
                self.status_hold_until = std.time.nanoTimestamp() + 2 * std.time.ns_per_s;
            },
            .about => self.dialog = .about,
            .none => {},
        }
    }

    fn pingThread(self: *Gui) void {
        self.setStatusStr("Pinging...");
        self.status_hold_until = std.time.nanoTimestamp() + 3 * std.time.ns_per_s;
        tray.wakeMainThread();
        const start = std.time.nanoTimestamp();
        self.cli.ping() catch {
            self.setStatusStr("Ping failed");
            self.status_hold_until = std.time.nanoTimestamp() + 3 * std.time.ns_per_s;
            tray.wakeMainThread();
            return;
        };
        const elapsed_ms = @divFloor(std.time.nanoTimestamp() - start, std.time.ns_per_ms);
        self.setStatus("Ping OK ({d} ms)", .{elapsed_ms});
        self.status_hold_until = std.time.nanoTimestamp() + 3 * std.time.ns_per_s;
        tray.wakeMainThread();
    }

    fn getToolbarAction(self: *Gui) ToolbarAction {
        _ = self;
        const mx = rl.getMouseX();
        const my = rl.getMouseY();
        if (my < 5 or my >= 35) return .none;
        const buttons = [_]ToolbarAction{ .connection, .edit, .network, .ping, .buzzer, .filter, .about };
        for (buttons, 0..) |btn, i| {
            const bx: i32 = @intCast(12 + i * 92);
            if (mx >= bx and mx < bx + 82) return btn;
        }
        return .none;
    }

    // ── Polling ──

    fn startPoller(self: *Gui) void {
        self.poll_running.store(true, .monotonic);
        self.poll_thread = std.Thread.spawn(.{}, pollLoop, .{self}) catch null;
    }

    fn stopPoller(self: *Gui) void {
        self.poll_running.store(false, .monotonic);
        if (self.poll_thread) |t| t.join();
        self.poll_thread = null;
    }

    fn pollLoop(self: *Gui) void {
        while (self.poll_running.load(.monotonic)) {
            // Skip polling during switch suppression window to avoid stale reads
            const suppress_until = self.poll_suppress_until.load(.acquire);
            const now_ms: i64 = @intCast(@as(i64, @truncate(@divTrunc(std.time.nanoTimestamp(), std.time.ns_per_ms))));
            if (now_ms < suppress_until) {
                std.Thread.sleep(@as(u64, self.cfg.poll_interval_ms) * std.time.ns_per_ms);
                continue;
            }
            if (self.cli.getActiveInput()) |port| {
                const changed = (port != self.polled_port.load(.monotonic));
                self.polled_port.store(port, .monotonic);
                self.poll_error = false;
                if (changed) tray.wakeMainThread();
            } else |_| {
                self.poll_error = true;
            }
            std.Thread.sleep(@as(u64, self.cfg.poll_interval_ms) * std.time.ns_per_ms);
        }
    }

    fn shouldIgnorePoll(self: *Gui, polled: u8) bool {
        _ = polled;
        return self.pending_port > 0 and std.time.nanoTimestamp() < self.pending_until_ns;
    }

    fn clearPendingIfMatch(self: *Gui, polled: u8) void {
        if (polled == self.pending_port) self.pending_until_ns = 0;
    }

    // ── Drawing ──

    fn draw(self: *Gui) void {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(BG);
        self.drawToolbar();
        self.drawGrid();
        self.drawStatusBar();
        if (self.dialog != .none) self.drawDialog();
    }

    fn drawToolbar(self: *Gui) void {
        rl.drawRectangle(0, 0, rl.getScreenWidth(), TOOLBAR_H, TOOLBAR_BG);
        // Separator line below toolbar
        rl.drawRectangle(0, TOOLBAR_H - 1, rl.getScreenWidth(), 1, SEPARATOR);
        const labels = [_][:0]const u8{ "Connect", "Edit", "Network", "Ping", "Buzzer", "Filter", "About" };
        const mx = rl.getMouseX();
        const my = rl.getMouseY();
        for (labels, 0..) |label, i| {
            const bx: i32 = @intCast(12 + i * 92);
            const by: i32 = 5;
            const bw: i32 = 82;
            const bh: i32 = 30;
            const hovered = (mx >= bx and mx < bx + bw and my >= by and my < by + bh);
            const is_buzzer = (i == 4);
            const is_filter = (i == 5);
            const color = if (is_buzzer and self.buzzer_enabled)
                rl.Color{ .r = 20, .g = 120, .b = 90, .a = 255 }
            else if (is_filter and self.hide_inactive)
                rl.Color{ .r = 20, .g = 120, .b = 90, .a = 255 }
            else if (hovered)
                BTN_HOVER
            else
                BTN_NORMAL;
            rl.drawRectangleRounded(.{ .x = @floatFromInt(bx), .y = @floatFromInt(by), .width = @floatFromInt(bw), .height = @floatFromInt(bh) }, 0.4, 8, color);
            // Subtle border on toolbar buttons
            if (!hovered and !(is_buzzer and self.buzzer_enabled) and !(is_filter and self.hide_inactive)) {
                rl.drawRectangleRoundedLines(.{ .x = @floatFromInt(bx), .y = @floatFromInt(by), .width = @floatFromInt(bw), .height = @floatFromInt(bh) }, 0.4, 8, TILE_BORDER);
            }
            const tw = measureTxt(label, SMALL_SZ);
            drawTxt(label, bx + @divFloor(bw - tw, 2), by + @divFloor(bh - SMALL_FONT, 2), SMALL_SZ, TEXT_WHITE);
        }
    }

    fn drawGrid(self: *Gui) void {
        const mx = rl.getMouseX();
        const my = rl.getMouseY();
        const now = std.time.nanoTimestamp();

        // Build visible port list
        var visible: [config.MAX_PORTS]usize = undefined;
        var visible_count: usize = 0;
        for (0..config.MAX_PORTS) |pi| {
            if (self.hide_inactive and !self.cfg.port_active[pi]) continue;
            visible[visible_count] = pi;
            visible_count += 1;
        }

        for (0..visible_count) |vi| {
            const i = visible[vi];
            const port: u8 = @intCast(i + 1);
            var rect = tileRect(vi);
            const hovered = (mx >= @as(i32, @intFromFloat(rect.x)) and
                mx < @as(i32, @intFromFloat(rect.x + rect.width)) and
                my >= @as(i32, @intFromFloat(rect.y)) and
                my < @as(i32, @intFromFloat(rect.y + rect.height)));

            // Animation progress for this tile
            const is_animating = (port == self.anim_port and now < self.anim_start_ns + ANIM_DURATION_NS);
            var anim_t: f32 = 0;
            if (is_animating) {
                const elapsed: f32 = @floatFromInt(@as(i64, @intCast(now - self.anim_start_ns)));
                const duration: f32 = @floatFromInt(@as(i64, @intCast(ANIM_DURATION_NS)));
                anim_t = elapsed / duration;
            }

            // Elastic bounce scale: overshoots to ~1.10x then settles to 1.0
            if (is_animating) {
                const elastic_t = 1.0 - anim_t; // invert so it decays
                const bounce = @as(f32, @floatCast(std.math.sin(anim_t * std.math.pi * 2.5))) * elastic_t * 0.10;
                const scale: f32 = 1.0 + bounce;
                const cx_f = rect.x + rect.width / 2;
                const cy_f = rect.y + rect.height / 2;
                const new_w = rect.width * scale;
                const new_h = rect.height * scale;
                rect = .{
                    .x = cx_f - new_w / 2,
                    .y = cy_f - new_h / 2,
                    .width = new_w,
                    .height = new_h,
                };
            }

            const is_inactive = !self.cfg.port_active[i];

            // Filter animation: fade + scale tiles in/out
            const filter_t = self.filterAnimProgress();
            const filter_animating = (self.filter_anim_start_ns > 0 and filter_t < 1.0);
            var tile_alpha: u8 = 255;
            if (filter_animating) {
                tile_alpha = @intFromFloat(filter_t * 255.0);
                // Scale up from 0.85 to 1.0
                const fscale = 0.85 + 0.15 * filter_t;
                const cx_f = rect.x + rect.width / 2;
                const cy_f = rect.y + rect.height / 2;
                const new_w = rect.width * fscale;
                const new_h = rect.height * fscale;
                rect = .{
                    .x = cx_f - new_w / 2,
                    .y = cy_f - new_h / 2,
                    .width = new_w,
                    .height = new_h,
                };
            }

            const base_color = if (is_inactive)
                rl.Color{ .r = 40, .g = 40, .b = 40, .a = 255 }
            else if (port == self.active_port)
                TILE_ACTIVE
            else if (hovered)
                TILE_HOVER
            else
                TILE_NORMAL;
            const color = rl.Color{ .r = base_color.r, .g = base_color.g, .b = base_color.b, .a = tile_alpha };

            // Soft glow behind active tile (always, not just during animation)
            if (port == self.active_port and !is_animating) {
                const glow_a = TILE_ACTIVE_GLOW;
                rl.drawRectangleRounded(.{
                    .x = rect.x - 4,
                    .y = rect.y - 4,
                    .width = rect.width + 8,
                    .height = rect.height + 8,
                }, 0.12, 8, rl.Color{ .r = glow_a.r, .g = glow_a.g, .b = glow_a.b, .a = glow_a.a });
            }

            // Glow rings behind the tile during animation
            if (is_animating) {
                // Outer expanding ring
                const ring1_expand: f32 = anim_t * 12;
                const ring1_alpha: u8 = @intFromFloat(@max(0, (1.0 - anim_t * 1.5)) * 100);
                if (ring1_alpha > 0) {
                    const r1_col = rl.Color{ .r = GLOW_COLOR.r, .g = GLOW_COLOR.g, .b = GLOW_COLOR.b, .a = ring1_alpha };
                    rl.drawRectangleRounded(.{
                        .x = rect.x - ring1_expand - 2,
                        .y = rect.y - ring1_expand - 2,
                        .width = rect.width + (ring1_expand + 2) * 2,
                        .height = rect.height + (ring1_expand + 2) * 2,
                    }, 0.12, 8, r1_col);
                }
                // Inner glow
                const inner_alpha: u8 = @intFromFloat((1.0 - anim_t) * 160);
                const inner_col = rl.Color{ .r = GLOW_COLOR.r, .g = GLOW_COLOR.g, .b = GLOW_COLOR.b, .a = inner_alpha };
                rl.drawRectangleRounded(.{
                    .x = rect.x - 3,
                    .y = rect.y - 3,
                    .width = rect.width + 6,
                    .height = rect.height + 6,
                }, 0.12, 8, inner_col);
            }

            rl.drawRectangleRounded(rect, 0.12, 8, color);

            // Subtle border on non-active tiles
            if (port != self.active_port and !is_animating) {
                const border_col = rl.Color{ .r = TILE_BORDER.r, .g = TILE_BORDER.g, .b = TILE_BORDER.b, .a = tile_alpha };
                rl.drawRectangleRoundedLines(rect, 0.12, 8, border_col);
            }

            // Color flash overlay on the tile (bright white that fades fast)
            if (is_animating and anim_t < 0.4) {
                const flash_alpha: u8 = @intFromFloat((1.0 - anim_t / 0.4) * 60);
                rl.drawRectangleRounded(rect, 0.15, 8, rl.Color{ .r = 200, .g = 230, .b = 255, .a = flash_alpha });
            }

            // Shine sweep across the tile surface
            if (is_animating) {
                const shine_x = rect.x + (rect.width + 40) * anim_t - 20;
                // Clamp shine to tile bounds
                const clip_left = @max(shine_x, rect.x);
                const clip_right = @min(shine_x + 20, rect.x + rect.width);
                if (clip_right > clip_left) {
                    const shine_alpha: u8 = @intFromFloat((1.0 - anim_t * 0.5) * 50);
                    rl.drawRectangleRounded(.{
                        .x = clip_left,
                        .y = rect.y,
                        .width = clip_right - clip_left,
                        .height = rect.height,
                    }, 0.05, 4, rl.Color{ .r = 255, .g = 255, .b = 255, .a = shine_alpha });
                }
            }

            const cx: i32 = @intFromFloat(rect.x + rect.width / 2);
            const tile_top: i32 = @intFromFloat(rect.y);

            // Draw icon (texture or placeholder)
            if (self.icon_loaded[i]) {
                const tex = self.icon_textures[i];
                const src_rect = rl.Rectangle{
                    .x = 0,
                    .y = 0,
                    .width = @floatFromInt(tex.width),
                    .height = @floatFromInt(tex.height),
                };
                const tex_w: f32 = @floatFromInt(tex.width);
                const tex_h: f32 = @floatFromInt(tex.height);
                const max_w: f32 = TILE_W - 20;
                const max_h: f32 = ICON_DISPLAY_SZ;
                const port_scale = self.cfg.portIconScale(i + 1);
                const base_scale = if (tex_w > 0 and tex_h > 0) @min(max_w / tex_w, max_h / tex_h) else 1.0;
                const scale = base_scale * port_scale;
                const disp_w = tex_w * scale;
                const disp_h = tex_h * scale;
                const dest_rect = rl.Rectangle{
                    .x = @as(f32, @floatFromInt(cx)) - disp_w / 2,
                    .y = @as(f32, @floatFromInt(tile_top)) + 12 + (max_h - disp_h) / 2,
                    .width = disp_w,
                    .height = disp_h,
                };
                rl.drawTexturePro(tex, src_rect, dest_rect, .{ .x = 0, .y = 0 }, 0, rl.Color{ .r = 255, .g = 255, .b = 255, .a = tile_alpha });
            } else {
                // Placeholder: simple monitor icon shape
                const px = cx - 16;
                const py = tile_top + 20;
                const ph_col = rl.Color{ .r = ICON_PLACEHOLDER.r, .g = ICON_PLACEHOLDER.g, .b = ICON_PLACEHOLDER.b, .a = tile_alpha };
                rl.drawRectangleRounded(.{ .x = @floatFromInt(px), .y = @floatFromInt(py), .width = 32, .height = 24 }, 0.2, 4, ph_col);
                rl.drawRectangle(cx - 4, py + 24, 8, 6, ph_col);
                rl.drawRectangle(cx - 10, py + 30, 20, 3, ph_col);
            }

            // Port name
            const name = self.cfg.portName(port);
            var name_z: [65:0]u8 = std.mem.zeroes([65:0]u8);
            const nlen = @min(name.len, 64);
            @memcpy(name_z[0..nlen], name[0..nlen]);
            const name_slice: [:0]const u8 = name_z[0..nlen :0];
            const name_base = if (is_inactive) TEXT_DIM else TEXT_WHITE;
            const name_color = rl.Color{ .r = name_base.r, .g = name_base.g, .b = name_base.b, .a = tile_alpha };
            const text_w = measureTxt(name_slice, SMALL_SZ);
            drawTxt(name_slice, cx - @divFloor(text_w, 2), tile_top + 76, SMALL_SZ, name_color);

            // Port number
            var num_z: [8:0]u8 = std.mem.zeroes([8:0]u8);
            const num_s = std.fmt.bufPrint(&num_z, "#{d}", .{port}) catch "";
            const num_slice: [:0]const u8 = num_z[0..num_s.len :0];
            const num_color = rl.Color{ .r = TEXT_DIM.r, .g = TEXT_DIM.g, .b = TEXT_DIM.b, .a = tile_alpha };
            const num_w = measureTxt(num_slice, SMALL_SZ - 2);
            drawTxt(num_slice, cx - @divFloor(num_w, 2), tile_top + 96, SMALL_SZ - 2, num_color);

            // Neon traveling thick line while switching (5s)
            const neon_active = (port == self.anim_port and self.anim_start_ns > 0 and now < self.anim_start_ns + NEON_DURATION_NS);
            if (neon_active) {
                // Fade out over last 1.5s
                const neon_elapsed_ns = now - self.anim_start_ns;
                const fade_start_ns: i128 = NEON_DURATION_NS - 1500 * std.time.ns_per_ms;
                const neon_fade: f32 = if (neon_elapsed_ns > fade_start_ns)
                    1.0 - @as(f32, @floatFromInt(@as(i64, @intCast(neon_elapsed_ns - fade_start_ns)))) / @as(f32, @floatFromInt(@as(i64, @intCast(1500 * std.time.ns_per_ms))))
                else
                    1.0;

                // Soft breathing outer glow
                const breath = @as(f32, @floatCast(std.math.sin(@as(f64, @floatFromInt(@as(i64, @intCast(@mod(now, 1_000_000_000))))) / 1_000_000_000.0 * std.math.pi * 2.0)));
                const glow_alpha: u8 = @intFromFloat((35.0 + (breath + 1.0) * 15.0) * neon_fade);
                rl.drawRectangleRounded(.{
                    .x = rect.x - 4,
                    .y = rect.y - 4,
                    .width = rect.width + 8,
                    .height = rect.height + 8,
                }, 0.15, 8, rl.Color{ .r = NEON_COLOR.r, .g = NEON_COLOR.g, .b = NEON_COLOR.b, .a = glow_alpha });

                // Dim base border
                const border_alpha: u8 = @intFromFloat(60.0 * neon_fade);
                rl.drawRectangleRoundedLines(rect, 0.15, 8, rl.Color{ .r = NEON_COLOR.r, .g = NEON_COLOR.g, .b = NEON_COLOR.b, .a = border_alpha });

                // Compute position along perimeter (0.0 - 1.0)
                const cycle_pos = @as(f32, @floatCast(@as(f64, @floatFromInt(@as(i64, @intCast(@mod(now, NEON_CYCLE_NS))))) / @as(f64, @floatFromInt(@as(i64, @intCast(NEON_CYCLE_NS))))));
                const perim = (rect.width + rect.height) * 2.0;
                const side_fracs = [4]f32{
                    rect.width / perim,
                    rect.height / perim,
                    rect.width / perim,
                    rect.height / perim,
                };

                // Draw the bright segment as a series of thick lines
                const num_samples = 20;
                var s: usize = 0;
                while (s < num_samples) : (s += 1) {
                    const frac_along = @as(f32, @floatFromInt(s)) / @as(f32, @floatFromInt(num_samples));
                    const t1 = @mod(cycle_pos + frac_along * NEON_SEG_FRAC, 1.0);
                    const t2 = @mod(cycle_pos + @as(f32, @floatFromInt(s + 1)) / @as(f32, @floatFromInt(num_samples)) * NEON_SEG_FRAC, 1.0);

                    // Fade: brightest at front (high frac_along), dimmer at tail
                    const intensity = 0.3 + 0.7 * frac_along;
                    const thick: f32 = 2.0 + intensity * 3.0;
                    const glow_a: u8 = @intFromFloat(intensity * 80 * neon_fade);
                    const core_a: u8 = @intFromFloat(intensity * 240 * neon_fade);
                    const glow_col = rl.Color{ .r = NEON_COLOR.r, .g = NEON_COLOR.g, .b = NEON_COLOR.b, .a = glow_a };
                    const core_col = rl.Color{ .r = 180, .g = 240, .b = 255, .a = core_a };

                    if (t2 < t1) {
                        // Wrap-around: draw two segments meeting at the seam point
                        const p1 = perimPoint(rect, t1, &side_fracs);
                        const seam = perimPoint(rect, 0.0, &side_fracs);
                        const p2 = perimPoint(rect, t2, &side_fracs);
                        rl.drawLineEx(p1, seam, thick + 4, glow_col);
                        rl.drawLineEx(p1, seam, thick, core_col);
                        rl.drawLineEx(seam, p2, thick + 4, glow_col);
                        rl.drawLineEx(seam, p2, thick, core_col);
                    } else {
                        const p1 = perimPoint(rect, t1, &side_fracs);
                        const p2 = perimPoint(rect, t2, &side_fracs);
                        rl.drawLineEx(p1, p2, thick + 4, glow_col);
                        rl.drawLineEx(p1, p2, thick, core_col);
                    }
                }
            }
        }
    }

    fn drawStatusBar(self: *Gui) void {
        const sh = rl.getScreenHeight();
        const sw = rl.getScreenWidth();
        const y = sh - STATUS_H;
        // Separator line above status bar
        rl.drawRectangle(0, y, sw, 1, SEPARATOR);
        rl.drawRectangle(0, y + 1, sw, STATUS_H - 1, STATUS_BG);
        var z: [257:0]u8 = std.mem.zeroes([257:0]u8);
        const n = @min(self.status_len, 256);
        @memcpy(z[0..n], self.status_text[0..n]);
        drawTxt(z[0..n :0], 10, y + 7, SMALL_SZ, TEXT_DIM);
    }

    // ── Dialog system ──

    fn drawDialog(self: *Gui) void {
        rl.drawRectangle(0, 0, rl.getScreenWidth(), rl.getScreenHeight(), DIALOG_OVERLAY);
        switch (self.dialog) {
            .connection, .first_setup => self.drawConnectionDialog(),
            .edit_port => self.drawEditDialog(),
            .network_config => self.drawNetworkConfigDialog(),
            .raw_hex => self.drawRawHexDialog(),
            .about => self.drawAboutDialog(),
            .none => {},
        }
    }

    fn updateDialog(self: *Gui) void {
        if (rl.isKeyPressed(.escape) and self.dialog != .first_setup) {
            self.dialog = .none;
            self.focused_field = null;
            return;
        }
        self.updateInputFields();
    }

    fn updateInputFields(self: *Gui) void {
        if (rl.isMouseButtonPressed(.left)) {
            self.focused_field = null;
            for (&self.input_fields, 0..) |*field, i| {
                if (!field.active) continue;
                const rect = field.rect;
                const mx = rl.getMouseX();
                const my = rl.getMouseY();
                if (mx >= @as(i32, @intFromFloat(rect.x)) and
                    mx < @as(i32, @intFromFloat(rect.x + rect.width)) and
                    my >= @as(i32, @intFromFloat(rect.y)) and
                    my < @as(i32, @intFromFloat(rect.y + rect.height)))
                {
                    self.focused_field = i;
                    break;
                }
            }
            self.handleDialogButtons();
        }

        if (rl.isKeyPressed(.tab)) {
            if (self.focused_field) |f| {
                var next = f + 1;
                while (next < self.input_fields.len) : (next += 1) {
                    if (self.input_fields[next].active) {
                        self.focused_field = next;
                        break;
                    }
                } else {
                    var wrap: usize = 0;
                    while (wrap < f) : (wrap += 1) {
                        if (self.input_fields[wrap].active) {
                            self.focused_field = wrap;
                            break;
                        }
                    }
                }
            } else {
                for (&self.input_fields, 0..) |*field, i| {
                    if (field.active) {
                        self.focused_field = i;
                        break;
                    }
                }
            }
        }

        if (self.focused_field) |fi| {
            var field = &self.input_fields[fi];

            // Delete at cursor
            if (rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) {
                if (field.cursor > 0) {
                    // Shift everything after cursor left by 1
                    std.mem.copyForwards(u8, field.buf[field.cursor - 1 .. field.len - 1], field.buf[field.cursor..field.len]);
                    field.len -= 1;
                    field.cursor -= 1;
                }
            }
            // Forward delete
            if (rl.isKeyPressed(.delete) or rl.isKeyPressedRepeat(.delete)) {
                if (field.cursor < field.len) {
                    std.mem.copyForwards(u8, field.buf[field.cursor .. field.len - 1], field.buf[field.cursor + 1 .. field.len]);
                    field.len -= 1;
                }
            }
            // Cursor movement
            if (rl.isKeyPressed(.left) or rl.isKeyPressedRepeat(.left)) {
                if (field.cursor > 0) field.cursor -= 1;
            }
            if (rl.isKeyPressed(.right) or rl.isKeyPressedRepeat(.right)) {
                if (field.cursor < field.len) field.cursor += 1;
            }
            if (rl.isKeyPressed(.home)) field.cursor = 0;
            if (rl.isKeyPressed(.end)) field.cursor = field.len;

            // Insert typed characters at cursor
            var ch = rl.getCharPressed();
            while (ch > 0) : (ch = rl.getCharPressed()) {
                if (ch >= 32 and ch < 127 and field.len < field.buf.len) {
                    // Shift everything after cursor right by 1
                    if (field.cursor < field.len) {
                        std.mem.copyBackwards(u8, field.buf[field.cursor + 1 .. field.len + 1], field.buf[field.cursor..field.len]);
                    }
                    field.buf[field.cursor] = @intCast(ch);
                    field.len += 1;
                    field.cursor += 1;
                }
            }
        }
    }

    fn handleDialogButtons(self: *Gui) void {
        switch (self.dialog) {
            .connection, .first_setup => self.handleConnectionButtons(),
            .edit_port => self.handleEditButtons(),
            .network_config => self.handleNetworkButtons(),
            .raw_hex => self.handleRawHexButtons(),
            .about => {
                if (isButtonClicked(160 + 400 / 2 - 35, 200 + 220 - 42, 70, 30)) {
                    self.dialog = .none;
                }
            },
            .none => {},
        }
    }

    // ── Connection dialog ──

    fn prepareConnectionFields(self: *Gui) void {
        self.input_fields[0] = InputField.initWith(self.cfg.ip[0..self.cfg.ip_len]);
        self.input_fields[0].active = true;
        var port_buf: [8]u8 = undefined;
        const ps = std.fmt.bufPrint(&port_buf, "{d}", .{self.cfg.port}) catch "5000";
        self.input_fields[1] = InputField.initWith(ps);
        self.input_fields[1].active = true;
        self.input_fields[2].active = false;
        self.input_fields[3].active = false;
        self.focused_field = 0;
    }

    fn drawConnectionDialog(self: *Gui) void {
        const dx: f32 = 160;
        const dy: f32 = 180;
        const dw: f32 = 400;
        const dh: f32 = 200;
        drawDialogBox(dx, dy, dw, dh);

        const title = if (self.dialog == .first_setup) "First-Time Setup" else "Connection Settings";
        drawTxt(title, @intFromFloat(dx + 20), @intFromFloat(dy + 15), FONT_SZ, TEXT_WHITE);
        drawTxt("KVM IP:", @intFromFloat(dx + 20), @intFromFloat(dy + 52), SMALL_SZ, TEXT_DIM);
        drawTxt("KVM Port:", @intFromFloat(dx + 20), @intFromFloat(dy + 92), SMALL_SZ, TEXT_DIM);

        self.input_fields[0].rect = .{ .x = dx + 100, .y = dy + 48, .width = 260, .height = 26 };
        self.input_fields[1].rect = .{ .x = dx + 100, .y = dy + 88, .width = 260, .height = 26 };
        self.drawInputField(0);
        self.drawInputField(1);

        const save_label = if (self.dialog == .first_setup) "Save & Go" else "Save";
        drawButton(@intFromFloat(dx + dw - 180), @intFromFloat(dy + dh - 42), 80, 30, save_label, BTN_ACTIVE);
        if (self.dialog != .first_setup)
            drawButton(@intFromFloat(dx + dw - 90), @intFromFloat(dy + dh - 42), 70, 30, "Close", BTN_NORMAL);
    }

    fn handleConnectionButtons(self: *Gui) void {
        const dx: f32 = 160;
        const dy: f32 = 180;
        const dw: f32 = 400;
        const dh: f32 = 200;
        if (isButtonClicked(@intFromFloat(dx + dw - 180), @intFromFloat(dy + dh - 42), 80, 30)) {
            const ip_s = self.input_fields[0].slice();
            const port_s = self.input_fields[1].slice();
            const p = std.fmt.parseUnsigned(u16, port_s, 10) catch {
                self.setStatusStr("Invalid port number");
                return;
            };
            if (ip_s.len == 0) {
                self.setStatusStr("IP cannot be empty");
                return;
            }
            @memcpy(self.cfg.ip[0..ip_s.len], ip_s);
            self.cfg.ip_len = ip_s.len;
            self.cfg.port = p;
            if (self.dialog == .first_setup) self.cfg.setup_completed = true;
            config.save(self.cfg) catch {};
            self.cli.setTarget(ip_s, p, self.cfg.get_timeout_ms, self.cfg.set_timeout_ms);
            self.setStatus("Connection → {s}:{d}", .{ ip_s, p });
            self.dialog = .none;
            self.focused_field = null;
        }
        if (self.dialog != .first_setup and
            isButtonClicked(@intFromFloat(dx + dw - 90), @intFromFloat(dy + dh - 42), 70, 30))
        {
            self.dialog = .none;
            self.focused_field = null;
        }
    }

    // ── Edit port dialog (with Browse button) ──

    fn prepareEditFields(self: *Gui) void {
        self.selected_edit_port = 1;
        self.input_fields[0] = InputField.initWith(self.cfg.portName(1));
        self.input_fields[0].active = true;
        self.input_fields[1] = InputField.initWith(self.cfg.portIcon(1));
        self.input_fields[1].active = true;
        self.input_fields[2].active = false;
        self.input_fields[3].active = false;
        self.edit_icon_scale = self.cfg.portIconScale(1);
        self.edit_port_active = self.cfg.isPortActive(1);
        self.focused_field = 0;
    }

    fn drawEditDialog(self: *Gui) void {
        const dx: f32 = 110;
        const dy: f32 = 150;
        const dw: f32 = 500;
        const dh: f32 = 360;
        drawDialogBox(dx, dy, dw, dh);

        drawTxt("Edit Port Names / Icons", @intFromFloat(dx + 20), @intFromFloat(dy + 15), FONT_SZ, TEXT_WHITE);

        // Port selector
        drawTxt("Port:", @intFromFloat(dx + 20), @intFromFloat(dy + 56), SMALL_SZ, TEXT_DIM);
        var num_z: [4:0]u8 = std.mem.zeroes([4:0]u8);
        const ns = std.fmt.bufPrint(&num_z, "{d}", .{self.selected_edit_port}) catch "";
        drawButton(@intFromFloat(dx + 80), @intFromFloat(dy + 52), 30, 24, "<", BTN_NORMAL);
        drawTxt(num_z[0..ns.len :0], @intFromFloat(dx + 120), @intFromFloat(dy + 56), SMALL_SZ, TEXT_WHITE);
        drawButton(@intFromFloat(dx + 150), @intFromFloat(dy + 52), 30, 24, ">", BTN_NORMAL);

        // Show current icon preview if loaded
        const idx = @as(usize, self.selected_edit_port) - 1;
        if (self.icon_loaded[idx]) {
            const tex = self.icon_textures[idx];
            const src_r = rl.Rectangle{ .x = 0, .y = 0, .width = @floatFromInt(tex.width), .height = @floatFromInt(tex.height) };
            const tex_w: f32 = @floatFromInt(tex.width);
            const tex_h: f32 = @floatFromInt(tex.height);
            const prev_max_w: f32 = 80;
            const prev_max_h: f32 = 48;
            const prev_scale = if (tex_w > 0 and tex_h > 0) @min(prev_max_w / tex_w, prev_max_h / tex_h) else 1.0;
            const preview_w = tex_w * prev_scale;
            const preview_h = tex_h * prev_scale;
            const dest_r = rl.Rectangle{ .x = dx + dw - 40 - preview_w / 2, .y = dy + 40 + (prev_max_h - preview_h) / 2, .width = preview_w, .height = preview_h };
            rl.drawTexturePro(tex, src_r, dest_r, .{ .x = 0, .y = 0 }, 0, WHITE);
        }

        drawTxt("Name:", @intFromFloat(dx + 20), @intFromFloat(dy + 100), SMALL_SZ, TEXT_DIM);
        drawTxt("Icon:", @intFromFloat(dx + 20), @intFromFloat(dy + 140), SMALL_SZ, TEXT_DIM);

        self.input_fields[0].rect = .{ .x = dx + 80, .y = dy + 96, .width = dw - 120, .height = 26 };
        self.input_fields[1].rect = .{ .x = dx + 80, .y = dy + 136, .width = dw - 210, .height = 26 };
        self.drawInputField(0);
        self.drawInputField(1);

        // Browse button (next to icon field)
        drawButton(@intFromFloat(dx + dw - 120), @intFromFloat(dy + 136), 80, 26, "Browse", ACCENT);

        // Scale row
        drawTxt("Scale:", @intFromFloat(dx + 20), @intFromFloat(dy + 180), SMALL_SZ, TEXT_DIM);
        drawButton(@intFromFloat(dx + 80), @intFromFloat(dy + 176), 30, 24, "-", BTN_NORMAL);
        var scale_z: [8:0]u8 = std.mem.zeroes([8:0]u8);
        const ss = std.fmt.bufPrint(&scale_z, "{d:.2}x", .{self.edit_icon_scale}) catch "1.00x";
        drawTxt(scale_z[0..ss.len :0], @intFromFloat(dx + 120), @intFromFloat(dy + 180), SMALL_SZ, TEXT_WHITE);
        drawButton(@intFromFloat(dx + 180), @intFromFloat(dy + 176), 30, 24, "+", BTN_NORMAL);

        // Active toggle row
        drawTxt("Active:", @intFromFloat(dx + 20), @intFromFloat(dy + 218), SMALL_SZ, TEXT_DIM);
        const active_color = if (self.edit_port_active)
            rl.Color{ .r = 0, .g = 120, .b = 80, .a = 255 }
        else
            BTN_NORMAL;
        const active_label: [:0]const u8 = if (self.edit_port_active) "Yes" else "No";
        drawButton(@intFromFloat(dx + 80), @intFromFloat(dy + 214), 60, 24, active_label, active_color);

        drawButton(@intFromFloat(dx + dw - 180), @intFromFloat(dy + dh - 42), 80, 30, "Save", BTN_ACTIVE);
        drawButton(@intFromFloat(dx + dw - 90), @intFromFloat(dy + dh - 42), 70, 30, "Close", BTN_NORMAL);
    }

    fn handleEditButtons(self: *Gui) void {
        const dx: f32 = 110;
        const dy: f32 = 150;
        const dw: f32 = 500;
        const dh: f32 = 360;

        // Port < >
        if (isButtonClicked(@intFromFloat(dx + 80), @intFromFloat(dy + 52), 30, 24)) {
            if (self.selected_edit_port > 1) {
                self.selected_edit_port -= 1;
                self.refreshEditFields();
            }
        }
        if (isButtonClicked(@intFromFloat(dx + 150), @intFromFloat(dy + 52), 30, 24)) {
            if (self.selected_edit_port < 16) {
                self.selected_edit_port += 1;
                self.refreshEditFields();
            }
        }

        // Browse button — opens OS native file picker, copies icon to config dir
        if (isButtonClicked(@intFromFloat(dx + dw - 120), @intFromFloat(dy + 136), 80, 26)) {
            var picked_path: [1024]u8 = undefined;
            const picked_len = native.openImageDialog(&picked_path);
            if (picked_len > 0) {
                // Copy icon to config directory
                var icon_filename: [256]u8 = undefined;
                const fn_len = native.copyIconToDir(
                    picked_path[0..picked_len],
                    self.cfg.dirSlice(),
                    &icon_filename,
                ) catch {
                    self.setStatusStr("Failed to copy icon");
                    return;
                };
                // Update icon field with just the filename
                self.input_fields[1] = InputField.initWith(icon_filename[0..fn_len]);
                self.input_fields[1].active = true;
                self.setStatus("Icon copied: {s}", .{icon_filename[0..fn_len]});
            }
        }

        // Scale - / +
        if (isButtonClicked(@intFromFloat(dx + 80), @intFromFloat(dy + 176), 30, 24)) {
            self.edit_icon_scale = @max(0.25, self.edit_icon_scale - 0.25);
        }
        if (isButtonClicked(@intFromFloat(dx + 180), @intFromFloat(dy + 176), 30, 24)) {
            self.edit_icon_scale = @min(4.0, self.edit_icon_scale + 0.25);
        }

        // Active toggle
        if (isButtonClicked(@intFromFloat(dx + 80), @intFromFloat(dy + 214), 60, 24)) {
            self.edit_port_active = !self.edit_port_active;
        }

        // Save
        if (isButtonClicked(@intFromFloat(dx + dw - 180), @intFromFloat(dy + dh - 42), 80, 30)) {
            const port_idx = @as(usize, self.selected_edit_port);
            self.cfg.setPortName(port_idx, self.input_fields[0].slice());
            self.cfg.setPortIcon(port_idx, self.input_fields[1].slice());
            self.cfg.setPortIconScale(port_idx, self.edit_icon_scale);
            self.cfg.setPortActive(port_idx, self.edit_port_active);
            config.save(self.cfg) catch {};
            // Reload the icon texture
            self.loadIconForPort(port_idx - 1);
            self.startFilterAnim();
            tray.forceUpdate();
            self.setStatus("Updated Port {d}", .{self.selected_edit_port});
        }
        // Close
        if (isButtonClicked(@intFromFloat(dx + dw - 90), @intFromFloat(dy + dh - 42), 70, 30)) {
            self.dialog = .none;
            self.focused_field = null;
        }
    }

    fn refreshEditFields(self: *Gui) void {
        self.input_fields[0] = InputField.initWith(self.cfg.portName(self.selected_edit_port));
        self.input_fields[0].active = true;
        self.input_fields[1] = InputField.initWith(self.cfg.portIcon(self.selected_edit_port));
        self.input_fields[1].active = true;
        self.edit_icon_scale = self.cfg.portIconScale(self.selected_edit_port);
        self.edit_port_active = self.cfg.isPortActive(self.selected_edit_port);
    }

    // ── Network config dialog ──

    fn prepareNetworkFields(self: *Gui) void {
        for (&self.input_fields) |*f| {
            f.* = InputField{};
            f.active = true;
        }
        self.focused_field = 0;
    }

    fn drawNetworkConfigDialog(self: *Gui) void {
        const dx: f32 = 100;
        const dy: f32 = 130;
        const dw: f32 = 520;
        const dh: f32 = 330;
        drawDialogBox(dx, dy, dw, dh);

        drawTxt("KVM Network Configuration", @intFromFloat(dx + 20), @intFromFloat(dy + 15), FONT_SZ, TEXT_WHITE);
        drawTxt("(ASCII protocol)", @intFromFloat(dx + 280), @intFromFloat(dy + 18), SMALL_SZ, TEXT_DIM);

        const labels = [_][:0]const u8{ "IPv4 Address:", "Netmask:", "Gateway:", "Port:" };
        for (labels, 0..) |label, i| {
            const fy = dy + 60 + @as(f32, @floatFromInt(i)) * 40;
            drawTxt(label, @intFromFloat(dx + 20), @intFromFloat(fy + 4), SMALL_SZ, TEXT_DIM);
            self.input_fields[i].rect = .{ .x = dx + 140, .y = fy, .width = dw - 180, .height = 26 };
            self.drawInputField(i);
        }

        drawButton(@intFromFloat(dx + 20), @intFromFloat(dy + dh - 46), 100, 30, "Get Config", BTN_NORMAL);
        drawButton(@intFromFloat(dx + 130), @intFromFloat(dy + dh - 46), 100, 30, "Set Config", BTN_ACTIVE);
        drawButton(@intFromFloat(dx + dw - 80), @intFromFloat(dy + dh - 46), 60, 30, "Close", BTN_NORMAL);
    }

    fn handleNetworkButtons(self: *Gui) void {
        const dx: f32 = 100;
        const dy: f32 = 130;
        const dw: f32 = 520;
        const dh: f32 = 330;
        if (isButtonClicked(@intFromFloat(dx + 20), @intFromFloat(dy + dh - 46), 100, 30)) {
            const t = std.Thread.spawn(.{}, netGetThread, .{self}) catch return;
            t.detach();
        }
        if (isButtonClicked(@intFromFloat(dx + 130), @intFromFloat(dy + dh - 46), 100, 30)) {
            const t = std.Thread.spawn(.{}, netSetThread, .{self}) catch return;
            t.detach();
        }
        if (isButtonClicked(@intFromFloat(dx + dw - 80), @intFromFloat(dy + dh - 46), 60, 30)) {
            self.dialog = .none;
            self.focused_field = null;
        }
    }

    fn netGetThread(self: *Gui) void {
        const net_cfg = self.cli.getNetworkConfigASCII() catch {
            self.setStatusStr("Failed to read network config");
            tray.wakeMainThread();
            return;
        };
        self.input_fields[0] = InputField.initWith(net_cfg.ipSlice());
        self.input_fields[0].active = true;
        self.input_fields[1] = InputField.initWith(net_cfg.maskSlice());
        self.input_fields[1].active = true;
        self.input_fields[2] = InputField.initWith(net_cfg.gwSlice());
        self.input_fields[2].active = true;
        var port_buf: [8]u8 = undefined;
        const ps = std.fmt.bufPrint(&port_buf, "{d}", .{net_cfg.port}) catch "5000";
        self.input_fields[3] = InputField.initWith(ps);
        self.input_fields[3].active = true;
        self.setStatusStr("Fetched network configuration");
        tray.wakeMainThread();
    }

    fn netSetThread(self: *Gui) void {
        const ip = self.input_fields[0].slice();
        const mask = self.input_fields[1].slice();
        const gw = self.input_fields[2].slice();
        const port_s = self.input_fields[3].slice();
        const p = std.fmt.parseUnsigned(u16, port_s, 10) catch {
            self.setStatusStr("Invalid port");
            tray.wakeMainThread();
            return;
        };
        self.cli.setNetworkConfigASCII(ip, p, mask, gw) catch {
            self.setStatusStr("Failed to set network config");
            tray.wakeMainThread();
            return;
        };
        @memcpy(self.cfg.ip[0..ip.len], ip);
        self.cfg.ip_len = ip.len;
        self.cfg.port = p;
        config.save(self.cfg) catch {};
        self.cli.setTarget(ip, p, self.cfg.get_timeout_ms, self.cfg.set_timeout_ms);
        self.setStatusStr("Network config sent — power-cycle switch");
        tray.wakeMainThread();
    }

    // ── Raw Hex dialog ──

    fn drawRawHexDialog(self: *Gui) void {
        const dx: f32 = 120;
        const dy: f32 = 180;
        const dw: f32 = 480;
        const dh: f32 = 230;
        drawDialogBox(dx, dy, dw, dh);

        drawTxt("Send Raw Hex", @intFromFloat(dx + 20), @intFromFloat(dy + 15), FONT_SZ, TEXT_WHITE);
        drawTxt("Hex:", @intFromFloat(dx + 20), @intFromFloat(dy + 56), SMALL_SZ, TEXT_DIM);

        self.input_fields[0].active = true;
        self.input_fields[0].rect = .{ .x = dx + 60, .y = dy + 52, .width = dw - 100, .height = 26 };
        self.drawInputField(0);

        drawTxt("Reply:", @intFromFloat(dx + 20), @intFromFloat(dy + 96), SMALL_SZ, TEXT_DIM);
        if (self.dialog_result_len > 0) {
            var z: [257:0]u8 = std.mem.zeroes([257:0]u8);
            const n = @min(self.dialog_result_len, 256);
            @memcpy(z[0..n], self.dialog_result[0..n]);
            drawTxt(z[0..n :0], @intFromFloat(dx + 60), @intFromFloat(dy + 96), SMALL_SZ, TEXT_WHITE);
        }

        drawButton(@intFromFloat(dx + dw - 160), @intFromFloat(dy + dh - 42), 70, 30, "Send", BTN_ACTIVE);
        drawButton(@intFromFloat(dx + dw - 80), @intFromFloat(dy + dh - 42), 60, 30, "Close", BTN_NORMAL);
    }

    fn handleRawHexButtons(self: *Gui) void {
        const dx: f32 = 120;
        const dy: f32 = 180;
        const dw: f32 = 480;
        const dh: f32 = 230;
        if (isButtonClicked(@intFromFloat(dx + dw - 160), @intFromFloat(dy + dh - 42), 70, 30)) {
            const t = std.Thread.spawn(.{}, rawHexThread, .{self}) catch return;
            t.detach();
        }
        if (isButtonClicked(@intFromFloat(dx + dw - 80), @intFromFloat(dy + dh - 42), 60, 30)) {
            self.dialog = .none;
            self.focused_field = null;
        }
    }

    fn rawHexThread(self: *Gui) void {
        const hex = self.input_fields[0].slice();
        self.dialog_result_len = self.cli.rawHexSend(hex, 1200, &self.dialog_result) catch {
            self.setStatusStr("Raw hex failed");
            tray.wakeMainThread();
            return;
        };
        tray.wakeMainThread();
    }

    // ── About dialog ──

    fn drawAboutDialog(self: *Gui) void {
        _ = self;
        const dx: f32 = 160;
        const dy: f32 = 200;
        const dw: f32 = 400;
        const dh: f32 = 220;
        drawDialogBox(dx, dy, dw, dh);

        drawTxt("TeSmart 16-Port GUI", @intFromFloat(dx + 20), @intFromFloat(dy + 20), FONT_SZ, TEXT_WHITE);
        drawTxt("Zig + raylib edition", @intFromFloat(dx + 20), @intFromFloat(dy + 48), SMALL_SZ, ACCENT);
        drawTxt("Ported from Go/Fyne by SiirRandall", @intFromFloat(dx + 20), @intFromFloat(dy + 76), SMALL_SZ, TEXT_DIM);
        drawTxt("Input switching, ping, buzzer,", @intFromFloat(dx + 20), @intFromFloat(dy + 106), SMALL_SZ, TEXT_DIM);
        drawTxt("LED timeout, raw hex, network config", @intFromFloat(dx + 20), @intFromFloat(dy + 124), SMALL_SZ, TEXT_DIM);
        drawTxt("MIT License", @intFromFloat(dx + 20), @intFromFloat(dy + 154), SMALL_SZ, TEXT_DIM);

        drawButton(@intFromFloat(dx + dw / 2 - 35), @intFromFloat(dy + dh - 42), 70, 30, "Close", BTN_NORMAL);
    }

    // ── Input field drawing ──

    fn drawInputField(self: *Gui, idx: usize) void {
        const field = &self.input_fields[idx];
        if (!field.active) return;

        const rect = field.rect;
        const focused = (self.focused_field != null and self.focused_field.? == idx);
        const border = if (focused) INPUT_FOCUS else TILE_BORDER;

        rl.drawRectangleRounded(rect, 0.25, 6, INPUT_BG);
        rl.drawRectangleRoundedLines(rect, 0.25, 6, border);

        var z: [129:0]u8 = std.mem.zeroes([129:0]u8);
        const n = @min(field.len, 128);
        @memcpy(z[0..n], field.buf[0..n]);
        const z_slice: [:0]const u8 = z[0..n :0];
        drawTxt(z_slice, @as(i32, @intFromFloat(rect.x)) + 6, @as(i32, @intFromFloat(rect.y)) + 5, SMALL_SZ, TEXT_WHITE);

        if (focused) {
            // Click to position cursor
            if (rl.isMouseButtonPressed(.left)) {
                const mx = rl.getMouseX();
                const field_x = @as(i32, @intFromFloat(rect.x)) + 6;
                if (mx >= field_x) {
                    // Find closest character position
                    var best: usize = n;
                    var best_dist: i32 = std.math.maxInt(i32);
                    for (0..n + 1) |ci| {
                        var sub: [129:0]u8 = std.mem.zeroes([129:0]u8);
                        @memcpy(sub[0..ci], field.buf[0..ci]);
                        const sub_slice: [:0]const u8 = sub[0..ci :0];
                        const cw = measureTxt(sub_slice, SMALL_SZ);
                        const dist = @as(i32, @intCast(@as(u32, @abs(mx - (field_x + cw)))));
                        if (dist < best_dist) {
                            best_dist = dist;
                            best = ci;
                        }
                    }
                    self.input_fields[idx].cursor = best;
                }
            }

            const t = @as(f32, @floatFromInt(@mod(std.time.milliTimestamp(), 1000)));
            if (t < 500) {
                // Measure text up to cursor position
                const cp = @min(field.cursor, n);
                var cur_z: [129:0]u8 = std.mem.zeroes([129:0]u8);
                @memcpy(cur_z[0..cp], field.buf[0..cp]);
                const cur_slice: [:0]const u8 = cur_z[0..cp :0];
                const tw = measureTxt(cur_slice, SMALL_SZ);
                rl.drawRectangle(
                    @as(i32, @intFromFloat(rect.x)) + 6 + tw,
                    @as(i32, @intFromFloat(rect.y)) + 4,
                    2,
                    18,
                    TEXT_WHITE,
                );
            }
        }
    }
};

// ── Input field ──

const InputField = struct {
    buf: [128]u8 = undefined,
    len: usize = 0,
    cursor: usize = 0,
    active: bool = false,
    rect: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },

    fn initWith(text: []const u8) InputField {
        var f = InputField{};
        const n = @min(text.len, f.buf.len);
        @memcpy(f.buf[0..n], text[0..n]);
        f.len = n;
        f.cursor = n;
        return f;
    }

    fn slice(self: *const InputField) []const u8 {
        return self.buf[0..self.len];
    }
};

// ── Drawing helpers ──

fn tileRect(index: usize) rl.Rectangle {
    const col: usize = index % GRID_COLS;
    const row: usize = index / GRID_COLS;
    const sw: f32 = @floatFromInt(rl.getScreenWidth());
    const grid_start_x: f32 = (sw - @as(f32, @floatFromInt(GRID_COLS * (TILE_W + TILE_PAD)))) / 2.0;
    const grid_start_y: f32 = TOOLBAR_H + 10;
    return .{
        .x = grid_start_x + @as(f32, @floatFromInt(col)) * @as(f32, TILE_W + TILE_PAD),
        .y = grid_start_y + @as(f32, @floatFromInt(row)) * @as(f32, TILE_H + TILE_PAD),
        .width = TILE_W,
        .height = TILE_H,
    };
}

/// Map a 0.0–1.0 fraction to a point on the rounded rectangle perimeter (top→right→bottom→left).
fn perimPoint(r: rl.Rectangle, t: f32, side_fracs: *const [4]f32) rl.Vector2 {
    _ = side_fracs;
    // Radius for rounded corners (matches drawRectangleRounded roundness=0.15)
    const corner_r = @min(r.width, r.height) * 0.15 * 0.5;

    // Straight edge lengths (minus corner arcs)
    const top_len = r.width - 2 * corner_r;
    const right_len = r.height - 2 * corner_r;
    const bot_len = top_len;
    const left_len = right_len;
    // Each corner arc = quarter circle = pi/2 * corner_r
    const arc_len = std.math.pi / 2.0 * corner_r;
    const perim = top_len + right_len + bot_len + left_len + 4 * arc_len;
    var dist = t * perim;

    // Top edge (left to right, after top-left arc)
    if (dist < top_len) {
        return .{ .x = r.x + corner_r + dist, .y = r.y };
    }
    dist -= top_len;
    // Top-right corner arc
    if (dist < arc_len) {
        const a = dist / corner_r; // 0 to pi/2
        const cx = r.x + r.width - corner_r;
        const cy = r.y + corner_r;
        return .{ .x = cx + corner_r * @as(f32, @floatCast(std.math.sin(a))), .y = cy - corner_r * @as(f32, @floatCast(std.math.cos(a))) };
    }
    dist -= arc_len;
    // Right edge (top to bottom)
    if (dist < right_len) {
        return .{ .x = r.x + r.width, .y = r.y + corner_r + dist };
    }
    dist -= right_len;
    // Bottom-right corner arc
    if (dist < arc_len) {
        const a = dist / corner_r;
        const cx = r.x + r.width - corner_r;
        const cy = r.y + r.height - corner_r;
        return .{ .x = cx + corner_r * @as(f32, @floatCast(std.math.cos(a))), .y = cy + corner_r * @as(f32, @floatCast(std.math.sin(a))) };
    }
    dist -= arc_len;
    // Bottom edge (right to left)
    if (dist < bot_len) {
        return .{ .x = r.x + r.width - corner_r - dist, .y = r.y + r.height };
    }
    dist -= bot_len;
    // Bottom-left corner arc
    if (dist < arc_len) {
        const a = dist / corner_r;
        const cx = r.x + corner_r;
        const cy = r.y + r.height - corner_r;
        return .{ .x = cx - corner_r * @as(f32, @floatCast(std.math.sin(a))), .y = cy + corner_r * @as(f32, @floatCast(std.math.cos(a))) };
    }
    dist -= arc_len;
    // Left edge (bottom to top)
    if (dist < left_len) {
        return .{ .x = r.x, .y = r.y + r.height - corner_r - dist };
    }
    dist -= left_len;
    // Top-left corner arc
    if (dist < arc_len) {
        const a = dist / corner_r;
        const cx = r.x + corner_r;
        const cy = r.y + corner_r;
        return .{ .x = cx - corner_r * @as(f32, @floatCast(std.math.cos(a))), .y = cy - corner_r * @as(f32, @floatCast(std.math.sin(a))) };
    }
    // Wrap to start
    return .{ .x = r.x + corner_r, .y = r.y };
}

fn drawDialogBox(x: f32, y: f32, w: f32, h: f32) void {
    // Shadow behind dialog
    rl.drawRectangleRounded(.{ .x = x + 4, .y = y + 4, .width = w, .height = h }, 0.06, 8, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 80 });
    rl.drawRectangleRounded(.{ .x = x, .y = y, .width = w, .height = h }, 0.06, 8, DIALOG_BG);
    rl.drawRectangleRoundedLines(.{ .x = x, .y = y, .width = w, .height = h }, 0.06, 8, TILE_BORDER);
}

fn drawButton(x: i32, y: i32, w: i32, h: i32, label: [:0]const u8, bg: rl.Color) void {
    const mx = rl.getMouseX();
    const my = rl.getMouseY();
    const hovered = (mx >= x and mx < x + w and my >= y and my < y + h);
    const color = if (hovered) BTN_HOVER else bg;
    const rect = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(w),
        .height = @floatFromInt(h),
    };
    rl.drawRectangleRounded(rect, 0.35, 8, color);
    // Border on non-accent buttons
    if (bg.r == BTN_NORMAL.r and bg.g == BTN_NORMAL.g and bg.b == BTN_NORMAL.b and !hovered) {
        rl.drawRectangleRoundedLines(rect, 0.35, 8, TILE_BORDER);
    }
    const tw = measureTxt(label, SMALL_SZ);
    drawTxt(label, x + @divFloor(w - tw, 2), y + @divFloor(h - SMALL_FONT, 2), SMALL_SZ, TEXT_WHITE);
}

fn isButtonClicked(x: i32, y: i32, w: i32, h: i32) bool {
    if (!rl.isMouseButtonPressed(.left)) return false;
    const mx = rl.getMouseX();
    const my = rl.getMouseY();
    return (mx >= x and mx < x + w and my >= y and my < y + h);
}
