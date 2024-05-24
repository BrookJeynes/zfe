const std = @import("std");
const vaxis = @import("vaxis");

pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        items: std.ArrayList(T),
        selected: usize,
        offset: usize,

        pub fn init(alloc: std.mem.Allocator) Self {
            return Self{
                .alloc = alloc,
                .items = std.ArrayList(T).init(alloc),
                .selected = 0,
                .offset = 0,
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

        // TODO: Move to view, the list should not have to care about this.
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
                    const is_selected = self.selected - self.offset == i;

                    if (i > window.height) {
                        continue;
                    }

                    const w = window.child(.{
                        .y_off = i,
                        .height = .{ .limit = 1 },
                    });
                    w.fill(vaxis.Cell{
                        .style = if (is_selected) selected_item_style orelse .{} else style orelse .{},
                    });

                    if (callback) |cb| {
                        cb(w);
                    }

                    _ = try w.print(&.{
                        .{
                            .text = if (field) |f| @field(item, f) else item,
                            .style = if (is_selected) selected_item_style orelse .{} else style orelse style orelse .{},
                        },
                    }, .{});
                }
            }
        }
    };
}
