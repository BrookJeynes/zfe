const std = @import("std");

/// Callers owns memory returned.
pub fn getGitBranch(alloc: std.mem.Allocator, dir: std.fs.Dir) !?[]const u8 {
    var file = dir.openFile(".git/HEAD", .{}) catch return null;
    defer file.close();

    var buf: [1024]u8 = undefined;
    const bytes = file.readAll(&buf) catch return null;

    var it = std.mem.splitBackwardsSequence(u8, buf[0..bytes], "/");
    const branch = it.next() orelse return null;
    if (std.mem.eql(u8, branch, "")) return null;

    return try alloc.dupe(u8, branch);
}
