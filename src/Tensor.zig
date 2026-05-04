const std = @import("std");
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;
const sh = @import("shared.zig");

// ─────────────────────────────────────────────────────────────────────────────
// File-scope RHS normalisation helpers
// ─────────────────────────────────────────────────────────────────────────────

inline fn isTensor(comptime Rhs: type) bool {
    return comptime @typeInfo(Rhs) == .@"struct" and @hasDecl(Rhs, "ISTENSOR");
}

/// SIMD implementation of a Tensor.
/// Limited to tensor of ~2000 values.
/// For more, see either TensorAlloc or TensorGPU
pub fn TensorStatic(
    comptime T: type,
    comptime d_opt: Dimensions.ArgOpts,
    comptime s_opt: Scales.ArgOpts,
    comptime shape_: []const comptime_int,
) type {
    comptime {
        if (shape_.len == 0)
            @compileError("Tensor shape must have at least 1 dimension (rank >= 1).");
        for (shape_) |s|
            if (s < 1) @compileError("Tensor shape dimensions must be strictly >= 1.");
    }
    @setEvalBranchQuota(100_000_000);

    const _total: usize = comptime sh.shapeTotal(shape_);
    const _strides = comptime sh.shapeStrides(shape_);
    const Vec = @Vector(_total, T);

    if (comptime _total * @bitSizeOf(T) > 1_000_000)
        @compileError("Tensor too big, consider using a TensorGPU or TensorAlloc.");

    return struct {
        data: Vec,

        const Self = @This();

        pub const ValueType: type = T;
        pub const dims: Dimensions = Dimensions.init(d_opt);
        pub const scales: Scales = Scales.init(s_opt);
        pub const shape: []const comptime_int = shape_;
        pub const rank: comptime_int = shape_.len;
        pub const total: comptime_int = _total;
        pub const strides_arr: [shape_.len]comptime_int = _strides;
        pub const ISTENSOR = true;

        /// Convert N-D coords (row-major) to flat index — fully comptime.
        /// Usage: Tensor.idx(.{row, col})
        pub inline fn idx(comptime coords: [rank]usize) usize {
            comptime {
                var flat: usize = 0;
                for (0..rank) |i| {
                    if (coords[i] >= shape[i]) @compileError("idx: Coordinate out of bounds");
                    flat += coords[i] * strides_arr[i];
                }
                return flat;
            }
        }

        /// Broadcast a single value across all elements.
        pub inline fn splat(v: T) Self {
            return .{ .data = @splat(v) };
        }

        pub const zero: Self = splat(0);
        pub const one: Self = splat(1);

        /// Return a mutable slice to the flat storage — zero-copy WebGPU buffer mapping.
        pub inline fn asSlice(self: *Self) []T {
            return @as([*]T, @ptrCast(&self.data))[0..total];
        }

        /// Element-wise add.  Dimensions must match; scales resolve to finer.
        /// RHS must have the same shape as self, or total == 1 (broadcast).
        pub inline fn add(self: *const Self, rhs: anytype) TensorStatic(
            T,
            dims.argsOpt(),
            sh.finerScales(Self, @TypeOf(rhs)).argsOpt(),
            shape,
        ) {
            const RhsType = @TypeOf(rhs);
            if (comptime !isTensor(RhsType))
                @compileError("rhs can only be a Tensor ");
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType.total != 1 and !sh.shapeEql(shape, RhsType.shape))
                @compileError("Shape mismatch in add: element-wise operations require identical shapes, or a scalar RHS.");

            const TargetType = TensorStatic(T, dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            const l: Vec = self.to(TargetType).data;
            const r: Vec = rhs.to(TargetType).data;
            return .{ .data = if (comptime sh.isInt(T)) l +| r else l + r };
        }

        /// Element-wise sub.  Dimensions must match; scales resolve to finer.
        /// RHS must have the same shape as self, or total == 1 (broadcast).
        pub inline fn sub(self: *const Self, rhs: anytype) TensorStatic(
            T,
            dims.argsOpt(),
            sh.finerScales(Self, @TypeOf(rhs)).argsOpt(),
            shape,
        ) {
            const RhsType = @TypeOf(rhs);
            if (comptime !isTensor(RhsType))
                @compileError("rhs can only be a Tensor ");
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType.total != 1 and !sh.shapeEql(shape, RhsType.shape))
                @compileError("Shape mismatch in add: element-wise operations require identical shapes, or a scalar RHS.");

            const TargetType = TensorStatic(T, dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            const l: Vec = self.to(TargetType).data;
            const r: Vec = rhs.to(TargetType).data;
            return .{ .data = if (comptime sh.isInt(T)) l -| r else l - r };
        }

        /// Element-wise multiply.  Dimension exponents summed.
        /// Shape {1} RHS is automatically broadcast across all elements.
        pub inline fn mul(self: *const Self, rhs: anytype) TensorStatic(
            T,
            dims.add(@TypeOf(rhs).dims).argsOpt(),
            sh.finerScales(Self, @TypeOf(rhs)).argsOpt(),
            shape,
        ) {
            const RhsType = @TypeOf(rhs);
            if (comptime !isTensor(RhsType))
                @compileError("rhs can only be a Tensor ");
            if (comptime RhsType.total != 1 and !sh.shapeEql(shape, RhsType.shape))
                @compileError("Shape mismatch in mul: element-wise operations require identical shapes, or a scalar RHS.");

            const SelfNorm = TensorStatic(T, dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            const RhsNorm = TensorStatic(T, RhsType.dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            const l: Vec = self.to(SelfNorm).data;
            const r: Vec = rhs.to(RhsNorm).data;
            return .{ .data = if (comptime sh.isInt(T)) l *| r else l * r };
        }

        /// Element-wise divide.  Dimension exponents subtracted.
        /// Shape {1} RHS is automatically broadcast across all elements.
        pub inline fn div(self: *const Self, rhs: anytype) TensorStatic(
            T,
            dims.sub(@TypeOf(rhs).dims).argsOpt(),
            sh.finerScales(Self, @TypeOf(rhs)).argsOpt(),
            shape,
        ) {
            const RhsType = @TypeOf(rhs);
            if (comptime !isTensor(RhsType))
                @compileError("rhs can only be a Tensor ");
            if (comptime RhsType.total != 1 and !sh.shapeEql(shape, RhsType.shape))
                @compileError("Shape mismatch in div: element-wise operations require identical shapes, or a scalar RHS.");

            const SelfNorm = TensorStatic(T, dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            const RhsNorm = TensorStatic(T, RhsType.dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            const l: Vec = self.to(SelfNorm).data;
            const r: Vec = rhs.to(RhsNorm).data;
            return .{ .data = if (comptime sh.isInt(T)) @divTrunc(l, r) else l / r };
        }

        /// Absolute value of every element.
        pub inline fn abs(self: *const Self) Self {
            return .{ .data = @bitCast(@abs(self.data)) };
        }

        /// Raise every element to a comptime integer exponent.
        pub inline fn pow(self: *const Self, comptime exp: comptime_int) TensorStatic(
            T,
            dims.scale(exp).argsOpt(),
            scales.argsOpt(),
            shape,
        ) {
            if (comptime exp < 0) @compileError("Pow only support exp >= 0");
            if (comptime exp == 0) return .{ .data = @splat(1) };
            if (comptime exp == 1) return self;
            var data: Vec = self.data;
            for (0..exp - 1) |_|
                data = data * self.data;
            return .{ .data = data };
        }

        /// Square root of every element.  All dimension exponents must be even.
        pub inline fn sqrt(self: *const Self) TensorStatic(
            T,
            dims.div(2).argsOpt(),
            scales.argsOpt(),
            shape,
        ) {
            if (comptime !dims.isSquare())
                @compileError("Cannot take sqrt of " ++ dims.str() ++ ": exponents must be even.");
            if (comptime @typeInfo(T) == .float)
                return .{ .data = @sqrt(self.data) };

            const arr: [total]T = self.data; // Add this!
            var res_arr: [total]T = undefined;
            const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
            for (0..total) |i| {
                const v = arr[i];
                res_arr[i] = if (v < 0) 0 else @as(T, @intCast(std.math.sqrt(@as(UnsignedT, @intCast(v)))));
            }
            return .{ .data = res_arr };
        }

        /// Negate every element.
        pub inline fn negate(self: *const Self) Self {
            return .{ .data = -self.data };
        }

        /// Convert to a compatible Tensor type.
        ///   • Dimension mismatch → compile error.
        ///   • Dest.shape must equal self.shape, or total == 1 -> splat to Dest shape (scalar pattern).
        ///   • Scale ratio is computed fully at comptime; only a SIMD multiply at runtime.
        pub inline fn to(
            self: *const Self,
            comptime Dest: type,
        ) Dest {
            if (comptime Self == Dest) return self.*;

            // Run validation checks FIRST before dealing with types
            if (comptime !dims.eql(Dest.dims))
                @compileError("Dimension mismatch in to: " ++ dims.str() ++ " vs " ++ Dest.dims.str());
            if (comptime total != 1 and !sh.shapeEql(shape, Dest.shape))
                @compileError("Shape mismatch in to: destination type must have the identical shape, or be a scalar.");

            const vec = if (comptime total == 1 and Dest.total != 1)
                TensorStatic(Dest.ValueType, dims.argsOpt(), scales.argsOpt(), Dest.shape){ .data = @splat(self.data[0]) }
            else
                self;

            const ratio = comptime (scales.getFactor(dims) / Dest.scales.getFactor(Dest.dims));
            const DestT = Dest.ValueType;
            const DestVec = @Vector(Dest.total, DestT);

            if (comptime ratio == 1.0 and T == DestT)
                return .{ .data = vec.data };

            // If ratio is 1, handle type conversion correctly based on BOTH source and dest types
            if (comptime ratio == 1.0) {
                const T_info = @typeInfo(T);
                const Dest_info = @typeInfo(DestT);

                return .{
                    .data = if (comptime T_info == .int and Dest_info == .int)
                        @as(DestVec, @intCast(vec.data))
                    else if (comptime T_info == .float and Dest_info == .float)
                        @as(DestVec, @floatCast(vec.data))
                    else if (comptime T_info == .int and Dest_info == .float)
                        @as(DestVec, @floatFromInt(vec.data))
                    else if (comptime T_info == .float and Dest_info == .int)
                        @as(DestVec, @intFromFloat(vec.data))
                    else
                        unreachable,
                };
            }

            if (comptime T == DestT) {
                if (comptime @typeInfo(T) == .float)
                    return .{ .data = vec.data * @as(DestVec, @splat(@as(T, @floatCast(ratio)))) };

                if (comptime ratio >= 1.0) {
                    const mult: T = comptime @intFromFloat(@round(ratio));
                    return .{ .data = vec.data *| @as(Vec, @splat(mult)) };
                } else {
                    const div_val: T = comptime @intFromFloat(@round(1.0 / ratio));
                    const half: T = comptime @divTrunc(div_val, 2);

                    if (comptime @typeInfo(T).int.signedness == .unsigned) {
                        return .{ .data = @divTrunc(vec.data + @as(Vec, @splat(half)), @as(Vec, @splat(div_val))) };
                    } else {
                        // Vectorized branchless negative handling
                        const is_pos = self.data >= @as(Vec, @splat(0));
                        const offsets = @select(T, is_pos, @as(Vec, @splat(half)), @as(Vec, @splat(-half)));
                        return .{ .data = @divTrunc(vec.data + offsets, @as(Vec, @splat(div_val))) };
                    }
                }
            }

            // Cross-type fully vectorized casting with scales
            const FVec = @Vector(total, f64);
            const float_vec: FVec = switch (comptime @typeInfo(T)) {
                .float => @floatCast(vec.data),
                .int => @floatFromInt(vec.data),
                else => unreachable,
            };

            const scaled = float_vec * @as(FVec, @splat(ratio));

            return switch (comptime @typeInfo(DestT)) {
                .float => .{ .data = @floatCast(scaled) },
                .int => .{ .data = @intFromFloat(@round(scaled)) },
                else => unreachable,
            };
        }

        const CmpResult = if (total == 1) bool else [total]bool;

        inline fn cmpResult(v: @Vector(total, bool)) CmpResult {
            return if (comptime total == 1) @reduce(.And, v) else @as([total]bool, v);
        }

        /// Resolve both sides to the finer scale, broadcasting shape {1} RHS if needed.
        inline fn resolveScalePair(self: *const Self, rhs: anytype) struct { l: Vec, r: Vec } {
            const RhsType = @TypeOf(rhs);
            if (comptime !isTensor(RhsType))
                @compileError("rhs can only be a Tensor ");
            if (comptime RhsType.total != 1 and !sh.shapeEql(shape, RhsType.shape))
                @compileError("Shape mismatch in comparison: element-wise operations require identical shapes, or a scalar RHS.");

            const TargetType = TensorStatic(T, dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            return .{ .l = self.to(TargetType).data, .r = rhs.to(TargetType).data };
        }

        pub inline fn eq(self: *const Self, rhs: anytype) CmpResult {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in eq.");
            const p = resolveScalePair(self, rhs);
            return cmpResult(p.l == p.r);
        }

        pub inline fn ne(self: *const Self, rhs: anytype) CmpResult {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in ne.");
            const p = resolveScalePair(self, rhs);
            return cmpResult(p.l != p.r);
        }

        pub inline fn gt(self: *const Self, rhs: anytype) CmpResult {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in gt.");
            const p = resolveScalePair(self, rhs);
            return cmpResult(p.l > p.r);
        }

        pub inline fn gte(self: *const Self, rhs: anytype) CmpResult {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in gte.");
            const p = resolveScalePair(self, rhs);
            return cmpResult(p.l >= p.r);
        }

        pub inline fn lt(self: *const Self, rhs: anytype) CmpResult {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in lt.");
            const p = resolveScalePair(self, rhs);
            return cmpResult(p.l < p.r);
        }

        pub inline fn lte(self: *const Self, rhs: anytype) CmpResult {
            if (comptime !dims.eql(@TypeOf(rhs).dims))
                @compileError("Dimension mismatch in lte.");
            const p = resolveScalePair(self, rhs);
            return cmpResult(p.l <= p.r);
        }

        /// True iff every element is equal after scale resolution.
        pub inline fn eqAll(self: *const Self, other: anytype) bool {
            if (comptime !dims.eql(@TypeOf(other).dims))
                @compileError("Dimension mismatch in eqAll.");
            const p = resolveScalePair(self, other);
            return @reduce(.And, p.l == p.r);
        }

        /// True iff any element differs after scale resolution.
        pub inline fn neAll(self: *const Self, other: anytype) bool {
            return !self.eqAll(other);
        }

        pub inline fn contract(
            self: *const Self,
            rhs: anytype,
            comptime axis_a: usize,
            comptime axis_b: usize,
        ) blk: {
            const RhsType = @TypeOf(rhs);
            if (!isTensor(RhsType))
                @compileError("rhs can only be a Tensor ");
            if (axis_a >= rank) @compileError("contract: axis_a out of bounds");
            if (axis_b >= RhsType.rank) @compileError("contract: axis_b out of bounds");
            if (shape[axis_a] != RhsType.shape[axis_b]) @compileError("contract: shape mismatch at contraction axes");

            const sa = sh.shapeRemoveAxis(shape, axis_a);
            const sb = sh.shapeRemoveAxis(RhsType.shape, axis_b);
            const rs_raw = sh.shapeCat(&sa, &sb);
            const rs: []const comptime_int = if (rs_raw.len == 0) &.{1} else &rs_raw;
            break :blk TensorStatic(
                T,
                dims.add(RhsType.dims).argsOpt(),
                sh.finerScales(Self, RhsType).argsOpt(),
                rs,
            );
        } {
            const RhsType = @TypeOf(rhs);
            const k: usize = comptime shape[axis_a]; // contraction dimension

            const sa = comptime sh.shapeRemoveAxis(shape, axis_a);
            const sb = comptime sh.shapeRemoveAxis(RhsType.shape, axis_b);
            const rs_raw = comptime sh.shapeCat(&sa, &sb);
            const rs: []const comptime_int = comptime if (rs_raw.len == 0) &.{1} else &rs_raw;

            const ResultType = TensorStatic(
                T,
                dims.add(RhsType.dims).argsOpt(),
                sh.finerScales(Self, RhsType).argsOpt(),
                rs,
            );

            const SelfNorm = TensorStatic(T, dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), shape);
            const OtherNorm = TensorStatic(T, RhsType.dims.argsOpt(), sh.finerScales(Self, RhsType).argsOpt(), RhsType.shape);

            const a_data = if (comptime Self == SelfNorm) self.data else self.to(SelfNorm).data;
            const b_data = if (comptime RhsType == OtherNorm) rhs.data else rhs.to(OtherNorm).data;

            // FAST PATH: Dot Product
            if (comptime rank == 1 and RhsType.rank == 1 and axis_a == 0 and axis_b == 0) {
                if (comptime !sh.isInt(T)) {
                    return .{ .data = @splat(@reduce(.Add, a_data * b_data)) };
                } else {
                    // For integers, we do a vectorized saturating multiply,
                    // then convert to an array to do a saturating sum
                    const mul_arr: [total]T = a_data *| b_data;
                    var acc: T = 0;
                    for (mul_arr) |val| acc +|= val;
                    return .{ .data = @splat(acc) };
                }
            }

            // --- ZERO-COST COERCION TO ARRAYS FOR RUNTIME INDEXING ---
            const a_arr: [total]T = a_data;
            const b_arr: [RhsType.total]T = b_data;

            // FAST PATH: 2D Matrix Multiplication
            if (comptime rank == 2 and RhsType.rank == 2 and axis_a == 1 and axis_b == 0) {
                const rows = shape[0];
                const cols = RhsType.shape[1];
                const inner = shape[1];

                // Create a mutable array for the result, NOT a Tensor struct
                var res_arr: [ResultType.total]T = undefined;

                for (0..rows) |i| {
                    for (0..cols) |j| {
                        var acc: T = 0;
                        for (0..inner) |id| {
                            const a_flat = i * _strides[0] + id * _strides[1];
                            const b_flat = id * RhsType.strides_arr[0] + j * RhsType.strides_arr[1];

                            // Use a_arr and b_arr here
                            if (comptime sh.isInt(T)) acc +|= a_arr[a_flat] *| b_arr[b_flat] else acc += a_arr[a_flat] * b_arr[b_flat];
                        }
                        // Write to the array
                        res_arr[i * cols + j] = acc;
                    }
                }
                // Return the initialized Tensor struct
                return .{ .data = res_arr };
            }

            // FALLBACK PATH
            const rs_raw_strides = comptime sh.shapeStrides(&rs_raw);

            // Create a mutable array for the result
            var result_arr: [ResultType.total]T = undefined;

            for (0..ResultType.total) |res_flat| {
                const res_coords = sh.decodeFlatCoords(res_flat, rs_raw.len, rs_raw_strides);

                var a_free: [sa.len]usize = undefined;
                for (0..sa.len) |i| a_free[i] = res_coords[i];
                var b_free: [sb.len]usize = undefined;
                for (0..sb.len) |i| b_free[i] = res_coords[sa.len + i];

                var acc: T = 0;
                for (0..k) |ki| {
                    const a_coords = sh.insertAxis(rank, axis_a, ki, &a_free);
                    const b_coords = sh.insertAxis(RhsType.rank, axis_b, ki, &b_free);
                    const a_flat = sh.encodeFlatCoords(&a_coords, rank, _strides);
                    const b_flat = sh.encodeFlatCoords(&b_coords, RhsType.rank, RhsType.strides_arr);

                    // Use a_arr and b_arr here
                    if (comptime sh.isInt(T)) acc +|= a_arr[a_flat] *| b_arr[b_flat] else acc += a_arr[a_flat] * b_arr[b_flat];
                }
                // Write to the array
                result_arr[res_flat] = acc;
            }

            // Return the initialized Tensor struct
            return .{ .data = result_arr };
        }

        /// 3D Cross Product. Only defined for Rank-1 tensors of length 3.
        /// Result dimensions are the sum of input dimensions.
        pub inline fn cross(self: *const Self, rhs: anytype) TensorStatic(
            T,
            dims.add(@TypeOf(rhs).dims).argsOpt(),
            sh.finerScales(Self, @TypeOf(rhs)).argsOpt(),
            &.{3},
        ) {
            const RhsType = @TypeOf(rhs);

            if (!isTensor(RhsType))
                @compileError("rhs can only be a Tensor ");
            if (comptime rank != 1 or shape[0] != 3 or RhsType.rank != 1 or RhsType.shape[0] != 3)
                @compileError("cross product is only defined for 3D vectors (rank-1, length 3)");

            // Bring both to the same scale (e.g., mm vs m)
            const p = self.resolveScalePair(rhs);
            const l = p.l;
            const r = p.r;

            var res: [3]T = undefined;
            if (comptime sh.isInt(T)) {
                res[0] = (l[1] *| r[2]) -| (l[2] *| r[1]);
                res[1] = (l[2] *| r[0]) -| (l[0] *| r[2]);
                res[2] = (l[0] *| r[1]) -| (l[1] *| r[0]);
            } else {
                res[0] = (l[1] * r[2]) - (l[2] * r[1]);
                res[1] = (l[2] * r[0]) - (l[0] * r[2]);
                res[2] = (l[0] * r[1]) - (l[1] * r[0]);
            }

            return .{ .data = res };
        }

        /// Sum of squared elements.  Cheaper than length(); use for ordering.
        pub inline fn lengthSqr(self: *const Self) T {
            return @reduce(.Add, self.data * self.data);
        }

        /// Euclidean length (L2 norm).
        pub inline fn length(self: *const Self) T {
            const sq = self.lengthSqr();
            if (comptime @typeInfo(T) == .int) {
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
                return @as(T, @intCast(std.math.sqrt(@as(UnsignedT, @intCast(sq)))));
            }
            return @sqrt(sq);
        }

        /// Product of all elements.  Result has shape {1}; dimension exponent * total.
        pub inline fn product(self: *const Self) TensorStatic(
            T,
            dims.scale(@as(comptime_int, total)).argsOpt(),
            scales.argsOpt(),
            &.{1},
        ) {
            return .{ .data = .{@reduce(.Mul, self.data)} };
        }

        pub fn formatNumber(
            self: *const Self,
            writer: *std.Io.Writer,
            options: std.fmt.Number,
        ) !void {
            if (comptime total == 1) {
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
                try writer.writeAll("(");
                const max_to_print = 6;
                inline for (0..@min(total, max_to_print)) |i| {
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
                    if (comptime i == max_to_print - 1 and total != max_to_print - 1)
                        try writer.writeAll(", ...");
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

                if (v != 1) try sh.printSuperscript(writer, v);
            }
        }
    };
}

// ═════════════════════════════════════════════════════════════════════════════
// Tests
// ─────────────────────────────────────────────────────────────────────────────

// ─── Scalar tests ─────────────────────────────────────────────────────────

test "Scalar initiat" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{ .L = @enumFromInt(-3) }, &.{1});
    const Second = TensorStatic(f32, .{ .T = 1 }, .{ .T = .n }, &.{1});

    const distance = Meter.splat(10);
    const time = Second.splat(2);

    try std.testing.expectEqual(10, distance.data[0]);
    try std.testing.expectEqual(2, time.data[0]);
}

test "Scalar comparisons (eq, ne, gt, gte, lt, lte)" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const KiloMeter = TensorStatic(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const m1000 = Meter.splat(1000);
    const km1 = KiloMeter.splat(1);
    const km2 = KiloMeter.splat(2);

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
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const KiloMeter = TensorStatic(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});
    const KiloMeter_f = TensorStatic(f64, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const distance = Meter.splat(10);
    const distance2 = Meter.splat(20);
    const added = distance.add(distance2);
    try std.testing.expectEqual(30, added.data[0]);
    try std.testing.expectEqual(1, @TypeOf(added).dims.get(.L));

    const distance3 = KiloMeter.splat(2);
    const added2 = distance.add(distance3);
    try std.testing.expectEqual(2010, added2.data[0]);

    const added3 = distance3.add(distance).to(KiloMeter);
    try std.testing.expectEqual(2, added3.data[0]);

    const distance4 = KiloMeter_f.splat(2);
    const added4 = distance4.add(distance).to(KiloMeter_f);
    try std.testing.expectApproxEqAbs(2.01, added4.data[0], 0.000001);
}

test "Scalar Sub" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const KiloMeter_f = TensorStatic(f64, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const a = Meter.splat(500);
    const b = Meter.splat(200);
    const diff = a.sub(b);
    try std.testing.expectEqual(300, diff.data[0]);
    const diff2 = b.sub(a);
    try std.testing.expectEqual(-300, diff2.data[0]);

    const km_f = KiloMeter_f.splat(2.5);
    const m_f = Meter.splat(500);
    const diff3 = km_f.sub(m_f);
    try std.testing.expectApproxEqAbs(2000, diff3.data[0], 1e-4);
}

test "Scalar MulBy" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const Second = TensorStatic(f32, .{ .T = 1 }, .{}, &.{1});

    const d = Meter.splat(3);
    const t = Second.splat(4);
    const at = d.mul(t);
    try std.testing.expectEqual(12, at.data[0]);
    try std.testing.expectEqual(1, @TypeOf(at).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(at).dims.get(.T));

    const d2 = Meter.splat(5);
    const area = d.mul(d2);
    try std.testing.expectEqual(15, area.data[0]);
    try std.testing.expectEqual(2, @TypeOf(area).dims.get(.L));
}

test "Scalar MulBy with scale" {
    const KiloMeter = TensorStatic(f32, .{ .L = 1 }, .{ .L = .k }, &.{1});
    const KiloGram = TensorStatic(f32, .{ .M = 1 }, .{ .M = .k }, &.{1});

    const dist = KiloMeter.splat(2.0);
    const mass = KiloGram.splat(3.0);
    const prod = dist.mul(mass);
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.M));
}

