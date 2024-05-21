const std = @import("std");
const vaxis = @import("vaxis");

pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        items: std.ArrayList(T),
        selected: usize,
        offset: usize,
        last_rendered_pos: usize,

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .alloc = alloc,
                .items = std.ArrayList(T).init(alloc),
                .selected = 0,
                .offset = 0,
                .last_rendered_pos = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn append(self: *Self, item: T) !void {
            try self.items.append(item);
        }

        pub fn clear(self: *Self) void {
            self.items.clearAndFree();
            self.selected = 0;
            self.offset = 0;
        }

        pub fn get(self: *Self, index: usize) !T {
            if (index + 1 > self.items.items.len) {
                return error.OutOfBounds;
            }

            return self.items.items[index];
        }

        pub fn all(self: *Self) []T {
            return self.items.items;
        }

        pub fn next(self: *Self, win_height: usize) void {
            if (self.selected + 1 < self.items.items.len) {
                self.selected += 1;

                if (self.items.items[self.offset..].len != win_height and self.selected >= win_height / 2) {
                    self.offset += 1;
                }
            }
        }

        pub fn previous(self: *Self, win_height: usize) void {
            _ = win_height;

            if (self.selected > 0) {
                self.selected -= 1;

                if (self.offset > 0) {
                    self.offset -= 1;
                }
            }
        }

        pub fn select_last(self: *Self, win_height: usize) void {
            self.selected = self.items.items.len - 1;
            if (self.selected >= win_height) {
                self.offset = self.selected - (win_height - 1);
            }
        }

        pub fn select_first(self: *Self) void {
            self.selected = 0;
            self.offset = 0;
        }

        pub fn render(
            self: *Self,
            window: vaxis.Window,
            comptime field: ?[]const u8,
            style: ?vaxis.Style,
            selected_item_style: ?vaxis.Style,
            callback: ?*const fn (item_win: vaxis.Window) void,
        ) !void {
            if (self.items.items.len != 0) {
                for (self.items.items[self.offset..], 0..) |item, i| {
                    if (i > window.height) {
                        continue;
                    }

                    const w = window.child(.{ .y_off = i });

                    if (callback) |cb| {
                        cb(w);
                    }

                    _ = try w.print(&.{
                        .{
                            .text = if (field) |f| @field(item, f) else item,
                            .style = if (self.selected - self.offset == i) selected_item_style orelse .{} else style orelse .{},
                        },
                    }, .{});

                    self.last_rendered_pos = i;
                }
            }
        }
    };
}
