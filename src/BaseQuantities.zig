const std = @import("std");

// Adjust these imports to match your actual file names
const Dimensions = @import("Dimensions.zig");
const Scales = @import("Scales.zig");
const Quantity = @import("Quantity.zig").Quantity;

/// Helper function to create a clean namespace for each physical dimension.
/// It exposes the raw dimensions, and easy type-creators for Base or Scaled variants.
pub fn QtyNamespace(comptime d: anytype) type {
    return struct {
        pub const dims = Dimensions.init(d);

        /// Creates a Quantity of this dimension using default scales.
        /// Example: const V = Quantities.Velocity.Base(f32);
        pub fn Base(comptime T: type) type {
            return Quantity(T, dims, Scales.init(.{}));
        }

        /// Creates a Quantity of this dimension using custom scales.
        /// Example: const Kmh = Quantities.Velocity.Scaled(f32, Scales.init(.{ .L = .k, .T = .hour }));
        pub fn Scaled(comptime T: type, comptime s: Scales) type {
            return Quantity(T, dims, s);
        }
    };
}

// ==========================================
// Base Quantities
// ==========================================
pub const Meter = QtyNamespace(.{ .L = 1 });
pub const Second = QtyNamespace(.{ .T = 1 });
pub const Gramm = QtyNamespace(.{ .M = 1 });
pub const Kelvin = QtyNamespace(.{ .Tr = 1 });
pub const ElectricCurrent = QtyNamespace(.{ .I = 1 });

// ==========================================
// Electric
// ==========================================
pub const ElectricConductivity = QtyNamespace(.{ .M = -1, .L = -3, .T = 3, .I = 2 });
pub const ElectricCharge = QtyNamespace(.{ .T = 1, .I = 1 });
pub const ElectricPotential = QtyNamespace(.{ .T = -3, .L = 2, .M = 1, .I = -1 });
pub const ElectricResistance = QtyNamespace(.{ .M = 1, .L = 2, .T = -3, .I = -2 });
pub const ElectricResistivity = QtyNamespace(.{ .M = 1, .L = 3, .T = -3, .I = -2 });
pub const ElectricCapacitance = QtyNamespace(.{ .T = 4, .L = -2, .M = -1, .I = 2 });
pub const ElectricImpedance = ElectricResistance;
pub const MagneticFlux = QtyNamespace(.{ .M = 1, .L = 2, .T = -2, .I = -1 });
pub const MagneticDensity = QtyNamespace(.{ .M = 1, .T = -2, .I = -1 });
pub const MagneticStrength = QtyNamespace(.{ .L = -1, .I = 1 }); // Fixed typo from MagneticStrengh
pub const MagneticMoment = QtyNamespace(.{ .L = 2, .I = 1 });

// ==========================================
// Movement
// ==========================================
pub const Velocity = QtyNamespace(.{ .L = 1, .T = -1 });
pub const Acceleration = QtyNamespace(.{ .L = 1, .T = -2 });
pub const Inertia = QtyNamespace(.{ .M = 1, .L = 2 });

// ==========================================
// Forces / Energy
// ==========================================
pub const Force = QtyNamespace(.{ .T = -2, .M = 1, .L = 1 });
pub const Pressure = QtyNamespace(.{ .T = -2, .L = -1, .M = 1 });
pub const Energy = QtyNamespace(.{ .T = -2, .L = 2, .M = 1 });
pub const Power = QtyNamespace(.{ .T = -3, .L = 2, .M = 1 });

// ==========================================
// Dimension
// ==========================================
pub const Area = QtyNamespace(.{ .L = 2 });
pub const Volume = QtyNamespace(.{ .L = 3 });
pub const AreaDensity = QtyNamespace(.{ .M = 1, .L = -2 });
pub const Density = QtyNamespace(.{ .M = 1, .L = -3 });