test "Scalar MulBy with type change" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});
    const Second = TensorStatic(f64, .{ .T = 1 }, .{}, &.{1});
    const KmSec = TensorStatic(i64, .{ .L = 1, .T = 1 }, .{ .L = .k }, &.{1});
    const KmSec_f = TensorStatic(f32, .{ .L = 1, .T = 1 }, .{ .L = .k }, &.{1});

    const d = Meter.splat(3);
    const t = Second.splat(4);

    try std.testing.expectEqual(12, d.mul(t).to(KmSec).data[0]);
    try std.testing.expectApproxEqAbs(12.0, d.mul(t).to(KmSec_f).data[0], 0.0001);
}

test "Scalar MulBy small" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{ .L = .n }, &.{1});
    const Second = TensorStatic(f32, .{ .T = 1 }, .{}, &.{1});
    const d = Meter.splat(3);
    const t = Second.splat(4);
    try std.testing.expectEqual(12, d.mul(t).data[0]);
}

test "Scalar MulBy dimensionless" {
    const DimLess = TensorStatic(i128, .{}, .{}, &.{1});
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const d = Meter.splat(7);
    const scaled = d.mul(DimLess.splat(3));
    try std.testing.expectEqual(21, scaled.data[0]);
}

test "Scalar Sqrt" {
    const MeterSquare = TensorStatic(i128, .{ .L = 2 }, .{}, &.{1});
    const MeterSquare_f = TensorStatic(f64, .{ .L = 2 }, .{}, &.{1});

    var d = MeterSquare.splat(9);
    var scaled = d.sqrt();
    try std.testing.expectEqual(3, scaled.data[0]);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));

    d = MeterSquare.splat(-5);
    scaled = d.sqrt();
    try std.testing.expectEqual(0, scaled.data[0]);

    const d2 = MeterSquare_f.splat(20);
    const scaled2 = d2.sqrt();
    try std.testing.expectApproxEqAbs(4.472135955, scaled2.data[0], 1e-4);
}

