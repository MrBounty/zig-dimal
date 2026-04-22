const std = @import("std");
const hlp = @import("helper.zig");

const Vector = @import("Vector.zig").Vector;
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

// TODO: Add those operation:
//  - eq: Equal
//  - ne: Not equal
//  - gt: Greather than
//  - gte: Greather than or equal
//  - lt: Less than
//  - lte Less than or equal
//  - abs: Absolut value
//  - pow: Scalar power another
//  - log: Scalar log another

pub fn Scalar(comptime T: type, comptime d: Dimensions, comptime s: Scales) type {
    @setEvalBranchQuota(10_000_000);
    return struct {
        value: T,

        const Self = @This();
        pub const Vec3: type = Vector(3, Self);
        pub const ValueType: type = T;

        pub const dims: Dimensions = d;
        pub const scales = s;

        pub inline fn add(self: Self, rhs: anytype) Scalar(
            T,
            dims,
            hlp.finerScales(Self, @TypeOf(rhs)),
        ) {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ @TypeOf(rhs).dims.str());
            if (comptime @TypeOf(rhs) == Self)
                return .{ .value = self.value + rhs.value };

            const TargetType = Scalar(T, dims, hlp.finerScales(Self, @TypeOf(rhs)));
            const lhs_val = if (comptime @TypeOf(self) == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime @TypeOf(rhs) == TargetType) rhs.value else rhs.to(TargetType).value;

            return .{ .value = lhs_val + rhs_val };
        }

        pub inline fn sub(self: Self, rhs: anytype) Scalar(
            T,
            dims,
            hlp.finerScales(Self, @TypeOf(rhs)),
        ) {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in sub: " ++ dims.str() ++ " vs " ++ @TypeOf(rhs).dims.str());
            if (comptime @TypeOf(rhs) == Self)
                return .{ .value = self.value - rhs.value };

            const TargetType = Scalar(T, dims, hlp.finerScales(Self, @TypeOf(rhs)));
            const lhs_val = if (comptime @TypeOf(self) == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime @TypeOf(rhs) == TargetType) rhs.value else rhs.to(TargetType).value;

            return .{ .value = lhs_val - rhs_val };
        }

        pub inline fn mulBy(self: Self, rhs: anytype) Scalar(
            T,
            dims.add(@TypeOf(rhs).dims),
            hlp.finerScales(Self, @TypeOf(rhs)),
        ) {
            const RhsType = @TypeOf(rhs);
            const SelfNorm = Scalar(T, dims, hlp.finerScales(Self, @TypeOf(rhs)));
            const RhsNorm = Scalar(T, RhsType.dims, hlp.finerScales(Self, @TypeOf(rhs)));
            if (comptime Self == SelfNorm and RhsType == RhsNorm)
                return .{ .value = self.value * rhs.value };

            const lhs_val = if (comptime Self == SelfNorm) self.value else self.to(SelfNorm).value;
            const rhs_val = if (comptime RhsType == RhsNorm) rhs.value else rhs.to(RhsNorm).value;
            return .{ .value = lhs_val * rhs_val };
        }

        pub inline fn divBy(self: Self, rhs: anytype) Scalar(
            T,
            dims.sub(@TypeOf(rhs).dims),
            hlp.finerScales(Self, @TypeOf(rhs)),
        ) {
            const RhsType = @TypeOf(rhs);
            const SelfNorm = Scalar(T, dims, hlp.finerScales(Self, @TypeOf(rhs)));
            const RhsNorm = Scalar(T, RhsType.dims, hlp.finerScales(Self, @TypeOf(rhs)));
            const lhs_val = if (comptime Self == SelfNorm) self.value else self.to(SelfNorm).value;
            const rhs_val = if (comptime RhsType == RhsNorm) rhs.value else rhs.to(RhsNorm).value;
            if (comptime @typeInfo(T) == .int) {
                return .{ .value = @divTrunc(lhs_val, rhs_val) };
            } else {
                return .{ .value = lhs_val / rhs_val };
            }
        }

        pub inline fn to(self: Self, comptime Dest: type) Dest {
            if (comptime !dims.eql(Dest.dims))
                @compileError("Dimension mismatch in to: " ++ dims.str() ++ " vs " ++ Dest.dims.str());
            if (comptime @TypeOf(self) == Dest)
                return self;

            const DestT = Dest.ValueType;
            const ratio = comptime (scales.getFactor(dims) / Dest.scales.getFactor(Dest.dims));

            // Fast-path: Native pure-integer exact conversions
            if (comptime @typeInfo(T) == .int and @typeInfo(DestT) == .int) {
                if (comptime ratio >= 1.0 and @round(ratio) == ratio) {
                    const mult: DestT = comptime @intFromFloat(ratio);
                    return .{ .value = @as(DestT, @intCast(self.value)) * mult };
                } else if (comptime ratio < 1.0 and @round(1.0 / ratio) == 1.0 / ratio) {
                    const div: DestT = comptime @intFromFloat(1.0 / ratio);
                    const val = @as(DestT, @intCast(self.value));
                    const half = comptime div / 2;
                    const rounded = if (val >= 0) @divTrunc(val + half, div) else @divTrunc(val - half, div);
                    return .{ .value = rounded };
                }
            }

            // Fallback preserving native Float types (e.g., f128 shouldn't downcast to f64)
            if (comptime @typeInfo(DestT) == .float) {
                const val_f = switch (@typeInfo(T)) {
                    inline .int => @as(DestT, @floatFromInt(self.value)),
                    inline .float => @as(DestT, @floatCast(self.value)),
                    else => unreachable,
                };
                return .{ .value = val_f * @as(DestT, @floatCast(ratio)) };
            } else {
                const val_f = switch (@typeInfo(T)) {
                    inline .int => @as(f64, @floatFromInt(self.value)),
                    inline .float => @as(f64, @floatCast(self.value)),
                    else => unreachable,
                };
                return .{ .value = @intFromFloat(@round(val_f * ratio)) };
            }
        }

        pub fn Vec(self: Self, comptime len: comptime_int) Vector(len, Self) {
            return Vector(len, Self).initDefault(self.value);
        }

        pub fn vec3(self: Self) Vec3 {
            return Vec3.initDefault(self.value);
        }

        pub fn formatNumber(
            self: Self,
            writer: *std.Io.Writer,
            options: std.fmt.Number,
        ) !void {
            switch (@typeInfo(T)) {
                .float, .comptime_float => try writer.printFloat(self.value, options),
                .int, .comptime_int => try writer.printInt(self.value, 10, .lower, .{
                    .width = options.width,
                    .alignment = options.alignment,
                    .fill = options.fill,
                    .precision = options.precision,
                }),
                else => unreachable,
            }
            var first = true;
            inline for (std.enums.values(Dimension)) |bu| {
                const v = dims.get(bu);
                if (comptime v == 0) continue;
                if (!first)
                    try writer.writeAll(".");

                first = false;

                const uscale = scales.get(bu);
                if (bu == .T and (uscale == .min or uscale == .hour or uscale == .year))
                    try writer.print("{s}", .{uscale.str()})
                else
                    try writer.print("{s}{s}", .{ uscale.str(), bu.unit() });

                if (v != 1)
                    try hlp.printSuperscript(writer, v);
            }
        }
    };
}

