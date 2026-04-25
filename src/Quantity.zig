const std = @import("std");
const hlp = @import("helper.zig");
const Scales = @import("Scales.zig");
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

// ---------------------------------------------------------------------------
// Quantity — the single unified dimensioned type.
//
//   T  : element numeric type  (f32, f64, i32, i128, …)
//   N  : lane count            (1 = Scalar, >1 = Vector)
//   d  : SI dimension exponents
//   s  : unit scales
//
// All arithmetic is performed directly on the underlying @Vector(N, T), so
// the compiler can emit SIMD instructions wherever the target supports them.
//
// Thin aliases (same type identity, no wrapper overhead):
//   Scalar(T, d, s)    ≡ Quantity(T, 1, d, s)
//   Vector(N, Q)       ≡ Quantity(Q.ValueType, N, Q.dims.argsOpt(), Q.scales.argsOpt())
// ---------------------------------------------------------------------------
//
// @reduce(comptime op: std.builtin.ReduceOp, value: anytype) E
// @select(comptime T: type, pred: @Vector(len, bool), a: @Vector(len, T), b: @Vector(len, T)) @Vector(len, T)
// @shuffle(comptime E: type, a: @Vector(a_len, E), b: @Vector(b_len, E), comptime mask: @Vector(mask_len, i32)) @Vector(mask_len, E)