test "Scalar Chained: velocity and acceleration" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const Second = TensorStatic(f32, .{ .T = 1 }, .{}, &.{1});

    const dist = Meter.splat(100);
    const t1 = Second.splat(5);
    const velocity = dist.div(t1);
    try std.testing.expectEqual(20, velocity.data[0]);

    const t2 = Second.splat(4);
    const accel = velocity.div(t2);
    try std.testing.expectEqual(5, accel.data[0]);
}

test "Scalar DivBy integer exact" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const Second = TensorStatic(f32, .{ .T = 1 }, .{}, &.{1});

    const dist = Meter.splat(120);
    const time = Second.splat(4);
    const vel = dist.div(time);
    try std.testing.expectEqual(30, vel.data[0]);
}

test "Scalar Finer scales skip dim 0" {
    const Dimless = TensorStatic(i128, .{}, .{}, &.{1});
    const KiloMetre = TensorStatic(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const r = Dimless.splat(30);
    const km = KiloMetre.splat(4);
    const vel = r.mul(km);
    try std.testing.expectEqual(120, vel.data[0]);
    try std.testing.expectEqual(Scales.UnitScale.k, @TypeOf(vel).scales.get(.L));
}

test "Scalar Conversion chain: km -> m -> cm" {
    const KiloMeter = TensorStatic(i128, .{ .L = 1 }, .{ .L = .k }, &.{1});
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const CentiMeter = TensorStatic(i128, .{ .L = 1 }, .{ .L = .c }, &.{1});

    const km = KiloMeter.splat(15);
    const m = km.to(Meter);
    const cm = m.to(CentiMeter);
    try std.testing.expectEqual(15_000, m.data[0]);
    try std.testing.expectEqual(1_500_000, cm.data[0]);
}

test "Scalar Conversion: hours -> minutes -> seconds" {
    const Hour = TensorStatic(i128, .{ .T = 1 }, .{ .T = .hour }, &.{1});
    const Minute = TensorStatic(i128, .{ .T = 1 }, .{ .T = .min }, &.{1});
    const Second = TensorStatic(i128, .{ .T = 1 }, .{}, &.{1});

    const h = Hour.splat(1);
    const min = h.to(Minute);
    const sec = min.to(Second);
    try std.testing.expectEqual(60, min.data[0]);
    try std.testing.expectEqual(3600, sec.data[0]);
}

test "Scalar Format" {
    const MeterPerSecondSq = TensorStatic(f32, .{ .L = 1, .T = -2 }, .{ .T = .n }, &.{1});
    const Meter = TensorStatic(f32, .{ .L = 1 }, .{}, &.{1});

    const m = Meter.splat(1.23456);
    const accel = MeterPerSecondSq.splat(9.81);

    var buf: [64]u8 = undefined;
    var res = try std.fmt.bufPrint(&buf, "{d:.2}", .{m});
    try std.testing.expectEqualStrings("1.23m", res);

    res = try std.fmt.bufPrint(&buf, "{d}", .{accel});
    try std.testing.expectEqualStrings("9.81m.ns⁻²", res);
}

test "Scalar Abs" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const MeterF = TensorStatic(f32, .{ .L = 1 }, .{}, &.{1});

    try std.testing.expectEqual(50, Meter.splat(-50).abs().data[0]);
    try std.testing.expectEqual(42.5, MeterF.splat(-42.5).abs().data[0]);
}

