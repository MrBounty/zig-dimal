const std = @import("std");

// Adjust these imports to match your actual file names
const Dimensions = @import("Dimensions.zig");
const Scales = @import("Scales.zig");
const quantity = @import("quantity.zig");
const Quantity = quantity.Quantity;

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
