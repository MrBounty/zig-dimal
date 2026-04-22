const std = @import("std");
const hlp = @import("helper.zig");

const Vector = @import("Vector.zig").Vector;
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

// ---------------------------------------------------------------------------

/// A dimensioned scalar value. `T` is the numeric type, `d` the dimension exponents, `s` the SI scales.
/// All dimension and unit tracking is resolved at comptime — zero runtime overhead.
pub fn Scalar(comptime T: type, comptime d_opt: Dimensions.ArgOpts, comptime s_opt: Scales.ArgOpts) type {
    @setEvalBranchQuota(10_000_000);
    return struct {
        value: T,

        const Self = @This();

        /// Type of Vector(3, Self)
        pub const Vec3: type = Vector(3, Self);

        /// Type of underline value, mostly use for Vector
        pub const ValueType: type = T;
        pub const dims: Dimensions = Dimensions.init(d_opt);
        pub const scales = Scales.init(s_opt);

        // ---------------------------------------------------------------
        // Internal: resolved-rhs shorthands
        // ---------------------------------------------------------------

        /// Scalar type that `rhs` normalises to (bare numbers → dimensionless).
        inline fn RhsT(comptime Rhs: type) type {
            return hlp.rhsScalarType(T, Rhs);
        }

        /// Normalise `rhs` (bare number or Scalar) into a proper Scalar value.
        inline fn rhs(r: anytype) RhsT(@TypeOf(r)) {
            return hlp.toRhsScalar(T, r);
        }

        // ---------------------------------------------------------------
        // Arithmetic
        // ---------------------------------------------------------------

        /// Add two quantities. Dimensions must match — compile error otherwise.
        /// Scales are auto-resolved to the finer of the two.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`
        /// (bare numbers are treated as dimensionless).
        pub inline fn add(self: Self, r: anytype) Scalar(
            T,
            dims.argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in add: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return .{ .value = self.value + rhs_s.value };

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return .{ .value = if (comptime hlp.isInt(T)) lhs_val +| rhs_val else lhs_val + rhs_val };
        }

        /// Subtract two quantities. Dimensions must match — compile error otherwise.
        /// Scales are auto-resolved to the finer of the two.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn sub(self: Self, r: anytype) Scalar(
            T,
            dims.argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in sub: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return .{ .value = self.value - rhs_s.value };

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return .{ .value = if (comptime hlp.isInt(T)) lhs_val -| rhs_val else lhs_val - rhs_val };
        }

        /// Multiply two quantities. Dimension exponents are summed: `L¹ * T⁻¹ → L¹T⁻¹`.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`
        /// (bare numbers are treated as dimensionless — dimensions pass through unchanged).
        pub inline fn mulBy(self: Self, r: anytype) Scalar(
            T,
            dims.add(RhsT(@TypeOf(r)).dims).argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            const SelfNorm = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const RhsNorm = Scalar(T, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            if (comptime Self == SelfNorm and RhsType == RhsNorm)
                return .{ .value = self.value * rhs_s.value };

            const lhs_val = if (comptime Self == SelfNorm) self.value else self.to(SelfNorm).value;
            const rhs_val = if (comptime RhsType == RhsNorm) rhs_s.value else rhs_s.to(RhsNorm).value;
            return .{ .value = if (comptime hlp.isInt(T)) lhs_val *| rhs_val else lhs_val * rhs_val };
        }

        /// Divide two quantities. Dimension exponents are subtracted: `L¹ / T¹ → L¹T⁻¹`.
        /// Integer types use truncating division.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn divBy(self: Self, r: anytype) Scalar(
            T,
            dims.sub(RhsT(@TypeOf(r)).dims).argsOpt(),
            hlp.finerScales(Self, RhsT(@TypeOf(r))).argsOpt(),
        ) {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            const SelfNorm = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const RhsNorm = Scalar(T, RhsType.dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == SelfNorm) self.value else self.to(SelfNorm).value;
            const rhs_val = if (comptime RhsType == RhsNorm) rhs_s.value else rhs_s.to(RhsNorm).value;
            if (comptime hlp.isInt(T)) {
                return .{ .value = @divTrunc(lhs_val, rhs_val) };
            } else {
                return .{ .value = lhs_val / rhs_val };
            }
        }

        // ---------------------------------------------------------------
        // Unary
        // ---------------------------------------------------------------

        /// Returns the absolute value of the quantity.
        /// Dimensions and scales remain entirely unchanged.
        pub inline fn abs(self: Self) Self {
            if (comptime @typeInfo(T) == .int)
                return .{ .value = @intCast(@abs(self.value)) }
            else
                return .{ .value = @abs(self.value) };
        }

        /// Raises the quantity to a compile-time integer exponent.
        /// Dimension exponents are multiplied by the exponent: `(L²)³ → L⁶`.
        pub inline fn pow(self: Self, comptime exp: comptime_int) Scalar(
            T,
            dims.scale(exp).argsOpt(),
            scales.argsOpt(),
        ) {
            if (comptime hlp.isInt(T))
                return .{ .value = std.math.powi(T, self.value, exp) catch std.math.maxInt(T) }
            else
                return .{ .value = std.math.pow(T, self.value, @as(T, @floatFromInt(exp))) };
        }

        pub inline fn sqrt(self: Self) Scalar(
            T,
            dims.div(2).argsOpt(),
            scales.argsOpt(),
        ) {
            if (comptime !dims.isSquare()) // Check if all exponents are divisible by 2
                @compileError("Cannot take sqrt of " ++ dims.str() ++ ": exponents must be even.");
            if (self.value < 0) return .{ .value = 0 };

            if (comptime hlp.isInt(T)) {
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
                const u_len_sq = @as(UnsignedT, @intCast(self.value));
                return .{ .value = @as(T, @intCast(std.math.sqrt(u_len_sq))) };
            } else {
                return .{ .value = @sqrt(self.value) };
            }
        }

        // ---------------------------------------------------------------
        // Conversion
        // ---------------------------------------------------------------

        /// Convert to a compatible unit type. The scale ratio is computed at comptime.
        /// Compile error if dimensions don't match.
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

        // ---------------------------------------------------------------
        // Comparisons
        // ---------------------------------------------------------------

        /// Compares two Scalar for exact equality.
        /// Dimensions must match — compile error otherwise. Scales are auto-resolved.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn eq(self: Self, r: anytype) bool {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in eq: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return self.value == rhs_s.value;

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return lhs_val == rhs_val;
        }

        /// Compares two quantities for inequality.
        /// Dimensions must match — compile error otherwise. Scales are auto-resolved.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn ne(self: Self, r: anytype) bool {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in ne: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return self.value != rhs_s.value;

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return lhs_val != rhs_val;
        }

        /// Returns true if this quantity is strictly greater than the right-hand side.
        /// Dimensions must match — compile error otherwise. Scales are auto-resolved.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn gt(self: Self, r: anytype) bool {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in gt: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return self.value > rhs_s.value;

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return lhs_val > rhs_val;
        }

        /// Returns true if this quantity is greater than or equal to the right-hand side.
        /// Dimensions must match — compile error otherwise. Scales are auto-resolved.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn gte(self: Self, r: anytype) bool {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in gte: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return self.value >= rhs_s.value;

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return lhs_val >= rhs_val;
        }

        /// Returns true if this quantity is strictly less than the right-hand side.
        /// Dimensions must match — compile error otherwise. Scales are auto-resolved.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn lt(self: Self, r: anytype) bool {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in lt: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return self.value < rhs_s.value;

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return lhs_val < rhs_val;
        }

        /// Returns true if this quantity is less than or equal to the right-hand side.
        /// Dimensions must match — compile error otherwise. Scales are auto-resolved.
        /// `rhs` may be a Scalar, `T`, `comptime_int`, or `comptime_float`.
        pub inline fn lte(self: Self, r: anytype) bool {
            const rhs_s = rhs(r);
            const RhsType = @TypeOf(rhs_s);
            if (comptime !dims.eql(RhsType.dims))
                @compileError("Dimension mismatch in lte: " ++ dims.str() ++ " vs " ++ RhsType.dims.str());
            if (comptime RhsType == Self)
                return self.value <= rhs_s.value;

            const TargetType = Scalar(T, dims.argsOpt(), hlp.finerScales(Self, RhsType).argsOpt());
            const lhs_val = if (comptime Self == TargetType) self.value else self.to(TargetType).value;
            const rhs_val = if (comptime RhsType == TargetType) rhs_s.value else rhs_s.to(TargetType).value;
            return lhs_val <= rhs_val;
        }

        // ---------------------------------------------------------------
        // Vector helpers
        // ---------------------------------------------------------------

        /// Return a `Vector(len, Self)` type.
        pub fn Vec(_: Self, comptime len: comptime_int) type {
            return Vector(len, Self);
        }

        /// Return a `Vector(len, Self)` with all components set to this value.
        pub fn vec(self: Self, comptime len: comptime_int) Vector(len, Self) {
            return Vector(len, Self).initDefault(self.value);
        }

        /// Shorthand for `Vec(3)` — wrap this value into a 3-component vector.
        pub fn vec3(self: Self) Vec3 {
            return Vec3.initDefault(self.value);
        }

        // ---------------------------------------------------------------
        // Formatting
        // ---------------------------------------------------------------

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
    const Meter = Scalar(i128, .{ .L = 1 }, .{ .L = @enumFromInt(-3) });
    const Second = Scalar(f32, .{ .T = 1 }, .{ .T = .n });

    const distance = Meter{ .value = 10 };
    const time = Second{ .value = 2 };

    try std.testing.expectEqual(10, distance.value);
    try std.testing.expectEqual(2, time.value);
}