test "Scalar Pow" {
    const Meter = TensorStatic(i128, .{ .L = 1 }, .{}, &.{1});
    const d = Meter.splat(4);
    try std.testing.expectEqual(16, d.pow(2).data[0]);
    try std.testing.expectEqual(64, d.pow(3).data[0]);
}

test "Scalar add/sub bare number on dimensionless scalar" {
    const DimLess = TensorStatic(i128, .{}, .{}, &.{1});
    const a = DimLess.splat(10);
    try std.testing.expectEqual(15, a.add(DimLess.splat(5)).data[0]);
    try std.testing.expectEqual(7, a.sub(DimLess.splat(3)).data[0]);
}

test "Scalar Imperial length scales" {
    const Foot = TensorStatic(f64, .{ .L = 1 }, .{ .L = .ft }, &.{1});
    const Meter = TensorStatic(f64, .{ .L = 1 }, .{}, &.{1});
    const Inch = TensorStatic(f64, .{ .L = 1 }, .{ .L = .inch }, &.{1});

    try std.testing.expectApproxEqAbs(0.3048, Foot.splat(1.0).to(Meter).data[0], 1e-9);
    try std.testing.expectApproxEqAbs(1.0, Inch.splat(12.0).to(Foot).data[0], 1e-9);
}

test "Scalar Imperial mass scales" {
    const Pound = TensorStatic(f64, .{ .M = 1 }, .{ .M = .lb }, &.{1});
    const Ounce = TensorStatic(f64, .{ .M = 1 }, .{ .M = .oz }, &.{1});

    const total = Pound.splat(2.0).add(Ounce.splat(8.0)).to(Pound);
    try std.testing.expectApproxEqAbs(2.5, total.data[0], 1e-6);
}

