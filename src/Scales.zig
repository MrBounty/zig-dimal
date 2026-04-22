const std = @import("std");
const hlp = @import("helper.zig");
const Dimensions = @import("Dimensions.zig");
const Dimension = @import("Dimensions.zig").Dimension;

// TODO: add more scales like feet and inch

/// Use to initiate Scalar and Scales type
pub const ArgOpts = struct {
    L: UnitScale = .none,
    M: UnitScale = .none,
    T: UnitScale = .none,
    I: UnitScale = .none,
    Tp: UnitScale = .none,
    N: UnitScale = .none,
    J: UnitScale = .none,
};

/// SI prefix (pico…peta) plus time-unit aliases (min, hour, year).
/// The integer value encodes the exponent for SI prefixes (e.g. `k = 3` → 10³),
/// and the literal factor for time units (e.g. `hour = 3600`).
pub const UnitScale = enum(isize) {
    P = 15,
    T = 12,
    G = 9,
    M = 6,
    k = 3,
    h = 2,
    da = 1,
    none = 0,
    d = -1,
    c = -2,
    m = -3,
    u = -6,
    n = -9,
    p = -12,
    f = -15,

    // Custom
    min = 60,
    hour = 3_600,
    year = 31_536_000,

    // Imperial Length (Literal factors in meters)
    // 1 inch = 0.0254 meters. Since enum backing is isize,
    // we use a unique tag and handle the float in getFactor.
    inch = -1001,
    ft = -1002,
    yd = -1003,
    mi = -1004,

    oz = -1005, //  1 oz  = 28.3495231 g
    lb = -1006, //  1 lb  = 453.59237 g  (= 16 oz)
    st = -1007, //  1 stone = 6350.29318 g (= 14 lb)

    // Undefined
    _,

    pub inline fn str(self: @This()) []const u8 {
        var buf: [16]u8 = undefined;
        return switch (self) {
            inline .none => "",
            inline .P, .T, .G, .M, .k, .h, .da, .d, .c, .m, .u, .n, .p, .f, .min, .hour, .year, .inch, .ft, .yd, .mi, .oz, .lb, .st => @tagName(self),
            else => std.fmt.bufPrint(&buf, "[{d}]", .{@intFromEnum(self)}) catch "[]", // This cannot be inline because of non exhaustive enum, but that's ok, it is just str, not calculation
        };
    }

    pub inline fn getFactor(self: @This()) comptime_float {
        return comptime switch (self) {
            // Standard SI Exponents
            inline .P, .T, .G, .M, .k, .h, .da, .none, .d, .c, .m, .u, .n, .p, .f => std.math.pow(f64, 10.0, @floatFromInt(@intFromEnum(self))),

            // Time Factors
            inline .min, .hour, .year => @floatFromInt(@intFromEnum(self)),

            // Imperial Length (metres)
            inline .inch => 0.0254,
            inline .ft => 0.3048,
            inline .yd => 0.9144,
            inline .mi => 1609.344,

            // Imperial Mass (grams — base unit for M is gram, i.e. .none = 1 g)
            inline .oz => 28.3495231,
            inline .lb => 453.59237,
            inline .st => 6350.29318,

            inline else => @floatFromInt(@intFromEnum(self)),
        };
    }
};

/// Maps each SI base dimension to its `UnitScale`. Stored and resolved entirely at comptime.
const Self = @This();

data: std.EnumArray(Dimension, UnitScale),

/// Create a `Scales` from a struct literal, e.g. `.{ .L = .k, .T = .hour }`.
/// Unspecified dimensions default to `.none` (factor 1).
pub fn init(comptime init_val: ArgOpts) Self {
    comptime var s = Self{ .data = std.EnumArray(Dimension, UnitScale).initFill(.none) };
    inline for (std.meta.fields(@TypeOf(init_val))) |f| {
        if (comptime hlp.isInt(@TypeOf(@field(init_val, f.name))))
            s.data.set(@field(Dimension, f.name), @enumFromInt(@field(init_val, f.name)))
        else
            s.data.set(@field(Dimension, f.name), @field(init_val, f.name));
    }
    return s;
}

pub fn initFill(comptime val: UnitScale) Self {
    return comptime .{ .data = std.EnumArray(Dimension, UnitScale).initFill(val) };
}

pub fn get(comptime self: Self, comptime key: Dimension) UnitScale {
    return comptime self.data.get(key);
}

pub fn set(comptime self: *Self, comptime key: Dimension, comptime val: UnitScale) void {
    comptime self.data.set(key, val);
}

pub fn argsOpt(self: Self) ArgOpts {
    var args: ArgOpts = undefined;
    inline for (std.enums.values(Dimension)) |d|
        @field(args, @tagName(d)) = self.get(d);
    return args;
}

/// Compute the combined scale factor for a given dimension signature.
/// Each dimension's prefix is raised to its exponent and multiplied together.
pub inline fn getFactor(comptime s: Self, comptime d: Dimensions) comptime_float {
    var factor: f64 = 1.0;
    for (std.enums.values(Dimension)) |dim| {
        const power = comptime d.get(dim);
        if (power == 0) continue;

        const base = s.get(dim).getFactor();

        var i: comptime_int = 0;
        const abs_power = if (power < 0) -power else power;
        while (i < abs_power) : (i += 1) {
            if (power > 0)
                factor *= base
            else
                factor /= base;
        }
    }
    return comptime factor;
}
