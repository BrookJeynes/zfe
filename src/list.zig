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

        pub fn get_selected(self: *Self) !T {
            if (self.items.items.len > 0) {
                if (self.selected >= self.items.items.len) {
                    self.selected = self.items.items.len - 1;
                }

                return self.items.items[self.selected];
            }

            return error.EmptyList;
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
            if (self.selected > 0) {
                self.selected -= 1;

                if (self.offset > 0 and self.selected < self.offset + (win_height / 2)) {
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
    };
}
