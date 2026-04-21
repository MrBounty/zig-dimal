const std = @import("std");
const hlp = @import("helper.zig");

const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

pub fn Quantity(T: type, d: Dimensions, s: Scales) type {
    return struct {
        value: T,

        const Self = @This();
        pub const Vec3: type = QuantityVec3(Self);
        pub const ValueType: type = T;

        pub const dims: Dimensions = d;
        pub const scales = s;

        pub fn add(self: Self, rhs: anytype) Quantity(
            T,
            dims,
            scales.min(@TypeOf(rhs).scales),
        ) {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ @TypeOf(rhs).dims.str());

            const TargetType = Quantity(T, dims, scales.min(@TypeOf(rhs).scales));
            const lhs_converted = self.to(TargetType);
            const rhs_converted = rhs.to(TargetType);

            return .{ .value = lhs_converted.value + rhs_converted.value };
        }

        pub fn sub(self: Self, rhs: anytype) Quantity(
            T,
            dims,
            scales.min(@TypeOf(rhs).scales),
        ) {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in sub: " ++ dims.str() ++ " vs " ++ @TypeOf(rhs).dims.str());

            const TargetType = Quantity(T, dims, scales.min(@TypeOf(rhs).scales));
            const lhs_converted = self.to(TargetType);
            const rhs_converted = rhs.to(TargetType);

            return .{ .value = lhs_converted.value - rhs_converted.value };
        }

        pub fn mulBy(self: Self, rhs: anytype) Quantity(
            T,
            dims.add(@TypeOf(rhs).dims),
            scales.min(@TypeOf(rhs).scales),
        ) {
            const self_ = self.to(Quantity(T, dims, scales.min(@TypeOf(rhs).scales)));
            const rhs_ = rhs.to(Quantity(T, @TypeOf(rhs).dims, scales.min(@TypeOf(rhs).scales)));
            return .{ .value = self_.value * rhs_.value };
        }

        pub fn divBy(self: Self, rhs: anytype) Quantity(T, dims.sub(@TypeOf(rhs).dims), scales.min(@TypeOf(rhs).scales)) {
            const self_ = self.to(Quantity(T, dims, scales.min(@TypeOf(rhs).scales)));
            const rhs_ = rhs.to(Quantity(T, @TypeOf(rhs).dims, scales.min(@TypeOf(rhs).scales)));

            if (comptime @typeInfo(T) == .int) {
                return .{ .value = @divTrunc(self_.value, rhs_.value) };
            } else {
                return .{ .value = self_.value / rhs_.value };
            }
        }

        pub fn scale(self: Self, sc: T) Self {
            return .{ .value = self.value * sc };
        }

        pub fn to(self: Self, comptime Dest: type) Dest {
            if (comptime !dims.eql(Dest.dims))
                @compileError("Dimension mismatch in to: " ++ dims.str() ++ " vs " ++ Dest.dims.str());
            if (comptime @TypeOf(self) == Dest)
                return self;

            const DestT = Dest.ValueType;
            const ratio = comptime (scales.getFactor(dims) / Dest.scales.getFactor(Dest.dims));

            // Fast-path: Native pure-integer exact conversions
            if (comptime @typeInfo(T) == .int and @typeInfo(DestT) == .int) {
                if (ratio >= 1.0 and @round(ratio) == ratio) {
                    const mult: DestT = @intFromFloat(ratio);
                    return .{ .value = @as(DestT, @intCast(self.value)) * mult };
                } else if (ratio < 1.0 and @round(1.0 / ratio) == 1.0 / ratio) {
                    const div: DestT = @intFromFloat(1.0 / ratio);
                    const val = @as(DestT, @intCast(self.value));
                    const half = div / 2;
                    // Native round-to-nearest
                    const rounded = if (val >= 0) @divTrunc(val + half, div) else @divTrunc(val - half, div);
                    return .{ .value = rounded };
                }
            }

            // Fallback preserving native Float types (e.g., f128 shouldn't downcast to f64)
            if (comptime @typeInfo(DestT) == .float) {
                const val_f = switch (@typeInfo(T)) {
                    .int => @as(DestT, @floatFromInt(self.value)),
                    .float => @as(DestT, @floatCast(self.value)),
                    else => unreachable,
                };
                return .{ .value = val_f * @as(DestT, @floatCast(ratio)) };
            } else {
                const val_f = switch (@typeInfo(T)) {
                    .int => @as(f64, @floatFromInt(self.value)),
                    .float => @as(f64, @floatCast(self.value)),
                    else => unreachable,
                };
                return .{ .value = @intFromFloat(@round(val_f * ratio)) };
            }
        }
        pub fn vec3(self: Self) Vec3 {
            return .{ .x = self.value, .y = self.value, .z = self.value };
        }

        pub fn format(
            self: Self,
            writer: *std.Io.Writer,
        ) !void {
            try writer.print("{d}", .{self.value});
            var iter = std.EnumSet(Dimension).initFull().iterator();
            var first = true;
            while (iter.next()) |bu| {
                const v = dims.get(bu);
                if (v == 0) continue;
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

pub fn QuantityVec3(Q: type) type {
    const T = Q.ValueType;
    const d: Dimensions = Q.dims;
    const s: Scales = Q.scales;

    return struct {
        x: T,
        y: T,
        z: T,

        const Self = @This();
        pub const QuantityType = Q;
        pub const ValueType = T;
        pub const dims: Dimensions = d;
        pub const scales = s;

        pub const zero = Self{ .x = 0, .y = 0, .z = 0 };
        pub const one = Self{ .x = 1, .y = 1, .z = 1 };

        pub fn initDefault(v: T) Self {
            return .{ .x = v, .y = v, .z = v };
        }

        pub fn add(self: Self, rhs: anytype) QuantityVec3(Quantity(T, d, s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            // We leverage the logic in the scalar Quantity.add
            const qx = (Q{ .value = self.x }).add(Tr.QuantityType{ .value = rhs.x });
            const qy = (Q{ .value = self.y }).add(Tr.QuantityType{ .value = rhs.y });
            const qz = (Q{ .value = self.z }).add(Tr.QuantityType{ .value = rhs.z });

            return .{
                .x = qx.value,
                .y = qy.value,
                .z = qz.value,
            };
        }

        pub fn sub(self: Self, rhs: anytype) QuantityVec3(Quantity(T, d, s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            const qx = (Q{ .value = self.x }).sub(Tr.QuantityType{ .value = rhs.x });
            const qy = (Q{ .value = self.y }).sub(Tr.QuantityType{ .value = rhs.y });
            const qz = (Q{ .value = self.z }).sub(Tr.QuantityType{ .value = rhs.z });

            return .{
                .x = qx.value,
                .y = qy.value,
                .z = qz.value,
            };
        }

        pub fn divBy(
            self: Self,
            rhs: anytype,
        ) QuantityVec3(Quantity(T, d.sub(@TypeOf(rhs).dims), s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            return .{
                .x = (Q{ .value = self.x }).divBy(Tr.QuantityType{ .value = rhs.x }).value,
                .y = (Q{ .value = self.y }).divBy(Tr.QuantityType{ .value = rhs.y }).value,
                .z = (Q{ .value = self.z }).divBy(Tr.QuantityType{ .value = rhs.z }).value,
            };
        }

        pub fn mulBy(
            self: Self,
            rhs: anytype,
        ) QuantityVec3(Quantity(T, d.sub(@TypeOf(rhs).dims), s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            return .{
                .x = (Q{ .value = self.x }).mulBy(Tr.QuantityType{ .value = rhs.x }).value,
                .y = (Q{ .value = self.y }).mulBy(Tr.QuantityType{ .value = rhs.y }).value,
                .z = (Q{ .value = self.z }).mulBy(Tr.QuantityType{ .value = rhs.z }).value,
            };
        }

        pub fn divByScalar(
            self: Self,
            scalar: anytype,
        ) QuantityVec3(Quantity(T, d.sub(@TypeOf(scalar).dims), s.min(@TypeOf(scalar).scales))) {
            const q_x = Q{ .value = self.x };
            const q_y = Q{ .value = self.y };
            const q_z = Q{ .value = self.z };

            return .{
                .x = q_x.divBy(scalar).value,
                .y = q_y.divBy(scalar).value,
                .z = q_z.divBy(scalar).value,
            };
        }

        pub fn mulByScalar(
            self: Self,
            scalar: anytype,
        ) QuantityVec3(Quantity(T, d.add(@TypeOf(scalar).dims), s.min(@TypeOf(scalar).scales))) {
            const q_x = Q{ .value = self.x };
            const q_y = Q{ .value = self.y };
            const q_z = Q{ .value = self.z };

            return .{
                .x = q_x.mulBy(scalar).value,
                .y = q_y.mulBy(scalar).value,
                .z = q_z.mulBy(scalar).value,
            };
        }

        pub fn negate(self: Self) Self {
            return .{ .x = -self.x, .y = -self.y, .z = -self.z };
        }

        pub fn scale(self: Self, rhs: T) Self {
            return .{
                .x = (Q{ .value = self.x }).scale(rhs).value,
                .y = (Q{ .value = self.y }).scale(rhs).value,
                .z = (Q{ .value = self.z }).scale(rhs).value,
            };
        }

        pub fn to(self: Self, comptime DestQ: type) QuantityVec3(DestQ) {
            return .{
                .x = (Q{ .value = self.x }).to(DestQ).value,
                .y = (Q{ .value = self.y }).to(DestQ).value,
                .z = (Q{ .value = self.z }).to(DestQ).value,
            };
        }

        pub fn lengthSqr(self: Self) T {
            return self.x * self.x + self.y * self.y + self.z * self.z;
        }

        pub fn length(self: Self) T {
            const len_sq = self.lengthSqr();

            if (comptime @typeInfo(T) == .int) {
                // Construct the unsigned equivalent of T at comptime (e.g., i32 -> u32)
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);

                // len_sq is always positive, so @intCast is perfectly safe
                const u_len_sq = @as(UnsignedT, @intCast(len_sq));
                return @as(T, @intCast(std.math.sqrt(u_len_sq)));
            } else {
                return @sqrt(len_sq);
            }
        }

        pub fn format(self: Self, writer: *std.Io.Writer) !void {
            try writer.print("({d:.2}, {d:.2}, {d:.2})", .{ self.x, self.y, self.z });
            var iter = std.EnumSet(Dimension).initFull().iterator();
            var first = true;
            while (iter.next()) |bu| {
                const v = dims.get(bu);
                if (v == 0) continue;
                if (!first) try writer.writeAll(".");
                first = false;
                try writer.print("{s}{s}", .{ scales.get(bu).str(), bu.unit() });
                if (v != 1) try hlp.printSuperscript(writer, v);
            }
        }
    };
}

pub fn main(_: std.process.Init) void {}

test "Generate quantity" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = -3 }));
    const Second = Quantity(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{ .T = .n }));

    const distance = Meter{ .value = 10 };
    const time = Second{ .value = 2 };

    try std.testing.expectEqual(10, distance.value);
    try std.testing.expectEqual(2, time.value);
}

test "Add" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const distance = Meter{ .value = 10 };
    const distance2 = Meter{ .value = 20 };

    const added = distance.add(distance2);
    try std.testing.expectEqual(30, added.value);
    try std.testing.expectEqual(1, @TypeOf(added).dims.get(.L));
    std.debug.print("KiloMeter {f} + {f} = {f} OK\n", .{ distance, distance2, added });

    const KiloMeter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const distance3 = KiloMeter{ .value = 2 };
    const added2 = distance.add(distance3);
    try std.testing.expectEqual(2010, added2.value);
    try std.testing.expectEqual(1, @TypeOf(added2).dims.get(.L));
    std.debug.print("KiloMeter {f} + {f} = {f} OK\n", .{ distance, distance3, added2 });

    const added3 = distance3.add(distance).to(KiloMeter);
    try std.testing.expectEqual(2, added3.value);
    try std.testing.expectEqual(1, @TypeOf(added3).dims.get(.L));
    std.debug.print("KiloMeter {f} + {f} = {f} OK\n", .{ distance3, distance, added3 });

    const KiloMeter_f = Quantity(f64, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const distance4 = KiloMeter_f{ .value = 2 };
    const added4 = distance4.add(distance).to(KiloMeter_f);
    try std.testing.expectApproxEqAbs(2.01, added4.value, 0.000001);
    try std.testing.expectEqual(1, @TypeOf(added4).dims.get(.L));
    std.debug.print("KiloMeter_f {f} + {f} = {f} OK\n", .{ distance4, distance, added4 });
}

test "Sub" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const KiloMeter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const KiloMeter_f = Quantity(f64, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));

    const a = Meter{ .value = 500 };
    const b = Meter{ .value = 200 };
    const diff = a.sub(b);
    try std.testing.expectEqual(300, diff.value);
    std.debug.print("Sub: {f} - {f} = {f} OK\n", .{ a, b, diff });

    const km = KiloMeter{ .value = 1 };
    const diff2 = a.sub(km);
    std.debug.print("Sub cross-scale: {f} - {f} = {f}\n", .{ a, km, diff2 });

    const km_f = KiloMeter_f{ .value = 2.5 };
    const m_f = Meter{ .value = 500 };
    const diff3 = km_f.sub(m_f);
    try std.testing.expectApproxEqAbs(2000, diff3.value, 1e-4);
    std.debug.print("Sub float cross-scale: {f} - {f} = {f} OK\n", .{ km_f, m_f, diff3 });
}

