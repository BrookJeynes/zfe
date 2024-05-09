const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.13.0-dev.44+9d64332a5";
const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

const Build = blk: {
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
    break :blk std.Build;
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = b.addOptions();

    options.addOption([]const u8, "min_zig_string", min_zig_string);
    options.addOption(std.SemanticVersion, "zfe_version", version);
    const exe_options_module = options.createModule();

    const libvaxis_dep = b.dependency("vaxis", .{ .target = target });
    const libvaxis_mod = libvaxis_dep.module("vaxis");

    const exe = b.addExecutable(.{
        .name = "zfe",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vaxis", libvaxis_mod);
    exe.root_module.addImport("options", exe_options_module);
    b.installArtifact(exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
