const std = @import("std");
const hlp = @import("helper.zig");

const Vector = @import("Vector.zig").Vector;
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

pub fn Scalar(comptime T: type, comptime d: Dimensions, comptime s: Scales) type {
    @setEvalBranchQuota(100_000);
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
            scales.min(@TypeOf(rhs).scales),
        ) {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ @TypeOf(rhs).dims.str());
            if (comptime @TypeOf(rhs) == Self)
                return .{ .value = self.value + rhs.value };

            const TargetType = Scalar(T, dims, scales.min(@TypeOf(rhs).scales));
            const lhs_val = if (comptime @TypeOf(self) == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime @TypeOf(rhs) == TargetType) rhs.value else rhs.to(TargetType).value;

            return .{ .value = lhs_val + rhs_val };
        }

        pub inline fn sub(self: Self, rhs: anytype) Scalar(
            T,
            dims,
            scales.min(@TypeOf(rhs).scales),
        ) {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in sub: " ++ dims.str() ++ " vs " ++ @TypeOf(rhs).dims.str());
            if (comptime @TypeOf(rhs) == Self)
                return .{ .value = self.value - rhs.value };

            const TargetType = Scalar(T, dims, scales.min(@TypeOf(rhs).scales));
            const lhs_val = if (comptime @TypeOf(self) == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime @TypeOf(rhs) == TargetType) rhs.value else rhs.to(TargetType).value;

            return .{ .value = lhs_val - rhs_val };
        }

        pub inline fn mulBy(self: Self, rhs: anytype) Scalar(
            T,
            dims.add(@TypeOf(rhs).dims),
            scales.min(@TypeOf(rhs).scales),
        ) {
            const RhsType = @TypeOf(rhs);
            const SelfNorm = Scalar(T, dims, scales.min(RhsType.scales));
            const RhsNorm = Scalar(T, RhsType.dims, scales.min(RhsType.scales));
            if (comptime Self == SelfNorm and RhsType == RhsNorm)
                return .{ .value = self.value * rhs.value };

            const lhs_val = if (comptime Self == SelfNorm) self.value else self.to(SelfNorm).value;
            const rhs_val = if (comptime RhsType == RhsNorm) rhs.value else rhs.to(RhsNorm).value;
            return .{ .value = lhs_val * rhs_val };
        }

        pub inline fn divBy(self: Self, rhs: anytype) Scalar(
            T,
            dims.sub(@TypeOf(rhs).dims),
            scales.min(@TypeOf(rhs).scales),
        ) {
            const RhsType = @TypeOf(rhs);
            const SelfNorm = Scalar(T, dims, scales.min(RhsType.scales));
            const RhsNorm = Scalar(T, RhsType.dims, scales.min(RhsType.scales));
            const lhs_val = if (comptime Self == SelfNorm) self.value else self.to(SelfNorm).value;
            const rhs_val = if (comptime RhsType == RhsNorm) rhs.value else rhs.to(RhsNorm).value;
            if (comptime @typeInfo(T) == .int) {
                return .{ .value = @divTrunc(lhs_val, rhs_val) };
            } else {
                return .{ .value = lhs_val / rhs_val };
            }
        }

        pub inline fn scale(self: Self, sc: T) Self {
            return .{ .value = self.value * sc };
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
                    // Native round-to-nearest
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

        pub fn format(
            self: Self,
            writer: *std.Io.Writer,
        ) !void {
            try writer.print("{d}", .{self.value});
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
    std.debug.print("KiloMeter {f} + {f} = {f} OK\n", .{ distance, distance2, added });

    const KiloMeter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const distance3 = KiloMeter{ .value = 2 };
    const added2 = distance.add(distance3);
    try std.testing.expectEqual(2010, added2.value);
    try std.testing.expectEqual(1, @TypeOf(added2).dims.get(.L));
    std.debug.print("KiloMeter {f} + {f} = {f} OK\n", .{ distance, distance3, added2 });

    const added3 = distance3.add(distance).to(KiloMeter);
    try std.testing.expectEqual(2, added3.value);
    try std.testing.expectEqual(1, @TypeOf(added3).dims.get(.L));
    std.debug.print("KiloMeter {f} + {f} = {f} OK\n", .{ distance3, distance, added3 });

    const KiloMeter_f = Scalar(f64, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const distance4 = KiloMeter_f{ .value = 2 };
    const added4 = distance4.add(distance).to(KiloMeter_f);
    try std.testing.expectApproxEqAbs(2.01, added4.value, 0.000001);
    try std.testing.expectEqual(1, @TypeOf(added4).dims.get(.L));
    std.debug.print("KiloMeter_f {f} + {f} = {f} OK\n", .{ distance4, distance, added4 });
}

test "Sub" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const KiloMeter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const KiloMeter_f = Scalar(f64, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));

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
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Scalar(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

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
    const KiloMeter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const KiloGram = Scalar(f32, Dimensions.init(.{ .M = 1 }), Scales.init(.{ .M = .k }));

    const dist = KiloMeter{ .value = 2.0 };
    const mass = KiloGram{ .value = 3.0 };
    const prod = dist.mulBy(mass);
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.M));
    std.debug.print("MulBy scaled: {f} * {f} = {f} OK\n", .{ dist, mass, prod });
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
    std.debug.print("MulBy: {f} * {f} = {f} OK\n", .{ d, t, area_time });
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
    std.debug.print("MulBy: {f} * {f} = {f} OK\n", .{ d, t, area_time });
}