test "MulBy" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Quantity(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const d = Meter{ .value = 3.0 };
    const t = Second{ .value = 4.0 };

    const area_time = d.mulBy(t);
    try std.testing.expectEqual(12, area_time.value);
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));
    std.debug.print("MulBy: {f} * {f} = {f} OK\n", .{ d, t, area_time });

    const d2 = Meter{ .value = 5.0 };
    const area = d.mulBy(d2);
    try std.testing.expectEqual(15, area.value);
    try std.testing.expectEqual(2, @TypeOf(area).dims.get(.L));
    try std.testing.expectEqual(0, @TypeOf(area).dims.get(.T));
    std.debug.print("MulBy: {f} * {f} = {f} OK\n", .{ d, d2, area });
}

test "MulBy with scale" {
    const KiloMeter = Quantity(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const KiloGram = Quantity(f32, Dimensions.init(.{ .M = 1 }), Scales.init(.{ .M = .k }));

    const dist = KiloMeter{ .value = 2.0 };
    const mass = KiloGram{ .value = 3.0 };
    const prod = dist.mulBy(mass);
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.M));
    std.debug.print("MulBy scaled: {f} * {f} = {f} OK\n", .{ dist, mass, prod });
}

test "MulBy with type change" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const Second = Quantity(f64, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));
    const KmSec = Quantity(i64, Dimensions.init(.{ .L = 1, .T = 1 }), Scales.init(.{ .L = .k }));
    const KmSec_f = Quantity(f32, Dimensions.init(.{ .L = 1, .T = 1 }), Scales.init(.{ .L = .k }));

    const d = Meter{ .value = 3.0 };
    const t = Second{ .value = 4.0 };

    const area_time = d.mulBy(t).to(KmSec);
    const area_time_f = d.mulBy(t).to(KmSec_f);
    try std.testing.expectEqual(12, area_time.value);
    try std.testing.expectApproxEqAbs(12, area_time_f.value, 0.0001);
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));
    std.debug.print("MulBy: {f} * {f} = {f} OK\n", .{ d, t, area_time });
}