// ─── Vector / Tensor tests ────────────────────────────────────────────────

test "Vector initiate" {
    const Meter4 = TensorStatic(f32, .{ .L = 1 }, .{}, &.{4});
    const m = Meter4.splat(1);
    try std.testing.expect(m.data[0] == 1);
    try std.testing.expect(m.data[3] == 1);
}

test "Vector format" {
    const MeterPerSecondSq = TensorStatic(f32, .{ .L = 1, .T = -2 }, .{ .T = .n }, &.{3});
    const KgMeterPerSecond = TensorStatic(f32, .{ .M = 1, .L = 1, .T = -1 }, .{ .M = .k }, &.{3});

    const accel = MeterPerSecondSq.splat(9.81);
    const momentum = KgMeterPerSecond{ .data = .{ 43, 0, 11 } };

    var buf: [64]u8 = undefined;
    var res = try std.fmt.bufPrint(&buf, "{d}", .{accel});
    try std.testing.expectEqualStrings("(9.81, 9.81, 9.81)m.ns⁻²", res);

    res = try std.fmt.bufPrint(&buf, "{d:.2}", .{momentum});
    try std.testing.expectEqualStrings("(43.00, 0.00, 11.00)m.kg.s⁻¹", res);
}

test "Vector Vec3 Init and Basic Arithmetic" {
    const Meter3 = TensorStatic(i32, .{ .L = 1 }, .{}, &.{3});

    const v_zero = Meter3.zero;
    try std.testing.expectEqual(0, v_zero.data[0]);
    try std.testing.expectEqual(0, v_zero.data[2]);

    const v_one = Meter3.one;
    try std.testing.expectEqual(1, v_one.data[0]);

    const v_def = Meter3.splat(5);
    try std.testing.expectEqual(5, v_def.data[2]);

    const v1 = Meter3{ .data = .{ 10, 20, 30 } };
    const v2 = Meter3{ .data = .{ 2, 4, 6 } };

    const added = v1.add(v2);
    try std.testing.expectEqual(12, added.data[0]);
    try std.testing.expectEqual(24, added.data[1]);
    try std.testing.expectEqual(36, added.data[2]);

    const subbed = v1.sub(v2);
    try std.testing.expectEqual(8, subbed.data[0]);
    try std.testing.expectEqual(16, subbed.data[1]);
    try std.testing.expectEqual(24, subbed.data[2]);

    const neg = v1.negate();
    try std.testing.expectEqual(-10, neg.data[0]);
    try std.testing.expectEqual(-20, neg.data[1]);
    try std.testing.expectEqual(-30, neg.data[2]);
}

