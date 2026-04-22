const std = @import("std");

pub const Dimension = enum {
    /// Length
    L,
    /// Mass
    M,
    /// Time
    T,
    /// Electric Current
    I,
    /// Temperature
    Tp,
    /// Amount of Substance
    N,
    /// Luminous Intensity
    J,

    pub fn unit(self: @This()) []const u8 {
        return switch (self) {
            .L => "m",
            .M => "g",
            .T => "s",
            .I => "A",
            .Tp => "K",
            .N => "mol",
            .J => "cd",
        };
    }
};

// --------- Dimensions struct ---------

/// Holds the exponent of each SI base dimension for a given quantity (e.g. velocity = L¹T⁻¹).
/// All values are `comptime_int` — no runtime storage.
const Self = @This();

data: std.EnumArray(Dimension, comptime_int),

/// Create a `Dimensions` from an anonymous struct literal, e.g. `.{ .L = 1, .T = -1 }`.
/// Unspecified dimensions default to 0.
pub fn init(comptime init_val: anytype) Self {
    var s = Self{ .data = std.EnumArray(Dimension, comptime_int).initFill(0) };
    inline for (std.meta.fields(@TypeOf(init_val))) |f|
        s.data.set(@field(Dimension, f.name), @field(init_val, f.name));
    return s;
}

pub fn initFill(comptime val: comptime_int) Self {
    return .{ .data = std.EnumArray(Dimension, comptime_int).initFill(val) };
}

pub fn get(comptime self: Self, comptime key: Dimension) comptime_int {
    return self.data.get(key);
}

pub fn set(comptime self: *Self, comptime key: Dimension, comptime val: i8) void {
    self.data.set(key, val);
}

/// Add exponents component-wise. Used internally by `mulBy`.
pub fn add(comptime a: Self, comptime b: Self) Self {
    var result = Self.initFill(0);
    for (std.enums.values(Dimension)) |d|
        result.set(d, a.get(d) + b.get(d));
    return result;
}

/// Subtract exponents component-wise. Used internally by `divBy`.
pub fn sub(comptime a: Self, comptime b: Self) Self {
    var result = Self.initFill(0);
    inline for (std.enums.values(Dimension)) |d|
        result.set(d, a.get(d) - b.get(d));
    return result;
}

/// Multiply exponents by a scalar integer. Used internally by `pow` in Scalar.
pub fn scale(comptime a: Self, comptime exp: comptime_int) Self {
    var result = Self.initFill(0);
    inline for (std.enums.values(Dimension)) |d|
        result.set(d, a.get(d) * exp);
    return result;
}

pub fn div(comptime a: Self, comptime exp: comptime_int) Self {
    var result = Self.initFill(0);
    inline for (std.enums.values(Dimension)) |d|
        result.set(d, a.get(d) / exp);
    return result;
}

/// Returns true if every dimension exponent is equal. Used to enforce type compatibility in `add`, `sub`, `to`.
pub fn eql(comptime a: Self, comptime b: Self) bool {
    inline for (std.enums.values(Dimension)) |d|
        if (a.get(d) != b.get(d)) return false;
    return true;
}

pub fn isSquare(comptime a: Self) bool {
    inline for (std.enums.values(Dimension)) |d|
        if (a.get(d) % 2 != 0) return false;
    return true;
}

pub fn str(comptime a: Self) []const u8 {
    var out: []const u8 = "";
    const dims = std.enums.values(Dimension);

    inline for (dims) |d| {
        const val = a.get(d);
        if (val != 0) {
            out = out ++ @tagName(d) ++ std.fmt.comptimePrint("{d}", .{val});
        }
    }

    return if (out.len == 0) "Dimensionless" else out;
}