pub fn Quantity(
    comptime T: type,
    comptime N: usize,
    comptime d_opt: Dimensions.ArgOpts,
    comptime s_opt: Scales.ArgOpts,
) type {
    comptime std.debug.assert(N >= 1);
    @setEvalBranchQuota(10_000_000);

    // Local shorthand for the SIMD vector type used in storage.
    const Vec = @Vector(N, T);

    return struct {
        /// SIMD-friendly storage. Arithmetic operates here directly.
        data: Vec,

        const Self = @This();

        pub const ValueType: type = T;
        pub const Len: usize = N;
        pub const dims: Dimensions = Dimensions.init(d_opt);
        pub const scales: Scales = Scales.init(s_opt);
        pub const ISQUANTITY = true;

        /// Scalar variant of this quantity (lane=1). Returned by dot(), product(), etc.
        pub const ScalarType: type = Quantity(T, 1, d_opt, s_opt);
        /// Convenience: a 3-lane vector of the same dimension/scale.
        pub const Vec3: type = Quantity(T, 3, d_opt, s_opt);

        // ---------------------------------------------------------------
        // Constructors
        // ---------------------------------------------------------------

        /// Broadcast a single value across all N lanes.
        pub inline fn splat(v: T) Self {
            return .{ .data = @splat(v) };
        }

        /// Backward-compat alias used by Vector tests (`initDefault`).
        pub const initDefault = splat;

        pub const zero: Self = splat(0);
        pub const one: Self = splat(1);

        // ---------------------------------------------------------------
        // Scalar-only helpers  (N = 1)
        // ---------------------------------------------------------------

        /// Return the single scalar value.  Compile error when N ≠ 1.
        pub inline fn value(self: Self) T {
            comptime if (N != 1)
                @compileError(".value() is only available on Scalar (N=1).");
            return self.data[0];
        }

        /// Expand this scalar into a len-lane vector by splatting.
        pub inline fn vec(self: Self, comptime len: usize) Quantity(T, len, d_opt, s_opt) {
            comptime if (N != 1)
                @compileError(".vec() is only available on Scalar (N=1).");
            return .{ .data = @splat(self.data[0]) };
        }

        pub inline fn vec3(self: Self) Vec3 {
            return self.vec(3);
        }

        // ---------------------------------------------------------------
        // Internal: RHS normalisation
        //
        //  • For N=1 (Scalar context):  bare numbers  →  Quantity(T, 1, dimless, none)
        //  • For N>1 (Vector context):  bare numbers  →  Quantity(T, N, dimless, none)
        //                               Quantity(T,1) →  broadcast (handled in each op)
        //
        // A bare number used as rhs is ALWAYS treated as dimensionless.
        // ---------------------------------------------------------------

        inline fn RhsT(comptime Rhs: type) type {
            return hlp.rhsQuantityType(T, N, Rhs);
        }
        inline fn rhs(r: anytype) RhsT(@TypeOf(r)) {
            return hlp.toRhsQuantity(T, N, r);
        }

        /// Scalar rhs (N=1) — used by mulScalar / divScalar / eqScalar etc.
        inline fn ScalarRhsT(comptime Rhs: type) type {
            return hlp.rhsQuantityType(T, 1, Rhs);
        }
        inline fn scalarRhs(r: anytype) ScalarRhsT(@TypeOf(r)) {
            return hlp.toRhsQuantity(T, 1, r);
        }

        // ---------------------------------------------------------------
        // Internal: broadcast helper
        //
        // When an N=1 rhs is used in an N>1 operation, splat it.
        // ---------------------------------------------------------------
        inline fn broadcastToVec(comptime RhsType: type, r: RhsType) Vec {
            if (comptime RhsType.Len == 1 and N > 1)
                return @splat(r.data[0])
            else
                return r.data;
        }

        // ---------------------------------------------------------------
        // Arithmetic
        // ---------------------------------------------------------------

        /// Element-wise add.  Dimensions must match; scales resolve to finer.
        /// For N=1: rhs may be a bare number (treated as dimensionless).
        /// For N>1: rhs must be a same-length Quantity.
        pub inline fn add(self: Self, r: anytype) Quantity(
            T,
            N,
            dims.argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_q = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime N > 1 and RhsType.Len != N)
                @compileError("Vector add requires same-length Quantity.");

            const TargetType = Quantity(T, N, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const l: Vec = if (comptime Self == TargetType) self.data else self.to(TargetType).data;
            const rr: Vec = if (comptime RhsType == TargetType) rhs_q.data else rhs_q.to(TargetType).data;
            return .{ .data = if (comptime hlp.isInt(T)) l +| rr else l + rr };
        }

        /// Element-wise subtract.  Dimensions must match; scales resolve to finer.
        pub inline fn sub(self: Self, r: anytype) Quantity(
            T,
            N,
            dims.argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_q = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in sub: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime N > 1 and RhsType.Len != N)
                @compileError("Vector sub requires same-length Quantity.");

            const TargetType = Quantity(T, N, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const l: Vec = if (comptime Self == TargetType) self.data else self.to(TargetType).data;
            const rr: Vec = if (comptime RhsType == TargetType) rhs_q.data else rhs_q.to(TargetType).data;
            return .{ .data = if (comptime hlp.isInt(T)) l -| rr else l - rr };
        }

        /// Element-wise multiply.  Dimension exponents are summed.
        /// An N=1 rhs on an N>1 self is automatically broadcast (scalar × vector).
        pub inline fn mul(self: Self, r: anytype) Quantity(
            T,
            N,
            dims.add(RhsT(@TypeOf(r)).dims).argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_q = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            const SelfNorm = Quantity(T, N, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const RhsNorm = Quantity(T, N, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const l: Vec = if (comptime Self == SelfNorm) self.data else self.to(SelfNorm).data;
            const rr_base = if (comptime RhsType == RhsNorm) rhs_q else rhs_q.to(RhsNorm);
            const rr: Vec = broadcastToVec(RhsNorm, rr_base);
            return .{ .data = if (comptime hlp.isInt(T)) l *| rr else l * rr };
        }

        /// Element-wise divide.  Dimension exponents are subtracted.
        /// An N=1 rhs on an N>1 self is automatically broadcast.
        pub inline fn div(self: Self, r: anytype) Quantity(
            T,
            N,
            dims.sub(RhsT(@TypeOf(r)).dims).argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_q = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            const SelfNorm = Quantity(T, N, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const RhsNorm = Quantity(T, N, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const l: Vec = if (comptime Self == SelfNorm) self.data else self.to(SelfNorm).data;
            const rr_base = if (comptime RhsType == RhsNorm) rhs_q else rhs_q.to(RhsNorm);
            const rr: Vec = broadcastToVec(RhsNorm, rr_base);
            if (comptime hlp.isInt(T)) {
                var result: Vec = undefined;
                inline for (0..N) |i| result[i] = @divTrunc(l[i], rr[i]);
                return .{ .data = result };
            } else {
                return .{ .data = l / rr };
            }
        }

        // ---------------------------------------------------------------
        // Unary
        // ---------------------------------------------------------------

        /// Absolute value of every lane.  Uses native `@abs` (SIMD for floats & ints).
        pub inline fn abs(self: Self) Self {
            return .{ .data = @bitCast(@abs(self.data)) };
        }

        /// Raise every lane to a comptime integer exponent.
        /// Repeated SIMD multiply — good for small exponents.
        pub inline fn pow(self: Self, comptime exp: comptime_int) Quantity(
            T,
            N,
            dims.scale(exp).argsOpt(),
            scales.argsOpt(),
        ) {
            if (comptime hlp.isInt(T)) {
                // No SIMD pow for integers — element-wise std.math.powi.
                var result: Vec = undefined;
                inline for (0..N) |i|
                    result[i] = std.math.powi(T, self.data[i], exp) catch std.math.maxInt(T);
                return .{ .data = result };
            } else {
                // Float: unrolled SIMD multiplications.
                const abs_exp = comptime @abs(exp);
                var result: Vec = @splat(1);
                comptime var i = 0;
                inline while (i < abs_exp) : (i += 1) result *= self.data;
                if (comptime exp < 0) result = @as(Vec, @splat(1)) / result;
                return .{ .data = result };
            }
        }

        /// Square root of every lane.  All dimension exponents must be even.
        pub inline fn sqrt(self: Self) Quantity(
            T,
            N,
            dims.div(2).argsOpt(),
            scales.argsOpt(),
        ) {
            if (comptime !dims.isSquare())
                @compileError("Cannot take sqrt of " ++ dims.str() ++ ": exponents must be even.");
            if (comptime @typeInfo(T) == .float) {
                return .{ .data = @sqrt(self.data) };
            } else {
                // Integer sqrt is not SIMD-able — element-wise.
                var result: Vec = undefined;
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
                inline for (0..N) |i| {
                    const v = self.data[i];
                    if (v < 0)
                        result[i] = 0
                    else
                        result[i] = @as(T, @intCast(std.math.sqrt(@as(UnsignedT, @intCast(v)))));
                }
                return .{ .data = result };
            }
        }

        /// Negate every lane.
        pub inline fn negate(self: Self) Self {
            return .{ .data = -self.data };
        }

        // ---------------------------------------------------------------
        // Conversion
        // ---------------------------------------------------------------

        /// Convert to a compatible quantity type.  Dimension mismatch is a compile error.
        /// The scale ratio is computed entirely at comptime; the only runtime cost is
        /// a SIMD multiply-by-splat (or element-wise cast for cross-numeric-type conversions).
        pub inline fn to(self: Self, comptime Dest: type) Dest {
            if (comptime !dims.eql(Dest.dims))
                @compileError("Dimension mismatch in to: " ++ dims.str() ++ " vs " ++ Dest.dims.str());
            if (comptime Self == Dest) return self;
            comptime std.debug.assert(Dest.Len == N);

            const DestT = Dest.ValueType;
            const ratio = comptime (scales.getFactor(dims) / Dest.scales.getFactor(Dest.dims));
            const DestVec = @Vector(N, DestT);

            // ── Same numeric type path ──
            if (comptime T == DestT) {
                if (comptime @typeInfo(T) == .float)
                    return .{ .data = self.data * @as(DestVec, @splat(@as(T, @floatCast(ratio)))) };

                // Integer logic: Branching prevents division by zero errors
                if (comptime ratio >= 1.0) {
                    // Upscaling (e.g., km -> m, ratio = 1000)
                    const mult: T = comptime @intFromFloat(@round(ratio));
                    return .{ .data = self.data *| @as(Vec, @splat(mult)) };
                } else {
                    // Downscaling (e.g., m -> km, ratio = 0.001)
                    const div_val: T = comptime @intFromFloat(@round(1.0 / ratio));
                    var result: DestVec = undefined;
                    const half: T = comptime @divTrunc(div_val, 2);

                    inline for (0..N) |i| {
                        const val = self.data[i];
                        // Rounding division for integers
                        result[i] = if (val >= 0) @divTrunc(val + half, div_val) else @divTrunc(val - half, div_val);
                    }
                    return .{ .data = result };
                }
            }

            // ── Cross-numeric-type (unchanged) ──
            var result: DestVec = undefined;
            inline for (0..N) |i| {
                const float_val: f64 = switch (comptime @typeInfo(T)) {
                    .float => @floatCast(self.data[i]),
                    .int => @floatFromInt(self.data[i]),
                    else => unreachable,
                };
                const scaled = float_val * ratio;
                result[i] = switch (comptime @typeInfo(DestT)) {
                    .float => @floatCast(scaled),
                    .int => @intFromFloat(@round(scaled)),
                    else => unreachable,
                };
            }
            return .{ .data = result };
        }

        // ---------------------------------------------------------------
        // Comparisons
        //
        // Return type:  bool    when N = 1  (Scalar semantics)
        //               [N]bool when N > 1  (Vector semantics, element-wise)
        //
        // Whole-vector "all equal/any differ" → use eqAll / neAll.
        // Broadcast scalar comparison         → use eqScalar / gtScalar / …
        // ---------------------------------------------------------------

        const CmpResult = if (N == 1) bool else [N]bool;

        inline fn cmpResult(v: @Vector(N, bool)) CmpResult {
            return if (comptime N == 1) v[0] else @as([N]bool, v);
        }

        inline fn resolveScalePair(self: Self, rhs_q: anytype) struct { l: Vec, r: Vec } {
            const RhsType = @TypeOf(rhs_q);
            const TargetType = Quantity(T, N, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            return .{
                .l = if (comptime Self == TargetType) self.data else self.to(TargetType).data,
                .r = if (comptime RhsType == TargetType) rhs_q.data else rhs_q.to(TargetType).data,
            };
        }

        pub inline fn eq(self: Self, r: anytype) CmpResult {
            const rhs_q = rhs(r);
            if (comptime !dims.eql(@TypeOf(rhs_q).dims))
                @compileError("Dimension mismatch in eq: " ++ dims.str() ++ " vs " ++ @TypeOf(rhs_q).dims.str());
            const p = resolveScalePair(self, rhs_q);
            return cmpResult(p.l == p.r);
        }

        pub inline fn ne(self: Self, r: anytype) CmpResult {
            const rhs_q = rhs(r);
            if (comptime !dims.eql(@TypeOf(rhs_q).dims))
                @compileError("Dimension mismatch in ne.");
            const p = resolveScalePair(self, rhs_q);
            return cmpResult(p.l != p.r);
        }

        pub inline fn gt(self: Self, r: anytype) CmpResult {
            const rhs_q = rhs(r);
            if (comptime !dims.eql(@TypeOf(rhs_q).dims))
                @compileError("Dimension mismatch in gt.");
            const p = resolveScalePair(self, rhs_q);
            return cmpResult(p.l > p.r);
        }

        pub inline fn gte(self: Self, r: anytype) CmpResult {
            const rhs_q = rhs(r);
            if (comptime !dims.eql(@TypeOf(rhs_q).dims))
                @compileError("Dimension mismatch in gte.");
            const p = resolveScalePair(self, rhs_q);
            return cmpResult(p.l >= p.r);
        }

        pub inline fn lt(self: Self, r: anytype) CmpResult {
            const rhs_q = rhs(r);
            if (comptime !dims.eql(@TypeOf(rhs_q).dims))
                @compileError("Dimension mismatch in lt.");
            const p = resolveScalePair(self, rhs_q);
            return cmpResult(p.l < p.r);
        }

        pub inline fn lte(self: Self, r: anytype) CmpResult {
            const rhs_q = rhs(r);
            if (comptime !dims.eql(@TypeOf(rhs_q).dims))
                @compileError("Dimension mismatch in lte.");
            const p = resolveScalePair(self, rhs_q);
            return cmpResult(p.l <= p.r);
        }

        // ---------------------------------------------------------------
        // Vector whole-quantity comparisons  (N > 1 intended, but work for N=1 too)
        // ---------------------------------------------------------------

        /// True iff every lane is equal after scale resolution.
        pub inline fn eqAll(self: Self, other: anytype) bool {
            if (comptime !dims.eql(@TypeOf(other).dims))
                @compileError("Dimension mismatch in eqAll.");
            const p = resolveScalePair(self, other);
            return @reduce(.And, p.l == p.r);
        }

        pub inline fn neAll(self: Self, other: anytype) bool {
            return !self.eqAll(other);
        }

        // ---------------------------------------------------------------
        // Vector broadcast-scalar comparisons  (always returns [N]bool)
        // ---------------------------------------------------------------

        inline fn broadcastScalarForCmp(self: Self, scalar: anytype) struct { l: Vec, r: Vec } {
            const s = scalarRhs(scalar);
            const SN = @TypeOf(s);
            const TargetScalar = Quantity(T, 1, dims.argsOpt(), hlp.finerScales(Self, SN).argsOpt());
            const TargetSelf = Quantity(T, N, dims.argsOpt(), hlp.finerScales(Self, SN).argsOpt());
            const s_val: T = if (comptime SN == TargetScalar) s.data[0] else s.to(TargetScalar).data[0];
            const l: Vec = if (comptime Self == TargetSelf) self.data else self.to(TargetSelf).data;
            return .{ .l = l, .r = @splat(s_val) };
        }

        pub inline fn eqScalar(self: Self, scalar: anytype) [N]bool {
            const p = broadcastScalarForCmp(self, scalar);
            return @as([N]bool, p.l == p.r);
        }

        pub inline fn neScalar(self: Self, scalar: anytype) [N]bool {
            const p = broadcastScalarForCmp(self, scalar);
            return @as([N]bool, p.l != p.r);
        }

        pub inline fn gtScalar(self: Self, scalar: anytype) [N]bool {
            const p = broadcastScalarForCmp(self, scalar);
            return @as([N]bool, p.l > p.r);
        }

        pub inline fn gteScalar(self: Self, scalar: anytype) [N]bool {
            const p = broadcastScalarForCmp(self, scalar);
            return @as([N]bool, p.l >= p.r);
        }

        pub inline fn ltScalar(self: Self, scalar: anytype) [N]bool {
            const p = broadcastScalarForCmp(self, scalar);
            return @as([N]bool, p.l < p.r);
        }

        pub inline fn lteScalar(self: Self, scalar: anytype) [N]bool {
            const p = broadcastScalarForCmp(self, scalar);
            return @as([N]bool, p.l <= p.r);
        }

        // ---------------------------------------------------------------
        // Vector broadcast multiply / divide
        // (These are explicit aliases for mul/div with an N=1 rhs; kept for
        //  clarity and backward-compat with the old Vector API.)
        // ---------------------------------------------------------------

        pub inline fn mulScalar(self: Self, scalar: anytype) Quantity(
            T,
            N,
            dims.add(ScalarRhsT(@TypeOf(scalar)).dims).argsOpt(),
            hlp.finerScales(Self, ScalarRhsT(@TypeOf(scalar))).argsOpt(),
        ) {
            return self.mul(scalar);
        }

        pub inline fn divScalar(self: Self, scalar: anytype) Quantity(
            T,
            N,
            dims.sub(ScalarRhsT(@TypeOf(scalar)).dims).argsOpt(),
            hlp.finerScales(Self, ScalarRhsT(@TypeOf(scalar))).argsOpt(),
        ) {
            return self.div(scalar);
        }

        // ---------------------------------------------------------------
        // Vector geometric operations
        // ---------------------------------------------------------------

        /// Dot product — sum of element-wise products; returns a Scalar.
        pub inline fn dot(self: Self, other: anytype) Quantity(
            T,
            1,
            dims.add(@TypeOf(other).dims).argsOpt(),
            hlp.finerScales(Self, @TypeOf(other)).argsOpt(),
        ) {
            const Tr = @TypeOf(other);
            const SelfNorm = Quantity(T, N, dims.argsOpt(), hlp.finerScales(Self, Tr).argsOpt());
            const OtherNorm = Quantity(T, N, Tr.dims.argsOpt(), hlp.finerScales(Self, Tr).argsOpt());
            const l: Vec = if (comptime Self == SelfNorm) self.data else self.to(SelfNorm).data;
            const r2: Vec = if (comptime Tr == OtherNorm) other.data else other.to(OtherNorm).data;
            return .{ .data = .{@reduce(.Add, l * r2)} };
        }

        /// 3D cross product. Requires N = 3.
        pub inline fn cross(self: Self, other: anytype) Quantity(
            T,
            3,
            dims.add(@TypeOf(other).dims).argsOpt(),
            hlp.finerScales(Self, @TypeOf(other)).argsOpt(),
        ) {
            comptime if (N != 3) @compileError("cross() requires len=3.");
            const a = self.data;
            const b = other.data;
            return .{ .data = .{
                a[1] * b[2] - a[2] * b[1],
                a[2] * b[0] - a[0] * b[2],
                a[0] * b[1] - a[1] * b[0],
            } };
        }

        /// Sum of squared components.  Cheaper than length(); use for comparisons.
        pub inline fn lengthSqr(self: Self) T {
            return @reduce(.Add, self.data * self.data);
        }

        /// Euclidean length.  Float types use SIMD @reduce → @sqrt.
        /// Integer types use integer sqrt (truncated).
        pub inline fn length(self: Self) T {
            const sq = self.lengthSqr();
            if (comptime @typeInfo(T) == .int) {
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
                return @as(T, @intCast(std.math.sqrt(@as(UnsignedT, @intCast(sq)))));
            }
            return @sqrt(sq);
        }

        /// Product of all components.  Result dimension is (original dim × N).
        pub inline fn product(self: Self) Quantity(T, 1, dims.scale(N).argsOpt(), scales.argsOpt()) {
            return .{ .data = .{@reduce(.Mul, self.data)} };
        }

        // ---------------------------------------------------------------
        // Formatting  (unchanged from old Scalar / Vector)
        // ---------------------------------------------------------------

        pub fn formatNumber(
            self: Self,
            writer: *std.Io.Writer,
            options: std.fmt.Number,
        ) !void {
            if (comptime N == 1) {
                // Scalar-style: just print the value + units
                switch (@typeInfo(T)) {
                    .float, .comptime_float => try writer.printFloat(self.data[0], options),
                    .int, .comptime_int => try writer.printInt(self.data[0], 10, .lower, .{
                        .width = options.width,
                        .alignment = options.alignment,
                        .fill = options.fill,
                        .precision = options.precision,
                    }),
                    else => unreachable,
                }
            } else {
                // Vector-style: (v0, v1, …) + units
                try writer.writeAll("(");
                inline for (0..N) |i| {
                    if (i > 0) try writer.writeAll(", ");
                    switch (@typeInfo(T)) {
                        .float, .comptime_float => try writer.printFloat(self.data[i], options),
                        .int, .comptime_int => try writer.printInt(self.data[i], 10, .lower, .{
                            .width = options.width,
                            .alignment = options.alignment,
                            .fill = options.fill,
                            .precision = options.precision,
                        }),
                        else => unreachable,
                    }
                }
                try writer.writeAll(")");
            }

            var first = true;
            inline for (std.enums.values(Dimension)) |bu| {
                const v = dims.get(bu);
                if (comptime v == 0) continue;
                if (!first) try writer.writeAll(".");
                first = false;

                const uscale = scales.get(bu);
                if (bu == .T and (uscale == .min or uscale == .hour or uscale == .year))
                    try writer.print("{s}", .{uscale.str()})
                else
                    try writer.print("{s}{s}", .{ uscale.str(), bu.unit() });

                if (v != 1) try hlp.printSuperscript(writer, v);
            }
        }
    };
}

pub fn Scalar(comptime T: type, comptime d: Dimensions.ArgOpts, comptime s: Scales.ArgOpts) type {
    return Quantity(T, 1, d, s);
}

test "Generate quantity" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{ .L = @enumFromInt(-3) });
    const Second = Scalar(f32, .{ .T = 1 }, .{ .T = .n });

    const distance = Meter.splat(10);
    const time = Second.splat(2);

    try std.testing.expectEqual(10, distance.value());
    try std.testing.expectEqual(2, time.value());
}

test "Comparisons (eq, ne, gt, gte, lt, lte)" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const KiloMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });

    const m1000 = Meter.splat(1000);
    const km1 = KiloMeter.splat(1);
    const km2 = KiloMeter.splat(2);

    // Equal / Not Equal
    try std.testing.expect(m1000.eq(km1));
    try std.testing.expect(km1.eq(m1000));
    try std.testing.expect(km2.ne(m1000));

    // Greater Than / Greater Than or Equal
    try std.testing.expect(km2.gt(m1000));
    try std.testing.expect(km2.gt(km1));
    try std.testing.expect(km1.gte(m1000));
    try std.testing.expect(km2.gte(m1000));

    // Less Than / Less Than or Equal
    try std.testing.expect(m1000.lt(km2));
    try std.testing.expect(km1.lt(km2));
    try std.testing.expect(km1.lte(m1000));
    try std.testing.expect(m1000.lte(km2));
}

