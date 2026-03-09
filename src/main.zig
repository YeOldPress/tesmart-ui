//! TeSmart 16-Port HDMI/KVM Switch – raylib UI
//!
//! Layout (800 × 560 px):
//!   ┌─ Header ───────────────────────────────────────────┐  40 px
//!   ├─ Connection panel ─────────────────────────────────┤  90 px
//!   ├─ Port grid (4 × 4 buttons) ───────────────────────┤ 390 px
//!   └─ Status bar ───────────────────────────────────────┘  40 px

const std = @import("std");
const rl = @import("raylib");
const tesmart_mod = @import("tesmart.zig");
const TeSmart = tesmart_mod.TeSmart;
const MAX_PORTS = tesmart_mod.MAX_PORTS;

// ── Window constants ───────────────────────────────────────────────────────────

const WIN_W: i32 = 800;
const WIN_H: i32 = 560;
const TITLE = "TeSmart 16-Port KVM Controller";
const TARGET_FPS: i32 = 60;

// ── Layout constants ───────────────────────────────────────────────────────────

const HEADER_H: i32 = 40;
const CONN_PANEL_Y: i32 = HEADER_H;
const CONN_PANEL_H: i32 = 90;
const GRID_Y: i32 = CONN_PANEL_Y + CONN_PANEL_H;
const GRID_H: i32 = WIN_H - GRID_Y - 40; // 40 px status bar
const STATUS_Y: i32 = WIN_H - 40;

// Port button grid
const COLS: i32 = 4;
const ROWS: i32 = 4;
const BTN_W: i32 = 130;
const BTN_H: i32 = 70;
const BTN_GAP_X: i32 = 16;
const BTN_GAP_Y: i32 = 14;
// Horizontal centering
const GRID_TOTAL_W: i32 = COLS * BTN_W + (COLS - 1) * BTN_GAP_X;
const GRID_X0: i32 = @divTrunc(WIN_W - GRID_TOTAL_W, 2);
// Vertical centering within grid area
const GRID_TOTAL_H: i32 = ROWS * BTN_H + (ROWS - 1) * BTN_GAP_Y;
const GRID_Y0: i32 = GRID_Y + @divTrunc(GRID_H - GRID_TOTAL_H, 2);

// Text box geometry (connection panel)
const TB_H: i32 = 26;
const TB_Y: i32 = CONN_PANEL_Y + 14;
const TB_HOST_X: i32 = 100;
const TB_HOST_W: i32 = 220;
const TB_PORT_X: i32 = 360;
const TB_PORT_W: i32 = 80;
const TB_DEV_X: i32 = 100;
const TB_DEV_W: i32 = 220;
const TB_DEV_Y: i32 = CONN_PANEL_Y + 52;

// Button geometry (connection panel)
const PBTN_W: i32 = 100;
const PBTN_H: i32 = 24;
const PBTN_TCP_X: i32 = 480;
const PBTN_TCP_Y: i32 = TB_Y;
const PBTN_SER_X: i32 = PBTN_TCP_X;
const PBTN_SER_Y: i32 = TB_DEV_Y;
const PBTN_DISC_X: i32 = PBTN_TCP_X + PBTN_W + 8;
const PBTN_DISC_Y: i32 = TB_Y;
const PBTN_QUERY_X: i32 = PBTN_DISC_X;
const PBTN_QUERY_Y: i32 = TB_DEV_Y;

// ── Miscellaneous constants ────────────────────────────────────────────────────

/// Cursor blink frequency in Hz (half-period toggles per second).
const CURSOR_BLINK_RATE: f64 = 2.0;

// ── Color palette ──────────────────────────────────────────────────────────────
const C_BG = rl.Color{ .r = 28, .g = 28, .b = 28, .a = 255 };
const C_PANEL = rl.Color{ .r = 38, .g = 38, .b = 42, .a = 255 };
const C_BTN = rl.Color{ .r = 55, .g = 55, .b = 60, .a = 255 };
const C_BTN_HOV = rl.Color{ .r = 75, .g = 75, .b = 82, .a = 255 };
const C_BTN_ACT = rl.Color{ .r = 30, .g = 160, .b = 60, .a = 255 };
const C_BTN_ACT_HOV = rl.Color{ .r = 40, .g = 180, .b = 75, .a = 255 };
const C_BORDER = rl.Color{ .r = 70, .g = 70, .b = 78, .a = 255 };
const C_BORDER_FOCUS = rl.Color{ .r = 0, .g = 120, .b = 215, .a = 255 };
const C_ACCENT = rl.Color{ .r = 0, .g = 120, .b = 215, .a = 255 };
const C_CONNECTED = rl.Color{ .r = 30, .g = 180, .b = 60, .a = 255 };
const C_DISCONNECTED = rl.Color{ .r = 190, .g = 40, .b = 40, .a = 255 };
const C_TEXT = rl.Color{ .r = 220, .g = 220, .b = 225, .a = 255 };
const C_TEXT_DIM = rl.Color{ .r = 130, .g = 130, .b = 140, .a = 255 };
const C_TB_BG = rl.Color{ .r = 48, .g = 48, .b = 54, .a = 255 };
const C_TB_BG_F = rl.Color{ .r = 55, .g = 55, .b = 65, .a = 255 };
const C_ERR = rl.Color{ .r = 210, .g = 50, .b = 50, .a = 255 };

