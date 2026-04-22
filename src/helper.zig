const std = @import("std");

pub fn isInt(comptime T: type) bool {
    return @typeInfo(T) == .int or @typeInfo(T) == .comptime_int;
}

pub fn printSuperscript(writer: *std.Io.Writer, n: i32) !void {
    if (n == 0) return;
    var val = n;
    if (val < 0) {
        try writer.writeAll("\u{207B}");
        val = -val;
    }
    var buf: [12]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return;
    for (str) |c| {
        const s = switch (c) {
            '0' => "\u{2070}",
            '1' => "\u{00B9}",
            '2' => "\u{00B2}",
            '3' => "\u{00B3}",
            '4' => "\u{2074}",
            '5' => "\u{2075}",
            '6' => "\u{2076}",
            '7' => "\u{2077}",
            '8' => "\u{2078}",
            '9' => "\u{2079}",
            else => unreachable,
        };
        try writer.writeAll(s);
    }
}

const Scales = @import("Scales.zig");
const Dimensions = @import("Dimensions.zig");
const Dimension = @import("Dimensions.zig").Dimension;

pub fn finerScales(comptime T1: type, comptime T2: type) Scales {
    const d1: Dimensions = T1.dims;
    const d2: Dimensions = T2.dims;
    const s1: Scales = T1.scales;
    const s2: Scales = T2.scales;
    comptime var out = Scales.initFill(.none);
    inline for (std.enums.values(Dimension)) |dim| {
        const scale1 = comptime s1.get(dim);
        const scale2 = comptime s2.get(dim);
        out.set(dim, if (comptime d1.get(dim) == 0 and d2.get(dim) == 0)
            .none
        else if (comptime d1.get(dim) == 0)
            scale2
        else if (comptime d2.get(dim) == 0)
            scale1
        else if (comptime scale1.getFactor() > scale2.getFactor())
            scale2
        else
            scale1);
    }
    comptime return out;
}