test "Generate quantity" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = -3 }));
    const Second = Scalar(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{ .T = .n }));

    const distance = Meter{ .value = 10 };
    const time = Second{ .value = 2 };

    try std.testing.expectEqual(10, distance.value);
    try std.testing.expectEqual(2, time.value);
}

test "Add" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const distance = Meter{ .value = 10 };
    const distance2 = Meter{ .value = 20 };

    const added = distance.add(distance2);
    try std.testing.expectEqual(30, added.value);
    try std.testing.expectEqual(1, @TypeOf(added).dims.get(.L));

    const KiloMeter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const distance3 = KiloMeter{ .value = 2 };
    const added2 = distance.add(distance3);
    try std.testing.expectEqual(2010, added2.value);
    try std.testing.expectEqual(1, @TypeOf(added2).dims.get(.L));

    const added3 = distance3.add(distance).to(KiloMeter);
    try std.testing.expectEqual(2, added3.value);
    try std.testing.expectEqual(1, @TypeOf(added3).dims.get(.L));

    const KiloMeter_f = Scalar(f64, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const distance4 = KiloMeter_f{ .value = 2 };
    const added4 = distance4.add(distance).to(KiloMeter_f);
    try std.testing.expectApproxEqAbs(2.01, added4.value, 0.000001);
    try std.testing.expectEqual(1, @TypeOf(added4).dims.get(.L));
}

test "Sub" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const KiloMeter_f = Scalar(f64, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));

    const a = Meter{ .value = 500 };
    const b = Meter{ .value = 200 };
    const diff = a.sub(b);
    try std.testing.expectEqual(300, diff.value);
    const diff2 = b.sub(a);
    try std.testing.expectEqual(-300, diff2.value);

    const km_f = KiloMeter_f{ .value = 2.5 };
    const m_f = Meter{ .value = 500 };
    const diff3 = km_f.sub(m_f);
    try std.testing.expectApproxEqAbs(2000, diff3.value, 1e-4);
}

test "MulBy" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Scalar(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const d = Meter{ .value = 3.0 };
    const t = Second{ .value = 4.0 };

    const area_time = d.mulBy(t);
    try std.testing.expectEqual(12, area_time.value);
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));

    const d2 = Meter{ .value = 5.0 };
    const area = d.mulBy(d2);
    try std.testing.expectEqual(15, area.value);
    try std.testing.expectEqual(2, @TypeOf(area).dims.get(.L));
    try std.testing.expectEqual(0, @TypeOf(area).dims.get(.T));
}

test "MulBy with scale" {
    const KiloMeter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const KiloGram = Scalar(f32, Dimensions.init(.{ .M = 1 }), Scales.init(.{ .M = .k }));

    const dist = KiloMeter{ .value = 2.0 };
    const mass = KiloGram{ .value = 3.0 };
    const prod = dist.mulBy(mass);
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.M));
}

