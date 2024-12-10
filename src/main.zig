const std = @import("std");
const builtin = @import("builtin");
const App = @import("app.zig");
const vaxis = @import("vaxis");
const config = &@import("./config.zig").config;

pub const panic = vaxis.panic_handler;

pub const std_options: std.Options = .{
    .log_scope_levels = &.{
        .{ .scope = .vaxis, .level = .warn },
        .{ .scope = .vaxis_parser, .level = .warn },
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const alloc = gpa.allocator();

    config.parse(alloc) catch |err| switch (err) {
        error.ConfigNotFound => {},
        error.MissingConfigHomeEnvironmentVariable => {
            std.log.err("Could not read config due to $HOME or $XDG_CONFIG_HOME not being set.", .{});
            return;
        },
        error.SyntaxError => {
            std.log.err("Could not read config due to a syntax error.", .{});
            return;
        },
        else => {
            std.log.err("Could not read config due to an unknown error.", .{});
            return;
        },
    };

    var app = try App.init(alloc);
    defer app.deinit();

    try app.run();
}