// ── Text-box helper ────────────────────────────────────────────────────────────

const MAX_TB = 128;

const TextBox = struct {
    buf: [MAX_TB + 1]u8 = std.mem.zeroes([MAX_TB + 1]u8),
    len: usize = 0,
    focused: bool = false,

    fn set(self: *TextBox, s: []const u8) void {
        const n = @min(s.len, MAX_TB);
        @memcpy(self.buf[0..n], s[0..n]);
        self.len = n;
        self.buf[self.len] = 0;
    }

    fn slice(self: *const TextBox) []const u8 {
        return self.buf[0..self.len];
    }

    fn cstr(self: *const TextBox) [*:0]const u8 {
        return @ptrCast(&self.buf);
    }

    /// Handle keyboard input when focused. Returns true if Enter was pressed.
    fn handleKeys(self: *TextBox) bool {
        // Append printable characters
        var ch = rl.getCharPressed();
        while (ch > 0) : (ch = rl.getCharPressed()) {
            if (ch >= 32 and ch <= 126 and self.len < MAX_TB) {
                self.buf[self.len] = @intCast(ch);
                self.len += 1;
                self.buf[self.len] = 0;
            }
        }
        // Backspace
        if (rl.isKeyPressed(.backspace) and self.len > 0) {
            self.len -= 1;
            self.buf[self.len] = 0;
        }
        // Clear on Ctrl+A then Delete / Ctrl+U
        if (rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control)) {
            if (rl.isKeyPressed(.u) or rl.isKeyPressed(.a)) {
                self.len = 0;
                self.buf[0] = 0;
            }
        }
        return rl.isKeyPressed(.enter);
    }

    fn draw(self: *const TextBox, x: i32, y: i32, w: i32, h: i32) void {
        const bg = if (self.focused) C_TB_BG_F else C_TB_BG;
        const border = if (self.focused) C_BORDER_FOCUS else C_BORDER;
        rl.drawRectangle(x, y, w, h, bg);
        rl.drawRectangleLines(x, y, w, h, border);
        // Text content
        const text_y = y + @divTrunc(h - 16, 2);
        rl.drawText(self.cstr(), x + 5, text_y, 16, C_TEXT);
        // Blinking cursor when focused
        if (self.focused and @mod(@as(i64, @intFromFloat(rl.getTime() * CURSOR_BLINK_RATE)), 2) == 0) {
            const tw = rl.measureText(self.cstr(), 16);
            rl.drawLine(x + 5 + tw, y + 4, x + 5 + tw, y + h - 4, C_TEXT);
        }
    }
};

// ── Panel button helper ────────────────────────────────────────────────────────

fn drawPanelButton(label: [*:0]const u8, x: i32, y: i32, w: i32, h: i32, enabled: bool) bool {
    const mouse = rl.getMousePosition();
    const rect = rl.Rectangle{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(w),
        .height = @floatFromInt(h),
    };
    const hovered = enabled and rl.checkCollisionPointRec(mouse, rect);
    const bg = if (!enabled)
        rl.Color{ .r = 45, .g = 45, .b = 48, .a = 255 }
    else if (hovered)
        C_ACCENT
    else
        rl.Color{ .r = 60, .g = 60, .b = 66, .a = 255 };
    const tc = if (enabled) C_TEXT else C_TEXT_DIM;

    rl.drawRectangleRec(rect, bg);
    rl.drawRectangleLinesEx(rect, 1.0, C_BORDER);
    const tw = rl.measureText(label, 14);
    rl.drawText(label, x + @divTrunc(w - tw, 2), y + @divTrunc(h - 14, 2), 14, tc);

    return hovered and rl.isMouseButtonPressed(.left);
}

// ── Application state ──────────────────────────────────────────────────────────

const MAX_STATUS = 192;

