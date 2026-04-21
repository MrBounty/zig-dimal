const std = @import("std");
const hlp = @import("helper.zig");
const Dimensions = @import("Dimensions.zig");
const Dimension = @import("Dimensions.zig").Dimension;

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

    // Undefined
    _,

    pub inline fn str(self: @This()) []const u8 {
        var buf: [16]u8 = undefined;
        return switch (self) {
            inline .none => "",
            inline .P, .T, .G, .M, .k, .h, .da, .d, .c, .m, .u, .n, .p, .f, .min, .hour, .year => @tagName(self),
            else => std.fmt.bufPrint(&buf, "[{d}]", .{@intFromEnum(self)}) catch "[]", // This cannot be inline because of non exhaustive enum, but that's ok, it is just str, not calculation
        };
    }

    /// Helper to get the actual scaling factor
    pub inline fn getFactor(self: @This()) comptime_float {
        return switch (self) {
            inline .P, .T, .G, .M, .k, .h, .da, .none, .d, .c, .m, .u, .n, .p, .f => std.math.pow(f64, 10.0, @floatFromInt(@intFromEnum(self))),
            inline else => @floatFromInt(@intFromEnum(self)),
        };
    }

    /// Helper to get the actual scaling factor in i32
    pub inline fn getFactorInt(self: @This()) comptime_int {
        return switch (self) {
            inline .P, .T, .G, .M, .k, .h, .da, .none, .d, .c, .m, .u, .n, .p, .f => comptime std.math.powi(i32, 10.0, @intFromEnum(self)) catch 0,
            inline else => comptime @intFromEnum(self),
        };
    }
};

const Scales = @This();

data: std.EnumArray(Dimension, UnitScale),

pub fn init(comptime init_val: anytype) Scales {
    comptime var s = Scales{ .data = std.EnumArray(Dimension, UnitScale).initFill(.none) };
    inline for (std.meta.fields(@TypeOf(init_val))) |f| {
        if (comptime hlp.isInt(@TypeOf(@field(init_val, f.name))))
            s.data.set(@field(Dimension, f.name), @enumFromInt(@field(init_val, f.name)))
        else
            s.data.set(@field(Dimension, f.name), @field(init_val, f.name));
    }
    return s;
}

pub fn initFill(comptime val: UnitScale) Scales {
    return comptime .{ .data = std.EnumArray(Dimension, UnitScale).initFill(val) };
}

pub fn get(comptime self: Scales, comptime key: Dimension) UnitScale {
    return comptime self.data.get(key);
}

pub fn set(comptime self: *Scales, comptime key: Dimension, comptime val: UnitScale) void {
    comptime self.data.set(key, val);
}

pub fn min(comptime s1: Scales, comptime s2: Scales) Scales {
    comptime var out = Scales.initFill(.none);
    inline for (std.enums.values(Dimension)) |dim|
        out.set(dim, if (s1.get(dim).getFactorInt() > s2.get(dim).getFactorInt()) s2.get(dim) else s1.get(dim));

    return out;
}

pub inline fn getFactor(comptime s: Scales, comptime d: Dimensions) comptime_float {
    comptime var factor: f64 = 1.0;
    inline for (std.enums.values(Dimension)) |dim| {
        const power = d.get(dim);
        if (power == 0) continue;

        const base = s.get(dim).getFactor();

        var i: i32 = 0;
        const abs_power = if (power < 0) -power else power;
        while (i < abs_power) : (i += 1) {
            if (power > 0)
                factor *= base
            else
                factor /= base;
        }
    }
    return factor;
}
