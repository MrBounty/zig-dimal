const std = @import("std");
const Io = std.Io;
const Tensor = @import("Tensor.zig").Tensor;

var io: Io = undefined;
pub fn main(init: std.process.Init) !void {
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buf);
    try stdout_writer.interface.print("Starting Benchmarks...", .{});

    io = init.io;

    // try vectorSIMDvsNative(f64, &stdout_writer.interface);
    // try stdout_writer.flush();
    // try vectorSIMDvsNative(f32, &stdout_writer.interface);
    // try stdout_writer.flush();
    // try vectorSIMDvsNative(i32, &stdout_writer.interface);
    // try stdout_writer.flush();
    // try vectorSIMDvsNative(i64, &stdout_writer.interface);
    // try stdout_writer.flush();
    // try vectorSIMDvsNative(i128, &stdout_writer.interface);
    // try stdout_writer.flush();
    //
    // try bench_Scalar(&stdout_writer.interface);
    // try stdout_writer.flush();
    try bench_vsNative(&stdout_writer.interface);
    try stdout_writer.flush();
    // try bench_crossTypeVsNative(&stdout_writer.interface);
    // try stdout_writer.flush();
    // try bench_Vector(&stdout_writer.interface);
    // try stdout_writer.flush();
    // try bench_HighDimTensor(&stdout_writer.interface);
    // try stdout_writer.flush();
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

    const Types = .{ i16, i32, i64, i128, i256, f32, f64 };
    const TNames = .{ "i16", "i32", "i64", "i128", "i256", "f32", "f64" };
    const Ops = .{ "add", "sub", "mul", "div", "to", "abs", "pow", "eq", "gt", "mul(n)" };

    var results_matrix: [Ops.len][Types.len]f64 = undefined;

    comptime var tidx: usize = 0;
    inline for (Types, TNames) |T, tname| {
        const M = Tensor(T, .{ .L = 1 }, .{}, &.{1});
        const KM = Tensor(T, .{ .L = 1 }, .{ .L = .k }, &.{1});
        const S = Tensor(T, .{ .T = 1 }, .{}, &.{1});

        inline for (Ops, 0..) |op_name, oidx| {
            var samples: [SAMPLES]f64 = undefined;

            for (0..SAMPLES) |s_idx| {
                const t_start = getTime();

                for (0..ITERS) |i| {
                    std.mem.doNotOptimizeAway(
                        {
                            _ = if (comptime std.mem.eql(u8, op_name, "add"))
                                (M.splat(getVal(T, i, 63))).add(M.splat(getVal(T, i +% 7, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "sub"))
                                (M.splat(getVal(T, i +% 10, 63))).sub(M.splat(getVal(T, i, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "mul"))
                                (M.splat(getVal(T, i, 63))).mul(M.splat(getVal(T, i +% 1, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "div"))
                                (M.splat(getVal(T, i +% 10, 63))).div(S.splat(getVal(T, i, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "to"))
                                (KM.splat(getVal(T, i, 15))).to(M)
                            else if (comptime std.mem.eql(u8, op_name, "abs"))
                                (M.splat(getVal(T, i, 63))).abs()
                            else if (comptime std.mem.eql(u8, op_name, "eq"))
                                (M.splat(getVal(T, i, 63))).eq(M.splat(getVal(T, i +% 3, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "gt"))
                                (M.splat(getVal(T, i, 63))).gt(M.splat(getVal(T, i +% 3, 63)))
                            else
                                (M.splat(getVal(T, i, 63))).mul(3);
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

    try writer.print("┌──────────────┬───────┬───────┬───────┬───────┬───────┬───────┬───────┐\n", .{});
    try writer.print("│  Operation   │  i16  │  i32  │  i64  │  i128 │  i256 │  f32  │  f64  │\n", .{});
    try writer.print("├──────────────┼───────┼───────┼───────┼───────┼───────┼───────┼───────┤\n", .{});

    inline for (Ops, 0..) |op_name, oidx| {
        try writer.print("│  {s:<11} │", .{op_name});
        var i: usize = 0;
        while (i < Types.len) : (i += 1)
            try writer.print("{d:>6.1} │", .{results_matrix[oidx][i]});

        try writer.print("\n", .{});
    }

    try writer.print("└──────────────┴───────┴───────┴───────┴───────┴───────┴───────┴───────┘\n", .{});
}

fn bench_vsNative(writer: *std.Io.Writer) !void {
    const ITERS: usize = 100_000;
    const SAMPLES: usize = 100;

    const getValT = struct {
        fn f(comptime TT: type, i: usize) TT {
            const v = (i % 100) + 1;
            return if (comptime @typeInfo(TT) == .float) @floatFromInt(v) else @intCast(v);
        }
    }.f;

    const Types = .{ i32, i64, i128, f32, f64 };
    const TNames = .{ "i32", "i64", "i128", "f32", "f64" };
    // Expanded Ops to match bench_Scalar
    const Ops = .{ "add", "sub", "mul", "div", "abs", "eq", "gt" };

    try writer.print(
        \\
        \\ Scalar vs Native Overhead Analysis
        \\
        \\┌───────────┬──────┬───────────┬───────────┬───────────┬───────────────────────┐
        \\│ Operation │ Type │ Native    │ @Vector   │ Tensor{{1}} │ Slowdown  Nat | Vec   │
        \\├───────────┼──────┼───────────┼───────────┼───────────┼───────────────────────┤
        \\
    , .{});

    inline for (Ops, 0..) |op_name, j| {
        inline for (Types, 0..) |T, tidx| {
            var native_total_ns: f64 = 0;
            var vector_total_ns: f64 = 0;
            var tensor_total_ns: f64 = 0;

            const M = Tensor(T, .{}, .{}, &.{1});

            for (0..SAMPLES) |_| {
                // --- 1. Benchmark Native ---
                const n_start = getTime();
                const a = getValT(T, 10);
                const b = getValT(T, 2);
                for (0..ITERS) |_| {
                    // Native logic branch
                    _ = if (comptime std.mem.eql(u8, op_name, "add"))
                        if (comptime @typeInfo(T) == .int) a +| b else a + b
                    else if (comptime std.mem.eql(u8, op_name, "sub"))
                        if (comptime @typeInfo(T) == .int) a -| b else a - b
                    else if (comptime std.mem.eql(u8, op_name, "mul"))
                        if (comptime @typeInfo(T) == .int) a *| b else a * b
                    else if (comptime std.mem.eql(u8, op_name, "div"))
                        if (comptime @typeInfo(T) == .int) @divTrunc(a, b) else a / b
                    else if (comptime std.mem.eql(u8, op_name, "abs"))
                        if (comptime @typeInfo(T) == .int) @abs(a) else @as(T, @abs(a))
                    else if (comptime std.mem.eql(u8, op_name, "eq"))
                        a == b
                    else if (comptime std.mem.eql(u8, op_name, "gt"))
                        a > b
                    else
                        unreachable;
                }
                const n_end = getTime();
                native_total_ns += @as(f64, @floatFromInt(n_start.durationTo(n_end).toNanoseconds()));

                const v_start = getTime();
                const va = @Vector(1, T){getValT(T, 10)};
                const vb = @Vector(1, T){getValT(T, 2)};
                for (0..ITERS) |_| {
                    // Native logic branch
                    _ = if (comptime std.mem.eql(u8, op_name, "add"))
                        if (comptime @typeInfo(T) == .int) va +| vb else va + vb
                    else if (comptime std.mem.eql(u8, op_name, "sub"))
                        if (comptime @typeInfo(T) == .int) va -| vb else va - vb
                    else if (comptime std.mem.eql(u8, op_name, "mul"))
                        if (comptime @typeInfo(T) == .int) va *| vb else va * vb
                    else if (comptime std.mem.eql(u8, op_name, "div"))
                        if (comptime @typeInfo(T) == .int) @divTrunc(va, vb) else va / vb
                    else if (comptime std.mem.eql(u8, op_name, "abs"))
                        if (comptime @typeInfo(T) == .int) @as(T, @intCast(@abs(va[0]))) else @abs(va)
                    else if (comptime std.mem.eql(u8, op_name, "eq"))
                        va == vb
                    else if (comptime std.mem.eql(u8, op_name, "gt"))
                        va > vb
                    else
                        unreachable;
                }
                const v_end = getTime();
                vector_total_ns += @as(f64, @floatFromInt(v_start.durationTo(v_end).toNanoseconds()));

                // --- 2. Benchmark Scalar ---
                const q_start = getTime();
                const qa = M.splat(getValT(T, 10));
                const qb = M.splat(getValT(T, 2));
                for (0..ITERS) |_| {
                    // Scalar logic branch
                    _ = if (comptime std.mem.eql(u8, op_name, "add"))
                        qa.add(qb)
                    else if (comptime std.mem.eql(u8, op_name, "sub"))
                        qa.sub(qb)
                    else if (comptime std.mem.eql(u8, op_name, "mul"))
                        qa.mul(qb)
                    else if (comptime std.mem.eql(u8, op_name, "div"))
                        qa.div(qb)
                    else if (comptime std.mem.eql(u8, op_name, "abs"))
                        qa.abs()
                    else if (comptime std.mem.eql(u8, op_name, "eq"))
                        qa.eq(qb)
                    else if (comptime std.mem.eql(u8, op_name, "gt"))
                        qa.gt(qb)
                    else
                        unreachable;
                }
                const q_end = getTime();
                tensor_total_ns += @as(f64, @floatFromInt(q_start.durationTo(q_end).toNanoseconds()));
            }

            const avg_n = (native_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
            const avg_v = (vector_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
            const avg_t = (tensor_total_ns / SAMPLES) / @as(f64, @floatFromInt(ITERS));
            const slowdown_nt = avg_t / avg_n;
            const slowdown_vt = avg_t / avg_v;

            try writer.print("│ {s:<9} │ {s:<4} │ {d:>7.2}ns │ {d:>7.2}ns │ {d:>7.2}ns │ {d:>8.2}x   {d:>8.2}x │\n", .{
                op_name, TNames[tidx], avg_n, avg_v, avg_t, slowdown_nt, slowdown_vt,
            });
        }
        if (j != Ops.len - 1) try writer.print("├───────────┼──────┼───────────┼───────────┼───────────┼───────────────────────┤\n", .{});
    }

    try writer.print("└───────────┴──────┴───────────┴───────────┴───────────┴───────────────────────┘\n", .{});
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
    const Ops = .{ "add", "mul", "div" };

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

                const M1 = Tensor(T1, .{ .L = 1 }, .{}, &.{1});
                const M2 = Tensor(T2, .{ .L = 1 }, .{}, &.{1});
                const S2 = Tensor(T2, .{ .T = 1 }, .{}, &.{1});

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
                            else if (comptime std.mem.eql(u8, op_name, "mul"))
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
                            const qa = M1.splat(getValT(T1, i));
                            const qb = if (comptime std.mem.eql(u8, op_name, "div"))
                                S2.splat(getValT(T2, 2))
                            else
                                M2.splat(getValT(T2, 2));

                            _ = if (comptime std.mem.eql(u8, op_name, "add"))
                                qa.add(qb)
                            else if (comptime std.mem.eql(u8, op_name, "mul"))
                                qa.mul(qb)
                            else
                                qa.div(qb);
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
        \\ (Results in ns/op; "---" = not applicable for this length)
        \\
        \\┌──────────────────┬──────┬─────────┬─────────┬─────────┬─────────┬─────────┐
        \\│ Operation        │ Type │   Len=1 │   Len=3 │   Len=4 │  Len=16 │ Len=100 │
        \\├──────────────────┼──────┼─────────┼─────────┼─────────┼─────────┼─────────┤
        \\
    , .{ ITERS, SAMPLES });

    const Types = .{ i32, i64, i128, f32, f64 };
    const TNames = .{ "i32", "i64", "i128", "f32", "f64" };
    const Lengths = .{ 1, 3, 4, 16, 100 };
    // "cross" is only valid for len=3; other cells will show "  ---  "
    const Ops = .{ "add", "div", "mulScalar", "dot", "cross", "product", "pow", "length" };

    inline for (Ops, 0..) |op_name, o_idx| {
        inline for (Types, TNames) |T, tname| {
            try writer.print("│ {s:<16} │ {s:<4} │", .{ op_name, tname });

            inline for (Lengths) |len| {
                const Q_time = Tensor(T, .{ .T = 1 }, .{}, &.{1});
                const V = Tensor(T, .{ .L = 1 }, .{}, &.{len});

                // cross product is only defined for len == 3
                const is_cross = comptime std.mem.eql(u8, op_name, "cross");
                if (comptime is_cross and len != 3) {
                    try writer.print("     --- │", .{});
                    continue;
                }

                var samples: [SAMPLES]f64 = undefined;

                std.mem.doNotOptimizeAway({
                    for (0..SAMPLES) |s_idx| {
                        const t_start = getTime();
                        for (0..ITERS) |i| {
                            const v1 = V.splat(getVal(T, i, 63));

                            if (comptime std.mem.eql(u8, op_name, "add")) {
                                const v2 = V.splat(getVal(T, i +% 7, 63));
                                _ = v1.add(v2);
                            } else if (comptime std.mem.eql(u8, op_name, "div")) {
                                _ = v1.div(V.splat(getVal(T, i +% 2, 63)));
                            } else if (comptime std.mem.eql(u8, op_name, "mulScalar")) {
                                const s_val = Q_time.splat(getVal(T, i +% 2, 63));
                                _ = v1.mul(s_val);
                            } else if (comptime std.mem.eql(u8, op_name, "dot")) {
                                const v2 = V.splat(getVal(T, i +% 5, 63));
                                _ = v1.contract(v2, 0, 0);
                            } else if (comptime std.mem.eql(u8, op_name, "cross")) {
                                // len == 3 guaranteed by the guard above
                                const v2 = V.splat(getVal(T, i +% 5, 63));
                                _ = v1.cross(v2);
                            } else if (comptime std.mem.eql(u8, op_name, "product")) {
                                _ = v1.product();
                            } else if (comptime std.mem.eql(u8, op_name, "pow")) {
                                _ = v1.pow(2);
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
            try writer.print("├──────────────────┼──────┼─────────┼─────────┼─────────┼─────────┼─────────┤\n", .{});
        }
    }
    try writer.print("└──────────────────┴──────┴─────────┴─────────┴─────────┴─────────┴─────────┘\n", .{});
}

fn bench_HighDimTensor(writer: *std.Io.Writer) !void {
    const ITERS: usize = 5_000;
    const SAMPLES: usize = 5;

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
        \\ High Dimension Tensor benchmark — {d} iterations, {d} samples/cell
        \\ (Results in ns/op)
        \\
        \\┌─────────────────┬──────┬──────────────┬──────────────┬──────────────┬──────────────┐
        \\│ Operation       │ Type │        2x2x2 │        3x3x3 │        4x4x4 │  10x10x10x10 │
        \\├─────────────────┼──────┼──────────────┼──────────────┼──────────────┼──────────────┤
        \\
    , .{ ITERS, SAMPLES });

    const Types = .{ i32, i64, f32, f64 };
    const TNames = .{ "i32", "i64", "f32", "f64" };

    // Testing multiple structural bounds
    const Shapes = .{
        &.{ 2, 2, 2 },
        &.{ 3, 3, 3 },
        &.{ 4, 4, 4 },
        &.{ 10, 10, 10, 10 },
    };

    const Ops = .{ "add", "sub", "mulElem", "mulScalar", "abs" };

    inline for (Ops, 0..) |op_name, o_idx| {
        inline for (Types, TNames) |T, tname| {
            try writer.print("│ {s:<15} │ {s:<4} │", .{ op_name, tname });

            inline for (Shapes) |shape| {
                const V = Tensor(T, .{ .L = 1 }, .{}, shape);
                const Q = Tensor(T, .{ .T = 1 }, .{}, &.{1}); // For scalar broadcasting operations

                var samples: [SAMPLES]f64 = undefined;

                for (0..SAMPLES) |s_idx| {
                    const t_start = getTime();

                    for (0..ITERS) |i| {
                        std.mem.doNotOptimizeAway({
                            const t1 = V.splat(getVal(T, i, 63));

                            _ = if (comptime std.mem.eql(u8, op_name, "add"))
                                t1.add(V.splat(getVal(T, i +% 7, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "sub"))
                                t1.sub(V.splat(getVal(T, i +% 3, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "mulElem"))
                                t1.mul(V.splat(getVal(T, i +% 5, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "mulScalar"))
                                t1.mul(Q.splat(getVal(T, i +% 2, 63)))
                            else if (comptime std.mem.eql(u8, op_name, "abs"))
                                t1.abs()
                            else
                                unreachable;
                        });
                    }

                    const t_end = getTime();
                    samples[s_idx] = @as(f64, @floatFromInt(t_start.durationTo(t_end).toNanoseconds()));
                }

                const median_ns_per_op = computeStats(&samples, ITERS);
                try writer.print(" {d:>12.1} │", .{median_ns_per_op});
            }
            try writer.print("\n", .{});
        }

        if (o_idx < Ops.len - 1) {
            try writer.print("├─────────────────┼──────┼──────────────┼──────────────┼──────────────┼──────────────┤\n", .{});
        }
    }
    try writer.print("└─────────────────┴──────┴──────────────┴──────────────┴──────────────┴──────────────┘\n", .{});
}

fn vectorSIMDvsNative(comptime T: type, writer: *std.Io.Writer) !void {
    const iterations: u64 = 10_000;
    const lens = [_]u32{ 1, 2, 3, 4, 5, 10, 100, 1_000, 10_000 };

    try writer.print("\nSIMD Speedup Analysis: {s}\n", .{@typeName(T)});
    try writer.print("┌────────────┬────────────┬────────────┬────────────┐\n", .{});
    try writer.print("│ Vector Len │ Scalar (us)│ Vector (us)│ Speedup    │\n", .{});
    try writer.print("├────────────┼────────────┼────────────┼────────────┤\n", .{});

    inline for (lens) |vector_len| {
        // --- Scalar Test ---
        var scalar_val: T = 10;
        const start_scalar = getTime();

        var i: u64 = 0;
        while (i < iterations * vector_len) : (i += 1) {
            if (comptime @typeInfo(T) == .int)
                scalar_val = scalar_val +% 1
            else
                scalar_val = scalar_val + 1;
        }
        const scalar_time = start_scalar.durationTo(getTime()).toMicroseconds();

        // --- Vector Test ---
        var vector_val: @Vector(vector_len, T) = @splat(20);
        const start_vector = getTime();

        i = 0;
        const increment: @Vector(vector_len, T) = @splat(1);
        while (i < iterations) : (i += 1) {
            if (comptime @typeInfo(T) == .int)
                vector_val = vector_val +% increment
            else
                vector_val = vector_val + increment;
        }
        const vector_time = start_vector.durationTo(getTime()).toMicroseconds();

        // --- Results ---
        const s_float = @as(f64, @floatFromInt(scalar_time));
        const v_float = @as(f64, @floatFromInt(vector_time));

        // Speedup = ScalarTime / VectorTime.
        // > 1.0 means SIMD is faster.
        const speedup = if (vector_time > 0) s_float / v_float else 0;

        try writer.print("│ {d:<10} │ {d:>10} │ {d:>10} │ {d:>9.2}x │\n", .{
            vector_len,
            scalar_time,
            vector_time,
            speedup,
        });
        try writer.flush();

        std.mem.doNotOptimizeAway(scalar_val);
        std.mem.doNotOptimizeAway(vector_val);
    }
    try writer.print("└────────────┴────────────┴────────────┴────────────┘\n", .{});
}
