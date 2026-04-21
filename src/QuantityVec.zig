const std = @import("std");
const hlp = @import("helper.zig");

const Quantity = @import("Quantity.zig").Quantity;
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

pub fn QuantityVec(comptime len: usize, comptime Q: type) type {
    const T = Q.ValueType;
    const d: Dimensions = Q.dims;
    const s: Scales = Q.scales;

    return struct {
        data: [len]T,

        const Self = @This();
        pub const QuantityType = Q;
        pub const ValueType = T;
        pub const dims: Dimensions = d;
        pub const scales = s;

        pub const zero = initDefault(0);
        pub const one = initDefault(1);

        pub fn initDefault(v: T) Self {
            var data: [len]T = undefined;
            for (&data) |*item| item.* = v;
            return .{ .data = data };
        }

        pub fn add(self: Self, rhs: anytype) QuantityVec(len, Quantity(T, d, s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            var res: QuantityVec(len, Quantity(T, d, s.min(Tr.scales))) = undefined;
            for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).add(Tr.QuantityType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }

        pub fn sub(self: Self, rhs: anytype) QuantityVec(len, Quantity(T, d, s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            var res: QuantityVec(len, Quantity(T, d, s.min(Tr.scales))) = undefined;
            for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).sub(Tr.QuantityType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }

        pub fn divBy(
            self: Self,
            rhs: anytype,
        ) QuantityVec(len, Quantity(T, d.sub(@TypeOf(rhs).dims), s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            var res: QuantityVec(len, Quantity(T, d.sub(Tr.dims), s.min(Tr.scales))) = undefined;
            for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).divBy(Tr.QuantityType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }

        pub fn mulBy(
            self: Self,
            rhs: anytype,
        ) QuantityVec(len, Quantity(T, d.add(@TypeOf(rhs).dims), s.min(@TypeOf(rhs).scales))) {
            const Tr = @TypeOf(rhs);
            var res: QuantityVec(len, Quantity(T, d.add(Tr.dims), s.min(Tr.scales))) = undefined;
            for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).mulBy(Tr.QuantityType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }

        pub fn divByScalar(
            self: Self,
            scalar: anytype,
        ) QuantityVec(len, Quantity(T, d.sub(@TypeOf(scalar).dims), s.min(@TypeOf(scalar).scales))) {
            var res: QuantityVec(len, Quantity(T, d.sub(@TypeOf(scalar).dims), s.min(@TypeOf(scalar).scales))) = undefined;
            for (self.data, 0..) |v, i| {
                const q = Q{ .value = v };
                res.data[i] = q.divBy(scalar).value;
            }
            return res;
        }

        pub fn mulByScalar(
            self: Self,
            scalar: anytype,
        ) QuantityVec(len, Quantity(T, d.add(@TypeOf(scalar).dims), s.min(@TypeOf(scalar).scales))) {
            var res: QuantityVec(len, Quantity(T, d.add(@TypeOf(scalar).dims), s.min(@TypeOf(scalar).scales))) = undefined;
            for (self.data, 0..) |v, i| {
                const q = Q{ .value = v };
                res.data[i] = q.mulBy(scalar).value;
            }
            return res;
        }

        pub fn negate(self: Self) Self {
            var res: Self = undefined;
            for (self.data, 0..) |v, i| {
                res.data[i] = -v;
            }
            return res;
        }

        pub fn scale(self: Self, rhs: T) Self {
            var res: Self = undefined;
            for (self.data, 0..) |v, i| {
                res.data[i] = (Q{ .value = v }).scale(rhs).value;
            }
            return res;
        }

        pub fn to(self: Self, comptime DestQ: type) QuantityVec(len, DestQ) {
            var res: QuantityVec(len, DestQ) = undefined;
            for (self.data, 0..) |v, i| {
                res.data[i] = (Q{ .value = v }).to(DestQ).value;
            }
            return res;
        }

        pub fn lengthSqr(self: Self) T {
            var sum: T = 0;
            for (self.data) |v| {
                sum += v * v;
            }
            return sum;
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
            try writer.writeAll("(");
            for (self.data, 0..) |v, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{d:.2}", .{v});
            }
            try writer.writeAll(")");
            var first = true;
            inline for (std.enums.values(Dimension)) |bu| {
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

test "Format VectorX" {
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
    const momentum = KgMeterPerSecond.Vec3{ .data = .{ 43, 0, 11 } };

    std.debug.print("Acceleration: {f}\n", .{accel});
    std.debug.print("Momentum: {f}\n", .{momentum});
}

test "VecX Init and Basic Arithmetic" {
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    // Test zero, one, initDefault
    const v_zero = Vec3M.zero;
    try std.testing.expectEqual(0, v_zero.data[0]);
    try std.testing.expectEqual(0, v_zero.data[1]);
    try std.testing.expectEqual(0, v_zero.data[2]);

    const v_one = Vec3M.one;
    try std.testing.expectEqual(1, v_one.data[0]);
    try std.testing.expectEqual(1, v_one.data[1]);
    try std.testing.expectEqual(1, v_one.data[2]);

    const v_def = Vec3M.initDefault(5);
    try std.testing.expectEqual(5, v_def.data[0]);
    try std.testing.expectEqual(5, v_def.data[1]);
    try std.testing.expectEqual(5, v_def.data[2]);

    // Test add and sub
    const v1 = Vec3M{ .data = .{ 10, 20, 30 } };
    const v2 = Vec3M{ .data = .{ 2, 4, 6 } };

    const added = v1.add(v2);
    try std.testing.expectEqual(12, added.data[0]);
    try std.testing.expectEqual(24, added.data[1]);
    try std.testing.expectEqual(36, added.data[2]);

    const subbed = v1.sub(v2);
    try std.testing.expectEqual(8, subbed.data[0]);
    try std.testing.expectEqual(16, subbed.data[1]);
    try std.testing.expectEqual(24, subbed.data[2]);

    // Test negate
    const neg = v1.negate();
    try std.testing.expectEqual(-10, neg.data[0]);
    try std.testing.expectEqual(-20, neg.data[1]);
    try std.testing.expectEqual(-30, neg.data[2]);
}

test "VecX Kinematics (Scalar Mul/Div)" {
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Quantity(i32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    const pos = Vec3M{ .data = .{ 100, 200, 300 } };
    const time = Second{ .value = 10 };

    // Vector divided by scalar Quantity (Velocity = Position / Time)
    const vel = pos.divByScalar(time);
    try std.testing.expectEqual(10, vel.data[0]);
    try std.testing.expectEqual(20, vel.data[1]);
    try std.testing.expectEqual(30, vel.data[2]);
    try std.testing.expectEqual(1, @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(vel).dims.get(.T));

    // Vector multiplied by scalar Quantity (Position = Velocity * Time)
    const new_pos = vel.mulByScalar(time);
    try std.testing.expectEqual(100, new_pos.data[0]);
    try std.testing.expectEqual(200, new_pos.data[1]);
    try std.testing.expectEqual(300, new_pos.data[2]);
    try std.testing.expectEqual(1, @TypeOf(new_pos).dims.get(.L));
    try std.testing.expectEqual(0, @TypeOf(new_pos).dims.get(.T));
}

test "VecX Element-wise Math and Scaling" {
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    const v1 = Vec3M{ .data = .{ 10, 20, 30 } };
    const v2 = Vec3M{ .data = .{ 2, 5, 10 } };

    // Element-wise division
    const div = v1.divBy(v2);
    try std.testing.expectEqual(5, div.data[0]);
    try std.testing.expectEqual(4, div.data[1]);
    try std.testing.expectEqual(3, div.data[2]);
    try std.testing.expectEqual(0, @TypeOf(div).dims.get(.L)); // M / M = Dimensionless

    // Scale by primitive
    const scaled = v1.scale(2);
    try std.testing.expectEqual(20, scaled.data[0]);
    try std.testing.expectEqual(40, scaled.data[1]);
    try std.testing.expectEqual(60, scaled.data[2]);
}

test "VecX Conversions" {
    const KiloMeter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const Meter = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const v_km = KiloMeter.Vec3{ .data = .{ 1, 2, 3 } };
    const v_m = v_km.to(Meter);

    try std.testing.expectEqual(1000, v_m.data[0]);
    try std.testing.expectEqual(2000, v_m.data[1]);
    try std.testing.expectEqual(3000, v_m.data[2]);

    // Type checking the result
    try std.testing.expectEqual(1, @TypeOf(v_m).dims.get(.L));
    try std.testing.expectEqual(UnitScale.none, @TypeOf(v_m).scales.get(.L));
}

test "VecX Length" {
    const MeterInt = Quantity(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const MeterFloat = Quantity(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    // Integer length (using your custom isqrt)
    // 3-4-5 triangle on XY plane
    const v_int = MeterInt.Vec3{ .data = .{ 3, 4, 0 } };
    try std.testing.expectEqual(25, v_int.lengthSqr());
    try std.testing.expectEqual(5, v_int.length());

    // Float length
    const v_float = MeterFloat.Vec3{ .data = .{ 3.0, 4.0, 0.0 } };
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), v_float.lengthSqr(), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), v_float.length(), 1e-4);
}

test "Benchmark QuantityVec ops" {
    const Io = std.Io;
    const ITERS: usize = 10_000;
    const SAMPLES: usize = 10;
    var gsink: f64 = 0;

    // In Zig 0.14+, we use the testing IO for clock access in tests
    const io = std.testing.io;

    const getTime = struct {
        fn f(i: Io) Io.Timestamp {
            return Io.Clock.awake.now(i);
        }
    }.f;

    const getVal = struct {
        fn f(comptime TT: type, i: usize, comptime mask: u7) TT {
            const v: u8 = @as(u8, @truncate(i & @as(usize, mask))) + 1;
            return if (comptime @typeInfo(TT) == .float) @floatFromInt(v) else @intCast(v);
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

    const computeStats = struct {
        fn f(samples: []f64, iters: usize) f64 {
            std.mem.sort(f64, samples, {}, std.sort.asc(f64));
            const mid = samples.len / 2;
            const median_ns = if (samples.len % 2 == 0)
                (samples[mid - 1] + samples[mid]) / 2.0
            else
                samples[mid];
            return median_ns / @as(f64, @floatFromInt(iters));
        }
    }.f;

    std.debug.print(
        \\
        \\ QuantityVec<N, T> benchmark — {d} iterations, {d} samples/cell
        \\ (Results in ns/op)
        \\
        \\┌─────────────┬──────┬─────────┬─────────┬─────────┐
        \\│ Operation   │ Type │   Len=3 │   Len=4 │  Len=16 │
        \\├─────────────┼──────┼─────────┼─────────┼─────────┤
        \\
    , .{ ITERS, SAMPLES });

    const Types = .{ i32, i64, i128, f32, f64 };
    const TNames = .{ "i32", "i64", "i128", "f32", "f64" };
    const Lengths = .{ 3, 4, 16 };
    const Ops = .{ "add", "scale", "mulByScalar", "length" };

    inline for (Ops, 0..) |op_name, o_idx| {
        inline for (Types, TNames) |T, tname| {
            std.debug.print("│ {s:<11} │ {s:<4} │", .{ op_name, tname });

            inline for (Lengths) |len| {
                const Q_base = Quantity(T, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
                const Q_time = Quantity(T, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));
                const V = QuantityVec(len, Q_base);

                var samples: [SAMPLES]f64 = undefined;

                for (0..SAMPLES) |s_idx| {
                    var sink: T = 0;

                    const t_start = getTime(io);
                    for (0..ITERS) |i| {
                        const v1 = V.initDefault(getVal(T, i, 63));

                        if (comptime std.mem.eql(u8, op_name, "add")) {
                            const v2 = V.initDefault(getVal(T, i +% 7, 63));
                            const res = v1.add(v2);
                            for (res.data) |val| {
                                if (comptime @typeInfo(T) == .float) sink += val else sink ^= val;
                            }
                        } else if (comptime std.mem.eql(u8, op_name, "scale")) {
                            const sc = getVal(T, i +% 2, 63);
                            const res = v1.scale(sc);
                            for (res.data) |val| {
                                if (comptime @typeInfo(T) == .float) sink += val else sink ^= val;
                            }
                        } else if (comptime std.mem.eql(u8, op_name, "mulByScalar")) {
                            const s_val = Q_time{ .value = getVal(T, i +% 2, 63) };
                            const res = v1.mulByScalar(s_val);
                            for (res.data) |val| {
                                if (comptime @typeInfo(T) == .float) sink += val else sink ^= val;
                            }
                        } else if (comptime std.mem.eql(u8, op_name, "length")) {
                            const r = v1.length();
                            if (comptime @typeInfo(T) == .float) sink += r else sink ^= r;
                        }
                    }
                    const t_end = getTime(io);

                    samples[s_idx] = @as(f64, @floatFromInt(t_start.durationTo(t_end).toNanoseconds()));
                    fold(T, &gsink, sink);
                }

                const median_ns_per_op = computeStats(&samples, ITERS);
                std.debug.print(" {d:>7.1} │", .{median_ns_per_op});
            }
            std.debug.print("\n", .{});
        }

        if (o_idx < Ops.len - 1) {
            std.debug.print("├─────────────┼──────┼─────────┼─────────┼─────────┤\n", .{});
        }
    }
    std.debug.print("└─────────────┴──────┴─────────┴─────────┴─────────┘\n", .{});
    std.debug.print("\nAnti-optimisation sink: {d:.4}\n", .{gsink});
    try std.testing.expect(gsink != 0);
}