test "Vector Kinematics (scalar mul/div broadcast)" {
    const Meter3 = TensorStatic(i32, .{ .L = 1 }, .{}, &.{3});
    const Second1 = TensorStatic(i32, .{ .T = 1 }, .{}, &.{1});

    const pos = Meter3{ .data = .{ 100, 200, 300 } };
    const time = Second1.splat(10);

    const vel = pos.div(time);
    try std.testing.expectEqual(10, vel.data[0]);
    try std.testing.expectEqual(20, vel.data[1]);
    try std.testing.expectEqual(30, vel.data[2]);
    try std.testing.expectEqual(1, @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(vel).dims.get(.T));

    const new_pos = vel.mul(time);
    try std.testing.expectEqual(100, new_pos.data[0]);
    try std.testing.expectEqual(0, @TypeOf(new_pos).dims.get(.T));
}

test "Vector Element-wise Math and Scaling" {
    const Meter3 = TensorStatic(i32, .{ .L = 1 }, .{}, &.{3});

    const v1 = Meter3{ .data = .{ 10, 20, 30 } };
    const v2 = Meter3{ .data = .{ 2, 5, 10 } };
    const dv = v1.div(v2);
    try std.testing.expectEqual(5, dv.data[0]);
    try std.testing.expectEqual(4, dv.data[1]);
    try std.testing.expectEqual(3, dv.data[2]);
    try std.testing.expectEqual(0, @TypeOf(dv).dims.get(.L));
}

