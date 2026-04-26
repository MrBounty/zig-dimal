const std = @import("std");
const hlp = @import("helper.zig");
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

// ─────────────────────────────────────────────────────────────────────────────
// Comptime shape utilities
// ─────────────────────────────────────────────────────────────────────────────

pub fn shapeTotal(comptime shape: []const usize) usize {
    var t: usize = 1;
    for (shape) |s| t *= s;
    return t;
}

/// Row-major (C-order) strides: strides[i] = product(shape[i+1..]).
///   e.g. shape {3, 4} → strides {4, 1}
///        shape {2, 3, 4} → strides {12, 4, 1}
pub fn shapeStrides(comptime shape: []const usize) [shape.len]usize {
    var st: [shape.len]usize = undefined;
    if (shape.len == 0) return st;
    st[shape.len - 1] = 1;
    if (shape.len > 1) {
        var i: usize = shape.len - 1;
        while (i > 0) : (i -= 1) st[i - 1] = st[i] * shape[i];
    }
    return st;
}

/// Return a copy of `shape` with the element at `axis` removed.
pub fn shapeRemoveAxis(comptime shape: []const usize, comptime axis: usize) [shape.len - 1]usize {
    var out: [shape.len - 1]usize = undefined;
    var j: usize = 0;
    for (shape, 0..) |v, i| {
        if (i != axis) { out[j] = v; j += 1; }
    }
    return out;
}

/// Concatenate two compile-time slices.
pub fn shapeCat(comptime a: []const usize, comptime b: []const usize) [a.len + b.len]usize {
    var out: [a.len + b.len]usize = undefined;
    for (a, 0..) |v, i| out[i] = v;
    for (b, 0..) |v, i| out[a.len + i] = v;
    return out;
}

/// Decode a flat row-major index into N-D coordinates.
/// Called only in comptime contexts (all arguments are comptime).
pub fn decodeFlatCoords(
    comptime flat: usize,
    comptime n: usize,
    comptime strd: [n]usize,
) [n]usize {
    var coords: [n]usize = undefined;
    var tmp = flat;
    for (0..n) |i| {
        coords[i] = if (strd[i] == 0) 0 else tmp / strd[i];
        tmp = if (strd[i] == 0) 0 else tmp % strd[i];
    }
    return coords;
}

/// Encode N-D coordinates into a flat row-major index.
/// Called only in comptime contexts.
pub fn encodeFlatCoords(
    comptime coords: []const usize,
    comptime n: usize,
    comptime strd: [n]usize,
) usize {
    var flat: usize = 0;
    for (0..n) |i| flat += coords[i] * strd[i];
    return flat;
}