test "Add" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});

    const distance = Meter.splat(10);
    const distance2 = Meter.splat(20);

    const added = distance.add(distance2);
    try std.testing.expectEqual(30, added.value());
    try std.testing.expectEqual(1, @TypeOf(added).dims.get(.L));

    const KiloMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });
    const distance3 = KiloMeter.splat(2);
    const added2 = distance.add(distance3);
    try std.testing.expectEqual(2010, added2.value());
    try std.testing.expectEqual(1, @TypeOf(added2).dims.get(.L));

    const added3 = distance3.add(distance).to(KiloMeter);
    try std.testing.expectEqual(2, added3.value());
    try std.testing.expectEqual(1, @TypeOf(added3).dims.get(.L));

    const KiloMeter_f = Scalar(f64, .{ .L = 1 }, .{ .L = .k });
    const distance4 = KiloMeter_f.splat(2);
    const added4 = distance4.add(distance).to(KiloMeter_f);
    try std.testing.expectApproxEqAbs(2.01, added4.value(), 0.000001);
    try std.testing.expectEqual(1, @TypeOf(added4).dims.get(.L));
}

test "Sub" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const KiloMeter_f = Scalar(f64, .{ .L = 1 }, .{ .L = .k });

    const a = Meter.splat(500);
    const b = Meter.splat(200);

    const diff = a.sub(b);
    try std.testing.expectEqual(300, diff.value());
    const diff2 = b.sub(a);
    try std.testing.expectEqual(-300, diff2.value());

    const km_f = KiloMeter_f.splat(2.5);
    const m_f = Meter.splat(500);
    const diff3 = km_f.sub(m_f);
    try std.testing.expectApproxEqAbs(2000, diff3.value(), 1e-4);
}

