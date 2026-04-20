const std = @import("std");
const hlp = @import("helper.zig");
const Dimensions = @import("Dimensions.zig");
const Dimension = @import("Dimensions.zig").Dimension;

pub const UnitScale = enum(i32) {
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

    pub fn str(self: @This()) []const u8 {
        var buf: [16]u8 = undefined;
        return switch (self) {
            .none => "",
            inline .P, .T, .G, .M, .k, .h, .da, .d, .c, .m, .u, .n, .p, .f, .min, .hour, .year => @tagName(self),
            else => std.fmt.bufPrint(&buf, "[{d}]", .{@intFromEnum(self)}) catch "[]",
        };
    }

    /// Helper to get the actual scaling factor
    pub fn getFactor(self: @This()) f64 {
        return switch (self) {
            inline .P, .T, .G, .M, .k, .h, .da, .none, .d, .c, .m, .u, .n, .p, .f => std.math.pow(f64, 10.0, @floatFromInt(@intFromEnum(self))),
            else => @floatFromInt(@intFromEnum(self)),
        };
    }

    /// Helper to get the actual scaling factor in i32
    pub fn getFactorInt(self: @This()) i32 {
        return switch (self) {
            inline .P, .T, .G, .M, .k, .h, .da, .none, .d, .c, .m, .u, .n, .p, .f => std.math.powi(i32, 10.0, @intFromEnum(self)) catch 0,
            else => @intFromEnum(self),
        };
    }
};

const Scales = @This();

data: std.EnumArray(Dimension, UnitScale),

pub fn init(comptime init_val: anytype) Scales {
    var s = Scales{ .data = std.EnumArray(Dimension, UnitScale).initFill(.none) };
    inline for (std.meta.fields(@TypeOf(init_val))) |f| {
        if (comptime hlp.isInt(@TypeOf(@field(init_val, f.name))))
            s.data.set(@field(Dimension, f.name), @enumFromInt(@field(init_val, f.name)))
        else
            s.data.set(@field(Dimension, f.name), @field(init_val, f.name));
    }
    return s;
}

pub fn initFill(val: UnitScale) Scales {
    return .{ .data = std.EnumArray(Dimension, UnitScale).initFill(val) };
}

pub fn get(self: Scales, key: Dimension) UnitScale {
    return self.data.get(key);
}

pub fn set(self: *Scales, key: Dimension, val: UnitScale) void {
    self.data.set(key, val);
}

pub fn min(comptime s1: Scales, comptime s2: Scales) Scales {
    var out = Scales.initFill(.none);
    for (std.enums.values(Dimension)) |dim|
        out.set(dim, if (s1.get(dim).getFactorInt() > s2.get(dim).getFactorInt()) s2.get(dim) else s1.get(dim));

    return out;
}

pub fn getFactor(comptime s: Scales, comptime d: Dimensions) f64 {
    var factor: f64 = 1.0;
    for (std.enums.values(Dimension)) |dim| {
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