test "Comparisons (eq, ne, gt, gte, lt, lte)" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const KiloMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });

    const m1000 = Meter{ .value = 1000 };
    const km1 = KiloMeter{ .value = 1 };
    const km2 = KiloMeter{ .value = 2 };

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

    const distance = Meter{ .value = 10 };
    const distance2 = Meter{ .value = 20 };

    const added = distance.add(distance2);
    try std.testing.expectEqual(30, added.value);
    try std.testing.expectEqual(1, @TypeOf(added).dims.get(.L));

    const KiloMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });
    const distance3 = KiloMeter{ .value = 2 };
    const added2 = distance.add(distance3);
    try std.testing.expectEqual(2010, added2.value);
    try std.testing.expectEqual(1, @TypeOf(added2).dims.get(.L));

    const added3 = distance3.add(distance).to(KiloMeter);
    try std.testing.expectEqual(2, added3.value);
    try std.testing.expectEqual(1, @TypeOf(added3).dims.get(.L));

    const KiloMeter_f = Scalar(f64, .{ .L = 1 }, .{ .L = .k });
    const distance4 = KiloMeter_f{ .value = 2 };
    const added4 = distance4.add(distance).to(KiloMeter_f);
    try std.testing.expectApproxEqAbs(2.01, added4.value, 0.000001);
    try std.testing.expectEqual(1, @TypeOf(added4).dims.get(.L));
}