test "MulBy" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const Second = Scalar(f32, .{ .T = 1 }, .{});

    const d = Meter.splat(3.0);
    const t = Second.splat(4.0);

    const area_time = d.mul(t);
    try std.testing.expectEqual(12, area_time.value());
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));

    const d2 = Meter.splat(5.0);
    const area = d.mul(d2);
    try std.testing.expectEqual(15, area.value());
    try std.testing.expectEqual(2, @TypeOf(area).dims.get(.L));
}

test "MulBy with scale" {
    const KiloMeter = Scalar(f32, .{ .L = 1 }, .{ .L = .k });
    const KiloGram = Scalar(f32, .{ .M = 1 }, .{ .M = .k });

    const dist = KiloMeter.splat(2.0);
    const mass = KiloGram.splat(3.0);
    const prod = dist.mul(mass);
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.M));
}

test "MulBy with type change" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });
    const Second = Scalar(f64, .{ .T = 1 }, .{});
    const KmSec = Scalar(i64, .{ .L = 1, .T = 1 }, .{ .L = .k });
    const KmSec_f = Scalar(f32, .{ .L = 1, .T = 1 }, .{ .L = .k });

    const d = Meter.splat(3.0);
    const t = Second.splat(4.0);

    const area_time = d.mul(t).to(KmSec);
    const area_time_f = d.mul(t).to(KmSec_f);
    try std.testing.expectEqual(12, area_time.value());
    try std.testing.expectApproxEqAbs(12.0, area_time_f.value(), 0.0001);
}

