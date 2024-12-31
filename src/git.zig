const std = @import("std");

/// Callers owns memory returned.
pub fn GetGitBranch(
    alloc: std.mem.Allocator,
    dir: std.fs.Dir,
) !?[]const u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.realpath(".", &path_buf);

    const res = try std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{ "git", "-C", path, "rev-parse", "--abbrev-ref", "HEAD" },
    });
    defer alloc.free(res.stderr);

    if (res.term.Exited != 0) {
        alloc.free(res.stdout);
        return null;
    }

    return res.stdout;
}
