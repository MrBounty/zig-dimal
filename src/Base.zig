const std = @import("std");

// Adjust these imports to match your actual file names
const Dimensions = @import("Dimensions.zig");
const Scales = @import("Scales.zig");
const Scalar = @import("Scalar.zig").Scalar;

// TODO: Add common constants like G

fn PhysicalConstant(comptime d: Dimensions.ArgOpts, comptime val: f64, comptime s: Scales.ArgOpts) type {
    return struct {
        const dims = Dimensions.init(d);
        const scales = Scales.init(s);

        /// Instantiates the constant into a specific numeric type.
        pub fn Of(comptime T: type) Scalar(T, d, s) {
            return .{ .value = @as(T, @floatCast(val)) };
        }
    };
}

fn BaseScalar(comptime d: Dimensions.ArgOpts) type {
    return struct {
        const dims = Dimensions.init(d);

        /// Creates a Scalar of this dimension using default scales.
        /// Example: const V = Quantities.Velocity.Base(f32);
        pub fn Of(comptime T: type) type {
            return Scalar(T, d, .{});
        }

        /// Creates a Scalar of this dimension using custom scales.
        /// Example: const Kmh = Quantities.Velocity.Scaled(f32, Scales.init(.{ .L = .k, .T = .hour }));
        pub fn Scaled(comptime T: type, comptime s: Scales.ArgOpts) type {
            return Scalar(T, d, s);
        }
    };
}

pub const Dimless = BaseScalar(.{});

// ==========================================
// Base Quantities
// ==========================================
pub const Meter = BaseScalar(.{ .L = 1 });
pub const Second = BaseScalar(.{ .T = 1 });
pub const Gramm = BaseScalar(.{ .M = 1 });
pub const Kelvin = BaseScalar(.{ .Tr = 1 });
pub const ElectricCurrent = BaseScalar(.{ .I = 1 });

// ==========================================
// Electric
// ==========================================
pub const ElectricConductivity = BaseScalar(.{ .M = -1, .L = -3, .T = 3, .I = 2 });
pub const ElectricCharge = BaseScalar(.{ .T = 1, .I = 1 });
pub const ElectricPotential = BaseScalar(.{ .T = -3, .L = 2, .M = 1, .I = -1 });
pub const ElectricResistance = BaseScalar(.{ .M = 1, .L = 2, .T = -3, .I = -2 });
pub const ElectricResistivity = BaseScalar(.{ .M = 1, .L = 3, .T = -3, .I = -2 });
pub const ElectricCapacitance = BaseScalar(.{ .T = 4, .L = -2, .M = -1, .I = 2 });
pub const ElectricImpedance = ElectricResistance;
pub const MagneticFlux = BaseScalar(.{ .M = 1, .L = 2, .T = -2, .I = -1 });
pub const MagneticDensity = BaseScalar(.{ .M = 1, .T = -2, .I = -1 });
pub const MagneticStrength = BaseScalar(.{ .L = -1, .I = 1 }); // Fixed typo from MagneticStrengh
pub const MagneticMoment = BaseScalar(.{ .L = 2, .I = 1 });

// ==========================================
// Movement
// ==========================================
pub const Speed = BaseScalar(.{ .L = 1, .T = -1 });
pub const Acceleration = BaseScalar(.{ .L = 1, .T = -2 });
pub const Inertia = BaseScalar(.{ .M = 1, .L = 2 });

// ==========================================
// Forces / Energy
// ==========================================
pub const Force = BaseScalar(.{ .T = -2, .M = 1, .L = 1 });
pub const Pressure = BaseScalar(.{ .T = -2, .L = -1, .M = 1 });
pub const Energy = BaseScalar(.{ .T = -2, .L = 2, .M = 1 });
pub const Power = BaseScalar(.{ .T = -3, .L = 2, .M = 1 });

// ==========================================
// Dimension
// ==========================================
pub const Area = BaseScalar(.{ .L = 2 });
pub const Volume = BaseScalar(.{ .L = 3 });
pub const AreaDensity = BaseScalar(.{ .M = 1, .L = -2 });
pub const Density = BaseScalar(.{ .M = 1, .L = -3 });