test "MulBy small" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{ .L = .n });
    const Second = Scalar(f32, .{ .T = 1 }, .{});

    const d = Meter.splat(3.0);
    const t = Second.splat(4.0);

    const area_time = d.mul(t);
    try std.testing.expectEqual(12, area_time.value());
}

test "MulBy dimensionless" {
    const DimLess = Scalar(i128, .{}, .{});
    const Meter = Scalar(i128, .{ .L = 1 }, .{});

    const d = Meter.splat(7);
    const scaled = d.mul(DimLess.splat(3));
    try std.testing.expectEqual(21, scaled.value());
}

test "Sqrt" {
    const MeterSquare = Scalar(i128, .{ .L = 2 }, .{});

    var d = MeterSquare.splat(9);
    var scaled = d.sqrt();
    try std.testing.expectEqual(3, scaled.value());
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));

    d = MeterSquare.splat(-5);
    scaled = d.sqrt();
    try std.testing.expectEqual(0, scaled.value());

    const MeterSquare_f = Scalar(f64, .{ .L = 2 }, .{});
    const d2 = MeterSquare_f.splat(20);
    const scaled2 = d2.sqrt();
    try std.testing.expectApproxEqAbs(4.472135955, scaled2.value(), 1e-4);
}

test "Chained: velocity and acceleration" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const Second = Scalar(f32, .{ .T = 1 }, .{});

    const dist = Meter.splat(100.0);
    const t1 = Second.splat(5.0);
    const velocity = dist.div(t1);
    try std.testing.expectEqual(20, velocity.value());

    const t2 = Second.splat(4.0);
    const accel = velocity.div(t2);
    try std.testing.expectEqual(5, accel.value());
}

