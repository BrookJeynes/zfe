const std = @import("std");
const List = @import("./list.zig").List;
const config = &@import("./config.zig").config;
const vaxis = @import("vaxis");
const fuzzig = @import("fuzzig");

const History = struct {
    selected: usize,
    offset: usize,
};

const Self = @This();

alloc: std.mem.Allocator,
dir: std.fs.Dir,
path_buf: [std.fs.max_path_bytes]u8 = undefined,
file_contents: [4096]u8 = undefined,
entries: List(std.fs.Dir.Entry),
history: std.ArrayList(History),
sub_entries: List([]const u8),
searcher: fuzzig.Ascii,

pub fn init(alloc: std.mem.Allocator) !Self {
    return Self{
        .alloc = alloc,
        .dir = try std.fs.cwd().openDir(".", .{ .iterate = true }),
        .entries = List(std.fs.Dir.Entry).init(alloc),
        .history = std.ArrayList(History).init(alloc),
        .sub_entries = List([]const u8).init(alloc),
        .searcher = try fuzzig.Ascii.init(
            alloc,
            std.fs.max_path_bytes,
            std.fs.max_path_bytes,
            .{ .case_sensitive = false },
        ),
    };
}

pub fn deinit(self: *Self) void {
    self.cleanup();
    self.cleanup_sub();

    self.entries.deinit();
    self.sub_entries.deinit();

    self.history.deinit();

    self.dir.close();
    self.searcher.deinit();
}

pub fn get_selected(self: *Self) !std.fs.Dir.Entry {
    return self.entries.get_selected();
}

/// Asserts there is a selected item.
pub fn remove_selected(self: *Self) void {
    const entry = self.get_selected() catch return;
    self.alloc.free(entry.name);
    _ = self.entries.items.orderedRemove(self.entries.selected);
}

pub fn full_path(self: *Self, relative_path: []const u8) ![]const u8 {
    return try self.dir.realpath(relative_path, &self.path_buf);
}

pub fn populate_sub_entries(
    self: *Self,
    relative_path: []const u8,
) !void {
    var dir = try self.dir.openDir(relative_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        try self.sub_entries.append(try self.alloc.dupe(u8, entry.name));
    }

    if (config.sort_dirs == true) {
        std.mem.sort([]const u8, self.sub_entries.items.items, {}, sort_sub_entry);
    }
}

pub fn write_sub_entries(
    self: *Self,
    window: vaxis.Window,
    style: vaxis.Style,
) !void {
    for (self.sub_entries.items.items, 0..) |item, i| {
        if (std.mem.startsWith(u8, item, ".") and config.show_hidden == false) {
            continue;
        }

        if (i > window.height) {
            continue;
        }

        const w = window.child(.{
            .y_off = i,
            .height = .{ .limit = 1 },
        });
        w.fill(vaxis.Cell{
            .style = style,
        });

        _ = try w.print(&.{
            .{
                .text = item,
                .style = style,
            },
        }, .{});
    }
}

pub fn populate_entries(self: *Self, fuzzy_search: []const u8) !void {
    var it = self.dir.iterate();
    while (try it.next()) |entry| {
        const score = self.searcher.score(entry.name, fuzzy_search) orelse 0;
        if (fuzzy_search.len > 0 and score < 1) {
            continue;
        }

        try self.entries.append(.{
            .kind = entry.kind,
            .name = try self.alloc.dupe(u8, entry.name),
        });
    }

    if (config.sort_dirs == true) {
        std.mem.sort(std.fs.Dir.Entry, self.entries.items.items, {}, sort_entry);
    }
}

pub fn write_entries(
    self: *Self,
    window: vaxis.Window,
    selected_list_item_style: vaxis.Style,
    list_item_style: vaxis.Style,
    callback: ?*const fn (item_win: vaxis.Window) void,
) !void {
    for (self.entries.items.items[self.entries.offset..], 0..) |item, i| {
        const is_selected = self.entries.selected - self.entries.offset == i;

        if (std.mem.startsWith(u8, item.name, ".") and config.show_hidden == false) {
            continue;
        }

        if (i > window.height) {
            continue;
        }

        const w = window.child(.{
            .y_off = i,
            .height = .{ .limit = 1 },
        });
        w.fill(vaxis.Cell{
            .style = if (is_selected) selected_list_item_style else list_item_style,
        });

        if (callback) |cb| {
            cb(w);
        }

        _ = try w.print(&.{
            .{
                .text = item.name,
                .style = if (is_selected) selected_list_item_style else list_item_style,
            },
        }, .{});
    }
}

fn sort_entry(_: void, lhs: std.fs.Dir.Entry, rhs: std.fs.Dir.Entry) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

fn sort_sub_entry(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}

pub fn cleanup(self: *Self) void {
    for (self.entries.all()) |entry| {
        self.entries.alloc.free(entry.name);
    }
    self.entries.clear();
}

pub fn cleanup_sub(self: *Self) void {
    for (self.sub_entries.all()) |entry| {
        self.sub_entries.alloc.free(entry);
    }
    self.sub_entries.clear();
}
