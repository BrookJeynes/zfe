// MIT License
//
// Copyright (c) 2024 Fre
// Modified by Brook Jeynes
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const std = @import("std");
const vaxis = @import("vaxis");
const c = @cImport({
    @cInclude("mupdf/fitz.h");
    @cInclude("mupdf/pdf.h");
});

const Pdf = @This();

alloc: std.mem.Allocator,
ctx: [*c]c.fz_context,
doc: [*c]c.fz_document,
page: ?vaxis.Image,

pub fn open(alloc: std.mem.Allocator, path: []const u8) !Pdf {
    const ctx = c.fz_new_context(null, null, c.FZ_STORE_UNLIMITED) orelse {
        return error.FailedToCreateContext;
    };
    errdefer c.fz_drop_context(ctx);
    c.fz_register_document_handlers(ctx);

    const path_z = try alloc.dupeZ(u8, path);
    defer alloc.free(path_z);
    const doc = c.fz_open_document(ctx, path_z) orelse {
        return error.FailedToOpenDocument;
    };
    errdefer c.fz_drop_document(ctx, doc);

    return Pdf{
        .alloc = alloc,
        .ctx = ctx,
        .doc = doc,
        .page = null,
    };
}

pub fn deinit(self: *Pdf) void {
    c.fz_drop_document(self.ctx, self.doc);
    c.fz_drop_context(self.ctx);
}

pub fn draw(self: *Pdf, vx: *vaxis.Vaxis, tty: *vaxis.Tty, win: vaxis.Window) !void {
    if (self.page == null) {
        var ctm = c.fz_scale(1.5, 1.5);
        ctm = c.fz_pre_translate(ctm, 0, 0);
        ctm = c.fz_pre_rotate(ctm, 0);

        const pix = c.fz_new_pixmap_from_page_number(
            self.ctx,
            self.doc,
            0,
            ctm,
            c.fz_device_rgb(self.ctx),
            0,
        ) orelse return error.PixmapCreationFailed;
        defer c.fz_drop_pixmap(self.ctx, pix);

        const width = c.fz_pixmap_width(self.ctx, pix);
        const height = c.fz_pixmap_height(self.ctx, pix);
        const samples = c.fz_pixmap_samples(self.ctx, pix);

        var img = try vaxis.zigimg.Image.fromRawPixels(
            self.alloc,
            @intCast(width),
            @intCast(height),
            samples[0..@intCast(width * height * 3)],
            .rgb24,
        );
        defer img.deinit();

        self.page = try vx.transmitImage(
            self.alloc,
            tty.anyWriter(),
            &img,
            .rgb,
        );
    }

    if (self.page) |img| {
        const dims = try img.cellSize(win);
        const center = vaxis.widgets.alignment.center(win, dims.cols, dims.rows);
        try img.draw(center, .{ .scale = .contain });
    }
}