test "MulBy small" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .n }));
    const Second = Quantity(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const d = Meter{ .value = 3.0 };
    const t = Second{ .value = 4.0 };

    const area_time = d.mulBy(t);
    try std.testing.expectEqual(12, area_time.value);
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));
    std.debug.print("MulBy: {f} * {f} = {f} OK\n", .{ d, t, area_time });
}

test "Scale" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Quantity(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const d = Meter{ .value = 7 };
    const scaled = d.scale(3);
    try std.testing.expectEqual(21, scaled.value);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
    std.debug.print("Scale int: {f} * 3 = {f} OK\n", .{ d, scaled });

    const t = Second{ .value = 1.5 };
    const scaled_f = t.scale(4.0);
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), scaled_f.value, 1e-4);
    std.debug.print("Scale float: {f} * 4 = {f} OK\n", .{ t, scaled_f });
}

test "Chained: velocity and acceleration" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Quantity(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

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

    std.debug.print("Velocity: {f}, Acceleration: {f} OK\n", .{ velocity, accel });
}

test "DivBy integer exact" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Quantity(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const dist = Meter{ .value = 120 };
    const time = Second{ .value = 4 };
    const vel = dist.divBy(time);

    try std.testing.expectEqual(30, vel.value);
    try std.testing.expectEqual(1, @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(vel).dims.get(.T));
    std.debug.print("DivBy int: {f} / {f} = {f} OK\n", .{ dist, time, vel });
}

