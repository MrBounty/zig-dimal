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
