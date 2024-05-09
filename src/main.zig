const std = @import("std");
const builtin = @import("builtin");
const vaxis = @import("vaxis");
const log = &@import("./log.zig").log;

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

    log.init();

    var file_buf: [1024]u8 = undefined;

    var current_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    var current_dir: []u8 = "";

    var current_item_path: []u8 = "";
    var path: [std.fs.max_path_bytes]u8 = undefined;

    var entries = std.ArrayList(std.fs.Dir.Entry).init(alloc);
    defer entries.deinit();

    var inner_entries = std.ArrayList([]const u8).init(alloc);
    defer inner_entries.deinit();

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    current_dir = try dir.realpath(".", &current_dir_buf);

    // First populate.
    var it = dir.iterate();
    while (try it.next()) |entry| {
        var e = try entries.addOne();
        e.kind = entry.kind;
        e.name = try alloc.dupe(u8, entry.name);
    }

    vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc);

    var loop: vaxis.Loop(Event) = .{ .vaxis = &vx };
    try loop.run();
    defer loop.stop();

    try vx.enterAltScreen();
    defer vx.exitAltScreen() catch {};

    var index: u8 = 0;

    while (true) {
        const event = loop.nextEvent();

        switch (event) {
            .key_press => |key| {
                if (key.codepoint == 'c' and key.mods.ctrl) {
                    break;
                }

                switch (key.codepoint) {
                    // -, h, Left arrow
                    45, 104, 57350 => {
                        index = 0;

                        for (entries.items) |entry| {
                            alloc.free(entry.name);
                        }

                        // Clear list for next render.
                        entries.clearAndFree();

                        // Get new items.
                        dir = try dir.openDir("../", .{ .iterate = true });
                        current_dir = try dir.realpath(".", &current_dir_buf);

                        it = dir.iterate();
                        while (try it.next()) |entry| {
                            var e = try entries.addOne();
                            e.kind = entry.kind;
                            e.name = try alloc.dupe(u8, entry.name);
                        }
                    },
                    // Enter, l, Right arrow
                    13, 108, 57351 => {
                        // Get new items.
                        dir = try dir.openDir(entries.items[index].name, .{ .iterate = true });
                        current_dir = try dir.realpath(".", &current_dir_buf);

                        for (entries.items) |entry| {
                            alloc.free(entry.name);
                        }

                        // Clear list for next render.
                        entries.clearAndFree();

                        it = dir.iterate();
                        while (try it.next()) |entry| {
                            var e = try entries.addOne();
                            e.kind = entry.kind;
                            e.name = try alloc.dupe(u8, entry.name);
                        }

                        index = 0;
                    },
                    // j, Arrow down
                    106, 57353 => {
                        if (index < entries.items.len - 1) {
                            index += 1;
                        }
                    },
                    // k, Arrow up
                    107, 57352 => {
                        if (index > 0) {
                            index -= 1;
                        }
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
            top_div + 1,
            .{ .limit = win.width / 2 },
            .{ .limit = win.height - (top_bar.height + 1) },
        );

        if (entries.items.len > 0) {
            const entry = entries.items[index];

            current_item_path = try std.fmt.bufPrint(&path, "{s}/{s}", .{ current_dir, entry.name });

            switch (entry.kind) {
                .directory => {
                    // Clear list for next render.
                    for (inner_entries.items) |inner_entry| {
                        alloc.free(inner_entry);
                    }

                    inner_entries.clearAndFree();

                    // Get new items.
                    var inner_dir = try dir.openDir(current_item_path, .{ .iterate = true });

                    var inner_it = inner_dir.iterate();
                    while (try inner_it.next()) |inner_entry| {
                        try inner_entries.append(try alloc.dupe(u8, inner_entry.name));
                    }

                    for (inner_entries.items, 0..) |inner_entry, i| {
                        _ = try right_bar.print(
                            &.{
                                .{
                                    .text = inner_entry,
                                },
                            },
                            .{ .row_offset = i },
                        );
                    }
                },
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

        for (entries.items, 0..) |entry, i| {
            const w = left_bar.child(.{ .y_off = i });
            _ = try w.print(&.{
                .{
                    .text = entry.name,
                    .style = .{
                        .bold = i == index,
                    },
                },
            }, .{});
        }

        try vx.render();
    }

    for (inner_entries.items) |inner_entry| {
        alloc.free(inner_entry);
    }

    for (entries.items) |entry| {
        alloc.free(entry.name);
    }
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    vx.deinit(null);
    std.builtin.default_panic(msg, trace, ret_addr);
}
