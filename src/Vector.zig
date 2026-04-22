const std = @import("std");
const hlp = @import("helper.zig");

const Scalar = @import("Scalar.zig").Scalar;
const Scales = @import("Scales.zig");
const UnitScale = Scales.UnitScale;
const Dimensions = @import("Dimensions.zig");
const Dimension = Dimensions.Dimension;

/// A fixed-size array of `len` elements sharing the same dimension and scale as scalar type `Q`.
pub fn Vector(comptime len: usize, comptime Q: type) type {
    const T = Q.ValueType;
    const d: Dimensions = Q.dims;
    const s: Scales = Q.scales;

    return struct {
        data: [len]T,

        const Self = @This();
        pub const ScalarType = Q;
        pub const ValueType = T;
        pub const dims: Dimensions = d;
        pub const scales = s;

        pub const zero = initDefault(0);
        pub const one = initDefault(1);

        pub fn initDefault(v: T) Self {
            var data: [len]T = undefined;
            inline for (&data) |*item| item.* = v;
            return .{ .data = data };
        }

        /// Element-wise addition. Dimensions must match; scales resolve to the finer of the two.
        pub inline fn add(self: Self, rhs: anytype) Vector(len, Scalar(
            T,
            dims,
            hlp.finerScales(Self, @TypeOf(rhs)),
        )) {
            const Tr = @TypeOf(rhs);
            var res: Vector(len, Scalar(T, d, hlp.finerScales(Self, @TypeOf(rhs)))) = undefined;
            inline for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).add(Tr.ScalarType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }
        /// Element-wise subtraction. Dimensions must match; scales resolve to the finer of the two.
        pub inline fn sub(self: Self, rhs: anytype) Vector(len, Scalar(
            T,
            dims,
            hlp.finerScales(Self, @TypeOf(rhs)),
        )) {
            const Tr = @TypeOf(rhs);
            var res: Vector(len, Scalar(T, d, hlp.finerScales(Self, @TypeOf(rhs)))) = undefined;
            inline for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).sub(Tr.ScalarType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }

        /// Element-wise division. Dimension exponents are subtracted per component.
        pub inline fn divBy(
            self: Self,
            rhs: anytype,
        ) Vector(len, Scalar(
            T,
            dims.sub(@TypeOf(rhs).dims),
            hlp.finerScales(Self, @TypeOf(rhs)),
        )) {
            const Tr = @TypeOf(rhs);
            var res: Vector(len, Scalar(T, d.sub(Tr.dims), hlp.finerScales(Self, @TypeOf(rhs)))) = undefined;
            inline for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).divBy(Tr.ScalarType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }

        /// Element-wise multiplication. Dimension exponents are summed per component.
        pub inline fn mulBy(
            self: Self,
            rhs: anytype,
        ) Vector(len, Scalar(
            T,
            dims.add(@TypeOf(rhs).dims),
            hlp.finerScales(Self, @TypeOf(rhs)),
        )) {
            const Tr = @TypeOf(rhs);
            var res: Vector(len, Scalar(T, d.add(Tr.dims), hlp.finerScales(Self, @TypeOf(rhs)))) = undefined;
            inline for (self.data, 0..) |v, i| {
                const q = (Q{ .value = v }).mulBy(Tr.ScalarType{ .value = rhs.data[i] });
                res.data[i] = q.value;
            }
            return res;
        }

        /// Divide every component by a single scalar. Dimensions are subtracted (e.g. position / time → velocity).
        pub inline fn divByScalar(
            self: Self,
            scalar: anytype,
        ) Vector(len, Scalar(
            T,
            dims.sub(@TypeOf(scalar).dims),
            hlp.finerScales(Self, @TypeOf(scalar)),
        )) {
            var res: Vector(len, Scalar(T, d.sub(@TypeOf(scalar).dims), hlp.finerScales(Self, @TypeOf(scalar)))) = undefined;
            inline for (self.data, 0..) |v, i| {
                const q = Q{ .value = v };
                res.data[i] = q.divBy(scalar).value;
            }
            return res;
        }

        /// Multiply every component by a single scalar. Dimensions are summed.
        pub inline fn mulByScalar(
            self: Self,
            scalar: anytype,
        ) Vector(len, Scalar(
            T,
            dims.add(@TypeOf(scalar).dims),
            hlp.finerScales(Self, @TypeOf(scalar)),
        )) {
            var res: Vector(len, Scalar(T, d.add(@TypeOf(scalar).dims), hlp.finerScales(Self, @TypeOf(scalar)))) = undefined;
            inline for (self.data, 0..) |v, i| {
                const q = Q{ .value = v };
                res.data[i] = q.mulBy(scalar).value;
            }
            return res;
        }

        /// Standard dot product. Dimensions are summed (e.g., Force * Distance = Energy).
        /// Returns a Scalar type with the combined dimensions and finest scale.
        pub inline fn dot(self: Self, rhs: anytype) Scalar(
            T,
            dims.add(@TypeOf(rhs).dims),
            hlp.finerScales(Self, @TypeOf(rhs)),
        ) {
            const Tr = @TypeOf(rhs);

            var sum: T = 0;
            inline for (self.data, 0..) |v, i| {
                const q_lhs = Q{ .value = v };
                const q_rhs = Tr.ScalarType{ .value = rhs.data[i] };
                sum += q_lhs.mulBy(q_rhs).value;
            }
            return .{ .value = sum };
        }

        /// 3D Cross product. Dimensions are summed.
        /// Only valid for vectors of length 3.
        pub inline fn cross(self: Self, rhs: anytype) Vector(3, Scalar(
            T,
            dims.add(@TypeOf(rhs).dims),
            hlp.finerScales(Self, @TypeOf(rhs)),
        )) {
            if (comptime len != 3)
                @compileError("Cross product is only defined for Vector(3, ...)");

            const Tr = @TypeOf(rhs);
            const ResScalar = Scalar(T, d.add(Tr.dims), hlp.finerScales(Self, Tr));
            const ResVec = Vector(3, ResScalar);

            // Calculation: [y1*z2 - z1*y2, z1*x2 - x1*z2, x1*y2 - y1*x2]
            const s1 = Q{ .value = self.data[0] };
            const s2 = Q{ .value = self.data[1] };
            const s3 = Q{ .value = self.data[2] };

            const o1 = Tr.ScalarType{ .value = rhs.data[0] };
            const o2 = Tr.ScalarType{ .value = rhs.data[1] };
            const o3 = Tr.ScalarType{ .value = rhs.data[2] };

            return ResVec{
                .data = .{
                    s2.mulBy(o3).sub(s3.mulBy(o2)).value,
                    s3.mulBy(o1).sub(s1.mulBy(o3)).value,
                    s1.mulBy(o2).sub(s2.mulBy(o1)).value,
                },
            };
        }

        /// Returns true only if all components are equal after scale resolution.
        pub inline fn eqAll(self: Self, rhs: anytype) bool {
            const Tr = @TypeOf(rhs);
            if (comptime !dims.eql(Tr.dims))
                @compileError("Dimension mismatch in eq: " ++ dims.str() ++ " vs " ++ Tr.dims.str());

            inline for (self.data, 0..) |v, i| {
                const lhs_q = Q{ .value = v };
                const rhs_q = Tr.ScalarType{ .value = rhs.data[i] };
                if (!lhs_q.eq(rhs_q)) return false;
            }
            return true;
        }

        /// Returns true if any component differs after scale resolution.
        pub inline fn neAll(self: Self, rhs: anytype) bool {
            return !self.eqAll(rhs);
        }

        /// Element-wise "Equal". Returns an array of booleans.
        pub inline fn eq(self: Self, rhs: anytype) [len]bool {
            const Tr = @TypeOf(rhs);
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).eq(Tr.ScalarType{ .value = rhs.data[i] });
            return res;
        }

        /// Element-wise "Not Equal". Returns an array of booleans.
        pub inline fn ne(self: Self, rhs: anytype) [len]bool {
            const Tr = @TypeOf(rhs);
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).ne(Tr.ScalarType{ .value = rhs.data[i] });
            return res;
        }

        /// Element-wise "Greater Than". Returns an array of booleans.
        pub inline fn gt(self: Self, rhs: anytype) [len]bool {
            const Tr = @TypeOf(rhs);
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).gt(Tr.ScalarType{ .value = rhs.data[i] });
            return res;
        }

        /// Element-wise "Greater Than or Equal". Returns an array of booleans.
        pub inline fn gte(self: Self, rhs: anytype) [len]bool {
            const Tr = @TypeOf(rhs);
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).gte(Tr.ScalarType{ .value = rhs.data[i] });
            return res;
        }

        /// Element-wise "Less Than". Returns an array of booleans.
        pub inline fn lt(self: Self, rhs: anytype) [len]bool {
            const Tr = @TypeOf(rhs);
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).lt(Tr.ScalarType{ .value = rhs.data[i] });
            return res;
        }

        /// Element-wise "Less Than or Equal". Returns an array of booleans.
        pub inline fn lte(self: Self, rhs: anytype) [len]bool {
            const Tr = @TypeOf(rhs);
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).lte(Tr.ScalarType{ .value = rhs.data[i] });
            return res;
        }

        /// Compares every element in the vector to a single scalar for equality.
        /// Returns an array of booleans [len]bool. Dimensions must match; scales are auto-resolved.
        pub inline fn eqScalar(self: Self, scalar: anytype) [len]bool {
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).eq(scalar);
            return res;
        }

        /// Compares every element in the vector to a single scalar for inequality.
        /// Returns an array of booleans [len]bool. Dimensions must match; scales are auto-resolved.
        pub inline fn neScalar(self: Self, scalar: anytype) [len]bool {
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).ne(scalar);
            return res;
        }

        /// Checks if each element in the vector is strictly greater than the given scalar.
        /// Returns an array of booleans [len]bool.
        pub inline fn gtScalar(self: Self, scalar: anytype) [len]bool {
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).gt(scalar);
            return res;
        }

        /// Checks if each element in the vector is greater than or equal to the given scalar.
        /// Returns an array of booleans [len]bool.
        pub inline fn gteScalar(self: Self, scalar: anytype) [len]bool {
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).gte(scalar);
            return res;
        }

        /// Checks if each element in the vector is strictly less than the given scalar.
        /// Returns an array of booleans [len]bool.
        pub inline fn ltScalar(self: Self, scalar: anytype) [len]bool {
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).lt(scalar);
            return res;
        }

        /// Checks if each element in the vector is less than or equal to the given scalar.
        /// Returns an array of booleans [len]bool.
        pub inline fn lteScalar(self: Self, scalar: anytype) [len]bool {
            var res: [len]bool = undefined;
            inline for (self.data, 0..) |v, i|
                res[i] = (Q{ .value = v }).lte(scalar);
            return res;
        }

        /// Negate all components. Dimensions are preserved.
        pub fn negate(self: Self) Self {
            var res: Self = undefined;
            inline for (self.data, 0..) |v, i|
                res.data[i] = -v;
            return res;
        }

        /// Convert all components to a compatible scalar type. Compile error on dimension mismatch.
        pub inline fn to(self: Self, comptime DestQ: type) Vector(len, DestQ) {
            var res: Vector(len, DestQ) = undefined;
            inline for (self.data, 0..) |v, i|
                res.data[i] = (Q{ .value = v }).to(DestQ).value;
            return res;
        }

        /// Sum of squared components. Cheaper than `length` — use for comparisons.
        pub inline fn lengthSqr(self: Self) T {
            var sum: T = 0;
            inline for (self.data) |v|
                sum += v * v;
            return sum;
        }

        /// Euclidean length. Integer types use integer sqrt (truncated).
        pub inline fn length(self: Self) T {
            const len_sq = self.lengthSqr();

            if (comptime @typeInfo(T) == .int) {
                const UnsignedT = @Int(.unsigned, @typeInfo(T).int.bits);
                const u_len_sq = @as(UnsignedT, @intCast(len_sq));
                return @as(T, @intCast(std.math.sqrt(u_len_sq)));
            } else {
                return @sqrt(len_sq);
            }
        }

        pub fn formatNumber(
            self: Self,
            writer: *std.Io.Writer,
            options: std.fmt.Number,
        ) !void {
            try writer.writeAll("(");
            for (self.data, 0..) |v, i| {
                if (i > 0) try writer.writeAll(", ");
                switch (@typeInfo(T)) {
                    .float, .comptime_float => try writer.printFloat(v, options),
                    .int, .comptime_int => try writer.printInt(v, 10, .lower, .{
                        .width = options.width,
                        .alignment = options.alignment,
                        .fill = options.fill,
                        .precision = options.precision,
                    }),
                    else => unreachable,
                }
            }
            try writer.writeAll(")");
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

test "Format VectorX" {
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

    const accel = MeterPerSecondSq.Vec3.initDefault(9.81);
    const momentum = KgMeterPerSecond.Vec3{ .data = .{ 43, 0, 11 } };

    var buf: [64]u8 = undefined;
    var res = try std.fmt.bufPrint(&buf, "{d}", .{accel});
    try std.testing.expectEqualStrings("(9.81, 9.81, 9.81)m.ns⁻²", res);

    res = try std.fmt.bufPrint(&buf, "{d:.2}", .{momentum});
    try std.testing.expectEqualStrings("(43.00, 0.00, 11.00)m.kg.s⁻¹", res);
}

test "VecX Init and Basic Arithmetic" {
    const Meter = Scalar(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
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
    const Meter = Scalar(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Second = Scalar(i32, Dimensions.init(.{ .T = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    const pos = Vec3M{ .data = .{ 100, 200, 300 } };
    const time = Second{ .value = 10 };

    // Vector divided by scalar (Velocity = Position / Time)
    const vel = pos.divByScalar(time);
    try std.testing.expectEqual(10, vel.data[0]);
    try std.testing.expectEqual(20, vel.data[1]);
    try std.testing.expectEqual(30, vel.data[2]);
    try std.testing.expectEqual(1, @TypeOf(vel).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(vel).dims.get(.T));

    // Vector multiplied by scalar (Position = Velocity * Time)
    const new_pos = vel.mulByScalar(time);
    try std.testing.expectEqual(100, new_pos.data[0]);
    try std.testing.expectEqual(200, new_pos.data[1]);
    try std.testing.expectEqual(300, new_pos.data[2]);
    try std.testing.expectEqual(1, @TypeOf(new_pos).dims.get(.L));
    try std.testing.expectEqual(0, @TypeOf(new_pos).dims.get(.T));
}

test "VecX Element-wise Math and Scaling" {
    const Meter = Scalar(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Vec3M = Meter.Vec3;

    const v1 = Vec3M{ .data = .{ 10, 20, 30 } };
    const v2 = Vec3M{ .data = .{ 2, 5, 10 } };

    // Element-wise division
    const div = v1.divBy(v2);
    try std.testing.expectEqual(5, div.data[0]);
    try std.testing.expectEqual(4, div.data[1]);
    try std.testing.expectEqual(3, div.data[2]);
    try std.testing.expectEqual(0, @TypeOf(div).dims.get(.L)); // M / M = Dimensionless
}

test "VecX Conversions" {
    const KiloMeter = Scalar(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
    const Meter = Scalar(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

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
    const MeterInt = Scalar(i32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const MeterFloat = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));

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

test "Vector Comparisons" {
    const Meter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const KiloMeter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));

    const v1 = Meter.Vec3{ .data = .{ 1000.0, 500.0, 0.0 } };
    const v2 = KiloMeter.Vec3{ .data = .{ 1.0, 0.5, 0.0 } };
    const v3 = KiloMeter.Vec3{ .data = .{ 1.0, 0.6, 0.0 } };

    // 1. Equality (Whole vector)
    try std.testing.expect(v1.eqAll(v2));
    try std.testing.expect(v1.neAll(v3));

    // 2. Element-wise Ordered Comparison
    const higher = v3.gt(v1); // compares 1km, 0.6km, 0km vs 1000m, 500m, 0m
    try std.testing.expectEqual(false, higher[0]); // 1km == 1000m
    try std.testing.expectEqual(true, higher[1]); // 0.6km > 500m
    try std.testing.expectEqual(false, higher[2]); // 0 == 0

    // 3. Element-wise Equal Comparison
    const equal = v3.eq(v1); // compares 1km, 0.6km, 0km vs 1000m, 500m, 0m
    try std.testing.expectEqual(true, equal[0]); // 1km == 1000m
    try std.testing.expectEqual(false, equal[1]); // 0.6km > 500m
    try std.testing.expectEqual(true, equal[2]); // 0 == 0

    // 3. Less than or equal
    const low_eq = v1.lte(v3);
    try std.testing.expect(low_eq[0] and low_eq[1] and low_eq[2]);
}

test "Vector vs Scalar Comparisons" {
    const Meter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const KiloMeter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));

    const positions = Meter.Vec3{ .data = .{ 500.0, 1200.0, 3000.0 } };
    const threshold = KiloMeter{ .value = 1.0 }; // 1km (1000m)

    // Check which axes exceed the 1km threshold
    const exceeded = positions.gtScalar(threshold);

    try std.testing.expectEqual(false, exceeded[0]); // 500m  > 1km is false
    try std.testing.expectEqual(true, exceeded[1]); // 1200m > 1km is true
    try std.testing.expectEqual(true, exceeded[2]); // 3000m > 1km is true

    // Check for equality (broadcasted)
    const exact_match = positions.eqScalar(Meter{ .value = 500.0 });
    try std.testing.expect(exact_match[0] == true);
    try std.testing.expect(exact_match[1] == false);
}

test "Vector Dot and Cross Products" {
    const Meter = Scalar(f32, Dimensions.init(.{ .L = 1 }), Scales.init(.{}));
    const Newton = Scalar(f32, Dimensions.init(.{ .M = 1, .L = 1, .T = -2 }), Scales.init(.{}));

    const pos = Meter.Vec3{ .data = .{ 10.0, 0.0, 0.0 } };
    const force = Newton.Vec3{ .data = .{ 5.0, 5.0, 0.0 } };

    // 1. Dot Product (Work = F dot d)
    const work = force.dot(pos);
    try std.testing.expectEqual(50.0, work.value);
    // Dimensions should be M¹L²T⁻² (Energy/Joules)
    try std.testing.expectEqual(1, @TypeOf(work).dims.get(.M));
    try std.testing.expectEqual(2, @TypeOf(work).dims.get(.L));
    try std.testing.expectEqual(-2, @TypeOf(work).dims.get(.T));

    // 2. Cross Product (Torque = r cross F)
    const torque = pos.cross(force);
    try std.testing.expectEqual(0.0, torque.data[0]);
    try std.testing.expectEqual(0.0, torque.data[1]);
    try std.testing.expectEqual(50.0, torque.data[2]);
    // Torque dimensions are same as Energy but as a Vector
    try std.testing.expectEqual(2, @TypeOf(torque).dims.get(.L));
}