test "Vector Conversions" {
    const KiloMeter3 = TensorStatic(i32, .{ .L = 1 }, .{ .L = .k }, &.{3});
    const Meter3 = TensorStatic(i32, .{ .L = 1 }, .{}, &.{3});

    const v_km = KiloMeter3{ .data = .{ 1, 2, 3 } };
    const v_m = v_km.to(Meter3);
    try std.testing.expectEqual(1000, v_m.data[0]);
    try std.testing.expectEqual(2000, v_m.data[1]);
    try std.testing.expectEqual(3000, v_m.data[2]);
    try std.testing.expectEqual(UnitScale.none, @TypeOf(v_m).scales.get(.L));
}

test "Vector Length" {
    const MeterInt3 = TensorStatic(i32, .{ .L = 1 }, .{}, &.{3});
    const MeterFloat3 = TensorStatic(f32, .{ .L = 1 }, .{}, &.{3});

    const v_int = MeterInt3{ .data = .{ 3, 4, 0 } };
    try std.testing.expectEqual(25, v_int.lengthSqr());
    try std.testing.expectEqual(5, v_int.length());

    const v_float = MeterFloat3{ .data = .{ 3.0, 4.0, 0.0 } };
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), v_float.lengthSqr(), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), v_float.length(), 1e-4);
}

test "Vector Comparisons" {
    const Meter3 = TensorStatic(f32, .{ .L = 1 }, .{}, &.{3});
    const KiloMeter3 = TensorStatic(f32, .{ .L = 1 }, .{ .L = .k }, &.{3});

    const v1 = Meter3{ .data = .{ 1000.0, 500.0, 0.0 } };
    const v2 = KiloMeter3{ .data = .{ 1.0, 0.5, 0.0 } };
    const v3 = KiloMeter3{ .data = .{ 1.0, 0.6, 0.0 } };

    try std.testing.expect(v1.eqAll(v2));
    try std.testing.expect(v1.neAll(v3));

    const higher = v3.gt(v1);
    try std.testing.expectEqual(false, higher[0]);
    try std.testing.expectEqual(true, higher[1]);
    try std.testing.expectEqual(false, higher[2]);

    const equal = v3.eq(v1);
    try std.testing.expectEqual(true, equal[0]);
    try std.testing.expectEqual(false, equal[1]);
    try std.testing.expectEqual(true, equal[2]);

    const low_eq = v1.lte(v3);
    try std.testing.expect(low_eq[0] and low_eq[1] and low_eq[2]);
}