test "Sub" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const KiloMeter_f = Scalar(f64, .{ .L = 1 }, .{ .L = .k });

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
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const Second = Scalar(f32, .{ .T = 1 }, .{});

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
    const KiloMeter = Scalar(f32, .{ .L = 1 }, .{ .L = .k });
    const KiloGram = Scalar(f32, .{ .M = 1 }, .{ .M = .k });

    const dist = KiloMeter{ .value = 2.0 };
    const mass = KiloGram{ .value = 3.0 };
    const prod = dist.mulBy(mass);
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(prod).dims.get(.M));
}

test "MulBy with type change" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });
    const Second = Scalar(f64, .{ .T = 1 }, .{});
    const KmSec = Scalar(i64, .{ .L = 1, .T = 1 }, .{ .L = .k });
    const KmSec_f = Scalar(f32, .{ .L = 1, .T = 1 }, .{ .L = .k });

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
    const Meter = Scalar(i128, .{ .L = 1 }, .{ .L = .n });
    const Second = Scalar(f32, .{ .T = 1 }, .{});

    const d = Meter{ .value = 3.0 };
    const t = Second{ .value = 4.0 };

    const area_time = d.mulBy(t);
    try std.testing.expectEqual(12, area_time.value);
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.L));
    try std.testing.expectEqual(1, @TypeOf(area_time).dims.get(.T));
}

