const std = @import("std");

pub fn CircularStack(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        head: usize = 0,
        count: usize = 0,
        buf: [capacity]T = undefined,

        pub fn init() Self {
            return Self{};
        }

        pub fn reset(self: *Self) void {
            self.head = 0;
            self.count = 0;
        }

        pub fn push(self: *Self, v: T) ?T {
            const prev_elem = if (self.count == capacity) self.buf[self.head] else null;

            self.buf[self.head] = v;
            self.head = (self.head + 1) % capacity;
            if (self.count != capacity) self.count += 1;

            return prev_elem;
        }

        pub fn pop(self: *Self) ?T {
            if (self.count == 0) return null;

            self.head = (self.head - 1) % capacity;
            const value = self.buf[self.head];
            self.count -= 1;
            return value;
        }
    };
}