test "DivBy integer exact" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const Second = Scalar(f32, .{ .T = 1 }, .{});

    const dist = Meter.splat(120);
    const time = Second.splat(4);
    const vel = dist.div(time);

    try std.testing.expectEqual(30, vel.value());
}

test "Finer scales skip dim 0" {
    const Dimless = Scalar(i128, .{}, .{});
    const KiloMetre = Scalar(i128, .{ .L = 1 }, .{ .L = .k });

    const r = Dimless.splat(30);
    const time = KiloMetre.splat(4);
    const vel = r.mul(time);

    try std.testing.expectEqual(120, vel.value());
    try std.testing.expectEqual(Scales.UnitScale.k, @TypeOf(vel).scales.get(.L));
}

test "Conversion chain: km -> m -> cm" {
    const KiloMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const CentiMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .c });

    const km = KiloMeter.splat(15);
    const m = km.to(Meter);
    const cm = m.to(CentiMeter);

    try std.testing.expectEqual(15_000, m.value());
    try std.testing.expectEqual(1_500_000, cm.value());
}

test "Conversion: hours -> minutes -> seconds" {
    const Hour = Scalar(i128, .{ .T = 1 }, .{ .T = .hour });
    const Minute = Scalar(i128, .{ .T = 1 }, .{ .T = .min });
    const Second = Scalar(i128, .{ .T = 1 }, .{});

    const h = Hour.splat(1.0);
    const min = h.to(Minute);
    const sec = min.to(Second);

    try std.testing.expectEqual(60, min.value());
    try std.testing.expectEqual(3600, sec.value());
}

