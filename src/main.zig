// main.zig — TeSmart UI entry point (Zig + raylib)
const std = @import("std");
const build_options = @import("build_options");
const config = @import("config.zig");
const Client = @import("client.zig").Client;
const Gui = @import("gui.zig").Gui;

pub fn main() !void {
    var cfg = config.load() catch |err| {
        std.debug.print("Config error: {}\n", .{err});
        std.process.exit(1);
    };

    var cli = Client.init(
        cfg.ip[0..cfg.ip_len],
        cfg.port,
        cfg.get_timeout_ms,
        cfg.set_timeout_ms,
    );

    var gui = Gui.init(&cfg, &cli);
    if (build_options.verbose) std.debug.print("[main] starting GUI\n", .{});
    gui.run();
    cli.close();
}