test "MulBy with type change" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const Second = Scalar(f64, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));
    const KmSec = Scalar(i64, Dimensions.init(.{ .L = 1, .T = 1 }), Scales.init(.{ .L = .k }));
    const KmSec_f = Scalar(f32, Dimensions.init(.{ .L = 1, .T = 1 }), Scales.init(.{ .L = .k }));

    const d = Meter{ .value = 3.0 };
    const t = Second{ .value = 4.0 };

    const area_time = d.mulBy(t).to(KmSec);
    const area_time_f = d.mulBy(t).to(KmSec_f);
    try std.testing.expectEqual(12, area_time.value);
    try std.testing.expectApproxEqAbs(12, area_time_f.value, 0.0001);
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));
}

test "MulBy small" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .n }));
    const Second = Scalar(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const d = Meter{ .value = 3.0 };
    const t = Second{ .value = 4.0 };

    const area_time = d.mulBy(t);
    try std.testing.expectEqual(12, area_time.value);
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));
}

test "MulBy dimensionless" {
    const DimLess = Scalar(i128, Dimensions.init(.{}), Scales.init(.{}));
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const d = Meter{ .value = 7 };
    const scaled = d.mulBy(DimLess{ .value = 3 });
    try std.testing.expectEqual(21, scaled.value);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
}

test "Chained: velocity and acceleration" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Scalar(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const dist = Meter{ .value = 100.0 };
    const t1 = Second{ .value = 5.0 };
    const velocity = dist.divBy(t1);
    try std.testing.expectEqual(20, velocity.value);
    try std.testing.expectEqual(1, @TypeOf(velocity).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(velocity).dims.get(.T));

    const t2 = Second{ .value = 4.0 };
    const accel = velocity.divBy(t2);
    try std.testing.expectEqual(5, accel.value);
    try std.testing.expectEqual(1, @TypeOf(accel).dims.get(.L));
    try std.testing.expectEqual(-2, @TypeOf(accel).dims.get(.T));
}

test "DivBy integer exact" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Scalar(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const dist = Meter{ .value = 120 };
    const time = Second{ .value = 4 };
    const vel = dist.divBy(time);

    try std.testing.expectEqual(30, vel.value);
    try std.testing.expectEqual(1, @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(vel).dims.get(.T));
}

test "Finer scales skip dim 0" {
    const Dimless = Scalar(i128, Dimensions.init(.{}), Scales.init(.{}));
    const KiloMetre = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));

    const r = Dimless{ .value = 30 };
    const time = KiloMetre{ .value = 4 };
    const vel = r.mulBy(time);

    try std.testing.expectEqual(120, vel.value);
    try std.testing.expectEqual(Scales.UnitScale.k, @TypeOf(vel).scales.get(.L));
}

test "Conversion chain: km -> m -> cm" {
    const KiloMeter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const CentiMeter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .c }));

    const km = KiloMeter{ .value = 15 };
    const m = km.to(Meter);
    const cm = m.to(CentiMeter);

    try std.testing.expectEqual(15_000, m.value);
    try std.testing.expectEqual(1_500_000, cm.value);
}

test "Conversion: hours -> minutes -> seconds" {
    const Hour = Scalar(i128, Dimensions.init(.{ .T = 1 }), Scales.init(.{ .T = .hour }));
    const Minute = Scalar(i128, Dimensions.init(.{ .T = 1 }), Scales.init(.{ .T = .min }));
    const Second = Scalar(i128, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const h = Hour{ .value = 1.0 };
    const min = h.to(Minute);
    const sec = min.to(Second);

    try std.testing.expectEqual(60, min.value);
    try std.testing.expectEqual(3600, sec.value);
}

test "Negative values" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const a = Meter{ .value = 5 };
    const b = Meter{ .value = 20 };
    const diff = a.sub(b);
    try std.testing.expectEqual(-15, diff.value);
}

test "Format Scalar" {
    const MeterPerSecondSq = Scalar(
        f32,
        Dimensions.init(.{ .L = 1, .T = -2 }),
        Scales.init(.{ .T = .n }),
    );
    const KgMeterPerSecond = Scalar(
        f32,
        Dimensions.init(.{ .M = 1, .L = 1, .T = -1 }),
        Scales.init(.{ .M = .k }),
    );
    const Meter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const m = Meter{ .value = 1.23456 };
    const accel = MeterPerSecondSq{ .value = 9.81 };
    const momentum = KgMeterPerSecond{ .value = 42.0 };

    var buf: [64]u8 = undefined;
    var res = try std.fmt.bufPrint(&buf, "{d:.2}", .{m});
    try std.testing.expectEqualStrings("1.23m", res);

    res = try std.fmt.bufPrint(&buf, "{d}", .{accel});
    try std.testing.expectEqualStrings("9.81m.ns⁻²", res);

    res = try std.fmt.bufPrint(&buf, "{d}", .{momentum});
    try std.testing.expectEqualStrings("42m.kg.s⁻¹", res);

    res = try std.fmt.bufPrint(&buf, "{d:_>10.1}", .{m});
    try std.testing.expectEqualStrings("_______1.2m", res);
}