test "Vector vs Scalar broadcast comparison" {
    const Meter3 = TensorStatic(f32, .{ .L = 1 }, .{}, &.{3});
    const KiloMeter1 = TensorStatic(f32, .{ .L = 1 }, .{ .L = .k }, &.{1});

    const positions = Meter3{ .data = .{ 500.0, 1200.0, 3000.0 } };
    const threshold = KiloMeter1.splat(1); // 1 km = 1000 m

    const exceeded = positions.gt(threshold);
    try std.testing.expectEqual(false, exceeded[0]);
    try std.testing.expectEqual(true, exceeded[1]);
    try std.testing.expectEqual(true, exceeded[2]);

    const Meter1 = TensorStatic(f32, .{ .L = 1 }, .{}, &.{1});
    const exact = positions.eq(Meter1.splat(500));
    try std.testing.expect(exact[0] == true);
    try std.testing.expect(exact[1] == false);
}

test "Vector contract — dot product (rank-1 * rank-1)" {
    const Meter3 = TensorStatic(f32, .{ .L = 1 }, .{}, &.{3});
    const Newton3 = TensorStatic(f32, .{ .M = 1, .L = 1, .T = -2 }, .{}, &.{3});

    const pos = Meter3{ .data = .{ 10.0, 0.0, 0.0 } };
    const force = Newton3{ .data = .{ 5.0, 5.0, 0.0 } };

    const work = force.contract(pos, 0, 0);
    try std.testing.expectEqual(50.0, work.data[0]);
    try std.testing.expectEqual(1, @TypeOf(work).dims.get(.M));
    try std.testing.expectEqual(2, @TypeOf(work).dims.get(.L));
    try std.testing.expectEqual(-2, @TypeOf(work).dims.get(.T));
}

test "Vector contract — matrix multiply (rank-2 * rank-2)" {
    const A = TensorStatic(f32, .{}, .{}, &.{ 2, 3 });
    const B = TensorStatic(f32, .{}, .{}, &.{ 3, 2 });

    const a = A{ .data = .{ 1, 2, 3, 4, 5, 6 } };
    const b = B{ .data = .{ 7, 8, 9, 10, 11, 12 } };

    const c = a.contract(b, 1, 0);
    try std.testing.expectEqual(58, c.data[TensorStatic(f32, .{}, .{}, &.{ 2, 2 }).idx(.{ 0, 0 })]);
    try std.testing.expectEqual(64, c.data[TensorStatic(f32, .{}, .{}, &.{ 2, 2 }).idx(.{ 0, 1 })]);
    try std.testing.expectEqual(139, c.data[TensorStatic(f32, .{}, .{}, &.{ 2, 2 }).idx(.{ 1, 0 })]);
    try std.testing.expectEqual(154, c.data[TensorStatic(f32, .{}, .{}, &.{ 2, 2 }).idx(.{ 1, 1 })]);
}

test "Vector Abs, Pow, Sqrt and Product" {
    const Meter3 = TensorStatic(f32, .{ .L = 1 }, .{}, &.{3});

    const v1 = Meter3{ .data = .{ -2.0, 3.0, -4.0 } };
    const v_abs = v1.abs();
    try std.testing.expectEqual(2.0, v_abs.data[0]);
    try std.testing.expectEqual(4.0, v_abs.data[2]);

    const vol = v_abs.product();
    try std.testing.expectEqual(24.0, vol.data[0]);
    try std.testing.expectEqual(3, @TypeOf(vol).dims.get(.L));

    const area_vec = v_abs.pow(2);
    try std.testing.expectEqual(4.0, area_vec.data[0]);
    try std.testing.expectEqual(16.0, area_vec.data[2]);
    try std.testing.expectEqual(2, @TypeOf(area_vec).dims.get(.L));

    const sqrted = area_vec.sqrt();
    try std.testing.expectEqual(2, sqrted.data[0]);
    try std.testing.expectEqual(4, sqrted.data[2]);
    try std.testing.expectEqual(1, @TypeOf(sqrted).dims.get(.L));
}

test "Vector eq broadcast on dimensionless" {
    const DimLess3 = TensorStatic(i32, .{}, .{}, &.{3});
    const v = DimLess3{ .data = .{ 1, 2, 3 } };

    const eq_res = v.eq(DimLess3.splat(2));
    try std.testing.expectEqual(false, eq_res[0]);
    try std.testing.expectEqual(true, eq_res[1]);
    try std.testing.expectEqual(false, eq_res[2]);
}

test "Tensor idx helper and matrix access" {
    const Mat3x3 = TensorStatic(f32, .{}, .{}, &.{ 3, 3 });
    var m: Mat3x3 = Mat3x3.zero;
    m.data[Mat3x3.idx(.{ 0, 0 })] = 1.0;
    m.data[Mat3x3.idx(.{ 1, 1 })] = 2.0;
    m.data[Mat3x3.idx(.{ 2, 2 })] = 3.0;

    try std.testing.expectEqual(1.0, m.data[0]);
    try std.testing.expectEqual(2.0, m.data[4]);
    try std.testing.expectEqual(3.0, m.data[8]);
    try std.testing.expectEqual(0.0, m.data[1]);
}

test "Tensor strides_arr correctness" {
    const T1 = TensorStatic(f32, .{}, .{}, &.{3});
    const T2 = TensorStatic(f32, .{}, .{}, &.{ 3, 4 });
    const T3 = TensorStatic(f32, .{}, .{}, &.{ 2, 3, 4 });

    try std.testing.expectEqual(1, T1.strides_arr[0]);
    try std.testing.expectEqual(4, T2.strides_arr[0]);
    try std.testing.expectEqual(1, T2.strides_arr[1]);
    try std.testing.expectEqual(12, T3.strides_arr[0]);
    try std.testing.expectEqual(4, T3.strides_arr[1]);
    try std.testing.expectEqual(1, T3.strides_arr[2]);
}