test "Scale" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Scalar(f32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

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

    std.debug.print("Velocity: {f}, Acceleration: {f} OK\n", .{ velocity, accel });
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
    std.debug.print("DivBy int: {f} / {f} = {f} OK\n", .{ dist, time, vel });
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
    std.debug.print("Chain: {f} -> {f} -> {f} OK\n", .{ km, m, cm });
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
    std.debug.print("Time chain: {f} -> {f} -> {f} OK\n", .{ h, min, sec });
}

test "Negative values" {
    const Meter = Scalar(i128, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

    const a = Meter{ .value = 5 };
    const b = Meter{ .value = 20 };
    const diff = a.sub(b);
    try std.testing.expectEqual(-15, diff.value);
    std.debug.print("Negative sub: {f} - {f} = {f} OK\n", .{ a, b, diff });
}

test "Format Quantity" {
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

    const accel = MeterPerSecondSq{ .value = 9.81 };
    const momentum = KgMeterPerSecond{ .value = 42.0 };

    std.debug.print("Acceleration: {f}\n", .{accel});
    std.debug.print("Momentum: {f}\n", .{momentum});
}

test "Benchmark" {
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
        const M = Scalar(T, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
        const KM = Scalar(T, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
        const S = Scalar(T, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

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

test "Overhead Analysis: Quantity vs Native" {
    const Io = std.Io;
    const ITERS: usize = 100_000;
    const SAMPLES: usize = 5;
    const io = std.testing.io;

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

    // Helper to safely get a value of type T from a loop index
    const getValT = struct {
        fn f(comptime TT: type, i: usize) TT {
            const v = (i % 100) + 1;
            return if (comptime @typeInfo(TT) == .float) @floatFromInt(v) else @intCast(v);
        }
    }.f;

    const Types = .{ i32, i64, i128, f32, f64 };
    const TNames = .{ "i32", "i64", "i128", "f32", "f64" };
    const Ops = .{ "add", "mulBy", "divBy" };

    var gsink: f64 = 0;

    std.debug.print(
        \\
        \\ Quantity vs Native Overhead Analysis
        \\
        \\┌───────────┬──────┬───────────┬───────────┬───────────┐
        \\│ Operation │ Type │ Native    │ Quantity  │ Slowdown  │
        \\├───────────┼──────┼───────────┼───────────┼───────────┤
        \\
    , .{});

    inline for (Ops, 0..) |op_name, j| {
        inline for (Types, 0..) |T, tidx| {
            var native_total_ns: f64 = 0;
            var quantity_total_ns: f64 = 0;

            const M = Scalar(T, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
            const S = Scalar(T, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

            for (0..SAMPLES) |_| {
                // --- 1. Benchmark Native ---
                var n_sink: T = 0;
                const n_start = getTime(io);
                for (0..ITERS) |i| {
                    const a = getValT(T, i);
                    const b = getValT(T, 2);
                    const r = if (comptime std.mem.eql(u8, op_name, "add"))
                        a + b
                    else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                        a * b
                    else if (comptime @typeInfo(T) == .int) @divTrunc(a, b) else a / b;

                    if (comptime @typeInfo(T) == .float) n_sink += r else n_sink ^= r;
                }
                const n_end = getTime(io);
                native_total_ns += @as(f64, @floatFromInt(n_start.durationTo(n_end).toNanoseconds()));
                fold(T, &gsink, n_sink);

                // --- 2. Benchmark Quantity ---
                var q_sink: T = 0;
                const q_start = getTime(io);
                for (0..ITERS) |i| {
                    const qa = M{ .value = getValT(T, i) };
                    const qb = if (comptime std.mem.eql(u8, op_name, "divBy")) S{ .value = getValT(T, 2) } else M{ .value = getValT(T, 2) };

                    const r = if (comptime std.mem.eql(u8, op_name, "add"))
                        qa.add(qb)
                    else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                        qa.mulBy(qb)
                    else
                        qa.divBy(qb);

                    if (comptime @typeInfo(T) == .float) q_sink += r.value else q_sink ^= r.value;
                }
                const q_end = getTime(io);
                quantity_total_ns += @as(f64, @floatFromInt(q_start.durationTo(q_end).toNanoseconds()));
                fold(T, &gsink, q_sink);
            }

            const avg_n = (native_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
            const avg_q = (quantity_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
            const slowdown = avg_q / avg_n;

            std.debug.print("│ {s:<9} │ {s:<4} │ {d:>7.2}ns │ {d:>7.2}ns │ {d:>8.2}x │\n", .{
                op_name, TNames[tidx], avg_n, avg_q, slowdown,
            });
        }
        if (j != Ops.len - 1) std.debug.print("├───────────┼──────┼───────────┼───────────┼───────────┤\n", .{});
    }

    std.debug.print("└───────────┴──────┴───────────┴───────────┴───────────┘\n", .{});
    try std.testing.expect(gsink != 0);
}

test "Cross-Type Overhead Analysis: Quantity vs Native" {
    const Io = std.Io;
    const ITERS: usize = 100_000;
    const SAMPLES: usize = 5;
    const io = std.testing.io;

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

    const getValT = struct {
        fn f(comptime TT: type, i: usize) TT {
            // Keep values safe and non-zero to avoid division by zero or overflows during cross-casting
            const v = (i % 50) + 1;
            return if (comptime @typeInfo(TT) == .float) @floatFromInt(v) else @intCast(v);
        }
    }.f;

    // Helper for the Native baseline: explicitly casting T2 to T1 before the operation
    const castTo = struct {
        fn f(comptime DestT: type, comptime SrcT: type, val: SrcT) DestT {
            if (comptime DestT == SrcT) return val;
            const src_info = @typeInfo(SrcT);
            const dest_info = @typeInfo(DestT);

            if (dest_info == .int and src_info == .int) return @intCast(val);
            if (dest_info == .float and src_info == .int) return @floatFromInt(val);
            if (dest_info == .int and src_info == .float) return @intFromFloat(val);
            if (dest_info == .float and src_info == .float) return @floatCast(val);
            unreachable;
        }
    }.f;

    const Types = .{ i16, i64, i128, f32, f64 };
    const TNames = .{ "i16", "i64", "i128", "f32", "f64" };
    const Ops = .{ "add", "mulBy", "divBy" };

    var gsink: f64 = 0;

    std.debug.print(
        \\
        \\ Cross-Type Overhead Analysis: Quantity vs Native
        \\
        \\┌─────────┬──────┬──────┬───────────┬───────────┬───────────┐
        \\│ Op      │ T1   │ T2   │ Native    │ Quantity  │ Slowdown  │
        \\├─────────┼──────┼──────┼───────────┼───────────┼───────────┤
        \\
    , .{});

    inline for (Ops, 0..) |op_name, j| {
        inline for (Types, 0..) |T1, t1_idx| {
            inline for (Types, 0..) |T2, t2_idx| {
                var native_total_ns: f64 = 0;
                var quantity_total_ns: f64 = 0;

                const M1 = Scalar(T1, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
                const M2 = Scalar(T2, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
                const S2 = Scalar(T2, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));

                for (0..SAMPLES) |_| {
                    // --- 1. Benchmark Native (Cast T2 to T1, then math) ---
                    var n_sink: T1 = 0;
                    const n_start = getTime(io);
                    for (0..ITERS) |i| {
                        const a = getValT(T1, i);
                        const b_raw = getValT(T2, 2);
                        const b = castTo(T1, T2, b_raw);

                        const r = if (comptime std.mem.eql(u8, op_name, "add"))
                            a + b
                        else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                            a * b
                        else if (comptime @typeInfo(T1) == .int)
                            @divTrunc(a, b)
                        else
                            a / b;

                        if (comptime @typeInfo(T1) == .float) n_sink += r else n_sink ^= r;
                    }
                    const n_end = getTime(io);
                    native_total_ns += @as(f64, @floatFromInt(n_start.durationTo(n_end).toNanoseconds()));
                    fold(T1, &gsink, n_sink);

                    // --- 2. Benchmark Quantity ---
                    var q_sink: T1 = 0;
                    const q_start = getTime(io);
                    for (0..ITERS) |i| {
                        const qa = M1{ .value = getValT(T1, i) };
                        const qb = if (comptime std.mem.eql(u8, op_name, "divBy"))
                            S2{ .value = getValT(T2, 2) }
                        else
                            M2{ .value = getValT(T2, 2) };

                        const r = if (comptime std.mem.eql(u8, op_name, "add"))
                            qa.add(qb)
                        else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                            qa.mulBy(qb)
                        else
                            qa.divBy(qb);

                        if (comptime @typeInfo(T1) == .float) q_sink += r.value else q_sink ^= r.value;
                    }
                    const q_end = getTime(io);
                    quantity_total_ns += @as(f64, @floatFromInt(q_start.durationTo(q_end).toNanoseconds()));
                    fold(T1, &gsink, q_sink);
                }

                const avg_n = (native_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
                const avg_q = (quantity_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
                const slowdown = avg_q / avg_n;

                std.debug.print("│ {s:<7} │ {s:<4} │ {s:<4} │ {d:>7.2}ns │ {d:>7.2}ns │ {d:>8.2}x │\n", .{
                    op_name, TNames[t1_idx], TNames[t2_idx], avg_n, avg_q, slowdown,
                });
            }
        }
        if (j != Ops.len - 1) {
            std.debug.print("├─────────┼──────┼──────┼───────────┼───────────┼───────────┤\n", .{});
        }
    }

    std.debug.print("└─────────┴──────┴──────┴───────────┴───────────┴───────────┘\n", .{});
    try std.testing.expect(gsink != 0);
}