// ==========================================
// Thermal
// ==========================================
pub const ThermalHeat = Energy;
pub const ThermalWork = Energy;
pub const ThermalCapacity = BaseScalar(.{ .M = 1, .L = 2, .T = -2, .Tr = -1 });
pub const ThermalCapacityPerMass = BaseScalar(.{ .L = 2, .T = -2, .Tr = -1 });
pub const ThermalFluxDensity = BaseScalar(.{ .M = 1, .T = -3 }); // Fixed typo from ThermalluxDensity
pub const ThermalConductance = BaseScalar(.{ .M = 1, .L = 2, .T = -3, .Tr = -1 });
pub const ThermalConductivity = BaseScalar(.{ .M = 1, .L = 1, .T = -3, .Tr = -1 });
pub const ThermalResistance = BaseScalar(.{ .M = -1, .L = -2, .T = 3, .Tr = 1 });
pub const ThermalResistivity = BaseScalar(.{ .M = -1, .L = -1, .T = 3, .Tr = 1 });
pub const ThermalEntropy = BaseScalar(.{ .M = 1, .L = 2, .T = -2, .Tr = -1 });

// ==========================================
// Others
// ==========================================
pub const Frequency = BaseScalar(.{ .T = -1 });
pub const Viscosity = BaseScalar(.{ .M = 1, .L = -1, .T = -1 });
pub const SurfaceTension = BaseScalar(.{ .M = 1, .T = -2 }); // Corrected from MT-2a

// ==========================================
// Physical Constants
// ==========================================
pub const Constants = struct {
    /// Speed of light in vacuum
    pub const c = Speed.Constant(299792458.0, Scales.init(.{}));

    /// Standard gravity
    pub const g = Acceleration.Constant(9.80665, Scales.init(.{}));

    /// Newton's Gravitational Constant: L³ M⁻¹ T⁻²
    pub const GravitationalConstant = PhysicalConstant(
        .{ .L = 3, .M = -1, .T = -2 },
        6.67430e-11,
        Scales.init(.{}),
    );

    /// Planck Constant: M L² T⁻¹
    pub const Planck = PhysicalConstant(
        .{ .M = 1, .L = 2, .T = -1 },
        6.62607015e-34,
        Scales.init(.{}),
    );
};

test "BaseQuantities - Core dimensions instantiation" {
    // Basic types via generic wrappers
    const M = Meter.Of(f32);
    const distance = M{ .value = 100.0 };
    try std.testing.expectEqual(100.0, distance.value);
    try std.testing.expectEqual(1, M.dims.get(.L));
    try std.testing.expectEqual(0, M.dims.get(.T));

    // Test specific scale variants
    const Kmh = Speed.Scaled(f32, .{ .L = .k, .T = .hour });
    const speed = Kmh{ .value = 120.0 };
    try std.testing.expectEqual(120.0, speed.value);
    try std.testing.expectEqual(.k, @TypeOf(speed).scales.get(.L));
    try std.testing.expectEqual(.hour, @TypeOf(speed).scales.get(.T));
}

test "BaseQuantities - Kinematics equations" {
    const d = Meter.Of(f32){ .value = 50.0 };
    const t = Second.Of(f32){ .value = 2.0 };

    // Velocity = Distance / Time
    const v = d.divBy(t);
    try std.testing.expectEqual(25.0, v.value);
    try std.testing.expect(Speed.dims.eql(@TypeOf(v).dims));

    // Acceleration = Velocity / Time
    const a = v.divBy(t);
    try std.testing.expectEqual(12.5, a.value);
    try std.testing.expect(Acceleration.dims.eql(@TypeOf(a).dims));
}

test "BaseQuantities - Dynamics (Force and Work)" {
    // 10 kg
    const m = Gramm.Scaled(f32, .{ .M = .k }){ .value = 10.0 };
    // 9.8 m/s^2
    const a = Acceleration.Of(f32){ .value = 9.8 };

    // Force = mass * acceleration
    const f = m.mulBy(a);
    try std.testing.expectEqual(98, f.value);
    try std.testing.expect(Force.dims.eql(@TypeOf(f).dims));

    // Energy (Work) = Force * distance
    const distance = Meter.Of(f32){ .value = 5.0 };
    const energy = f.mulBy(distance);
    try std.testing.expectEqual(490, energy.value);
    try std.testing.expect(Energy.dims.eql(@TypeOf(energy).dims));
}

test "BaseQuantities - Electric combinations" {
    const current = ElectricCurrent.Of(f32){ .value = 2.0 }; // 2 A
    const time = Second.Of(f32){ .value = 3.0 }; // 3 s

    // Charge = Current * time
    const charge = current.mulBy(time);
    try std.testing.expectEqual(6.0, charge.value);
    try std.testing.expect(ElectricCharge.dims.eql(@TypeOf(charge).dims));
}