// ==========================================
// Thermal
// ==========================================
pub const ThermalHeat = Energy;
pub const ThermalWork = Energy;
pub const ThermalCapacity = QtyNamespace(.{ .M = 1, .L = 2, .T = -2, .Tr = -1 });
pub const ThermalCapacityPerMass = QtyNamespace(.{ .L = 2, .T = -2, .Tr = -1 });
pub const ThermalFluxDensity = QtyNamespace(.{ .M = 1, .T = -3 }); // Fixed typo from ThermalluxDensity
pub const ThermalConductance = QtyNamespace(.{ .M = 1, .L = 2, .T = -3, .Tr = -1 });
pub const ThermalConductivity = QtyNamespace(.{ .M = 1, .L = 1, .T = -3, .Tr = -1 });
pub const ThermalResistance = QtyNamespace(.{ .M = -1, .L = -2, .T = 3, .Tr = 1 });
pub const ThermalResistivity = QtyNamespace(.{ .M = -1, .L = -1, .T = 3, .Tr = 1 });
pub const ThermalEntropy = QtyNamespace(.{ .M = 1, .L = 2, .T = -2, .Tr = -1 });

// ==========================================
// Others
// ==========================================
pub const Frequency = QtyNamespace(.{ .T = -1 });
pub const Viscosity = QtyNamespace(.{ .M = 1, .L = -1, .T = -1 });
pub const SurfaceTension = QtyNamespace(.{ .M = 1, .T = -2 }); // Corrected from MT-2a

test "BaseQuantities - Core dimensions instantiation" {
    // Basic types via generic wrappers
    const M = Meter.Base(f32);
    const distance = M{ .value = 100.0 };
    try std.testing.expectEqual(100.0, distance.value);
    try std.testing.expectEqual(1, M.dims.get(.L));
    try std.testing.expectEqual(0, M.dims.get(.T));

    // Test specific scale variants
    const Kmh = Velocity.Scaled(f32, Scales.init(.{ .L = .k, .T = .hour }));
    const speed = Kmh{ .value = 120.0 };
    try std.testing.expectEqual(120.0, speed.value);
    try std.testing.expectEqual(.k, @TypeOf(speed).scales.get(.L));
    try std.testing.expectEqual(.hour, @TypeOf(speed).scales.get(.T));
}

test "BaseQuantities - Kinematics equations" {
    const d = Meter.Base(f32){ .value = 50.0 };
    const t = Second.Base(f32){ .value = 2.0 };

    // Velocity = Distance / Time
    const v = d.divBy(t);
    try std.testing.expectEqual(25.0, v.value);
    try std.testing.expect(Velocity.dims.eql(@TypeOf(v).dims));

    // Acceleration = Velocity / Time
    const a = v.divBy(t);
    try std.testing.expectEqual(12.5, a.value);
    try std.testing.expect(Acceleration.dims.eql(@TypeOf(a).dims));
}

test "BaseQuantities - Dynamics (Force and Work)" {
    // 10 kg
    const m = Gramm.Scaled(f32, Scales.init(.{ .M = .k })){ .value = 10.0 };
    // 9.8 m/s^2
    const a = Acceleration.Base(f32){ .value = 9.8 };

    // Force = mass * acceleration
    const f = m.mulBy(a);
    try std.testing.expectEqual(98000, f.value);
    try std.testing.expect(Force.dims.eql(@TypeOf(f).dims));

    // Energy (Work) = Force * distance
    const distance = Meter.Base(f32){ .value = 5.0 };
    const energy = f.mulBy(distance);
    try std.testing.expectEqual(490000, energy.value);
    try std.testing.expect(Energy.dims.eql(@TypeOf(energy).dims));
}

test "BaseQuantities - Electric combinations" {
    const current = ElectricCurrent.Base(f32){ .value = 2.0 }; // 2 A
    const time = Second.Base(f32){ .value = 3.0 }; // 3 s

    // Charge = Current * time
    const charge = current.mulBy(time);
    try std.testing.expectEqual(6.0, charge.value);
    try std.testing.expect(ElectricCharge.dims.eql(@TypeOf(charge).dims));
}
