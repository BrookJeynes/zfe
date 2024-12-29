const std = @import("std");
const builtin = @import("builtin");
const App = @import("app.zig");
const vaxis = @import("vaxis");
const ConfigParseRes = @import("./config.zig").ParseRes;
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

    var app = try App.init(alloc);
    defer app.deinit();

    const config_parse_res = config.parse(alloc) catch |err| lbl: {
        switch (err) {
            error.SyntaxError => {
                try app.notification.writeErr(.ConfigSyntaxError);
            },
            else => {
                try app.notification.writeErr(.ConfigUnknownError);
            },
        }

        break :lbl ConfigParseRes{ .deprecated = false };
    };
    if (config_parse_res.deprecated) try app.notification.writeWarn(.DeprecatedConfigPath);

    try app.run();
}
