const std = @import("std");
const builtin = @import("builtin");

const App = @import("app.zig");

const log = &@import("./log.zig").log;
const config = &@import("./config.zig").config;
const vaxis = @import("vaxis");

var app: App = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    config.parse(alloc) catch |err| switch (err) {
        error.ConfigNotFound => {},
        error.MissingConfigHomeEnvironmentVariable => {
            log.err("Could not read config due to $HOME or $XDG_CONFIG_HOME not being set.", .{});
            return;
        },
        error.SyntaxError => {
            log.err("Could not read config due to a syntax error.", .{});
            return;
        },
        else => {
            log.err("Could not read config due to an unknown error.", .{});
            return;
        },
    };

    app = try App.init(alloc);
    defer app.deinit();

    try app.run();
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    app.vx.deinit(app.alloc);
    std.builtin.default_panic(msg, trace, ret_addr);
}
