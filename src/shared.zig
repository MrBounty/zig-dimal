const std = @import("std");
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

pub fn isTensor(comptime T: type) bool {
    return comptime @typeInfo(T) == .@"struct" and @hasDecl(T, "ISTENSOR");
}

pub fn isTensorStatic(comptime T: type) bool {
    return comptime isTensor(T) and @hasDecl(T, "TENSORSTATIC");
}

pub fn isTensorAlloc(comptime T: type) bool {
    return comptime isTensor(T) and @hasDecl(T, "TENSORALLOC");
}

pub fn shapeTotal(shape: []const comptime_int) usize {
    var t: comptime_int = 1;
    for (shape) |s| t *= s;
    return t;
}

/// Check if two shapes are strictly identical.
pub fn shapeEql(a: []const comptime_int, b: []const comptime_int) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |v, i|
        if (v != b[i]) return false;
    return true;
}

/// Row-major (C-order) strides: strides[i] = product(shape[i+1..]).
///   e.g. shape {3, 4} → strides {4, 1}
///        shape {2, 3, 4} → strides {12, 4, 1}
pub fn shapeStrides(shape: []const comptime_int) [shape.len]comptime_int {
    var st: [shape.len]comptime_int = undefined;
    if (shape.len == 0) return st;
    st[shape.len - 1] = 1;
    if (shape.len > 1) {
        var i: comptime_int = shape.len - 1;
        while (i > 0) : (i -= 1) st[i - 1] = st[i] * shape[i];
    }
    return st;
}

/// Return a copy of `shape` with the element at `axis` removed.
pub fn shapeRemoveAxis(shape: []const comptime_int, axis: comptime_int) [shape.len - 1]comptime_int {
    var out: [shape.len - 1]comptime_int = undefined;
    var j: comptime_int = 0;
    for (shape, 0..) |v, i| {
        if (i != axis) {
            out[j] = v;
            j += 1;
        }
    }
    return out;
}

/// Concatenate two compile-time slices.
pub fn shapeCat(a: []const comptime_int, b: []const comptime_int) [a.len + b.len]comptime_int {
    var out: [a.len + b.len]comptime_int = undefined;
    for (a, 0..) |v, i| out[i] = v;
    for (b, 0..) |v, i| out[a.len + i] = v;
    return out;
}

/// Decode a flat row-major index into N-D coordinates.
/// Called only in comptime contexts (all arguments are comptime).
pub fn decodeFlatCoords(flat: comptime_int, n: comptime_int, strd: [n]comptime_int) [n]usize {
    var coords: [n]comptime_int = undefined;
    var tmp = flat;
    for (0..n) |i| {
        coords[i] = if (strd[i] == 0) 0 else tmp / strd[i];
        tmp = if (strd[i] == 0) 0 else tmp % strd[i];
    }
    return coords;
}

/// Encode N-D coordinates into a flat row-major index.
/// Called only in comptime contexts.
pub fn encodeFlatCoords(coords: []const usize, n: usize, strd: [n]usize) usize {
    var flat: usize = 0;
    for (0..n) |i| flat += coords[i] * strd[i];
    return flat;
}

/// Rebuild a full coordinate array by inserting `val` at `axis` into `free`.
/// `free` holds the remaining (non-contracted) coordinates in order.
pub fn insertAxis(
    comptime n: usize,
    comptime axis: usize,
    comptime val: usize,
    comptime free: []const usize,
) [n]usize {
    var out: [n]usize = undefined;
    var fi: usize = 0;
    for (0..n) |i| {
        if (i == axis) {
            out[i] = val;
        } else {
            out[i] = free[fi];
            fi += 1;
        }
    }
    return out;
}

pub inline fn isInt(comptime T: type) bool {
    return @typeInfo(T) == .int or @typeInfo(T) == .comptime_int;
}

pub fn finerScales(comptime T1: type, comptime T2: type) Scales {
    const d1: Dimensions = T1.dims;
    const d2: Dimensions = T2.dims;
    const s1: Scales = T1.scales;
    const s2: Scales = T2.scales;
    comptime var out = Scales.initFill(.none);
    for (std.enums.values(Dimension)) |dim| {
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
    return out;
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