const AppState = struct {
    ts: TeSmart,

    // Connection panel inputs
    tb_host: TextBox = .{},
    tb_port: TextBox = .{},
    tb_dev: TextBox = .{},

    // Status message
    status: [MAX_STATUS + 1]u8 = std.mem.zeroes([MAX_STATUS + 1]u8),
    status_len: usize = 0,
    status_err: bool = false,

    fn init(allocator: std.mem.Allocator) AppState {
        var s = AppState{ .ts = TeSmart.init(allocator) };
        s.tb_host.set("192.168.1.10");
        s.tb_port.set("5000");
        s.tb_dev.set("/dev/ttyUSB0");
        s.setStatus("Ready – not connected.", false);
        return s;
    }

    fn deinit(self: *AppState) void {
        self.ts.deinit();
    }

    fn setStatus(self: *AppState, msg: []const u8, is_err: bool) void {
        const n = @min(msg.len, MAX_STATUS);
        @memcpy(self.status[0..n], msg[0..n]);
        self.status_len = n;
        self.status[self.status_len] = 0;
        self.status_err = is_err;
    }

    fn statusCStr(self: *const AppState) [*:0]const u8 {
        return @ptrCast(&self.status);
    }
};

// ── Entry point ────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = AppState.init(allocator);
    defer app.deinit();

    rl.initWindow(WIN_W, WIN_H, TITLE);
    defer rl.closeWindow();
    rl.setTargetFPS(TARGET_FPS);
    // KEY_NULL (0) as exit key – prevents ESC from closing the window
    // so the user can type freely in text boxes.
    rl.setExitKey(@enumFromInt(0));

    while (!rl.windowShouldClose()) {
        handleInput(&app);

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(C_BG);
        drawHeader(&app);
        drawConnectionPanel(&app);
        drawPortGrid(&app);
        drawStatusBar(&app);
    }
}

// ── Input processing ───────────────────────────────────────────────────────────

fn handleInput(app: *AppState) void {
    const mouse = rl.getMousePosition();
    const clicked = rl.isMouseButtonPressed(.left);

    // ── Text-box focus toggle ──────────────────────────────────────────────────
    const host_rect = tbRect(TB_HOST_X, TB_Y, TB_HOST_W, TB_H);
    const port_rect = tbRect(TB_PORT_X, TB_Y, TB_PORT_W, TB_H);
    const dev_rect = tbRect(TB_DEV_X, TB_DEV_Y, TB_DEV_W, TB_H);

    if (clicked) {
        app.tb_host.focused = rl.checkCollisionPointRec(mouse, host_rect);
        app.tb_port.focused = rl.checkCollisionPointRec(mouse, port_rect);
        app.tb_dev.focused = rl.checkCollisionPointRec(mouse, dev_rect);
    }

    // ── Text-box key handling (only for the focused box) ──────────────────────
    if (app.tb_host.focused) _ = app.tb_host.handleKeys();
    if (app.tb_port.focused) {
        if (app.tb_port.handleKeys()) tryConnectTcp(app); // Enter in port box = connect
    }
    if (app.tb_dev.focused) _ = app.tb_dev.handleKeys();

    // ── Port buttons ───────────────────────────────────────────────────────────
    if (app.ts.isConnected()) {
        for (0..MAX_PORTS) |i| {
            const port: u8 = @intCast(i + 1);
            const col: i32 = @intCast(i % 4);
            const row: i32 = @intCast(i / 4);
            const bx = GRID_X0 + col * (BTN_W + BTN_GAP_X);
            const by = GRID_Y0 + row * (BTN_H + BTN_GAP_Y);
            const brect = rl.Rectangle{
                .x = @floatFromInt(bx),
                .y = @floatFromInt(by),
                .width = @floatFromInt(BTN_W),
                .height = @floatFromInt(BTN_H),
            };
            if (clicked and rl.checkCollisionPointRec(mouse, brect)) {
                app.ts.switchToPort(port) catch |err| {
                    var buf: [64]u8 = undefined;
                    const msg: []const u8 = std.fmt.bufPrint(&buf, "Switch error: {s}", .{@errorName(err)}) catch "Switch error.";
                    app.setStatus(msg, true);
                    return;
                };
                var buf: [32]u8 = undefined;
                const msg: []const u8 = std.fmt.bufPrint(&buf, "Switched to port {d}.", .{port}) catch "Switched.";
                app.setStatus(msg, false);
            }
        }
    }
}

// ── Drawing subroutines ────────────────────────────────────────────────────────