test "Conversion chain: km -> m -> cm" {
    const KiloMeter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const CentiMeter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .c }));

    const km = KiloMeter{ .value = 15 };
    const m = km.to(Meter);
    const cm = m.to(CentiMeter);

    try std.testing.expectEqual(15_000, m.value);
    try std.testing.expectEqual(1_500_000, cm.value);
    std.debug.print("Chain: {f} -> {f} -> {f} OK\n", .{ km, m, cm });
}

test "Conversion: hours -> minutes -> seconds" {
    const Hour = Quantity(i128, Dimensions.init(.{ .T = 1 }), Scales.init(.{ .T = .hour }));
    const Minute = Quantity(i128, Dimensions.init(.{ .T = 1 }), Scales.init(.{ .T = .min }));
    const Second = Quantity(i128, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

    const h = Hour{ .value = 1.0 };
    const min = h.to(Minute);
    const sec = min.to(Second);

    try std.testing.expectEqual(60, min.value);
    try std.testing.expectEqual(3600, sec.value);
    std.debug.print("Time chain: {f} -> {f} -> {f} OK\n", .{ h, min, sec });
}

test "Negative values" {
    const Meter = Quantity(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const a = Meter{ .value = 5 };
    const b = Meter{ .value = 20 };
    const diff = a.sub(b);
    try std.testing.expectEqual(-15, diff.value);
    std.debug.print("Negative sub: {f} - {f} = {f} OK\n", .{ a, b, diff });
}

test "Format Quantity" {
    const MeterPerSecondSq = Quantity(
        f32,
        Dimensions.init(.{ .L = 1, .T = -2 }),
        Scales.init(.{ .T = .n }),
    );
    const KgMeterPerSecond = Quantity(
        f32,
        Dimensions.init(.{ .M = 1, .L = 1, .T = -1 }),
        Scales.init(.{ .M = .k }),
    );

    const accel = MeterPerSecondSq{ .value = 9.81 };
    const momentum = KgMeterPerSecond{ .value = 42.0 };

    std.debug.print("Acceleration: {f}\n", .{accel});
    std.debug.print("Momentum: {f}\n", .{momentum});
}

test "Format Vector3" {
    const MeterPerSecondSq = Quantity(
        f32,
        Dimensions.init(.{ .L = 1, .T = -2 }),
        Scales.init(.{ .T = .n }),
    );
    const KgMeterPerSecond = Quantity(
        f32,
        Dimensions.init(.{ .M = 1, .L = 1, .T = -1 }),
        Scales.init(.{ .M = .k }),
    );

    const accel = MeterPerSecondSq.Vec3.initDefault(9.81);
    const momentum = KgMeterPerSecond.Vec3{ .x = 43, .y = 0, .z = 11 };

    std.debug.print("Acceleration: {f}\n", .{accel});
    std.debug.print("Momentum: {f}\n", .{momentum});
}

test "Vec3 Init and Basic Arithmetic" {
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    // Test zero, one, initDefault
    const v_zero = Vec3M.zero;
    try std.testing.expectEqual(0, v_zero.x);

    const v_one = Vec3M.one;
    try std.testing.expectEqual(1, v_one.x);

    const v_def = Vec3M.initDefault(5);
    try std.testing.expectEqual(5, v_def.x);
    try std.testing.expectEqual(5, v_def.y);
    try std.testing.expectEqual(5, v_def.z);

    // Test add and sub
    const v1 = Vec3M{ .x = 10, .y = 20, .z = 30 };
    const v2 = Vec3M{ .x = 2, .y = 4, .z = 6 };

    const added = v1.add(v2);
    try std.testing.expectEqual(12, added.x);
    try std.testing.expectEqual(24, added.y);
    try std.testing.expectEqual(36, added.z);

    const subbed = v1.sub(v2);
    try std.testing.expectEqual(8, subbed.x);
    try std.testing.expectEqual(16, subbed.y);
    try std.testing.expectEqual(24, subbed.z);

    // Test negate
    const neg = v1.negate();
    try std.testing.expectEqual(-10, neg.x);
    try std.testing.expectEqual(-20, neg.y);
    try std.testing.expectEqual(-30, neg.z);
}

test "Vec3 Kinematics (Scalar Mul/Div)" {
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Quantity(i32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    const pos = Vec3M{ .x = 100, .y = 200, .z = 300 };
    const time = Second{ .value = 10 };

    // Vector divided by scalar Quantity (Velocity = Position / Time)
    const vel = pos.divByScalar(time);
    try std.testing.expectEqual(10, vel.x);
    try std.testing.expectEqual(20, vel.y);
    try std.testing.expectEqual(30, vel.z);
    try std.testing.expectEqual(1, @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(vel).dims.get(.T));

    // Vector multiplied by scalar Quantity (Position = Velocity * Time)
    const new_pos = vel.mulByScalar(time);
    try std.testing.expectEqual(100, new_pos.x);
    try std.testing.expectEqual(200, new_pos.y);
    try std.testing.expectEqual(300, new_pos.z);
    try std.testing.expectEqual(1, @TypeOf(new_pos).dims.get(.L));
    try std.testing.expectEqual(0, @TypeOf(new_pos).dims.get(.T));
}

test "Vec3 Element-wise Math and Scaling" {
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    const v1 = Vec3M{ .x = 10, .y = 20, .z = 30 };
    const v2 = Vec3M{ .x = 2, .y = 5, .z = 10 };

    // Element-wise division
    const div = v1.divBy(v2);
    try std.testing.expectEqual(5, div.x);
    try std.testing.expectEqual(4, div.y);
    try std.testing.expectEqual(3, div.z);
    try std.testing.expectEqual(0, @TypeOf(div).dims.get(.L)); // M / M = Dimensionless

    // Scale by primitive
    const scaled = v1.scale(2);
    try std.testing.expectEqual(20, scaled.x);
    try std.testing.expectEqual(40, scaled.y);
    try std.testing.expectEqual(60, scaled.z);
}

test "Vec3 Conversions" {
    const KiloMeter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const v_km = KiloMeter.Vec3{ .x = 1, .y = 2, .z = 3 };
    const v_m = v_km.to(Meter);

    try std.testing.expectEqual(1000, v_m.x);
    try std.testing.expectEqual(2000, v_m.y);
    try std.testing.expectEqual(3000, v_m.z);

    // Type checking the result
    try std.testing.expectEqual(1, @TypeOf(v_m).dims.get(.L));
    try std.testing.expectEqual(UnitScale.none, @TypeOf(v_m).scales.get(.L));
}

test "Vec3 Length" {
    const MeterInt = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const MeterFloat = Quantity(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    // Integer length (using your custom isqrt)
    // 3-4-5 triangle on XY plane
    const v_int = MeterInt.Vec3{ .x = 3, .y = 4, .z = 0 };
    try std.testing.expectEqual(25, v_int.lengthSqr());
    try std.testing.expectEqual(5, v_int.length());

    // Float length
    const v_float = MeterFloat.Vec3{ .x = 3.0, .y = 4.0, .z = 0.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), v_float.lengthSqr(), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), v_float.length(), 1e-4);
}

test "Comprehensive Benchmark: All Ops × All Types" {
    const Io = std.Io;
    const ITERS: usize = 100_000;
    const SAMPLES: usize = 10; // Number of samples for stats

    var gsink: f64 = 0;
    const io = std.testing.io;

    // Standard Zig 0.16 timestamp retrieval
    const getTime = struct {
        fn f(i: Io) Io.Timestamp {
            return Io.Clock.awake.now(i);
        }
    }.f;

    const fold = struct {
        fn f(comptime TT: type, s: *f64, v: TT) void {
            s.* += if (comptime @typeInfo(TT) == .float)
                @as(f64, @floatCast(v))
            else
                @as(f64, @floatFromInt(v));
        }
    }.f;

    const getVal = struct {
        fn f(comptime TT: type, i: usize, comptime mask: u7) TT {
            const v: u8 = @as(u8, @truncate(i & @as(usize, mask))) + 1;
            return if (comptime @typeInfo(TT) == .float) @floatFromInt(v) else @intCast(v);
        }
    }.f;

    const Stats = struct {
        median: f64,
        delta: f64,
        ops_per_sec: f64,
    };

    const computeStats = struct {
        fn f(samples: []f64, iters: usize) Stats {
            std.mem.sort(f64, samples, {}, std.sort.asc(f64));
            const mid = samples.len / 2;
            const median_ns = if (samples.len % 2 == 0) (samples[mid - 1] + samples[mid]) / 2.0 else samples[mid];

            const low = samples[0];
            const high = samples[samples.len - 1];
            const delta_ns = (high - low) / 2.0;

            const ns_per_op = median_ns / @as(f64, @floatFromInt(iters));
            return .{
                .median = ns_per_op,
                .delta = (delta_ns / @as(f64, @floatFromInt(iters))),
                .ops_per_sec = 1_000_000_000.0 / ns_per_op,
            };
        }
    }.f;

    std.debug.print(
        \\
        \\ Quantity<T> benchmark — {d} iterations, {d} samples/cell
        \\
        \\┌───────────────────┬──────┬─────────────────────┬─────────────────────┐
        \\│ Operation         │ Type │ ns / op (± delta)   │ Throughput (ops/s)  │
        \\├───────────────────┼──────┼─────────────────────┼─────────────────────┤
        \\
    , .{ ITERS, SAMPLES });

    const Types = .{ i16, i32, i64, i128, i256, f32, f64, f128 };
    const TNames = .{ "i16", "i32", "i64", "i128", "i256", "f32", "f64", "f128" };
    const Ops = .{ "add", "sub", "mulBy", "divBy", "scale", "to" };

    var results_matrix: [Ops.len][Types.len]f64 = undefined;

    comptime var tidx: usize = 0;
    inline for (Types, TNames) |T, tname| {
        const M = Quantity(T, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
        const KM = Quantity(T, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
        const S = Quantity(T, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

        inline for (Ops, 0..) |op_name, oidx| {
            var samples: [SAMPLES]f64 = undefined;

            for (0..SAMPLES) |s_idx| {
                var sink: T = 0;
                const t_start = getTime(io);

                for (0..ITERS) |i| {
                    const r = if (comptime std.mem.eql(u8, op_name, "add"))
                        (M{ .value = getVal(T, i, 63) }).add(M{ .value = getVal(T, i +% 7, 63) })
                    else if (comptime std.mem.eql(u8, op_name, "sub"))
                        (M{ .value = getVal(T, i +% 10, 63) }).sub(M{ .value = getVal(T, i, 63) })
                    else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                        (M{ .value = getVal(T, i, 63) }).mulBy(M{ .value = getVal(T, i +% 1, 63) })
                    else if (comptime std.mem.eql(u8, op_name, "divBy"))
                        (M{ .value = getVal(T, i +% 10, 63) }).divBy(S{ .value = getVal(T, i, 63) })
                    else if (comptime std.mem.eql(u8, op_name, "scale"))
                        (M{ .value = getVal(T, i, 63) }).scale(getVal(T, i +% 2, 63))
                    else
                        (KM{ .value = getVal(T, i, 15) }).to(M);

                    if (comptime @typeInfo(T) == .float) sink += r.value else sink ^= r.value;
                }

                const t_end = getTime(io);
                samples[s_idx] = @as(f64, @floatFromInt(t_start.durationTo(t_end).toNanoseconds()));
                fold(T, &gsink, sink);
            }

            const stats = computeStats(&samples, ITERS);
            results_matrix[oidx][tidx] = stats.median;

            std.debug.print("│ {s:<17} │ {s:<4} │ {d:>8.2} ns ±{d:<6.2} │ {d:>19.0} │\n", .{ op_name, tname, stats.median, stats.delta, stats.ops_per_sec });
        }

        if (comptime tidx < Types.len - 1) {
            std.debug.print("├───────────────────┼──────┼─────────────────────┼─────────────────────┤\n", .{});
        }
        tidx += 1;
    }

    // Median Summary Table
    std.debug.print("└───────────────────┴──────┴─────────────────────┴─────────────────────┘\n\n", .{});
    std.debug.print("Median Summary (ns/op):\n", .{});

    std.debug.print("┌──────────────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┐\n", .{});
    std.debug.print("│  Operation   │  i16  │  i32  │  i64  │  i128 │  i256 │  f32  │  f64  │  f128 │\n", .{});
    std.debug.print("├──────────────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┤\n", .{});

    inline for (Ops, 0..) |op_name, oidx| {
        std.debug.print("│  {s:<11} │", .{op_name});
        var i: usize = 0;
        while (i < Types.len) : (i += 1) {
            std.debug.print("{d:>6.1} │", .{results_matrix[oidx][i]});
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("└──────────────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘\n", .{});

    std.debug.print("\nAnti-optimisation sink: {d:.4}\n", .{gsink});
    try std.testing.expect(gsink != 0);
}
