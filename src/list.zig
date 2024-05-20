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

        pub fn next(self: *Self) void {
            if (self.selected + 1 < self.items.items.len) {
                self.selected += 1;

                if (self.selected > 10) {
                    self.offset += 1;
                }
            }
        }

        pub fn previous(self: *Self) void {
            if (self.selected > 0) {
                self.selected -= 1;

                if (self.offset > 0) {
                    self.offset -= 1;
                }
            }
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
                }
            }
        }
    };
}
