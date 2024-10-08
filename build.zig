const std = @import("std");
const builtin = @import("builtin");

/// Must match the `minimum_zig_version` in `build.zig.zon`.
const minimum_zig_version = "0.13.0";
/// Must match the `version` in `build.zig.zon`.
const version = std.SemanticVersion{ .major = 0, .minor = 5, .patch = 0 };

pub fn build(b: *std.Build) !void {
    const build_options = b.addOptions();
    build_options.step.name = "build options";
    const build_options_module = build_options.createModule();
    build_options.addOption([]const u8, "minimum_zig_string", minimum_zig_version);
    build_options.addOption(std.SemanticVersion, "zfe_version", version);

    // Building targets for release.
    const build_all = b.option(bool, "build-all-targets", "Build all targets in ReleaseSafe mode.") orelse false;
    if (build_all) {
        try build_targets(b, build_options_module);
        return;
    }

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libvaxis = b.dependency("vaxis", .{ .target = target }).module("vaxis");
    const fuzzig = b.dependency("fuzzig", .{ .target = target }).module("fuzzig");
    const zuid = b.dependency("zuid", .{ .target = target }).module("zuid");

    const exe = b.addExecutable(.{
        .name = "zfe",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vaxis", libvaxis);
    exe.root_module.addImport("fuzzig", fuzzig);
    exe.root_module.addImport("zuid", zuid);
    exe.root_module.addImport("options", build_options_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn build_targets(b: *std.Build, build_options_module: *std.Build.Module) !void {
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
    };

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const libvaxis = b.dependency("vaxis", .{ .target = target }).module("vaxis");
        const fuzzig = b.dependency("fuzzig", .{ .target = target }).module("fuzzig");
        const zuid = b.dependency("zuid", .{ .target = target }).module("zuid");

        const exe = b.addExecutable(.{
            .name = "zfe",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = .ReleaseSafe,
        });
        exe.root_module.addImport("fuzzig", fuzzig);
        exe.root_module.addImport("vaxis", libvaxis);
        exe.root_module.addImport("zuid", zuid);
        exe.root_module.addImport("options", build_options_module);
        b.installArtifact(exe);

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);
    }
}
