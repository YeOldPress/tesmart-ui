const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── raylib-zig dependency ─────────────────────────────────────────────────
    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const raylib_mod = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    // ── Executable ────────────────────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "tesmart-ui",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("raylib", raylib_mod);
    exe.linkLibrary(raylib_artifact);

    b.installArtifact(exe);

    // ── Run step ──────────────────────────────────────────────────────────────
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Build and run the TeSmart UI");
    run_step.dependOn(&run_cmd.step);
}
