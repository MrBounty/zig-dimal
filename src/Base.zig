const std = @import("std");

// Adjust these imports to match your actual file names
const Dimensions = @import("Dimensions.zig");
const Scales = @import("Scales.zig");
const Scalar = @import("Quantity.zig").Scalar;

fn PhysicalConstant(comptime d: Dimensions.ArgOpts, comptime val: f64, comptime s: Scales.ArgOpts) type {
    return struct {
        const dims = Dimensions.init(d);
        const scales = Scales.init(s);

        /// Instantiates the constant into a specific numeric type.
        pub fn Of(comptime T: type) Scalar(T, d, s) {
            return .{ .data = @splat(@as(T, @floatCast(val))) };
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

// ==========================================
// Physical Constants
// ==========================================

pub const Constants = struct {
    /// Speed of light in vacuum (c) [m/s]
    pub const SpeedOfLight = PhysicalConstant(.{ .L = 1, .T = -1 }, 299792458.0, .{});

    /// Planck constant (h) [J⋅s = kg⋅m²⋅s⁻¹]
    pub const Planck = PhysicalConstant(.{ .M = 1, .L = 2, .T = -1 }, 6.62607015e-34, .{ .M = .k });

    /// Reduced Planck constant (ℏ) [J⋅s]
    pub const ReducedPlanck = PhysicalConstant(.{ .M = 1, .L = 2, .T = -1 }, 1.054571817e-34, .{ .M = .k });

    /// Boltzmann constant (k_B) [J⋅K⁻¹ = kg⋅m²⋅s⁻²⋅K⁻¹]
    pub const Boltzmann = PhysicalConstant(.{ .M = 1, .L = 2, .T = -2, .Tp = -1 }, 1.380649e-23, .{ .M = .k });

    /// Newtonian constant of gravitation (G) [m³⋅kg⁻¹⋅s⁻²]
    pub const Gravitational = PhysicalConstant(.{ .M = -1, .L = 3, .T = -2 }, 6.67430e-11, .{ .M = .k });

    /// Stefan–Boltzmann constant (σ) [W⋅m⁻²⋅K⁻⁴ = kg⋅s⁻³⋅K⁻⁴]
    pub const StefanBoltzmann = PhysicalConstant(.{ .M = 1, .T = -3, .Tp = -4 }, 5.670374419e-8, .{ .M = .k });

    /// Elementary charge (e) [C = A⋅s]
    pub const ElementaryCharge = PhysicalConstant(.{ .T = 1, .I = 1 }, 1.602176634e-19, .{});

    /// Vacuum magnetic permeability (μ_0) [N⋅A⁻² = kg⋅m⋅s⁻²⋅A⁻²]
    pub const VacuumPermeability = PhysicalConstant(.{ .M = 1, .L = 1, .T = -2, .I = -2 }, 1.25663706127e-6, .{ .M = .k });

    /// Vacuum electric permittivity (ε_0) [F⋅m⁻¹ = A²⋅s⁴⋅kg⁻¹⋅m⁻³]
    pub const VacuumPermittivity = PhysicalConstant(.{ .M = -1, .L = -3, .T = 4, .I = 2 }, 8.8541878188e-12, .{ .M = .k });

    /// Electron mass (m_e) [kg]
    pub const ElectronMass = PhysicalConstant(.{ .M = 1 }, 9.1093837139e-31, .{ .M = .k });

    /// Proton mass (m_p) [kg]
    pub const ProtonMass = PhysicalConstant(.{ .M = 1 }, 1.67262192595e-27, .{ .M = .k });

    /// Neutron mass (m_n) [kg]
    pub const NeutronMass = PhysicalConstant(.{ .M = 1 }, 1.67492750056e-27, .{ .M = .k });

    /// Fine-structure constant (α) [Dimensionless]
    pub const FineStructure = PhysicalConstant(.{}, 0.0072973525643, .{});

    /// Avogadro constant (N_A) [mol⁻¹]
    /// Note: Assuming mol is currently treated as dimensionless in the base system,
    /// otherwise requires adding an `.N` dimension to Dimensions.ArgOpts.
    pub const Avogadro = PhysicalConstant(.{}, 6.02214076e23, .{});
};

// ==========================================
// Base Quantities
// ==========================================
pub const Dimless = BaseScalar(.{});
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

test "BaseQuantities - Core dimensions instantiation" {
    // Basic types via generic wrappers
    const M = Meter.Of(f32);
    const distance = M.splat(100);
    try std.testing.expectEqual(100.0, distance.value());
    try std.testing.expectEqual(1, M.dims.get(.L));
    try std.testing.expectEqual(0, M.dims.get(.T));

    // Test specific scale variants
    const Kmh = Speed.Scaled(f32, .{ .L = .k, .T = .hour });
    const speed = Kmh.splat(120);
    try std.testing.expectEqual(120.0, speed.value());
    try std.testing.expectEqual(.k, @TypeOf(speed).scales.get(.L));
    try std.testing.expectEqual(.hour, @TypeOf(speed).scales.get(.T));
}

test "BaseQuantities - Kinematics equations" {
    const d = Meter.Of(f32).splat(50.0);
    const t = Second.Of(f32).splat(2.0);

    // Velocity = Distance / Time
    const v = d.div(t);
    try std.testing.expectEqual(25.0, v.value());
    try std.testing.expect(Speed.dims.eql(@TypeOf(v).dims));

    // Acceleration = Velocity / Time
    const a = v.div(t);
    try std.testing.expectEqual(12.5, a.value());
    try std.testing.expect(Acceleration.dims.eql(@TypeOf(a).dims));
}

test "BaseQuantities - Dynamics (Force and Work)" {
    // 10 kg
    const m = Gramm.Scaled(f32, .{ .M = .k }).splat(10.0);
    // 9.8 m/s^2
    const a = Acceleration.Of(f32).splat(9.8);

    // Force = mass * acceleration
    const f = m.mul(a);
    try std.testing.expectEqual(98, f.value());
    try std.testing.expect(Force.dims.eql(@TypeOf(f).dims));

    // Energy (Work) = Force * distance
    const distance = Meter.Of(f32).splat(5.0);
    const energy = f.mul(distance);
    try std.testing.expectEqual(490, energy.value());
    try std.testing.expect(Energy.dims.eql(@TypeOf(energy).dims));
}

test "BaseQuantities - Electric combinations" {
    const current = ElectricCurrent.Of(f32).splat(2); // 2 A
    const time = Second.Of(f32).splat(3.0); // 3 s

    // Charge = Current * time
    const charge = current.mul(time);
    try std.testing.expectEqual(6.0, charge.value());
    try std.testing.expect(ElectricCharge.dims.eql(@TypeOf(charge).dims));
}

test "Constants - Initialization and dimension checks" {
    // Speed of Light
    const c = Constants.SpeedOfLight.Of(f64);
    try std.testing.expectEqual(299792458.0, c.value());
    try std.testing.expectEqual(1, @TypeOf(c).dims.get(.L));
    try std.testing.expectEqual(-1, @TypeOf(c).dims.get(.T));

    // Electron Mass (verifying scale as well)
    const me = Constants.ElectronMass.Of(f64);
    try std.testing.expectEqual(9.1093837139e-31, me.value());
    try std.testing.expectEqual(1, @TypeOf(me).dims.get(.M));
    try std.testing.expectEqual(.k, @TypeOf(me).scales.get(.M)); // Should be scaled to kg

    // Boltzmann Constant (Complex derived dimensions)
    const kb = Constants.Boltzmann.Of(f64);
    try std.testing.expectEqual(1.380649e-23, kb.value());
    try std.testing.expectEqual(1, @TypeOf(kb).dims.get(.M));
    try std.testing.expectEqual(2, @TypeOf(kb).dims.get(.L));
    try std.testing.expectEqual(-2, @TypeOf(kb).dims.get(.T));
    try std.testing.expectEqual(-1, @TypeOf(kb).dims.get(.Tp));
    try std.testing.expectEqual(.k, @TypeOf(kb).scales.get(.M));

    // Vacuum Permittivity
    const eps0 = Constants.VacuumPermittivity.Of(f64);
    try std.testing.expectEqual(8.8541878188e-12, eps0.value());
    try std.testing.expectEqual(-1, @TypeOf(eps0).dims.get(.M));
    try std.testing.expectEqual(-3, @TypeOf(eps0).dims.get(.L));
    try std.testing.expectEqual(4, @TypeOf(eps0).dims.get(.T));
    try std.testing.expectEqual(2, @TypeOf(eps0).dims.get(.I));

    // Fine Structure Constant (Dimensionless)
    const alpha = Constants.FineStructure.Of(f64);
    try std.testing.expectEqual(0.0072973525643, alpha.value());
    try std.testing.expectEqual(0, @TypeOf(alpha).dims.get(.M));
    try std.testing.expectEqual(0, @TypeOf(alpha).dims.get(.L));
}
