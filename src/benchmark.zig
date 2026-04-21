const std = @import("std");
const tracy = @import("ztracy");
const Io = std.Io;
const Scalar = @import("Scalar.zig").Scalar;
const Vector = @import("Vector.zig").Vector;

var io: Io = undefined;
pub fn main(init: std.process.Init) !void {
    const zone = tracy.ZoneN(@src(), "Main Loop");
    defer zone.End();

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buf);
    try stdout_writer.interface.print("Starting Benchmarks...", .{});

    io = init.io;

    try bench_Scalar(&stdout_writer.interface);
    try stdout_writer.flush();
    try bench_vsNative(&stdout_writer.interface);
    try stdout_writer.flush();
    try bench_crossTypeVsNative(&stdout_writer.interface);
    try stdout_writer.flush();
    try bench_Vector(&stdout_writer.interface);
    try stdout_writer.flush();

    tracy.FrameMark();
}

fn getTime() Io.Timestamp {
    return Io.Clock.awake.now(io);
}

fn fold(comptime TT: type, s: *f64, v: TT) void {
    s.* += if (comptime @typeInfo(TT) == .float)
        @as(f64, @floatCast(v))
    else
        @as(f64, @floatFromInt(v));
}

fn bench_Scalar(writer: *std.Io.Writer) !void {
    const ITERS: usize = 100_000;
    const SAMPLES: usize = 10;

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

    try writer.print(
        \\
        \\ Scalar<T> benchmark — {d} iterations, {d} samples/cell
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
        const M = Scalar(T, .init(.{ .L = 1 }), .init(.{}));
        const KM = Scalar(T, .init(.{ .L = 1 }), .init(.{ .L = .k }));
        const S = Scalar(T, .init(.{ .T = 1 }), .init(.{}));

        inline for (Ops, 0..) |op_name, oidx| {
            var samples: [SAMPLES]f64 = undefined;

            for (0..SAMPLES) |s_idx| {
                const t_start = getTime();

                for (0..ITERS) |i| {
                    std.mem.doNotOptimizeAway(
                        {
                            _ = if (comptime std.mem.eql(u8, op_name, "add"))
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
                        },
                    );
                }

                const t_end = getTime();
                samples[s_idx] = @as(f64, @floatFromInt(t_start.durationTo(t_end).toNanoseconds()));
            }

            const stats = computeStats(&samples, ITERS);
            results_matrix[oidx][tidx] = stats.median;

            try writer.print("│ {s:<17} │ {s:<4} │ {d:>8.2} ns ±{d:<6.2} │ {d:>19.0} │\n", .{ op_name, tname, stats.median, stats.delta, stats.ops_per_sec });
        }

        if (comptime tidx < Types.len - 1) {
            try writer.print("├───────────────────┼──────┼─────────────────────┼─────────────────────┤\n", .{});
        }
        tidx += 1;
    }

    // Median Summary Table
    try writer.print("└───────────────────┴──────┴─────────────────────┴─────────────────────┘\n\n", .{});
    try writer.print("Median Summary (ns/op):\n", .{});

    try writer.print("┌──────────────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┐\n", .{});
    try writer.print("│  Operation   │  i16  │  i32  │  i64  │  i128 │  i256 │  f32  │  f64  │  f128 │\n", .{});
    try writer.print("├──────────────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┤\n", .{});

    inline for (Ops, 0..) |op_name, oidx| {
        try writer.print("│  {s:<11} │", .{op_name});
        var i: usize = 0;
        while (i < Types.len) : (i += 1)
            try writer.print("{d:>6.1} │", .{results_matrix[oidx][i]});

        try writer.print("\n", .{});
    }

    try writer.print("└──────────────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘\n", .{});
}