test "MulBy dimensionless" {
    const DimLess = Scalar(i128, .{}, .{});
    const Meter = Scalar(i128, .{ .L = 1 }, .{});

    const d = Meter{ .value = 7 };
    const scaled = d.mulBy(DimLess{ .value = 3 });
    try std.testing.expectEqual(21, scaled.value);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
}

test "Sqrt" {
    const MeterSquare = Scalar(i128, .{ .L = 2 }, .{});

    var d = MeterSquare{ .value = 9 };
    var scaled = d.sqrt();
    try std.testing.expectEqual(3, scaled.value);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));

    d = MeterSquare{ .value = -5 };
    scaled = d.sqrt();
    try std.testing.expectEqual(0, scaled.value);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));

    const MeterSquare_f = Scalar(f64, .{ .L = 2 }, .{});
    const d2 = MeterSquare_f{ .value = 20 };
    const scaled2 = d2.sqrt();
    try std.testing.expectApproxEqAbs(4.472135955, scaled2.value, 1e-4);
    try std.testing.expectEqual(1, @TypeOf(scaled2).dims.get(.L));
}

test "Chained: velocity and acceleration" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const Second = Scalar(f32, .{ .T = 1 }, .{});

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
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const Second = Scalar(f32, .{ .T = 1 }, .{});

    const dist = Meter{ .value = 120 };
    const time = Second{ .value = 4 };
    const vel = dist.divBy(time);

    try std.testing.expectEqual(30, vel.value);
    try std.testing.expectEqual(1, @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(vel).dims.get(.T));
}

test "Finer scales skip dim 0" {
    const Dimless = Scalar(i128, .{}, .{});
    const KiloMetre = Scalar(i128, .{ .L = 1 }, .{ .L = .k });

    const r = Dimless{ .value = 30 };
    const time = KiloMetre{ .value = 4 };
    const vel = r.mulBy(time);

    try std.testing.expectEqual(120, vel.value);
    try std.testing.expectEqual(Scales.UnitScale.k, @TypeOf(vel).scales.get(.L));
}

test "Conversion chain: km -> m -> cm" {
    const KiloMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .k });
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const CentiMeter = Scalar(i128, .{ .L = 1 }, .{ .L = .c });

    const km = KiloMeter{ .value = 15 };
    const m = km.to(Meter);
    const cm = m.to(CentiMeter);

    try std.testing.expectEqual(15_000, m.value);
    try std.testing.expectEqual(1_500_000, cm.value);
}

test "Conversion: hours -> minutes -> seconds" {
    const Hour = Scalar(i128, .{ .T = 1 }, .{ .T = .hour });
    const Minute = Scalar(i128, .{ .T = 1 }, .{ .T = .min });
    const Second = Scalar(i128, .{ .T = 1 }, .{});

    const h = Hour{ .value = 1.0 };
    const min = h.to(Minute);
    const sec = min.to(Second);

    try std.testing.expectEqual(60, min.value);
    try std.testing.expectEqual(3600, sec.value);
}

test "Negative values" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});

    const a = Meter{ .value = 5 };
    const b = Meter{ .value = 20 };
    const diff = a.sub(b);
    try std.testing.expectEqual(-15, diff.value);
}

