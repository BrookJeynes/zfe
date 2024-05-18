const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;
const List = @import("./list.zig").List;

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

var vx: vaxis.Vaxis = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var entries = List(std.fs.Dir.Entry).init(alloc);
    defer entries.deinit();

    var inner_entries = List([]const u8).init(alloc);
    defer inner_entries.deinit();

    log.init();

    // TODO: Figure out size.
    var file_buf: [4096]u8 = undefined;

    var current_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    var current_dir: []u8 = "";

    var current_item_path: []u8 = "";
    var path: [std.fs.max_path_bytes]u8 = undefined;

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    current_dir = try dir.realpath(".", &current_dir_buf);

    // First populate.
    var it = dir.iterate();
    while (try it.next()) |entry| {
        try entries.append(.{
            .kind = entry.kind,
            .name = try alloc.dupe(u8, entry.name),
        });
    }

    vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc);

    var loop: vaxis.Loop(Event) = .{ .vaxis = &vx };
    try loop.run();
    defer loop.stop();

    try vx.enterAltScreen();
    defer vx.exitAltScreen() catch {};

    while (true) {
        const event = loop.nextEvent();

        switch (event) {
            .key_press => |key| {
                if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 113) {
                    break;
                }

                switch (key.codepoint) {
                    // -, h, Left arrow
                    45, 104, 57350 => {
                        for (entries.all()) |entry| {
                            entries.alloc.free(entry.name);
                        }

                        // Clear list for next render.
                        entries.clear();

                        // Get new items.
                        dir = try dir.openDir("../", .{ .iterate = true });
                        current_dir = try dir.realpath(".", &current_dir_buf);

                        it = dir.iterate();
                        while (try it.next()) |entry| {
                            try entries.append(.{
                                .kind = entry.kind,
                                .name = try alloc.dupe(u8, entry.name),
                            });
                        }
                    },
                    // Enter, l, Right arrow
                    13, 108, 57351 => {
                        const entry = entries.get(entries.selected) catch continue;

                        switch (entry.kind) {
                            .directory => {
                                // Get new items.
                                dir = try dir.openDir(entry.name, .{ .iterate = true });
                                current_dir = try dir.realpath(".", &current_dir_buf);

                                for (entries.all()) |e| {
                                    entries.alloc.free(e.name);
                                }

                                // Clear list for next render.
                                entries.clear();

                                it = dir.iterate();
                                while (try it.next()) |e| {
                                    try entries.append(.{
                                        .kind = e.kind,
                                        .name = try alloc.dupe(u8, e.name),
                                    });
                                }
                            },
                            .file => {},
                            else => {},
                        }
                    },
                    // j, Arrow down
                    106, 57353 => {
                        entries.next();
                    },
                    // k, Arrow up
                    107, 57352 => {
                        entries.previous();
                    },
                    else => {
                        // log.debug("codepoint: {d}\n", .{key.codepoint});
                    },
                }
            },
            .winsize => |ws| {
                try vx.resize(alloc, ws);
            },
        }

        const win = vx.window();
        win.clear();

        const top_div = 1;
        const top_bar = win.initChild(
            0,
            0,
            .{ .limit = win.width },
            .{ .limit = top_div },
        );

        const left_bar = win.initChild(
            0,
            top_div + 1,
            .{ .limit = win.width / 2 },
            .{ .limit = win.height - (top_bar.height + 1) },
        );

        const right_bar = win.initChild(
            win.width / 2,
            0,
            .{ .limit = win.width / 2 },
            .{ .limit = win.height - (top_bar.height + 1) },
        );

        if (entries.all().len > 0) {
            const entry = try entries.get(entries.selected);

            current_item_path = try std.fmt.bufPrint(&path, "{s}/{s}", .{ current_dir, entry.name });

            switch (entry.kind) {
                .directory => {
                    // Clear list for next render.
                    for (inner_entries.all()) |inner_entry| {
                        inner_entries.alloc.free(inner_entry);
                    }

                    inner_entries.clear();

                    // Get new items.
                    var inner_dir = try dir.openDir(current_item_path, .{ .iterate = true });

                    var inner_it = inner_dir.iterate();
                    while (try inner_it.next()) |inner_entry| {
                        try inner_entries.append(try alloc.dupe(u8, inner_entry.name));
                    }

                    try inner_entries.render(right_bar, null, null, null);
                },
                // TODO: Handle binary files.
                .file => {
                    var file = try dir.openFile(entry.name, .{ .mode = .read_only });
                    defer file.close();
                    const bytes = try file.readAll(&file_buf);

                    _ = try right_bar.print(&.{
                        .{
                            .text = file_buf[0..bytes],
                        },
                    }, .{});
                },
                else => {
                    _ = try right_bar.print(&.{vaxis.Segment{ .text = current_item_path }}, .{});
                },
            }
        }

        _ = try top_bar.print(&.{vaxis.Segment{ .text = current_dir }}, .{});

        try entries.render(
            left_bar,
            "name",
            .{
                .fg = .{ .rgb = .{ 255, 255, 0 } },
            },
            .{
                .bold = true,
                .fg = .{ .rgb = .{ 255, 255, 0 } },
            },
        );

        try vx.render();
    }

    for (inner_entries.all()) |inner_entry| {
        inner_entries.alloc.free(inner_entry);
    }

    for (entries.all()) |entry| {
        entries.alloc.free(entry.name);
    }
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    vx.deinit(null);
    std.builtin.default_panic(msg, trace, ret_addr);
}