fn bench_vsNative(writer: *std.Io.Writer) !void {
    const ITERS: usize = 100_000;
    const SAMPLES: usize = 5;

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

    try writer.print(
        \\
        \\ Scalar vs Native Overhead Analysis
        \\
        \\┌───────────┬──────┬───────────┬───────────┬───────────┐
        \\│ Operation │ Type │ Native    │ Scalar    │ Slowdown  │
        \\├───────────┼──────┼───────────┼───────────┼───────────┤
        \\
    , .{});

    inline for (Ops, 0..) |op_name, j| {
        inline for (Types, 0..) |T, tidx| {
            var native_total_ns: f64 = 0;
            var quantity_total_ns: f64 = 0;

            const M = Scalar(T, .init(.{ .L = 1 }), .init(.{}));
            const S = Scalar(T, .init(.{ .T = 1 }), .init(.{}));

            std.mem.doNotOptimizeAway({
                for (0..SAMPLES) |_| {
                    // --- 1. Benchmark Native ---
                    const n_start = getTime();
                    for (0..ITERS) |i| {
                        const a = getValT(T, i);
                        const b = getValT(T, 2);
                        _ = if (comptime std.mem.eql(u8, op_name, "add"))
                            a + b
                        else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                            a * b
                        else if (comptime @typeInfo(T) == .int) @divTrunc(a, b) else a / b;
                    }
                    const n_end = getTime();
                    native_total_ns += @as(f64, @floatFromInt(n_start.durationTo(n_end).toNanoseconds()));

                    // --- 2. Benchmark Scalar ---
                    const q_start = getTime();
                    for (0..ITERS) |i| {
                        const qa = M{ .value = getValT(T, i) };
                        const qb = if (comptime std.mem.eql(u8, op_name, "divBy")) S{ .value = getValT(T, 2) } else M{ .value = getValT(T, 2) };

                        _ = if (comptime std.mem.eql(u8, op_name, "add"))
                            qa.add(qb)
                        else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                            qa.mulBy(qb)
                        else
                            qa.divBy(qb);
                    }
                    const q_end = getTime();
                    quantity_total_ns += @as(f64, @floatFromInt(q_start.durationTo(q_end).toNanoseconds()));
                }
            });

            const avg_n = (native_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
            const avg_q = (quantity_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
            const slowdown = avg_q / avg_n;

            try writer.print("│ {s:<9} │ {s:<4} │ {d:>7.2}ns │ {d:>7.2}ns │ {d:>8.2}x │\n", .{
                op_name, TNames[tidx], avg_n, avg_q, slowdown,
            });
        }
        if (j != Ops.len - 1) try writer.print("├───────────┼──────┼───────────┼───────────┼───────────┤\n", .{});
    }

    try writer.print("└───────────┴──────┴───────────┴───────────┴───────────┘\n", .{});
}

fn bench_crossTypeVsNative(writer: *std.Io.Writer) !void {
    const ITERS: usize = 100_000;
    const SAMPLES: usize = 5;

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

    try writer.print(
        \\
        \\ Cross-Type Overhead Analysis: Scalar vs Native
        \\
        \\┌─────────┬──────┬──────┬───────────┬───────────┬───────────┐
        \\│ Op      │ T1   │ T2   │ Native    │ Scalar    │ Slowdown  │
        \\├─────────┼──────┼──────┼───────────┼───────────┼───────────┤
        \\
    , .{});

    inline for (Ops, 0..) |op_name, j| {
        inline for (Types, 0..) |T1, t1_idx| {
            inline for (Types, 0..) |T2, t2_idx| {
                var native_total_ns: f64 = 0;
                var quantity_total_ns: f64 = 0;

                const M1 = Scalar(T1, .init(.{ .L = 1 }), .init(.{}));
                const M2 = Scalar(T2, .init(.{ .L = 1 }), .init(.{}));
                const S2 = Scalar(T2, .init(.{ .T = 1 }), .init(.{}));

                std.mem.doNotOptimizeAway({
                    for (0..SAMPLES) |_| {
                        // --- 1. Benchmark Native (Cast T2 to T1, then math) ---
                        const n_start = getTime();
                        for (0..ITERS) |i| {
                            const a = getValT(T1, i);
                            const b_raw = getValT(T2, 2);
                            const b = castTo(T1, T2, b_raw);

                            _ = if (comptime std.mem.eql(u8, op_name, "add"))
                                a + b
                            else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                                a * b
                            else if (comptime @typeInfo(T1) == .int)
                                @divTrunc(a, b)
                            else
                                a / b;
                        }
                        const n_end = getTime();
                        native_total_ns += @as(f64, @floatFromInt(n_start.durationTo(n_end).toNanoseconds()));

                        // --- 2. Benchmark Scalar ---
                        const q_start = getTime();
                        for (0..ITERS) |i| {
                            const qa = M1{ .value = getValT(T1, i) };
                            const qb = if (comptime std.mem.eql(u8, op_name, "divBy"))
                                S2{ .value = getValT(T2, 2) }
                            else
                                M2{ .value = getValT(T2, 2) };

                            _ = if (comptime std.mem.eql(u8, op_name, "add"))
                                qa.add(qb)
                            else if (comptime std.mem.eql(u8, op_name, "mulBy"))
                                qa.mulBy(qb)
                            else
                                qa.divBy(qb);
                        }
                        const q_end = getTime();
                        quantity_total_ns += @as(f64, @floatFromInt(q_start.durationTo(q_end).toNanoseconds()));
                    }

                    const avg_n = (native_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
                    const avg_q = (quantity_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
                    const slowdown = avg_q / avg_n;

                    try writer.print("│ {s:<7} │ {s:<4} │ {s:<4} │ {d:>7.2}ns │ {d:>7.2}ns │ {d:>8.2}x │\n", .{
                        op_name, TNames[t1_idx], TNames[t2_idx], avg_n, avg_q, slowdown,
                    });
                });
            }
        }
        if (j != Ops.len - 1) {
            try writer.print("├─────────┼──────┼──────┼───────────┼───────────┼───────────┤\n", .{});
        }
    }

    try writer.print("└─────────┴──────┴──────┴───────────┴───────────┴───────────┘\n", .{});
}

fn bench_Vector(writer: *std.Io.Writer) !void {
    const ITERS: usize = 10_000;
    const SAMPLES: usize = 10;

    const getVal = struct {
        fn f(comptime TT: type, i: usize, comptime mask: u7) TT {
            const v: u8 = @as(u8, @truncate(i & @as(usize, mask))) + 1;
            return if (comptime @typeInfo(TT) == .float) @floatFromInt(v) else @intCast(v);
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

    try writer.print(
        \\
        \\ Vector<N, T> benchmark — {d} iterations, {d} samples/cell
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
            try writer.print("│ {s:<11} │ {s:<4} │", .{ op_name, tname });

            inline for (Lengths) |len| {
                const Q_base = Scalar(T, .init(.{ .L = 1 }), .init(.{}));
                const Q_time = Scalar(T, .init(.{ .T = 1 }), .init(.{}));
                const V = Vector(len, Q_base);

                var samples: [SAMPLES]f64 = undefined;

                std.mem.doNotOptimizeAway({
                    for (0..SAMPLES) |s_idx| {
                        const t_start = getTime();
                        for (0..ITERS) |i| {
                            const v1 = V.initDefault(getVal(T, i, 63));

                            if (comptime std.mem.eql(u8, op_name, "add")) {
                                const v2 = V.initDefault(getVal(T, i +% 7, 63));
                                _ = v1.add(v2);
                            } else if (comptime std.mem.eql(u8, op_name, "scale")) {
                                const sc = getVal(T, i +% 2, 63);
                                _ = v1.scale(sc);
                            } else if (comptime std.mem.eql(u8, op_name, "mulByScalar")) {
                                const s_val = Q_time{ .value = getVal(T, i +% 2, 63) };
                                _ = v1.mulByScalar(s_val);
                            } else if (comptime std.mem.eql(u8, op_name, "length")) {
                                _ = v1.length();
                            }
                        }
                        const t_end = getTime();

                        samples[s_idx] = @as(f64, @floatFromInt(t_start.durationTo(t_end).toNanoseconds()));
                    }

                    const median_ns_per_op = computeStats(&samples, ITERS);
                    try writer.print(" {d:>7.1} │", .{median_ns_per_op});
                });
            }
            try writer.print("\n", .{});
        }

        if (o_idx < Ops.len - 1) {
            try writer.print("├─────────────┼──────┼─────────┼─────────┼─────────┤\n", .{});
        }
    }
    try writer.print("└─────────────┴──────┴─────────┴─────────┴─────────┘\n", .{});
}
