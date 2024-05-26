const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;
const environment = @import("./environment.zig");
const config = &@import("./config.zig").config;
const List = @import("./list.zig").List;
const View = @import("./view.zig");

const vaxis = @import("vaxis");
const TextInput = @import("vaxis").widgets.TextInput;
const Cell = vaxis.Cell;
const Key = vaxis.Key;

const State = enum {
    normal,
    input,
};

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

var vx: vaxis.Vaxis = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var view = try View.init(alloc);
    defer view.deinit();

    var file_metadata = try view.dir.metadata();

    log.init();

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

    // TODO: Figure out size.
    var file_buf: [4096]u8 = undefined;

    var current_item_path: []u8 = "";
    var last_item_path: []u8 = "";
    var image: ?vaxis.Image = null;
    var path: [std.fs.max_path_bytes]u8 = undefined;
    var last_path: [std.fs.max_path_bytes]u8 = undefined;

    try view.populate_entries("");

    vx = try vaxis.init(alloc, .{ .kitty_keyboard_flags = .{
        .report_text = false,
        .disambiguate = false,
        .report_events = false,
        .report_alternate_keys = false,
        .report_all_as_ctl_seqs = false,
    } });
    defer vx.deinit(alloc);

    var loop: vaxis.Loop(Event) = .{ .vaxis = &vx };
    try loop.run();
    defer loop.stop();

    try vx.enterAltScreen();
    try vx.queryTerminal();
    vx.caps.kitty_keyboard = false;

    var text_input = TextInput.init(alloc, &vx.unicode);
    defer text_input.deinit();

    var err_len: usize = 0;
    var err_buf: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&err_buf);

    var state = State.normal;
    var last_pressed: ?vaxis.Key = null;
    var last_known_height: usize = vx.window().height;
    while (true) {
        err_len = 0;
        const event = loop.nextEvent();

        switch (state) {
            .normal => {
                switch (event) {
                    .key_press => |key| {
                        if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 'q') {
                            break;
                        }

                        switch (key.codepoint) {
                            '-', 'h', Key.left => {
                                text_input.clearAndFree();

                                if (view.dir.openDir("../", .{ .iterate = true })) |dir| {
                                    view.dir = dir;

                                    var fuzzy_buf: [std.fs.max_path_bytes]u8 = undefined;
                                    const fuzzy = text_input.sliceToCursor(&fuzzy_buf);

                                    view.cleanup();
                                    view.populate_entries(fuzzy) catch |err| {
                                        err_len = switch (err) {
                                            error.AccessDenied => try fbs.write("Permission denied."),
                                            else => try fbs.write("An unknown error occurred."),
                                        };
                                    };
                                } else |err| {
                                    err_len = switch (err) {
                                        error.AccessDenied => try fbs.write("Permission denied."),
                                        else => try fbs.write("An unknown error occurred."),
                                    };
                                }
                                last_pressed = null;
                            },
                            Key.enter, 'l', Key.right => {
                                const entry = view.entries.get(view.entries.selected) catch continue;

                                switch (entry.kind) {
                                    .directory => {
                                        text_input.clearAndFree();

                                        if (view.dir.openDir(entry.name, .{ .iterate = true })) |dir| {
                                            view.dir = dir;

                                            var fuzzy_buf: [std.fs.max_path_bytes]u8 = undefined;
                                            const fuzzy = text_input.sliceToCursor(&fuzzy_buf);

                                            view.cleanup();
                                            view.populate_entries(fuzzy) catch |err| {
                                                err_len = switch (err) {
                                                    error.AccessDenied => try fbs.write("Permission denied."),
                                                    else => try fbs.write("An unknown error occurred."),
                                                };
                                            };
                                        } else |err| {
                                            err_len = switch (err) {
                                                error.AccessDenied => try fbs.write("Permission denied."),
                                                else => try fbs.write("An unknown error occurred."),
                                            };
                                        }
                                        last_pressed = null;
                                    },
                                    .file => {
                                        if (environment.get_editor()) |editor| {
                                            try vx.exitAltScreen();
                                            loop.stop();

                                            environment.open_file(alloc, view.dir, entry.name, editor) catch {
                                                err_len = try fbs.write("Unable to open file.");
                                            };

                                            try loop.run();
                                            try vx.enterAltScreen();
                                            vx.queueRefresh();
                                        } else {
                                            err_len = try fbs.write("$EDITOR is not set.");
                                        }
                                    },
                                    else => {},
                                }
                            },
                            'j', Key.down => {
                                view.entries.next(last_known_height);
                                last_pressed = null;
                            },
                            'k', Key.up => {
                                view.entries.previous(last_known_height);
                                last_pressed = null;
                            },
                            'G' => {
                                view.entries.select_last(last_known_height);
                                last_pressed = null;
                            },
                            'g' => {
                                if (last_pressed) |k| {
                                    if (k.codepoint == 103) {
                                        view.entries.select_first();
                                        last_pressed = null;
                                    }
                                } else {
                                    last_pressed = key;
                                }
                            },
                            '/' => state = State.input,
                            else => {
                                // log.debug("codepoint: {d}\n", .{key.codepoint});
                            },
                        }
                    },
                    .winsize => |ws| {
                        try vx.resize(alloc, ws);
                    },
                }
            },
            .input => {
                switch (event) {
                    .key_press => |key| {
                        if ((key.codepoint == 'c' and key.mods.ctrl) or key.codepoint == 'q') {
                            break;
                        }

                        switch (key.codepoint) {
                            Key.escape => {
                                text_input.clearAndFree();
                                state = State.normal;

                                view.cleanup();
                                view.populate_entries("") catch |err| {
                                    err_len = switch (err) {
                                        error.AccessDenied => try fbs.write("Permission denied."),
                                        else => try fbs.write("An unknown error occurred."),
                                    };
                                };
                            },
                            Key.enter => {
                                state = State.normal;
                            },
                            else => {
                                try text_input.update(.{ .key_press = key });

                                var fuzzy_buf: [std.fs.max_path_bytes]u8 = undefined;
                                const fuzzy = text_input.sliceToCursor(&fuzzy_buf);
                                view.cleanup();
                                view.populate_entries(fuzzy) catch |err| {
                                    err_len = switch (err) {
                                        error.AccessDenied => try fbs.write("Permission denied."),
                                        else => try fbs.write("An unknown error occurred."),
                                    };
                                };
                            },
                        }
                    },
                    .winsize => |ws| {
                        try vx.resize(alloc, ws);
                    },
                }
            },
        }

        const win = vx.window();
        win.clear();

        const top_div = 1;
        const info_div = 1;
        const bottom_div = 1;

        const info_bar = win.child(.{
            .x_off = 0,
            .y_off = top_div,
            .width = .{ .limit = win.width },
            .height = .{ .limit = info_div },
        });

        const top_left_bar = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = .{ .limit = win.width },
            .height = .{ .limit = top_div },
        });

        const bottom_left_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - bottom_div,
            .width = if (config.preview_file) .{ .limit = win.width / 2 } else .{ .limit = win.width },
            .height = .{ .limit = bottom_div },
        });
        bottom_left_bar.fill(vaxis.Cell{ .style = config.styles.file_information });

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
            .width = if (config.preview_file) .{ .limit = win.width / 2 } else .{ .limit = win.width },
            .height = .{ .limit = win.height - (top_left_bar.height + bottom_left_bar.height + top_div + bottom_div) },
        });

        const right_bar = win.child(.{
            .x_off = win.width / 2,
            .y_off = top_div + 1,
            .width = .{ .limit = win.width / 2 },
            .height = .{ .limit = win.height - (top_right_bar.height + bottom_right_bar.height + top_div + bottom_div) },
        });

        if (view.entries.all().len > 0 and config.preview_file == true) {
            const entry = try view.entries.get(view.entries.selected);

            @memcpy(&last_path, &path);
            last_item_path = last_path[0..current_item_path.len];
            current_item_path = try std.fmt.bufPrint(&path, "{s}/{s}", .{ try view.full_path("."), entry.name });

            switch (entry.kind) {
                .directory => {
                    view.cleanup_sub();
                    if (view.populate_sub_entries(entry.name)) {
                        try view.write_sub_entries(right_bar, config.styles.list_item);
                    } else |err| {
                        err_len = switch (err) {
                            error.AccessDenied => try fbs.write("Permission denied."),
                            else => try fbs.write("An unknown error occurred."),
                        };
                    }
                },
                .file => file: {
                    var file = view.dir.openFile(entry.name, .{ .mode = .read_only }) catch |err| {
                        err_len = switch (err) {
                            error.AccessDenied => try fbs.write("Permission denied."),
                            else => try fbs.write("An unknown error occurred."),
                        };

                        _ = try right_bar.print(&.{
                            .{
                                .text = "No preview available.",
                            },
                        }, .{});

                        break :file;
                    };
                    defer file.close();
                    const bytes = try file.readAll(&file_buf);

                    // Handle image.
                    if (config.show_images == true) unsupported_terminal: {
                        const supported: [1][]const u8 = .{".png"};

                        for (supported) |ext| {
                            if (std.mem.eql(u8, get_extension(entry.name), ext)) {
                                // Don't re-render preview if we haven't changed selection.
                                if (std.mem.eql(u8, last_item_path, current_item_path)) break :file;

                                if (vx.loadImage(alloc, .{ .path = current_item_path })) |img| {
                                    image = img;
                                } else |_| {
                                    image = null;
                                    break :unsupported_terminal;
                                }

                                break :file;
                            } else {
                                // Free any image we might have already.
                                if (image) |img| {
                                    vx.freeImage(img.id);
                                }
                            }
                        }
                    }

                    // Handle utf-8.
                    if (std.unicode.utf8ValidateSlice(file_buf[0..bytes])) {
                        _ = try right_bar.print(&.{
                            .{
                                .text = file_buf[0..bytes],
                            },
                        }, .{});
                        break :file;
                    }

                    // Fallback to no preview.
                    _ = try right_bar.print(&.{
                        .{
                            .text = "No preview available.",
                        },
                    }, .{});
                },
                else => {
                    _ = try right_bar.print(&.{vaxis.Segment{ .text = current_item_path }}, .{});
                },
            }
        }

        if (image) |img| {
            try img.draw(right_bar, .{ .scale = .fit });
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
        _ = try bottom_left_bar.print(&.{vaxis.Segment{ .text = file_information, .style = config.styles.file_information }}, .{});
        _ = try bottom_right_bar.print(&.{vaxis.Segment{
            .text = if (last_pressed) |key| key.text.? else "",
            .style = if (config.preview_file) .{} else config.styles.file_information,
        }}, .{});

        if (config.preview_file == true) {
            if (view.entries.get(view.entries.selected)) |entry| {
                var file_name_buf: [std.fs.MAX_NAME_BYTES + 2]u8 = undefined;
                const file_name = try std.fmt.bufPrint(&file_name_buf, "[{s}]", .{entry.name});
                _ = try top_right_bar.print(&.{vaxis.Segment{
                    .text = file_name,
                    .style = config.styles.file_name,
                }}, .{});
            } else |_| {}
        }

        try view.write_entries(left_bar, config.styles.selected_list_item, config.styles.list_item, null);

        if (err_len > 0) {
            if (text_input.grapheme_count > 0) {
                text_input.clearAndFree();
            }

            _ = try info_bar.print(&.{
                .{
                    .text = err_buf[0..err_len],
                    .style = config.styles.error_bar,
                },
            }, .{});
        }

        if (state == State.input or text_input.grapheme_count > 0) {
            err_len = 0;
            text_input.draw(info_bar);
        }

        if (state == State.normal) {
            win.hideCursor();
        }

        try vx.render();

        last_known_height = left_bar.height;
        fbs.reset();
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
