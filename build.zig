const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main = b.addExecutable(.{
        .name = "pinim",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    main.linkSystemLibrary("SDL2");
    main.linkSystemLibrary("OpenGL");
    main.linkLibC();

    main.root_module.addImport("qoiz", b.dependency("qoiz", .{
        .target = target,
        .optimize = optimize,
    }).module("qoiz"));

    b.installArtifact(main);

    {
        const run = b.addRunArtifact(main);
        b.step("run", "Run the app").dependOn(&run.step);

        if (b.args) |args| run.addArgs(args);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    {
        const run = b.addRunArtifact(unit_tests);
        b.step("test", "Run unit tests").dependOn(&run.step);
    }
}
