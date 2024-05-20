const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;
const List = @import("./list.zig").List;
const View = @import("./view.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

var vx: vaxis.Vaxis = undefined;

const Styles = struct {
    selected_list_item: vaxis.Style,
    list_item: vaxis.Style,
    file_name: vaxis.Style,
    file_information: vaxis.Style,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const styles = Styles{
        .file_name = .{},
        .list_item = .{},
        .selected_list_item = .{ .bold = true },
        .file_information = .{
            .fg = .{ .rgb = .{ 0, 0, 0 } },
            .bg = .{ .rgb = .{ 255, 255, 255 } },
        },
    };

    var view = try View.init(alloc);
    defer view.deinit();

    var file_metadata = try view.dir.metadata();

    log.init();

    // TODO: Figure out size.
    var file_buf: [4096]u8 = undefined;

    var current_item_path: []u8 = "";
    var path: [std.fs.max_path_bytes]u8 = undefined;

    try view.populate();

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
                        view.cleanup();
                        try view.open("../");
                        try view.populate();
                    },
                    // Enter, l, Right arrow
                    13, 108, 57351 => {
                        const entry = view.entries.get(view.entries.selected) catch continue;

                        switch (entry.kind) {
                            .directory => {
                                try view.open(entry.name);
                                view.cleanup();
                                try view.populate();
                            },
                            .file => {},
                            else => {},
                        }
                    },
                    // j, Arrow down
                    106, 57353 => {
                        view.entries.next();
                    },
                    // k, Arrow up
                    107, 57352 => {
                        view.entries.previous();
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
        const bottom_div = 1;

        const top_left_bar = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = .{ .limit = win.width },
            .height = .{ .limit = top_div },
        });

        const bottom_left_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - bottom_div,
            .width = .{ .limit = win.width / 2 },
            .height = .{ .limit = bottom_div },
        });
        bottom_left_bar.fill(vaxis.Cell{ .style = styles.file_information });

        const top_right_bar = win.child(.{
            .x_off = win.width / 2,
            .y_off = 0,
            .width = .{ .limit = win.width },
            .height = .{ .limit = top_div },
        });

        const left_bar = win.child(.{
            .x_off = 0,
            .y_off = top_div + 1,
            .width = .{ .limit = win.width / 2 },
            .height = .{ .limit = win.height - (top_left_bar.height + bottom_left_bar.height + top_div + bottom_div) },
        });

        const right_bar = win.child(.{
            .x_off = win.width / 2,
            .y_off = top_div + 1,
            .width = .{ .limit = win.width / 2 },
            .height = .{ .limit = win.height - (top_left_bar.height + 1) },
        });

        if (view.entries.all().len > 0) {
            const entry = try view.entries.get(view.entries.selected);

            current_item_path = try std.fmt.bufPrint(&path, "{s}/{s}", .{ try view.full_path("."), entry.name });

            switch (entry.kind) {
                .directory => {
                    view.cleanup_sub();
                    try view.open_sub(current_item_path);
                    try view.populate_sub();

                    file_metadata = try view.sub_dir.metadata();

                    try view.sub_entries.render(right_bar, null, styles.list_item, null, null);
                },
                // TODO: Handle binary files.
                .file => {
                    var file = try view.dir.openFile(entry.name, .{ .mode = .read_only });
                    defer file.close();
                    const bytes = try file.readAll(&file_buf);

                    file_metadata = try file.metadata();

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

        _ = try top_left_bar.print(&.{vaxis.Segment{ .text = try view.full_path(".") }}, .{});

        var file_information_buf: [1024]u8 = undefined;
        const file_information = try std.fmt.bufPrint(&file_information_buf, "{d}/{d} {s} {s}", .{
            view.entries.selected + 1,
            view.entries.items.items.len,
            get_extension((try view.entries.get(view.entries.selected)).name),
            std.fmt.fmtIntSizeDec(file_metadata.size()),
        });
        _ = try bottom_left_bar.print(&.{vaxis.Segment{ .text = file_information, .style = styles.file_information }}, .{});

        if (view.entries.get(view.entries.selected)) |entry| {
            var file_name_buf: [std.fs.MAX_NAME_BYTES + 2]u8 = undefined;
            const file_name = try std.fmt.bufPrint(&file_name_buf, "[{s}]", .{entry.name});
            _ = try top_right_bar.print(&.{vaxis.Segment{
                .text = file_name,
                .style = styles.file_name,
            }}, .{});
        } else |_| {}

        try view.entries.render(left_bar, "name", styles.list_item, styles.selected_list_item, null);

        try vx.render();
    }
}

fn get_extension(file: []const u8) []const u8 {
    const index = std.mem.indexOf(u8, file, ".") orelse 0;
    if (index == 0) {
        return "";
    }
    return file[std.mem.indexOf(u8, file, ".") orelse 0 ..];
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    vx.deinit(null);
    std.builtin.default_panic(msg, trace, ret_addr);
}