fn drawHeader(app: *const AppState) void {
    rl.drawRectangle(0, 0, WIN_W, HEADER_H, C_PANEL);
    rl.drawLine(0, HEADER_H - 1, WIN_W, HEADER_H - 1, C_BORDER);

    // Title
    rl.drawText(TITLE, 12, @divTrunc(HEADER_H - 20, 2), 20, C_TEXT);

    // Connection status indicator (right side)
    const dot_x: i32 = WIN_W - 20;
    const dot_y: i32 = @divTrunc(HEADER_H, 2);
    const dot_color = if (app.ts.isConnected()) C_CONNECTED else C_DISCONNECTED;
    rl.drawCircle(dot_x, dot_y, 7, dot_color);
    rl.drawCircleLines(dot_x, dot_y, 7, C_BORDER);
    const conn_label: [*:0]const u8 = if (app.ts.isConnected()) "Connected" else "Disconnected";
    const lw = rl.measureText(conn_label, 14);
    rl.drawText(conn_label, dot_x - lw - 12, @divTrunc(HEADER_H - 14, 2), 14, C_TEXT_DIM);
}

fn drawConnectionPanel(app: *AppState) void {
    rl.drawRectangle(0, CONN_PANEL_Y, WIN_W, CONN_PANEL_H, C_PANEL);
    rl.drawLine(0, CONN_PANEL_Y + CONN_PANEL_H - 1, WIN_W, CONN_PANEL_Y + CONN_PANEL_H - 1, C_BORDER);

    // Row 1: TCP host / port
    rl.drawText("Host:", 10, TB_Y + @divTrunc(TB_H - 14, 2), 14, C_TEXT_DIM);
    app.tb_host.draw(TB_HOST_X, TB_Y, TB_HOST_W, TB_H);
    rl.drawText("Port:", TB_PORT_X - 42, TB_Y + @divTrunc(TB_H - 14, 2), 14, C_TEXT_DIM);
    app.tb_port.draw(TB_PORT_X, TB_Y, TB_PORT_W, TB_H);

    if (drawPanelButton("Connect TCP", PBTN_TCP_X, PBTN_TCP_Y, PBTN_W, PBTN_H, true))
        tryConnectTcp(app);
    if (drawPanelButton("Disconnect", PBTN_DISC_X, PBTN_DISC_Y, PBTN_W, PBTN_H, app.ts.isConnected()))
        tryDisconnect(app);

    // Row 2: Serial device
    rl.drawText("Serial:", 10, TB_DEV_Y + @divTrunc(TB_H - 14, 2), 14, C_TEXT_DIM);
    app.tb_dev.draw(TB_DEV_X, TB_DEV_Y, TB_DEV_W, TB_H);

    if (drawPanelButton("Connect RS232", PBTN_SER_X, PBTN_SER_Y, PBTN_W, PBTN_H, true))
        tryConnectSerial(app);
    if (drawPanelButton("Query Port", PBTN_QUERY_X, PBTN_QUERY_Y, PBTN_W, PBTN_H, app.ts.isConnected()))
        tryQueryPort(app);
}

fn drawPortGrid(app: *const AppState) void {
    const mouse = rl.getMousePosition();
    // Zero-initialised so the null terminator is always in place.
    var port_buf: [8]u8 = std.mem.zeroes([8]u8);

    for (0..MAX_PORTS) |i| {
        const port: u8 = @intCast(i + 1);
        const col: i32 = @intCast(i % 4);
        const row: i32 = @intCast(i / 4);
        const bx = GRID_X0 + col * (BTN_W + BTN_GAP_X);
        const by = GRID_Y0 + row * (BTN_H + BTN_GAP_Y);

        const rect = rl.Rectangle{
            .x = @floatFromInt(bx),
            .y = @floatFromInt(by),
            .width = @floatFromInt(BTN_W),
            .height = @floatFromInt(BTN_H),
        };
        const hovered = app.ts.isConnected() and rl.checkCollisionPointRec(mouse, rect);
        const active = app.ts.current_port == port;

        const bg = if (active and hovered)
            C_BTN_ACT_HOV
        else if (active)
            C_BTN_ACT
        else if (hovered)
            C_BTN_HOV
        else
            C_BTN;

        rl.drawRectangleRec(rect, bg);
        // Highlight border for active port
        const border_c = if (active) C_BTN_ACT else C_BORDER;
        rl.drawRectangleLinesEx(rect, if (active) @as(f32, 2.5) else @as(f32, 1.0), border_c);

        // Port number label (centred) – format into a zero-terminated buffer.
        // The buffer is pre-zeroed before the loop so no explicit clear is needed
        // here: the loop visits ports 1–16 in ascending order and single-digit
        // ports (1–9) are always processed before two-digit ports (10–16).
        _ = std.fmt.bufPrint(port_buf[0..7], "{d}", .{port}) catch {};
        const label: [*:0]const u8 = @ptrCast(&port_buf);
        const font_size: i32 = 28;
        const lw = rl.measureText(label, font_size);
        const lx = bx + @divTrunc(BTN_W - lw, 2);
        const ly = by + @divTrunc(BTN_H - font_size, 2);
        rl.drawText(label, lx, ly, font_size, if (active) rl.Color.white else C_TEXT);

        // "ACTIVE" badge
        if (active) {
            rl.drawText("ACTIVE", bx + @divTrunc(BTN_W - rl.measureText("ACTIVE", 10), 2), by + BTN_H - 16, 10, rl.Color.white);
        }
    }

    // Dim overlay when not connected
    if (!app.ts.isConnected()) {
        rl.drawRectangle(0, GRID_Y, WIN_W, GRID_H, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 100 });
        const msg = "Connect to a switch to enable port selection";
        const mw = rl.measureText(msg, 16);
        rl.drawText(msg, @divTrunc(WIN_W - mw, 2), GRID_Y + @divTrunc(GRID_H, 2) - 8, 16, C_TEXT_DIM);
    }
}

