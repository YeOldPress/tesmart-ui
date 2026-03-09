const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const verbose = b.option(bool, "verbose", "Enable console logging") orelse false;

    // ---------- raylib-zig dependency ----------
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // ---------- executable ----------
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const options = b.addOptions();
    options.addOption(bool, "verbose", verbose);
    exe_mod.addOptions("build_options", options);

    exe_mod.addImport("raylib", raylib);
    exe_mod.linkLibrary(raylib_artifact);

    // ---------- system tray (per-platform) ----------
    switch (target.result.os.tag) {
        .macos => {
            exe_mod.addCSourceFile(.{
                .file = b.path("src/tray_macos.m"),
                .flags = &.{"-fobjc-arc"},
            });
            exe_mod.linkFramework("Cocoa", .{});
        },
        .linux => {
            exe_mod.addCSourceFile(.{
                .file = b.path("src/tray_linux.c"),
                .flags = &.{},
            });
            // pkg-config names — requires: gtk3-devel libayatana-appindicator-gtk3-devel
            exe_mod.linkSystemLibrary("ayatana-appindicator3-0.1", .{});
            exe_mod.linkSystemLibrary("gtk+-3.0", .{});
        },
        .windows => {
            exe_mod.addCSourceFile(.{
                .file = b.path("src/tray_windows.c"),
                .flags = &.{},
            });
            exe_mod.linkSystemLibrary("shell32", .{});
            exe_mod.linkSystemLibrary("user32", .{});
        },
        else => {},
    }

    const exe = b.addExecutable(.{
        .name = "tesmart-ui",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // ---------- run step ----------
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run TeSmart UI");
    run_step.dependOn(&run_cmd.step);

    // ---------- tests ----------
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/protocol.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
