const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.12.0";
const version = std.SemanticVersion{ .major = 0, .minor = 3, .patch = 0 };

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
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

    // Building targets for release.
    // for (targets) |t| {
    //     const build_target = b.resolveTargetQuery(t);
    //
    //     const build_libvaxis = b.dependency("vaxis", .{ .target = target }).module("vaxis");
    //     const build_fuzzig = b.dependency("fuzzig", .{ .target = target }).module("fuzzig");
    //     const build_zuid = b.dependency("zuid", .{ .target = target }).module("zuid");
    //
    //     const build_exe = b.addExecutable(.{
    //         .name = "zfe",
    //         .root_source_file = b.path("src/main.zig"),
    //         .target = build_target,
    //         .optimize = optimize,
    //     });
    //     build_exe.root_module.addImport("fuzzig", build_fuzzig);
    //     build_exe.root_module.addImport("vaxis", build_libvaxis);
    //     build_exe.root_module.addImport("zuid", build_zuid);
    //     build_exe.root_module.addImport("options", exe_options_module);
    //     b.installArtifact(exe);
    //
    //     const target_output = b.addInstallArtifact(exe, .{
    //         .dest_dir = .{
    //             .override = .{
    //                 .custom = try t.zigTriple(b.allocator),
    //             },
    //         },
    //     });
    //
    //     b.getInstallStep().dependOn(&target_output.step);
    // }
}