test "Format Scalar" {
    const MeterPerSecondSq = Scalar(f32, .{ .L = 1, .T = -2 }, .{ .T = .n });
    const KgMeterPerSecond = Scalar(f32, .{ .M = 1, .L = 1, .T = -1 }, .{ .M = .k });
    const Meter = Scalar(f32, .{ .L = 1 }, .{});

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

test "Abs" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const m1 = Meter{ .value = -50 };
    const m2 = m1.abs();

    try std.testing.expectEqual(50, m2.value);
    try std.testing.expectEqual(1, @TypeOf(m2).dims.get(.L));

    const m_float = Scalar(f32, .{ .L = 1 }, .{});
    const m3 = m_float{ .value = -42.5 };
    try std.testing.expectEqual(42.5, m3.abs().value);
}

test "Pow" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const d = Meter{ .value = 4 };

    const area = d.pow(2);
    try std.testing.expectEqual(16, area.value);
    try std.testing.expectEqual(2, @TypeOf(area).dims.get(.L));

    const volume = d.pow(3);
    try std.testing.expectEqual(64, volume.value);
    try std.testing.expectEqual(3, @TypeOf(volume).dims.get(.L));

    // Float test
    const MeterF = Scalar(f32, .{ .L = 1 }, .{});
    const d_f = MeterF{ .value = 2.0 };
    const area_f = d_f.pow(3);
    try std.testing.expectEqual(8.0, area_f.value);
    try std.testing.expectEqual(3, @TypeOf(area_f).dims.get(.L));
}

test "mulBy comptime_int" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const d = Meter{ .value = 7 };

    const scaled = d.mulBy(3); // comptime_int → dimensionless
    try std.testing.expectEqual(21, scaled.value);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
    try std.testing.expectEqual(0, @TypeOf(scaled).dims.get(.T));
}

test "mulBy comptime_float" {
    const MeterF = Scalar(f64, .{ .L = 1 }, .{});
    const d = MeterF{ .value = 4.0 };

    const scaled = d.mulBy(2.5); // comptime_float → dimensionless
    try std.testing.expectApproxEqAbs(10.0, scaled.value, 1e-9);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
}

test "mulBy T (value type)" {
    const MeterF = Scalar(f32, .{ .L = 1 }, .{});
    const d = MeterF{ .value = 6.0 };
    const factor: f32 = 0.5;

    const scaled = d.mulBy(factor); // bare f32 → dimensionless
    try std.testing.expectApproxEqAbs(3.0, scaled.value, 1e-6);
    try std.testing.expectEqual(1, @TypeOf(scaled).dims.get(.L));
}

test "divBy comptime_int" {
    const Meter = Scalar(i128, .{ .L = 1 }, .{});
    const d = Meter{ .value = 100 };

    const half = d.divBy(4); // comptime_int → dimensionless divisor
    try std.testing.expectEqual(25, half.value);
    try std.testing.expectEqual(1, @TypeOf(half).dims.get(.L));
}

test "divBy comptime_float" {
    const MeterF = Scalar(f64, .{ .L = 1 }, .{});
    const d = MeterF{ .value = 9.0 };

    const r = d.divBy(3.0);
    try std.testing.expectApproxEqAbs(3.0, r.value, 1e-9);
    try std.testing.expectEqual(1, @TypeOf(r).dims.get(.L));
}

test "add/sub bare number on dimensionless scalar" {
    // Bare numbers are dimensionless, so add/sub only works when Self is also dimensionless.
    const DimLess = Scalar(i128, .{}, .{});
    const a = DimLess{ .value = 10 };

    const b = a.add(5); // comptime_int, both dimensionless → ok
    try std.testing.expectEqual(15, b.value);

    const c = a.sub(3);
    try std.testing.expectEqual(7, c.value);
}

test "comparisons with comptime_int on dimensionless scalar" {
    const DimLess = Scalar(i128, .{}, .{});
    const x = DimLess{ .value = 42 };

    try std.testing.expect(x.eq(42));
    try std.testing.expect(x.ne(0));
    try std.testing.expect(x.gt(10));
    try std.testing.expect(x.gte(42));
    try std.testing.expect(x.lt(100));
    try std.testing.expect(x.lte(42));
}
