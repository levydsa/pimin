const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "pinim",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    {
        const run = b.addRunArtifact(exe);

        run.step.dependOn(b.getInstallStep());
        if (b.args) |args| run.addArgs(args);

        const step = b.step("run", "Run the app");
        step.dependOn(&run.step);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    {
        const run = b.addRunArtifact(unit_tests);
        const step = b.step("test", "Run unit tests");
        step.dependOn(&run.step);
    }

    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("OpenGL");
    exe.linkLibC();

    exe.addModule("qoiz", b.dependency("qoiz", .{
        .target = target,
        .optimize = optimize,
    }).module("qoiz"));
}