/// Rebuild a full coordinate array by inserting `val` at `axis` into `free`.
/// `free` holds the remaining (non-contracted) coordinates in order.
pub fn insertAxis(
    comptime n: usize,
    comptime axis: usize,
    comptime val: usize,
    comptime free: []const usize,
) [n]usize {
    var out: [n]usize = undefined;
    var fi: usize = 0;
    for (0..n) |i| {
        if (i == axis) {
            out[i] = val;
        } else {
            out[i] = free[fi];
            fi += 1;
        }
    }
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// File-scope RHS normalisation helpers
//
// Any bare comptime_int / comptime_float / runtime T used as an arithmetic
// or comparison RHS is wrapped into a dimensionless Tensor of shape {1}.
// Actual Tensor types are passed through unchanged.
// ─────────────────────────────────────────────────────────────────────────────

fn RhsTensorType(comptime T: type, comptime Rhs: type) type {
    if (@hasDecl(Rhs, "ISTENSOR")) return Rhs;
    return Tensor(T, .{}, .{}, &.{1});
}

fn toRhsTensor(comptime T: type, r: anytype) RhsTensorType(T, @TypeOf(r)) {
    const Rhs = @TypeOf(r);
    if (comptime @hasDecl(Rhs, "ISTENSOR")) return r;
    const scalar: T = switch (comptime @typeInfo(Rhs)) {
        .comptime_int => switch (comptime @typeInfo(T)) {
            .float => @as(T, @floatFromInt(r)),
            else  => @as(T, r),
        },
        .comptime_float => switch (comptime @typeInfo(T)) {
            .int  => @as(T, @intFromFloat(r)),
            else  => @as(T, r),
        },
        .int   => switch (comptime @typeInfo(T)) {
            .float => @floatFromInt(r),
            else  => @intCast(r),
        },
        .float => switch (comptime @typeInfo(T)) {
            .int  => @intFromFloat(r),
            else  => @floatCast(r),
        },
        else => @compileError("Unsupported RHS type: " ++ @typeName(Rhs)),
    };
    return Tensor(T, .{}, .{}, &.{1}){ .data = .{scalar} };
}

// ─────────────────────────────────────────────────────────────────────────────
// Tensor — unified dimensioned ND type.
//
//   T      : element numeric type  (f32, f64, i32, i128, …)
//   d_opt  : SI dimension exponents
//   s_opt  : unit scales
//   shape_ : compile-time shape
//              &.{1}       → scalar
//              &.{3}       → 3-vector
//              &.{4, 4}    → 4×4 matrix
//              &.{3, 3, 3} → 3D field
//
// Storage: flat @Vector(total, T) where total = product(shape_).
// All arithmetic operates on the flat vector directly → SIMD wherever possible.
//
// Shape-related comptime constants exposed on every Tensor type:
//   dims        : Dimensions  — SI exponent struct
//   scales      : Scales      — unit scale struct
//   shape       : []const usize
//   rank        : usize        = shape.len
//   total       : usize        = product(shape)
//   strides_arr : [rank]usize  — row-major strides
//
// Index helper:
//   Tensor.idx(.{row, col}) → flat index  (comptime, no runtime cost)
//
// GPU readiness:
//   tensor.asSlice() → []T  (zero-copy pointer to the flat @Vector storage)
//
// Contraction (replaces dot / cross / matmul):
//   a.contract(b, axis_a, axis_b)
//   For rank-1 × rank-1 this is the dot product.
//   For rank-2 × rank-2 with axis_a=1, axis_b=0 this is matrix multiply.
//
// Removed from Quantity:
//   Scalar / Vector aliases, Vec3 / ScalarType, .value(), .vec(), .vec3(),
//   dot(), cross(), mulScalar(), divScalar(), eqScalar() and friends.
//   Use Tensor(..., &.{1}), .data[0], mul(), div(), eq() respectively.
// ─────────────────────────────────────────────────────────────────────────────

pub fn Tensor(
    comptime T: type,
    comptime d_opt: Dimensions.ArgOpts,
    comptime s_opt: Scales.ArgOpts,
    comptime shape_: []const usize,
) type {
    comptime {
        std.debug.assert(shape_.len >= 1);
        for (shape_) |s| std.debug.assert(s >= 1);
    }
    @setEvalBranchQuota(10_000_000);

    const _total: usize  = comptime shapeTotal(shape_);
    const _strides       = comptime shapeStrides(shape_);
    const Vec            = @Vector(_total, T);

    return struct {
        /// Flat SIMD storage.  All arithmetic operates here directly.
        data: Vec,

        const Self = @This();

        pub const ValueType : type               = T;
        pub const dims      : Dimensions         = Dimensions.init(d_opt);
        pub const scales    : Scales             = Scales.init(s_opt);
        pub const shape     : []const usize      = shape_;
        pub const rank      : usize              = shape_.len;
        pub const total     : usize              = _total;
        pub const strides_arr: [shape_.len]usize = _strides;
        pub const ISTENSOR                       = true;

        // ───────────────────────────────────────────────────────────────
        // Index helper
        // ───────────────────────────────────────────────────────────────

        /// Convert N-D coords (row-major) to flat index — fully comptime.
        /// Usage: Tensor.idx(.{row, col})
        pub fn idx(comptime coords: [rank]usize) usize {
            comptime {
                var flat: usize = 0;
                for (0..rank) |i| {
                    std.debug.assert(coords[i] < shape[i]);
                    flat += coords[i] * strides_arr[i];
                }
                return flat;
            }
        }

        // ───────────────────────────────────────────────────────────────
        // Constructors
        // ───────────────────────────────────────────────────────────────

        /// Broadcast a single value across all elements.
        pub inline fn splat(v: T) Self {
            return .{ .data = @splat(v) };
        }

        pub const zero: Self = splat(0);
        pub const one:  Self = splat(1);

        // ───────────────────────────────────────────────────────────────
        // GPU readiness
        // ───────────────────────────────────────────────────────────────

        /// Return a mutable slice to the flat storage — zero-copy WebGPU buffer mapping.
        pub inline fn asSlice(self: *Self) []T {
            return @as([*]T, @ptrCast(&self.data))[0..total];
        }

        // ───────────────────────────────────────────────────────────────
        // Internal: RHS normalisation
        // ───────────────────────────────────────────────────────────────

        inline fn RhsT(comptime Rhs: type) type { return RhsTensorType(T, Rhs); }
        inline fn rhs(r: anytype) RhsT(@TypeOf(r)) { return toRhsTensor(T, r); }

        // ───────────────────────────────────────────────────────────────
        // Internal: scalar broadcast  (shape {1} → full Vec)
        // ───────────────────────────────────────────────────────────────

        inline fn broadcastToVec(comptime RhsType: type, r: RhsType) Vec {
            return if (comptime RhsType.total == 1 and total > 1)
                @splat(r.data[0])
            else
                r.data;
        }

        // ───────────────────────────────────────────────────────────────
        // Arithmetic
        // ───────────────────────────────────────────────────────────────

        /// Element-wise add.  Dimensions must match; scales resolve to finer.
        /// RHS must have the same element count as self, or total == 1 (broadcast).
        pub inline fn add(self: Self, r: anytype) Tensor(
            T,
            dims.argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
            shape_,
        ) {
            const rhs_q   = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType.total != total and RhsType.total != 1)
                @compileError("Shape mismatch in add: element counts must match or RHS must be scalar (total=1).");

            const TargetType = Tensor(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), shape_);
            const l: Vec = if (comptime Self == TargetType) self.data else self.to(TargetType).data;
            const rr: Vec = blk: {
                const RhsNorm = Tensor(T, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), RhsType.shape);
                const rn = if (comptime RhsType == RhsNorm) rhs_q else rhs_q.to(RhsNorm);
                break :blk broadcastToVec(RhsNorm, rn);
            };
            return .{ .data = if (comptime hlp.isInt(T)) l +| rr else l + rr };
        }

        /// Element-wise subtract.  Dimensions must match; scales resolve to finer.
        pub inline fn sub(self: Self, r: anytype) Tensor(
            T,
            dims.argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
            shape_,
        ) {
            const rhs_q   = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in sub: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType.total != total and RhsType.total != 1)
                @compileError("Shape mismatch in sub.");

            const TargetType = Tensor(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), shape_);
            const l: Vec = if (comptime Self == TargetType) self.data else self.to(TargetType).data;
            const rr: Vec = blk: {
                const RhsNorm = Tensor(T, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), RhsType.shape);
                const rn = if (comptime RhsType == RhsNorm) rhs_q else rhs_q.to(RhsNorm);
                break :blk broadcastToVec(RhsNorm, rn);
            };
            return .{ .data = if (comptime hlp.isInt(T)) l -| rr else l - rr };
        }

        /// Element-wise multiply.  Dimension exponents summed.
        /// Shape {1} RHS is automatically broadcast across all elements.
        pub inline fn mul(self: Self, r: anytype) Tensor(
            T,
            dims.add(RhsT(@TypeOf(r)).dims).argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
            shape_,
        ) {
            const rhs_q   = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            if (comptime RhsType.total != total and RhsType.total != 1)
                @compileError("Shape mismatch in mul.");

            const SelfNorm = Tensor(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), shape_);
            const RhsNorm  = Tensor(T, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), RhsType.shape);
            const l: Vec       = if (comptime Self == SelfNorm) self.data else self.to(SelfNorm).data;
            const rr_base      = if (comptime RhsType == RhsNorm) rhs_q else rhs_q.to(RhsNorm);
            const rr: Vec      = broadcastToVec(RhsNorm, rr_base);
            return .{ .data = if (comptime hlp.isInt(T)) l *| rr else l * rr };
        }

        /// Element-wise divide.  Dimension exponents subtracted.
        /// Shape {1} RHS is automatically broadcast across all elements.
        pub inline fn div(self: Self, r: anytype) Tensor(
            T,
            dims.sub(RhsT(@TypeOf(r)).dims).argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
            shape_,
        ) {
            const rhs_q   = rhs(r);
            const RhsType = @TypeOf(rhs_q);
            if (comptime RhsType.total != total and RhsType.total != 1)
                @compileError("Shape mismatch in div.");

            const SelfNorm = Tensor(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), shape_);
            const RhsNorm  = Tensor(T, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), RhsType.shape);
            const l: Vec   = if (comptime Self == SelfNorm) self.data else self.to(SelfNorm).data;
            const rr_base  = if (comptime RhsType == RhsNorm) rhs_q else rhs_q.to(RhsNorm);
            const rr: Vec  = broadcastToVec(RhsNorm, rr_base);
            if (comptime hlp.isInt(T)) {
                var result: Vec = undefined;
                inline for (0..total) |i| result[i] = @divTrunc(l[i], rr[i]);
                return .{ .data = result };
            } else {
                return .{ .data = l / rr };
            }
        }

        // ───────────────────────────────────────────────────────────────
        // Unary
        // ───────────────────────────────────────────────────────────────

        /// Absolute value of every element.
        pub inline fn abs(self: Self) Self {
            return .{ .data = @bitCast(@abs(self.data)) };
        }

        /// Raise every element to a comptime integer exponent.
        pub inline fn pow(self: Self, comptime exp: comptime_int) Tensor(
            T,
            dims.scale(exp).argsOpt(),
            scales.argsOpt(),
            shape_,
        ) {
            if (comptime hlp.isInt(T)) {
                var result: Vec = undefined;
                inline for (0..total) |i|
                    result[i] = std.math.powi(T, self.data[i], exp) catch std.math.maxInt(T);
                return .{ .data = result };
            } else {
                const abs_exp = comptime @abs(exp);
                var result: Vec = @splat(1);
                comptime var i = 0;
                inline while (i < abs_exp) : (i += 1) result *= self.data;
                if (comptime exp < 0) result = @as(Vec, @splat(1)) / result;
                return .{ .data = result };
            }
        }

        /// Square root of every element.  All dimension exponents must be even.
        pub inline fn sqrt(self: Self) Tensor(
            T,
            dims.div(2).argsOpt(),
            scales.argsOpt(),
            shape_,
        ) {
            if (comptime !dims.isSquare())
                @compileError("Cannot take sqrt of " ++ dims.str() ++ ": exponents must be even.");
            if (comptime @typeInfo(T) == .float) {
                return .{ .data = @sqrt(self.data) };
            } else {
                var result: Vec = undefined;
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
                inline for (0..total) |i| {
                    const v = self.data[i];
                    result[i] = if (v < 0) 0 else @as(T, @intCast(std.math.sqrt(@as(UnsignedT, @intCast(v)))));
                }
                return .{ .data = result };
            }
        }

        /// Negate every element.
        pub inline fn negate(self: Self) Self {
            return .{ .data = -self.data };
        }

        // ───────────────────────────────────────────────────────────────
        // Conversion
        // ───────────────────────────────────────────────────────────────

        /// Convert to a compatible Tensor type.
        ///   • Dimension mismatch → compile error.
        ///   • Dest.total must equal self.total, or Dest.total == 1 (scalar pattern).
        ///   • Scale ratio is computed fully at comptime; only a SIMD multiply at runtime.
        pub inline fn to(
            self: Self,
            comptime Dest: type,
        ) Tensor(Dest.ValueType, Dest.dims.argsOpt(), Dest.scales.argsOpt(), shape_) {
            const ActualDest = Tensor(Dest.ValueType, Dest.dims.argsOpt(), Dest.scales.argsOpt(), shape_);

            if (comptime !dims.eql(ActualDest.dims))
                @compileError("Dimension mismatch in to: " ++ dims.str() ++ " vs " ++ ActualDest.dims.str());
            if (comptime Self == ActualDest) return self;

            comptime std.debug.assert(Dest.total == total or Dest.total == 1);

            const DestT  = ActualDest.ValueType;
            const ratio  = comptime (scales.getFactor(dims) / ActualDest.scales.getFactor(ActualDest.dims));
            const DestVec = @Vector(total, DestT);

            // ── Same numeric type ──────────────────────────────────────
            if (comptime T == DestT) {
                if (comptime @typeInfo(T) == .float)
                    return .{ .data = self.data * @as(DestVec, @splat(@as(T, @floatCast(ratio)))) };

                // Integer — branch prevents division-by-zero
                if (comptime ratio >= 1.0) {
                    const mult: T = comptime @intFromFloat(@round(ratio));
                    return .{ .data = self.data *| @as(Vec, @splat(mult)) };
                } else {
                    const div_val: T = comptime @intFromFloat(@round(1.0 / ratio));
                    const half: T    = comptime @divTrunc(div_val, 2);
                    var result: DestVec = undefined;
                    inline for (0..total) |i| {
                        const val = self.data[i];
                        result[i] = if (val >= 0)
                            @divTrunc(val + half, div_val)
                        else
                            @divTrunc(val - half, div_val);
                    }
                    return .{ .data = result };
                }
            }

            // ── Cross numeric type ─────────────────────────────────────
            var result: DestVec = undefined;
            inline for (0..total) |i| {
                const float_val: f64 = switch (comptime @typeInfo(T)) {
                    .float => @floatCast(self.data[i]),
                    .int   => @floatFromInt(self.data[i]),
                    else   => unreachable,
                };
                const scaled = float_val * ratio;
                result[i] = switch (comptime @typeInfo(DestT)) {
                    .float => @floatCast(scaled),
                    .int   => @intFromFloat(@round(scaled)),
                    else   => unreachable,
                };
            }
            return .{ .data = result };
        }

        // ───────────────────────────────────────────────────────────────
        // Comparisons
        //
        // Return type:  bool       when total == 1  (scalar semantics)
        //               [total]bool when total >  1  (element-wise, flat-indexed)
        //
        // Whole-tensor equality check → eqAll / neAll (always returns bool).
        // A shape {1} RHS is broadcast automatically, unifying the old
        // eqScalar / gtScalar / … family into the plain eq / gt / … methods.
        // ───────────────────────────────────────────────────────────────

        const CmpResult = if (total == 1) bool else [total]bool;

        inline fn cmpResult(v: @Vector(total, bool)) CmpResult {
            return if (comptime total == 1) v[0] else @as([total]bool, v);
        }

        /// Resolve both sides to the finer scale, broadcasting shape {1} RHS if needed.
        inline fn resolveScalePair(self: Self, rhs_q: anytype) struct { l: Vec, r: Vec } {
            const RhsType   = @TypeOf(rhs_q);
            const TargetType = Tensor(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), shape_);
            const l: Vec = if (comptime Self == TargetType) self.data else self.to(TargetType).data;
            const rr: Vec = blk: {
                const RhsNorm = Tensor(T, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt(), RhsType.shape);
                const rn = if (comptime RhsType == RhsNorm) rhs_q else rhs_q.to(RhsNorm);
                break :blk broadcastToVec(RhsNorm, rn);
            };
            return .{ .l = l, .r = rr };
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

        /// True iff every element is equal after scale resolution.
        pub inline fn eqAll(self: Self, other: anytype) bool {
            if (comptime !dims.eql(@TypeOf(other).dims))
                @compileError("Dimension mismatch in eqAll.");
            const p = resolveScalePair(self, other);
            return @reduce(.And, p.l == p.r);
        }

        /// True iff any element differs after scale resolution.
        pub inline fn neAll(self: Self, other: anytype) bool {
            return !self.eqAll(other);
        }

        // ───────────────────────────────────────────────────────────────
        // Contraction — generalised dot product / matrix multiply / einsum
        //
        //   a.contract(b, axis_a, axis_b)
        //
        //   Sums over dimension `axis_a` of `a` and `axis_b` of `b`.
        //   Requires a.shape[axis_a] == b.shape[axis_b]  (checked at comptime).
        //
        //   Result shape  = a.shape \ axis_a  ++  b.shape \ axis_b
        //   Result dims   = a.dims + b.dims  (exponents summed, as in mul)
        //   Result scales = finer of a, b
        //
        //   Special cases:
        //     rank-1 × rank-1, axis 0 × 0  →  dot product (result shape {1})
        //     rank-2 × rank-2, axis 1 × 0  →  matrix multiply
        //     rank-1 × rank-2, axis 0 × 0  →  vector–matrix product
        //
        //   All index arithmetic is comptime; runtime cost is the multiply-add loop only.
        // ───────────────────────────────────────────────────────────────

        pub inline fn contract(
            self: Self,
            other: anytype,
            comptime axis_a: usize,
            comptime axis_b: usize,
        ) blk: {
            const OT = @TypeOf(other);
            comptime std.debug.assert(axis_a < rank);
            comptime std.debug.assert(axis_b < OT.rank);
            comptime std.debug.assert(shape_[axis_a] == OT.shape[axis_b]);
            // Contracted-away free axes; empty joint → scalar shape {1}
            const sa     = shapeRemoveAxis(shape_, axis_a);
            const sb     = shapeRemoveAxis(OT.shape, axis_b);
            const rs_raw = shapeCat(&sa, &sb);
            const rs: []const usize = if (rs_raw.len == 0) &.{1} else &rs_raw;
            break :blk Tensor(
                T,
                dims.add(OT.dims).argsOpt(),
                hlp.finerScales(Self, OT).argsOpt(),
                rs,
            );
        } {
            const OT = @TypeOf(other);
            const k: usize = comptime shape_[axis_a]; // contraction dimension

            const sa     = comptime shapeRemoveAxis(shape_, axis_a);
            const sb     = comptime shapeRemoveAxis(OT.shape, axis_b);
            const rs_raw = comptime shapeCat(&sa, &sb);
            const rs: []const usize = comptime if (rs_raw.len == 0) &.{1} else &rs_raw;

            const ResultType = Tensor(
                T,
                dims.add(OT.dims).argsOpt(),
                hlp.finerScales(Self, OT).argsOpt(),
                rs,
            );

            // Normalise scales before accumulation
            const SelfNorm  = Tensor(T, dims.argsOpt(), hlp.finerScales(Self, OT).argsOpt(), shape_);
            const OtherNorm = Tensor(T, OT.dims.argsOpt(), hlp.finerScales(Self, OT).argsOpt(), OT.shape);
            const a_data = if (comptime Self == SelfNorm) self.data else self.to(SelfNorm).data;
            const b_data = if (comptime OT == OtherNorm) other.data else other.to(OtherNorm).data;

            // Precompute result strides from rs_raw (for coord decoding)
            const rs_raw_strides = comptime shapeStrides(&rs_raw);

            var result: ResultType = .{ .data = @splat(0) };

            inline for (0..ResultType.total) |res_flat| {
                // Decode result flat index into free coords using rs_raw layout.
                // When rs_raw.len == 0, decodeFlatCoords returns [0]usize{} — correct.
                const res_coords = comptime decodeFlatCoords(res_flat, rs_raw.len, rs_raw_strides);

                const a_free: [sa.len]usize = comptime res_coords[0..sa.len].*;
                const b_free: [sb.len]usize = comptime res_coords[sa.len..].*;

                var acc: T = 0;
                inline for (0..k) |ki| {
                    // Reinsert the contracted index into free coords → full coord arrays
                    const a_coords = comptime insertAxis(rank, axis_a, ki, &a_free);
                    const b_coords = comptime insertAxis(OT.rank, axis_b, ki, &b_free);
                    const a_flat   = comptime encodeFlatCoords(&a_coords, rank, _strides);
                    const b_flat   = comptime encodeFlatCoords(&b_coords, OT.rank, OT.strides_arr);

                    if (comptime hlp.isInt(T))
                        acc +|= a_data[a_flat] *| b_data[b_flat]
                    else
                        acc += a_data[a_flat] * b_data[b_flat];
                }
                result.data[res_flat] = acc;
            }
            return result;
        }

        // ───────────────────────────────────────────────────────────────
        // Reduction helpers
        // ───────────────────────────────────────────────────────────────

        /// Sum of squared elements.  Cheaper than length(); use for ordering.
        pub inline fn lengthSqr(self: Self) T {
            return @reduce(.Add, self.data * self.data);
        }

        /// Euclidean length (L2 norm).
        pub inline fn length(self: Self) T {
            const sq = self.lengthSqr();
            if (comptime @typeInfo(T) == .int) {
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
                return @as(T, @intCast(std.math.sqrt(@as(UnsignedT, @intCast(sq)))));
            }
            return @sqrt(sq);
        }

        /// Product of all elements.  Result has shape {1}; dimension exponent × total.
        pub inline fn product(self: Self) Tensor(
            T,
            dims.scale(@as(comptime_int, total)).argsOpt(),
            scales.argsOpt(),
            &.{1},
        ) {
            return .{ .data = .{@reduce(.Mul, self.data)} };
        }

        // ───────────────────────────────────────────────────────────────
        // Formatting
        // ───────────────────────────────────────────────────────────────

        pub fn formatNumber(
            self: Self,
            writer: *std.Io.Writer,
            options: std.fmt.Number,
        ) !void {
            if (comptime total == 1) {
                switch (@typeInfo(T)) {
                    .float, .comptime_float => try writer.printFloat(self.data[0], options),
                    .int, .comptime_int     => try writer.printInt(self.data[0], 10, .lower, .{
                        .width     = options.width,
                        .alignment = options.alignment,
                        .fill      = options.fill,
                        .precision = options.precision,
                    }),
                    else => unreachable,
                }
            } else {
                try writer.writeAll("(");
                inline for (0..total) |i| {
                    if (i > 0) try writer.writeAll(", ");
                    switch (@typeInfo(T)) {
                        .float, .comptime_float => try writer.printFloat(self.data[i], options),
                        .int, .comptime_int     => try writer.printInt(self.data[i], 10, .lower, .{
                            .width     = options.width,
                            .alignment = options.alignment,
                            .fill      = options.fill,
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

// ═════════════════════════════════════════════════════════════════════════════
// Tests
// ─────────────────────────────────────────────────────────────────────────────
// Naming convention used throughout:
//   Tensor(T, d, s, &.{1})  →  former Scalar
//   Tensor(T, d, s, &.{N})  →  former Vector of length N
//   .data[0]                →  former .value()
//   .mul(x)                 →  former .mulScalar(x)  (x may be scalar Tensor or bare number)
//   .div(x)                 →  former .divScalar(x)
//   .eq(x)                  →  former .eqScalar(x)   (broadcasts when x.total==1)
//   .contract(other, 0, 0)  →  former .dot(other)    (for rank-1 tensors)
// ═════════════════════════════════════════════════════════════════════════════

// ─── Scalar tests ─────────────────────────────────────────────────────────

test "Scalar initiat" {
    const Meter  = Tensor(i128, .{ .L = 1 }, .{ .L = @enumFromInt(-3) }, &.{1});
    const Second = Tensor(f32,  .{ .T = 1 }, .{ .T = .n },               &.{1});

    const distance = Meter.splat(10);
    const time     = Second.splat(2);

    try std.testing.expectEqual(10, distance.data[0]);
    try std.testing.expectEqual(2,  time.data[0]);
}

test "Scalar comparisons (eq, ne, gt, gte, lt, lte)" {
    const Meter     = Tensor(i128, .{ .L = 1 }, .{},        &.{1});
    const KiloMeter = Tensor(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const m1000 = Meter.splat(1000);
    const km1   = KiloMeter.splat(1);
    const km2   = KiloMeter.splat(2);

    try std.testing.expect(m1000.eq(km1));
    try std.testing.expect(km1.eq(m1000));
    try std.testing.expect(km2.ne(m1000));

    try std.testing.expect(km2.gt(m1000));
    try std.testing.expect(km2.gt(km1));
    try std.testing.expect(km1.gte(m1000));
    try std.testing.expect(km2.gte(m1000));

    try std.testing.expect(m1000.lt(km2));
    try std.testing.expect(km1.lt(km2));
    try std.testing.expect(km1.lte(m1000));
    try std.testing.expect(m1000.lte(km2));
}

test "Scalar Add" {
    const Meter     = Tensor(i128, .{ .L = 1 }, .{},           &.{1});
    const KiloMeter = Tensor(i128, .{ .L = 1 }, .{ .L = .k },  &.{1});
    const KiloMeter_f = Tensor(f64, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const distance  = Meter.splat(10);
    const distance2 = Meter.splat(20);
    const added     = distance.add(distance2);
    try std.testing.expectEqual(30, added.data[0]);
    try std.testing.expectEqual(1,  @TypeOf(added).dims.get(.L));

    const distance3 = KiloMeter.splat(2);
    const added2    = distance.add(distance3);
    try std.testing.expectEqual(2010, added2.data[0]);

    const added3 = distance3.add(distance).to(KiloMeter);
    try std.testing.expectEqual(2, added3.data[0]);

    const distance4 = KiloMeter_f.splat(2);
    const added4    = distance4.add(distance).to(KiloMeter_f);
    try std.testing.expectApproxEqAbs(2.01, added4.data[0], 0.000001);
}

test "Scalar Sub" {
    const Meter       = Tensor(i128, .{ .L = 1 }, .{},          &.{1});
    const KiloMeter_f = Tensor(f64,  .{ .L = 1 }, .{ .L = .k }, &.{1});

    const a    = Meter.splat(500);
    const b    = Meter.splat(200);
    const diff = a.sub(b);
    try std.testing.expectEqual(300,  diff.data[0]);
    const diff2 = b.sub(a);
    try std.testing.expectEqual(-300, diff2.data[0]);

    const km_f  = KiloMeter_f.splat(2.5);
    const m_f   = Meter.splat(500);
    const diff3 = km_f.sub(m_f);
    try std.testing.expectApproxEqAbs(2000, diff3.data[0], 1e-4);
}

test "Scalar MulBy" {
    const Meter  = Tensor(i128, .{ .L = 1 }, .{}, &.{1});
    const Second = Tensor(f32,  .{ .T = 1 }, .{}, &.{1});

    const d  = Meter.splat(3);
    const t  = Second.splat(4);
    const at = d.mul(t);
    try std.testing.expectEqual(12, at.data[0]);
    try std.testing.expectEqual(1,  @TypeOf(at).dims.get(.L));
    try std.testing.expectEqual(1,  @TypeOf(at).dims.get(.T));

    const d2   = Meter.splat(5);
    const area = d.mul(d2);
    try std.testing.expectEqual(15, area.data[0]);
    try std.testing.expectEqual(2,  @TypeOf(area).dims.get(.L));
}

test "Scalar MulBy with scale" {
    const KiloMeter = Tensor(f32, .{ .L = 1 }, .{ .L = .k }, &.{1});
    const KiloGram  = Tensor(f32, .{ .M = 1 }, .{ .M = .k }, &.{1});

    const dist = KiloMeter.splat(2.0);
    const mass = KiloGram.splat(3.0);
    const prod = dist.mul(mass);
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.M));
}

test "Scalar MulBy with type change" {
    const Meter  = Tensor(i128, .{ .L = 1 },      .{ .L = .k }, &.{1});
    const Second = Tensor(f64,  .{ .T = 1 },      .{},          &.{1});
    const KmSec  = Tensor(i64,  .{ .L = 1, .T = 1 }, .{ .L = .k }, &.{1});
    const KmSec_f = Tensor(f32, .{ .L = 1, .T = 1 }, .{ .L = .k }, &.{1});

    const d = Meter.splat(3);
    const t = Second.splat(4);

    try std.testing.expectEqual(12, d.mul(t).to(KmSec).data[0]);
    try std.testing.expectApproxEqAbs(12.0, d.mul(t).to(KmSec_f).data[0], 0.0001);
}

test "Scalar MulBy small" {
    const Meter  = Tensor(i128, .{ .L = 1 }, .{ .L = .n }, &.{1});
    const Second = Tensor(f32,  .{ .T = 1 }, .{},          &.{1});
    const d = Meter.splat(3);
    const t = Second.splat(4);
    try std.testing.expectEqual(12, d.mul(t).data[0]);
}

test "Scalar MulBy dimensionless" {
    const DimLess = Tensor(i128, .{},        .{}, &.{1});
    const Meter   = Tensor(i128, .{ .L = 1 }, .{}, &.{1});
    const d      = Meter.splat(7);
    const scaled = d.mul(DimLess.splat(3));
    try std.testing.expectEqual(21, scaled.data[0]);
}

test "Scalar Sqrt" {
    const MeterSquare   = Tensor(i128, .{ .L = 2 }, .{}, &.{1});
    const MeterSquare_f = Tensor(f64,  .{ .L = 2 }, .{}, &.{1});

    var d      = MeterSquare.splat(9);
    var scaled = d.sqrt();
    try std.testing.expectEqual(3, scaled.data[0]);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));

    d      = MeterSquare.splat(-5);
    scaled = d.sqrt();
    try std.testing.expectEqual(0, scaled.data[0]);

    const d2      = MeterSquare_f.splat(20);
    const scaled2 = d2.sqrt();
    try std.testing.expectApproxEqAbs(4.472135955, scaled2.data[0], 1e-4);
}

test "Scalar Chained: velocity and acceleration" {
    const Meter  = Tensor(i128, .{ .L = 1 }, .{}, &.{1});
    const Second = Tensor(f32,  .{ .T = 1 }, .{}, &.{1});

    const dist     = Meter.splat(100);
    const t1       = Second.splat(5);
    const velocity = dist.div(t1);
    try std.testing.expectEqual(20, velocity.data[0]);

    const t2    = Second.splat(4);
    const accel = velocity.div(t2);
    try std.testing.expectEqual(5, accel.data[0]);
}

test "Scalar DivBy integer exact" {
    const Meter  = Tensor(i128, .{ .L = 1 }, .{}, &.{1});
    const Second = Tensor(f32,  .{ .T = 1 }, .{}, &.{1});

    const dist = Meter.splat(120);
    const time = Second.splat(4);
    const vel  = dist.div(time);
    try std.testing.expectEqual(30, vel.data[0]);
}

test "Scalar Finer scales skip dim 0" {
    const Dimless    = Tensor(i128, .{},        .{},          &.{1});
    const KiloMetre  = Tensor(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const r    = Dimless.splat(30);
    const km   = KiloMetre.splat(4);
    const vel  = r.mul(km);
    try std.testing.expectEqual(120, vel.data[0]);
    try std.testing.expectEqual(Scales.UnitScale.k, @TypeOf(vel).scales.get(.L));
}

test "Scalar Conversion chain: km -> m -> cm" {
    const KiloMeter  = Tensor(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});
    const Meter      = Tensor(i128, .{ .L = 1 }, .{},           &.{1});
    const CentiMeter = Tensor(i128, .{ .L = 1 }, .{ .L = .c },  &.{1});

    const km = KiloMeter.splat(15);
    const m  = km.to(Meter);
    const cm = m.to(CentiMeter);
    try std.testing.expectEqual(15_000,   m.data[0]);
    try std.testing.expectEqual(1_500_000, cm.data[0]);
}

test "Scalar Conversion: hours -> minutes -> seconds" {
    const Hour   = Tensor(i128, .{ .T = 1 }, .{ .T = .hour }, &.{1});
    const Minute = Tensor(i128, .{ .T = 1 }, .{ .T = .min },  &.{1});
    const Second = Tensor(i128, .{ .T = 1 }, .{},             &.{1});

    const h   = Hour.splat(1);
    const min = h.to(Minute);
    const sec = min.to(Second);
    try std.testing.expectEqual(60,   min.data[0]);
    try std.testing.expectEqual(3600, sec.data[0]);
}

test "Scalar Format" {
    const MeterPerSecondSq = Tensor(f32, .{ .L = 1, .T = -2 }, .{ .T = .n }, &.{1});
    const Meter            = Tensor(f32, .{ .L = 1 },           .{},          &.{1});

    const m     = Meter.splat(1.23456);
    const accel = MeterPerSecondSq.splat(9.81);

    var buf: [64]u8 = undefined;
    var res = try std.fmt.bufPrint(&buf, "{d:.2}", .{m});
    try std.testing.expectEqualStrings("1.23m", res);

    res = try std.fmt.bufPrint(&buf, "{d}", .{accel});
    try std.testing.expectEqualStrings("9.81m.ns⁻²", res);
}

test "Scalar Abs" {
    const Meter    = Tensor(i128, .{ .L = 1 }, .{}, &.{1});
    const MeterF   = Tensor(f32,  .{ .L = 1 }, .{}, &.{1});

    try std.testing.expectEqual(50,   Meter.splat(-50).abs().data[0]);
    try std.testing.expectEqual(42.5, MeterF.splat(-42.5).abs().data[0]);
}

test "Scalar Pow" {
    const Meter = Tensor(i128, .{ .L = 1 }, .{}, &.{1});
    const d     = Meter.splat(4);
    try std.testing.expectEqual(16, d.pow(2).data[0]);
    try std.testing.expectEqual(64, d.pow(3).data[0]);
}

test "Scalar mul comptime_int" {
    const Meter = Tensor(i128, .{ .L = 1 }, .{}, &.{1});
    const d     = Meter.splat(7);
    try std.testing.expectEqual(21, d.mul(3).data[0]);
}

test "Scalar add/sub bare number on dimensionless scalar" {
    const DimLess = Tensor(i128, .{}, .{}, &.{1});
    const a = DimLess.splat(10);
    try std.testing.expectEqual(15, a.add(5).data[0]);
    try std.testing.expectEqual(7,  a.sub(3).data[0]);
}

test "Scalar Imperial length scales" {
    const Foot  = Tensor(f64, .{ .L = 1 }, .{ .L = .ft   }, &.{1});
    const Meter = Tensor(f64, .{ .L = 1 }, .{},             &.{1});
    const Inch  = Tensor(f64, .{ .L = 1 }, .{ .L = .inch  }, &.{1});

    try std.testing.expectApproxEqAbs(0.3048, Foot.splat(1.0).to(Meter).data[0], 1e-9);
    try std.testing.expectApproxEqAbs(1.0,    Inch.splat(12.0).to(Foot).data[0],  1e-9);
}

test "Scalar Imperial mass scales" {
    const Pound = Tensor(f64, .{ .M = 1 }, .{ .M = .lb }, &.{1});
    const Ounce = Tensor(f64, .{ .M = 1 }, .{ .M = .oz }, &.{1});

    const total = Pound.splat(2.0).add(Ounce.splat(8.0)).to(Pound);
    try std.testing.expectApproxEqAbs(2.5, total.data[0], 1e-6);
}

test "Scalar comparisons with comptime_int on dimensionless scalar" {
    const DimLess = Tensor(i128, .{}, .{}, &.{1});
    const x = DimLess.splat(42);
    try std.testing.expect(x.eq(42));
    try std.testing.expect(x.gt(10));
}

// ─── Vector / Tensor tests ────────────────────────────────────────────────

test "Vector initiate" {
    const Meter4 = Tensor(f32, .{ .L = 1 }, .{}, &.{4});
    const m = Meter4.splat(1);
    try std.testing.expect(m.data[0] == 1);
    try std.testing.expect(m.data[3] == 1);
}

test "Vector format" {
    const MeterPerSecondSq  = Tensor(f32, .{ .L = 1, .T = -2 },          .{ .T = .n }, &.{3});
    const KgMeterPerSecond  = Tensor(f32, .{ .M = 1, .L = 1, .T = -1 },  .{ .M = .k }, &.{3});

    const accel    = MeterPerSecondSq.splat(9.81);
    const momentum = KgMeterPerSecond{ .data = .{ 43, 0, 11 } };

    var buf: [64]u8 = undefined;
    var res = try std.fmt.bufPrint(&buf, "{d}", .{accel});
    try std.testing.expectEqualStrings("(9.81, 9.81, 9.81)m.ns⁻²", res);

    res = try std.fmt.bufPrint(&buf, "{d:.2}", .{momentum});
    try std.testing.expectEqualStrings("(43.00, 0.00, 11.00)m.kg.s⁻¹", res);
}

test "Vector Vec3 Init and Basic Arithmetic" {
    const Meter3 = Tensor(i32, .{ .L = 1 }, .{}, &.{3});

    const v_zero = Meter3.zero;
    try std.testing.expectEqual(0, v_zero.data[0]);
    try std.testing.expectEqual(0, v_zero.data[2]);

    const v_one = Meter3.one;
    try std.testing.expectEqual(1, v_one.data[0]);

    const v_def = Meter3.splat(5);
    try std.testing.expectEqual(5, v_def.data[2]);

    const v1 = Meter3{ .data = .{ 10, 20, 30 } };
    const v2 = Meter3{ .data = .{ 2,  4,  6  } };

    const added = v1.add(v2);
    try std.testing.expectEqual(12, added.data[0]);
    try std.testing.expectEqual(24, added.data[1]);
    try std.testing.expectEqual(36, added.data[2]);

    const subbed = v1.sub(v2);
    try std.testing.expectEqual(8,  subbed.data[0]);
    try std.testing.expectEqual(16, subbed.data[1]);
    try std.testing.expectEqual(24, subbed.data[2]);

    const neg = v1.negate();
    try std.testing.expectEqual(-10, neg.data[0]);
    try std.testing.expectEqual(-20, neg.data[1]);
    try std.testing.expectEqual(-30, neg.data[2]);
}

test "Vector Kinematics (scalar mul/div broadcast)" {
    const Meter3  = Tensor(i32, .{ .L = 1 }, .{}, &.{3});
    const Second1 = Tensor(i32, .{ .T = 1 }, .{}, &.{1});

    const pos  = Meter3{ .data = .{ 100, 200, 300 } };
    const time = Second1.splat(10);

    const vel = pos.div(time);
    try std.testing.expectEqual(10,  vel.data[0]);
    try std.testing.expectEqual(20,  vel.data[1]);
    try std.testing.expectEqual(30,  vel.data[2]);
    try std.testing.expectEqual(1,   @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1,  @TypeOf(vel).dims.get(.T));

    const new_pos = vel.mul(time);
    try std.testing.expectEqual(100, new_pos.data[0]);
    try std.testing.expectEqual(0,   @TypeOf(new_pos).dims.get(.T));
}

test "Vector Element-wise Math and Scaling" {
    const Meter3 = Tensor(i32, .{ .L = 1 }, .{}, &.{3});

    const v1  = Meter3{ .data = .{ 10, 20, 30 } };
    const v2  = Meter3{ .data = .{ 2,  5,  10 } };
    const dv  = v1.div(v2);
    try std.testing.expectEqual(5, dv.data[0]);
    try std.testing.expectEqual(4, dv.data[1]);
    try std.testing.expectEqual(3, dv.data[2]);
    try std.testing.expectEqual(0, @TypeOf(dv).dims.get(.L));
}

test "Vector Conversions" {
    const KiloMeter3 = Tensor(i32, .{ .L = 1 }, .{ .L = .k }, &.{3});
    const Meter3     = Tensor(i32, .{ .L = 1 }, .{},           &.{3});

    const v_km = KiloMeter3{ .data = .{ 1, 2, 3 } };
    const v_m  = v_km.to(Meter3);
    try std.testing.expectEqual(1000, v_m.data[0]);
    try std.testing.expectEqual(2000, v_m.data[1]);
    try std.testing.expectEqual(3000, v_m.data[2]);
    try std.testing.expectEqual(UnitScale.none, @TypeOf(v_m).scales.get(.L));
}

test "Vector Length" {
    const MeterInt3   = Tensor(i32, .{ .L = 1 }, .{}, &.{3});
    const MeterFloat3 = Tensor(f32, .{ .L = 1 }, .{}, &.{3});

    const v_int = MeterInt3{ .data = .{ 3, 4, 0 } };
    try std.testing.expectEqual(25, v_int.lengthSqr());
    try std.testing.expectEqual(5,  v_int.length());

    const v_float = MeterFloat3{ .data = .{ 3.0, 4.0, 0.0 } };
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), v_float.lengthSqr(), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0),  v_float.length(),    1e-4);
}

test "Vector Comparisons" {
    const Meter3     = Tensor(f32, .{ .L = 1 }, .{},           &.{3});
    const KiloMeter3 = Tensor(f32, .{ .L = 1 }, .{ .L = .k },  &.{3});

    const v1 = Meter3{    .data = .{ 1000.0, 500.0, 0.0 } };
    const v2 = KiloMeter3{ .data = .{ 1.0,  0.5,  0.0 } };
    const v3 = KiloMeter3{ .data = .{ 1.0,  0.6,  0.0 } };

    try std.testing.expect(v1.eqAll(v2));
    try std.testing.expect(v1.neAll(v3));

    const higher = v3.gt(v1);
    try std.testing.expectEqual(false, higher[0]);
    try std.testing.expectEqual(true,  higher[1]);
    try std.testing.expectEqual(false, higher[2]);

    const equal = v3.eq(v1);
    try std.testing.expectEqual(true,  equal[0]);
    try std.testing.expectEqual(false, equal[1]);
    try std.testing.expectEqual(true,  equal[2]);

    const low_eq = v1.lte(v3);
    try std.testing.expect(low_eq[0] and low_eq[1] and low_eq[2]);
}

test "Vector vs Scalar broadcast comparison" {
    // Replaces the old eqScalar / gtScalar — now just eq / gt with a shape-{1} rhs.
    const Meter3     = Tensor(f32, .{ .L = 1 }, .{},          &.{3});
    const KiloMeter1 = Tensor(f32, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const positions = Meter3{ .data = .{ 500.0, 1200.0, 3000.0 } };
    const threshold = KiloMeter1.splat(1); // 1 km = 1000 m

    const exceeded = positions.gt(threshold);
    try std.testing.expectEqual(false, exceeded[0]);
    try std.testing.expectEqual(true,  exceeded[1]);
    try std.testing.expectEqual(true,  exceeded[2]);

    const Meter1   = Tensor(f32, .{ .L = 1 }, .{}, &.{1});
    const exact    = positions.eq(Meter1.splat(500));
    try std.testing.expect(exact[0] == true);
    try std.testing.expect(exact[1] == false);
}

test "Vector contract — dot product (rank-1 × rank-1)" {
    const Meter3   = Tensor(f32, .{ .L = 1 },                 .{}, &.{3});
    const Newton3  = Tensor(f32, .{ .M = 1, .L = 1, .T = -2 }, .{}, &.{3});

    const pos   = Meter3{  .data = .{ 10.0, 0.0, 0.0 } };
    const force = Newton3{ .data = .{ 5.0,  5.0, 0.0 } };

    // work = force · pos
    const work = force.contract(pos, 0, 0);
    try std.testing.expectEqual(50.0, work.data[0]);
    try std.testing.expectEqual(1, @TypeOf(work).dims.get(.M));
    try std.testing.expectEqual(2, @TypeOf(work).dims.get(.L));
    try std.testing.expectEqual(-2, @TypeOf(work).dims.get(.T));
}

test "Vector contract — matrix multiply (rank-2 × rank-2)" {
    // 2×3 matrix multiplied by 3×2 matrix → 2×2 result
    const A = Tensor(f32, .{}, .{}, &.{2, 3});
    const B = Tensor(f32, .{}, .{}, &.{3, 2});

    // A = [[1, 2, 3],
    //      [4, 5, 6]]
    const a = A{ .data = .{ 1, 2, 3, 4, 5, 6 } };
    // B = [[7, 8],
    //      [9, 10],
    //      [11, 12]]
    const b = B{ .data = .{ 7, 8, 9, 10, 11, 12 } };

    // C = A @ B  (contract over axis 1 of A × axis 0 of B)
    // C[0][0] = 1*7 + 2*9  + 3*11 = 7  + 18 + 33 = 58
    // C[0][1] = 1*8 + 2*10 + 3*12 = 8  + 20 + 36 = 64
    // C[1][0] = 4*7 + 5*9  + 6*11 = 28 + 45 + 66 = 139
    // C[1][1] = 4*8 + 5*10 + 6*12 = 32 + 50 + 72 = 154
    const c = a.contract(b, 1, 0);
    try std.testing.expectEqual(58,  c.data[Tensor(f32, .{}, .{}, &.{2,2}).idx(.{0, 0})]);
    try std.testing.expectEqual(64,  c.data[Tensor(f32, .{}, .{}, &.{2,2}).idx(.{0, 1})]);
    try std.testing.expectEqual(139, c.data[Tensor(f32, .{}, .{}, &.{2,2}).idx(.{1, 0})]);
    try std.testing.expectEqual(154, c.data[Tensor(f32, .{}, .{}, &.{2,2}).idx(.{1, 1})]);
}

test "Vector Abs, Pow, Sqrt and Product" {
    const Meter3 = Tensor(f32, .{ .L = 1 }, .{}, &.{3});

    const v1    = Meter3{ .data = .{ -2.0, 3.0, -4.0 } };
    const v_abs = v1.abs();
    try std.testing.expectEqual(2.0, v_abs.data[0]);
    try std.testing.expectEqual(4.0, v_abs.data[2]);

    const vol = v_abs.product();
    try std.testing.expectEqual(24.0, vol.data[0]);
    try std.testing.expectEqual(3, @TypeOf(vol).dims.get(.L));

    const area_vec = v_abs.pow(2);
    try std.testing.expectEqual(4.0,  area_vec.data[0]);
    try std.testing.expectEqual(16.0, area_vec.data[2]);
    try std.testing.expectEqual(2, @TypeOf(area_vec).dims.get(.L));

    const sqrted = area_vec.sqrt();
    try std.testing.expectEqual(2, sqrted.data[0]);
    try std.testing.expectEqual(4, sqrted.data[2]);
    try std.testing.expectEqual(1, @TypeOf(sqrted).dims.get(.L));
}

test "Vector mul comptime_int broadcast" {
    const Meter3 = Tensor(i32, .{ .L = 1 }, .{}, &.{3});
    const v      = Meter3{ .data = .{ 1, 2, 3 } };
    const scaled = v.mul(10);
    try std.testing.expectEqual(10, scaled.data[0]);
    try std.testing.expectEqual(20, scaled.data[1]);
    try std.testing.expectEqual(30, scaled.data[2]);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
}

test "Vector mul comptime_float broadcast" {
    const MeterF3 = Tensor(f32, .{ .L = 1 }, .{}, &.{3});
    const v       = MeterF3{ .data = .{ 1.0, 2.0, 4.0 } };
    const scaled  = v.mul(0.5);
    try std.testing.expectApproxEqAbs(0.5, scaled.data[0], 1e-6);
    try std.testing.expectApproxEqAbs(1.0, scaled.data[1], 1e-6);
    try std.testing.expectApproxEqAbs(2.0, scaled.data[2], 1e-6);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
}

test "Vector div comptime_int broadcast" {
    const Meter3 = Tensor(i32, .{ .L = 1 }, .{}, &.{3});
    const v      = Meter3{ .data = .{ 10, 20, 30 } };
    const halved = v.div(2);
    try std.testing.expectEqual(5,  halved.data[0]);
    try std.testing.expectEqual(10, halved.data[1]);
    try std.testing.expectEqual(15, halved.data[2]);
    try std.testing.expectEqual(1, @TypeOf(halved).dims.get(.L));
}

test "Vector div comptime_float broadcast" {
    const MeterF3 = Tensor(f64, .{ .L = 1 }, .{}, &.{3});
    const v       = MeterF3{ .data = .{ 9.0, 6.0, 3.0 } };
    const r       = v.div(3.0);
    try std.testing.expectApproxEqAbs(3.0, r.data[0], 1e-9);
    try std.testing.expectApproxEqAbs(2.0, r.data[1], 1e-9);
    try std.testing.expectApproxEqAbs(1.0, r.data[2], 1e-9);
}

test "Vector eq broadcast on dimensionless" {
    const DimLess3 = Tensor(i32, .{}, .{}, &.{3});
    const v = DimLess3{ .data = .{ 1, 2, 3 } };

    const eq_res = v.eq(2);
    try std.testing.expectEqual(false, eq_res[0]);
    try std.testing.expectEqual(true,  eq_res[1]);
    try std.testing.expectEqual(false, eq_res[2]);

    const gt_res = v.gt(1);
    try std.testing.expectEqual(false, gt_res[0]);
    try std.testing.expectEqual(true,  gt_res[1]);
    try std.testing.expectEqual(true,  gt_res[2]);
}

test "Tensor idx helper and matrix access" {
    const Mat3x3 = Tensor(f32, .{}, .{}, &.{3, 3});
    // Identity-like: set [0][0]=1, [1][1]=2, [2][2]=3
    var m: Mat3x3 = Mat3x3.zero;
    m.data[Mat3x3.idx(.{0, 0})] = 1.0;
    m.data[Mat3x3.idx(.{1, 1})] = 2.0;
    m.data[Mat3x3.idx(.{2, 2})] = 3.0;

    try std.testing.expectEqual(1.0, m.data[0]); // [0][0]
    try std.testing.expectEqual(2.0, m.data[4]); // [1][1]  (stride 3 → 1*3+1=4)
    try std.testing.expectEqual(3.0, m.data[8]); // [2][2]  (2*3+2=8)
    try std.testing.expectEqual(0.0, m.data[1]); // [0][1]
}

test "Tensor strides_arr correctness" {
    const T1 = Tensor(f32, .{}, .{}, &.{3});
    const T2 = Tensor(f32, .{}, .{}, &.{3, 4});
    const T3 = Tensor(f32, .{}, .{}, &.{2, 3, 4});

    try std.testing.expectEqual(1,  T1.strides_arr[0]);
    try std.testing.expectEqual(4,  T2.strides_arr[0]);
    try std.testing.expectEqual(1,  T2.strides_arr[1]);
    try std.testing.expectEqual(12, T3.strides_arr[0]);
    try std.testing.expectEqual(4,  T3.strides_arr[1]);
    try std.testing.expectEqual(1,  T3.strides_arr[2]);
}
