# zig_units

**Compile-time dimensional analysis and physical quantities for Zig.**

`zig_units` lets you attach physical units to numeric values so that dimension mismatches (like adding distance to time) become **compile errors** rather than silent bugs. 

At runtime, a `Quantity` is just its underlying numeric value — **zero memory overhead.**

```zig
const velocity = distance.divBy(time);  // Result type: L¹T⁻¹  ✓
const error    = mass.add(velocity);    // COMPILE ERROR: M¹ != L¹T⁻¹
```

**Requirements:** Zig `0.16.0`

---

## Installation

### 1. Add as a Zig dependency
```bash
zig fetch --save https://github.com/YOUR_USERNAME/zig_units/archive/refs/heads/main.tar.gz
```

### 2. Configure `build.zig`
```zig
const zig_units = b.dependency("zig_units", .{
    .target = target,
    .optimize = optimize,
});
// Add to your module or executable
exe.root_module.addImport("units", zig_units.module("zig_units"));
```

---

## Quick Start: Using Predefined Quantities

`units.Base` provides a clean way to instantiate common physical types without manually defining dimensions.

```zig
const std = @import("std");
const units = @import("units");

pub fn main() !void {
    // Instantiate types for f32 backing
    const Meter  = units.Base.Meter.Of(f32);
    const Second = units.Base.Second.Of(f32);
    
    const dist = Meter{ .value = 10.0 };
    const time = Second{ .value = 2.0 };

    // Arithmetic is type-safe and creates the correct resulting dimension
    const vel = dist.divBy(time); // Type is Velocity (L/T)
    
    std.debug.print("Speed: {f}\n", .{vel}); // Output: 5m.s⁻¹
}
```

---

## Defining Custom Quantities

You aren't limited to the built-in library. You can define any physical quantity by specifying its **Dimensions**
(powers of base units) and its **Scale** (SI prefixes).

### 1. Create a custom dimension
Dimensions are defined by 7 base SI units: `L` (Length), `M` (Mass), `T` (Time), `I` (Current), `Tp` (Temp), `N` (Substance), `J` (Intensity).

```zig
const Dims = units.Dimensions;
const Scales = units.Scales;

// Frequency is T⁻¹
const FreqDims = Dims.init(.{ .T = -1 });

// Force is M¹ L¹ T⁻²
const ForceDims = Dims.init(.{ .M = 1, .L = 1, .T = -2 });
```

### 2. Create a custom Type
Combine a numeric type, the dimensions, and a scale.

```zig
const Hertz = units.Quantity(f32, FreqDims, Scales.init(.{}));

// A specialized scale: Millimeters per Second Squared
const MmPerSecSq = units.Quantity(f32, 
    Dims.init(.{ .L = 1, .T = -2 }), 
    Scales.init(.{ .L = .m }) // .m = milli
);
```

---

## Unit Conversions

The library handles SI prefixes (`k`, `m`, `u`, `n`, etc.) and time aliases (`.min`, `.hour`) automatically.
When performing arithmetic between different scales, the **finer (smaller) scale wins** to preserve precision.

```zig
const KM = units.Base.Meter.Scaled(f32, Scales.init(.{ .L = .k })); // Kilometers
const M  = units.Base.Meter.Of(f32);                               // Meters

const d1 = KM{ .value = 1.2 };  // 1.2 km
const d2 = M{ .value = 300.0 }; // 300 m

const total = d1.add(d2);      // Result is 1500.0 (Meters)
const final = total.to(KM);    // Explicitly convert back to KM -> 1.5
```

---

## Physical Vectors (Vec3)

Physical quantities often come in 3D vectors (Position, Velocity, Force). Every `Quantity` type has a `.Vec3` alias built-in.

```zig
const Vec3M = units.Base.Meter.Of(f32).Vec3;

const gravity = Vec3M{ .data = .{ 0, -9.81, 0 } };
const pos     = Vec3M.initDefault(0); // [0, 0, 0]

// Vectors support standard operations
const length = gravity.length(); // Returns f32: 9.81
const double = gravity.scale(2.0);
```

You can also create a Vector of any length.
Vec3 found in a Quantity is just a convenience.

```zig
const M  = units.Base.Meter.Of(f32);
const Vec10M = units.QuantityVec(10, Meter);

const gravity = Vec10M.initDefault(1);
const length = gravity.length(); // Returns f32: 1.0
```

---

## SI Scales Reference

| Prefix | Enum | Factor |
| :--- | :--- | :--- |
| **Kilo** | `.k` | 10³ |
| **Mega** | `.M` | 10⁶ |
| **Giga** | `.G` | 10⁹ |
| **Milli** | `.m` | 10⁻³ |
| **Micro** | `.u` | 10⁻⁶ |
| **Minute**| `.min` | 60 |
| **Hour**  | `.hour`| 3,600 |

---

## API Summary

### `Quantity(T, dims, scales)`
- `.add(rhs)` / `.sub(rhs)`: Automatic scaling, requires same dimensions.
- `.mulBy(rhs)` / `.divBy(rhs)`: Composes dimensions (e.g., $L \times L = L^2$).
- `.scale(scalar)`: Multiply by a raw number (preserves dimensions).
- `.to(OtherType)`: Safely convert between scales of the same dimension.
- `.vec3()`: Create a 3D vector from a scalar.

### `Dimensions`
- `L`: Length (m)
- `M`: Mass (g)
- `T`: Time (s)
- `I`: Current (A)
- `Tp`: Temperature (K)
- `N`: Amount (mol)
- `J`: Intensity (cd)