test "Format Scalar" {
    const MeterPerSecondSq = Scalar(f32, .{ .L = 1, .T = -2 }, .{ .T = .n });
    const Meter = Scalar(f32, .{ .L = 1 }, .{});

    const m = Meter.splat(1.23456);
    const accel = MeterPerSecondSq.splat(9.81);

    var buf: [64]u8 = undefined;
    var res = try std.fmt.bufPrint(&buf, "{d:.2}", .{m});
    try std.testing.expectEqualStrings("1.23m", res);

    res = try std.fmt.bufPrint(&buf, "{d}", .{accel});
    try std.testing.expectEqualStrings("9.81m.ns⁻²", res);
}

test "Abs" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const m1 = Meter.splat(-50);
    const m2 = m1.abs();

    try std.testing.expectEqual(50, m2.value());

    const m_float = Scalar(f32, .{ .L = 1 }, .{});
    const m3 = m_float.splat(-42.5);
    try std.testing.expectEqual(42.5, m3.abs().value());
}

test "Pow" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const d = Meter.splat(4);

    const area = d.pow(2);
    try std.testing.expectEqual(16, area.value());

    const volume = d.pow(3);
    try std.testing.expectEqual(64, volume.value());
}

test "mul comptime_int" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const d = Meter.splat(7);

    const scaled = d.mul(3);
    try std.testing.expectEqual(21, scaled.value());
}