fn drawStatusBar(app: *const AppState) void {
    rl.drawRectangle(0, STATUS_Y, WIN_W, 40, C_PANEL);
    rl.drawLine(0, STATUS_Y, WIN_W, STATUS_Y, C_BORDER);

    const tc = if (app.status_err) C_ERR else C_TEXT_DIM;
    rl.drawText(app.statusCStr(), 12, STATUS_Y + @divTrunc(40 - 14, 2), 14, tc);

    // Active port badge on the right
    if (app.ts.current_port > 0) {
        var buf: [32]u8 = std.mem.zeroes([32]u8);
        _ = std.fmt.bufPrint(buf[0..31], "Active: Port {d}", .{app.ts.current_port}) catch {};
        const s: [*:0]const u8 = @ptrCast(&buf);
        const sw = rl.measureText(s, 14);
        rl.drawText(s, WIN_W - sw - 12, STATUS_Y + @divTrunc(40 - 14, 2), 14, C_CONNECTED);
    }
}

// ── Action handlers ────────────────────────────────────────────────────────────

fn tryConnectTcp(app: *AppState) void {
    const host = app.tb_host.slice();
    const port = std.fmt.parseInt(u16, app.tb_port.slice(), 10) catch {
        app.setStatus("Invalid port number.", true);
        return;
    };
    app.ts.connectTcp(host, port) catch |err| {
        var buf: [128]u8 = undefined;
        const msg: []const u8 = std.fmt.bufPrint(&buf, "TCP connect failed: {s}", .{@errorName(err)}) catch "TCP connect failed.";
        app.setStatus(msg, true);
        return;
    };
    var buf: [128]u8 = undefined;
    const msg: []const u8 = std.fmt.bufPrint(&buf, "Connected to {s}:{d} via TCP.", .{ host, port }) catch "Connected via TCP.";
    app.setStatus(msg, false);
}

fn tryConnectSerial(app: *AppState) void {
    const dev = app.tb_dev.slice();
    app.ts.connectSerial(dev) catch |err| {
        var buf: [128]u8 = undefined;
        const msg: []const u8 = std.fmt.bufPrint(&buf, "Serial connect failed: {s}", .{@errorName(err)}) catch "Serial connect failed.";
        app.setStatus(msg, true);
        return;
    };
    var buf: [128]u8 = undefined;
    const msg: []const u8 = std.fmt.bufPrint(&buf, "Connected to {s} via RS-232.", .{dev}) catch "Connected via RS-232.";
    app.setStatus(msg, false);
}

fn tryDisconnect(app: *AppState) void {
    app.ts.disconnect();
    app.setStatus("Disconnected.", false);
}

fn tryQueryPort(app: *AppState) void {
    const port = app.ts.queryCurrentPort() catch |err| {
        var buf: [64]u8 = undefined;
        const msg: []const u8 = std.fmt.bufPrint(&buf, "Query failed: {s}", .{@errorName(err)}) catch "Query failed.";
        app.setStatus(msg, true);
        return;
    };
    var buf: [48]u8 = undefined;
    const msg: []const u8 = std.fmt.bufPrint(&buf, "Active port is {d}.", .{port}) catch "Query succeeded.";
    app.setStatus(msg, false);
}

// ── Geometry helper ────────────────────────────────────────────────────────────

fn tbRect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .width = @floatFromInt(w),
        .height = @floatFromInt(h),
    };
}
