const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;
const List = @import("./list.zig").List;
const View = @import("./view.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Key = vaxis.Key;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

var vx: vaxis.Vaxis = undefined;

const Config = struct {
    show_hidden: bool,
    sort_dirs: bool,
};

const Styles = struct {
    selected_list_item: vaxis.Style,
    list_item: vaxis.Style,
    file_name: vaxis.Style,
    file_information: vaxis.Style,
};

pub const styles = Styles{
    .file_name = .{},
    .list_item = .{},
    .selected_list_item = .{ .bold = true },
    .file_information = .{
        .fg = .{ .rgb = .{ 0, 0, 0 } },
        .bg = .{ .rgb = .{ 255, 255, 255 } },
    },
};

pub const config = Config{
    .show_hidden = false,
    .sort_dirs = true,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

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
    try vx.queryTerminal();

    var last_pressed: ?vaxis.Key = null;
    var last_known_height: usize = vx.window().height;
    while (true) {
        const event = loop.nextEvent();

        switch (event) {
            .key_press => |key| {
                if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 113) {
                    break;
                }

                switch (key.codepoint) {
                    // -, h, Left arrow
                    '-', 'h', Key.left => {
                        view.cleanup();
                        try view.open("../");
                        try view.populate();
                        last_pressed = null;
                    },
                    // Enter, l, Right arrow
                    Key.enter, 'l', Key.right => {
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
                        last_pressed = null;
                    },
                    // j, Arrow down
                    'j', Key.down => {
                        view.entries.next(last_known_height);
                        last_pressed = null;
                    },
                    // k, Arrow up
                    'k', Key.up => {
                        view.entries.previous(last_known_height);
                        last_pressed = null;
                    },
                    // g
                    'g' => {
                        if (key.matches('G', .{})) {
                            view.entries.select_last(last_known_height);
                            last_pressed = null;
                        } else if (last_pressed) |k| {
                            if (k.codepoint == 103) {
                                view.entries.select_first();
                                last_pressed = null;
                            }
                        } else {
                            last_pressed = key;
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

        const bottom_right_bar = win.child(.{
            .x_off = (win.width / 2) + 5,
            .y_off = win.height - bottom_div,
            .width = .{ .limit = win.width / 2 },
            .height = .{ .limit = bottom_div },
        });

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
            .height = .{ .limit = win.height - (top_right_bar.height + bottom_right_bar.height + top_div + bottom_div) },
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
                .file => {
                    var file = try view.dir.openFile(entry.name, .{ .mode = .read_only });
                    defer file.close();
                    const bytes = try file.readAll(&file_buf);

                    if (std.unicode.utf8ValidateSlice(file_buf[0..bytes])) {
                        _ = try right_bar.print(&.{
                            .{
                                .text = file_buf[0..bytes],
                            },
                        }, .{});
                    } else {
                        if (std.mem.eql(u8, get_extension(entry.name), ".png") or std.mem.eql(u8, get_extension(entry.name), ".jpg")) {
                            var image = try vx.loadImage(alloc, .{ .path = current_item_path });
                            defer vx.freeImage(image.id);

                            const scale = true;
                            const z_index = 0;
                            image.draw(right_bar, scale, z_index);
                        } else {
                            _ = try right_bar.print(&.{
                                .{
                                    .text = "No preview available.",
                                },
                            }, .{});
                        }
                    }
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
            get_extension(
                if (view.entries.get(view.entries.selected)) |entry| entry.name else |_| "",
            ),
            std.fmt.fmtIntSizeDec(file_metadata.size()),
        });
        _ = try bottom_left_bar.print(&.{vaxis.Segment{ .text = file_information, .style = styles.file_information }}, .{});
        _ = try bottom_right_bar.print(&.{vaxis.Segment{ .text = if (last_pressed) |key| key.text.? else "" }}, .{});

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

        last_known_height = left_bar.height;
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