test "add/sub bare number on dimensionless scalar" {
    const DimLess = Scalar(i128, .{}, .{});
    const a = DimLess.splat(10);

    const b = a.add(5);
    try std.testing.expectEqual(15, b.value());

    const c = a.sub(3);
    try std.testing.expectEqual(7, c.value());
}

test "Imperial length scales" {
    const Foot = Scalar(f64, .{ .L = 1 }, .{ .L = .ft });
    const Meter = Scalar(f64, .{ .L = 1 }, .{});
    const Inch = Scalar(f64, .{ .L = 1 }, .{ .L = .inch });

    const one_ft = Foot.splat(1.0);
    try std.testing.expectApproxEqAbs(0.3048, one_ft.to(Meter).value(), 1e-9);

    const twelve_in = Inch.splat(12.0);
    try std.testing.expectApproxEqAbs(1.0, twelve_in.to(Foot).value(), 1e-9);
}

test "Imperial mass scales" {
    const Pound = Scalar(f64, .{ .M = 1 }, .{ .M = .lb });
    const Ounce = Scalar(f64, .{ .M = 1 }, .{ .M = .oz });

    const two_lb = Pound.splat(2.0);
    const eight_oz = Ounce.splat(8.0);
    const total = two_lb.add(eight_oz).to(Pound);
    try std.testing.expectApproxEqAbs(2.5, total.value(), 1e-6);
}

test "comparisons with comptime_int on dimensionless scalar" {
    const DimLess = Scalar(i128, .{}, .{});
    const x = DimLess.splat(42);

    try std.testing.expect(x.eq(42));
    try std.testing.expect(x.gt(10));
}
