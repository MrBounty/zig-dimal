# dimal — Dimensional Analysis for Zig

A comptime-first dimensional analysis module for Zig. If you try to add meters to seconds, **it won't compile**. That's the point.

Started by a space simulation where `i128` positions were needed to avoid float imprecision far from the origin, this module grew into a full physical-unit type system with zero runtime overhead.

> **Source:** [git.bouvais.lu/adrien/zig-dimal](https://git.bouvais.lu/adrien/zig-dimal)  
> **Minimum Zig version:** `0.16.0`

---

## Features

- **100% comptime** — all dimension and unit tracking happens at compile time. No added memory, *almost* native performance.
- **Compile-time dimension errors** — adding `Meter` to `Second` is a compile error, not a runtime panic.
- **Automatic unit conversion** — use `.to()` to convert between compatible units (e.g. `km/h` → `m/s`). Scale factors are resolved at comptime.
* **Full SI prefix & Imperial support** — `pico` through `peta`, plus common Imperial units like `inch`, `ft`, `mi`, `lb`, and `oz`.
- **Time scale support** — `min`, `hour`, `year` built in.
- **Scalar and Vector types** — operate on individual values or fixed-size arrays with the same dimensional safety.
- **Built-in physical quantities** — `dma.Base` provides ready-made types for `Velocity`, `Acceleration`, `Force`, `Energy`, `Pressure`, `ElectricCharge`, `ThermalConductivity`, and many more.
- **Comparison operations** — `eq`, `ne`, `gt`, `gte`, `lt`, `lte` on both `Scalar` and `Vector`, with automatic scale resolution.
- **Arithmetic with bare numbers** — multiply or divide a dimensioned value by a `comptime_int`, `comptime_float`, or plain `T` directly. The value is treated as dimensionless; dimensions pass through unchanged.
- **`abs`, `pow`, `sqrt`** — unary operations with correct dimension tracking (`pow(2)` on `L¹` → `L²`, etc.).
- **Vector geometry** — `dot` product (returns a `Scalar`), `cross` product (Vec3 only), element-wise `product` (all components multiplied).
- **Rich formatting** — values print with their unit automatically: `9.81m.s⁻²`, `42m.kg.s⁻¹`, `0.172km`.
- **`i128` support** — the whole reason this exists. Use large integers for high-precision fixed-point positions without manual conversion.
- **Tests and benchmarks included** — run them and see how it performs on your machine (results welcome!).

---

## The 7 SI Base Dimensions

| Symbol | Dimension            | SI Unit  |
|--------|----------------------|----------|
| `L`    | Length               | `m`      |
| `M`    | Mass                 | `g`      |
| `T`    | Time                 | `s`      |
| `I`    | Electric Current     | `A`      |
| `Tp`   | Temperature          | `K`      |
| `N`    | Amount of Substance  | `mol`    |
| `J`    | Luminous Intensity   | `cd`     |

---

## Installation

### 1. Fetch the dependency

```sh
zig fetch --save git+https://git.bouvais.lu/adrien/zig-dimal#0.1.1
```

### 2. Wire it up in `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const dimal = b.dependency("dimal", .{}).module("dimal");

    const exe = b.addExecutable(.{
        .name = "my_project",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .imports = &.{.{
                .name = "dimal",
                .module = dimal,
            }},
        }),
    });
    b.installArtifact(exe);
}
```

### 3. Import in your code

```zig
const dma = @import("dimal");
const Scalar     = dma.Scalar;
const Dimensions = dma.Dimensions;
const Scales     = dma.Scales;
```

---

## Quick Start

### Defining unit types

A `Scalar` type is parameterized by three things: the numeric type (`f64`, `i128`, …), the dimensions (which physical quantities and their exponents), and the scales (SI prefixes or custom time units). Both the dimension and scale arguments are plain struct literals — no wrapper call needed.

```zig
const Meter     = Scalar(f64, .{ .L = 1 },           .{});
const NanoMeter = Scalar(i64, .{ .L = 1 },           .{ .L = .n });
const KiloMeter = Scalar(f64, .{ .L = 1 },           .{ .L = .k });
const Second    = Scalar(f64, .{ .T = 1 },           .{});
const Velocity  = Scalar(f64, .{ .L = 1, .T = -1 },  .{});
const Kmh       = Scalar(f64, .{ .L = 1, .T = -1 },  .{ .L = .k, .T = .hour });
```

Or use the pre-built helpers from `dma.Base`:

```zig
const Acceleration = dma.Base.Acceleration.Of(f64);
const KmhSpeed     = dma.Base.Speed.Scaled(f64, .{ .L = .k, .T = .hour });
```

### Kinematics example

```zig
const v0    = Velocity{ .value = 10.0 };       // 10 m/s
const accel = Acceleration{ .value = 9.81 };   // 9.81 m/s²
const time  = Second{ .value = 5.0 };          // 5 s

// d = v₀t + ½at²
const d1   = v0.mul(time);                         // → Meter
const d2   = accel.mul(time).mul(time).mul(0.5);   // → Meter  (bare 0.5 is dimensionless)
const dist = d1.add(d2);

const v_final = v0.add(accel.mul(time));

std.debug.print("Distance: {d} | {d}\n", .{ dist, dist.to(KiloMeter) });
// Distance: 172.625m | 0.172625km

std.debug.print("Final speed: {d:.2}\n", .{v_final});
// Final speed: 59.05m.s⁻¹
```

### Unit conversion

`.to()` converts between compatible units at comptime. Mixing incompatible dimensions is a **compile error**.

```zig
const speed_kmh = Kmh{ .value = 120.0 };
const speed_ms  = speed_kmh.to(Velocity); // 33.333... m/s — comptime ratio

// This would NOT compile:
// const bad = speed_kmh.to(Second); // "Dimension mismatch in to: L1T-1 vs T1"
```

#### Imperial

```zig
const Inch      = Scalar(f64, .{ .L = 1 }, .{ .L = .inch });
const Mile      = Scalar(f64, .{ .L = 1 }, .{ .L = .mi });
const Pound     = Scalar(f64, .{ .M = 1 }, .{ .M = .lb });

// Conversion example
const dist_m = Meter{ .value = 1609.344 };
const dist_mi = dist_m.to(Mile); // Result: 1.0
```

### Arithmetic with bare numbers

Passing a `comptime_int`, `comptime_float`, or plain `T` to `mul` / `div` treats it as a dimensionless value. Dimensions pass through unchanged.

```zig
const Meter = Scalar(f64, .{ .L = 1 }, .{});
const d     = Meter{ .value = 6.0 };

const half    = d.mul(0.5);   // comptime_float → still Meter
const doubled = d.mul(2);     // comptime_int   → still Meter
const factor: f64 = 3.0;
const tripled = d.mul(factor); // runtime f64    → still Meter
```

### Comparisons

`eq`, `ne`, `gt`, `gte`, `lt`, `lte` work on any two `Scalar` values of the **same dimension**. Scales are resolved automatically before comparing.

```zig
const Meter     = Scalar(i64, .{ .L = 1 }, .{});
const KiloMeter = Scalar(i64, .{ .L = 1 }, .{ .L = .k });

const m1000 = Meter{ .value = 1000 };
const km1   = KiloMeter{ .value = 1 };
const km2   = KiloMeter{ .value = 2 };

_ = m1000.eq(km1);   // true  — same magnitude
_ = km2.gt(m1000);   // true  — 2 km > 1000 m
_ = m1000.lte(km2);  // true

// Comparing with a bare number works when the scalar is dimensionless.
// Comparing incompatible dimensions is a compile error.
```

### Unary operations: `abs`, `pow`, `sqrt`

```zig
const Meter = Scalar(f64, .{ .L = 1 }, .{});
const d     = Meter{ .value = -4.0 };

const magnitude = d.abs();    // 4.0 m      — dimension unchanged
const area      = d.pow(2);   // 16.0 m²    — dims scaled by exponent
const side      = area.sqrt(); // 4.0 m     — dims halved (requires even exponents)
```

`pow` accepts any `comptime_int` exponent and adjusts the dimension exponents accordingly. `sqrt` is a compile error unless all dimension exponents are even.

### Working with Vectors

Every `Scalar` type exposes a `.Vec3` alias and a generic `.Vec(n)` type accessor:

```zig
const Vec3Meter = Meter.Vec3; // equivalent to Vector(3, Meter)

const pos = Vec3Meter{ .data = .{ 100, 200, 300 } };
const t   = Second{ .value = 10 };

const vel = pos.divScalar(t);  // → Vec3 of Velocity (m/s)
std.debug.print("{d}\n", .{vel}); // (10, 20, 30)m.s⁻¹
```

#### Dot and cross products

```zig
const Newton = Scalar(f32, .{ .M = 1, .L = 1, .T = -2 }, .{});

const r     = Meter.Vec3{ .data = .{ 10.0, 0.0, 0.0 } };
const force = Newton.Vec3{ .data = .{ 5.0, 5.0, 0.0 } };

// Dot product — returns a Scalar (dimensions summed)
const work   = force.dot(r);     // 50.0 J  (M¹L²T⁻²)

// Cross product — returns a Vec3 (dimensions summed, Vec3 only)
const torque = r.cross(force);   // (0, 0, 50) N·m
```

#### Vector comparisons

Element-wise comparisons return `[len]bool`. Whole-vector equality uses `eqAll` / `neAll`. A single scalar can be broadcast with the `*Scalar` variants.

```zig
const positions  = Meter.Vec3{ .data = .{ 500.0, 1200.0, 3000.0 } };
const threshold  = KiloMeter{ .value = 1.0 }; // 1 km

const exceeded = positions.gtScalar(threshold); // [false, true, true]
const eq_each  = positions.eq(positions);        // [true, true, true]  (element-wise)
const all_same = positions.eqAll(positions);     // true  (whole-vector)
```

#### Other Vector operations

```zig
const v = Meter.Vec3{ .data = .{ -2.0, 3.0, -4.0 } };

const v_abs  = v.abs();       // { 2, 3, 4 } m
const vol    = v_abs.product(); // 24 m³  (dims × len)
const area   = v_abs.pow(2);  // { 4, 9, 16 } m²
const sides  = area.sqrt();   // { 2, 3, 4 } m  (element-wise sqrt)
```

---

## API Reference

### `Scalar(T, dims, scales)`

| Method | Description |
|---|---|
| `.add(rhs)` | Add two quantities of the same dimension. Auto-converts scales. |
| `.sub(rhs)` | Subtract. Auto-converts scales. |
| `.mul(rhs)` | Multiply — dimensions are **summed**. `rhs` may be a `Scalar`, `T`, `comptime_int`, or `comptime_float` (bare numbers are dimensionless). |
| `.div(rhs)` | Divide — dimensions are **subtracted**. Same `rhs` flexibility as `mul`. |
| `.abs()` | Absolute value. Dimensions and scales unchanged. |
| `.pow(exp)` | Raise to a `comptime_int` exponent. Dimension exponents are multiplied by `exp`. |
| `.sqrt()` | Square root. Compile error unless all dimension exponents are even. |
| `.eq(rhs)` / `.ne(rhs)` | Equality / inequality comparison. Scales auto-resolved. |
| `.gt(rhs)` / `.gte(rhs)` | Greater-than / greater-than-or-equal. |
| `.lt(rhs)` / `.lte(rhs)` | Less-than / less-than-or-equal. |
| `.to(DestType)` | Convert to another unit of the same dimension. Compile error on mismatch. |
| `.vec(len)` | Return a `Vector(len, Self)` with all components set to this value. |
| `.vec3()` | Shorthand for `.vec(3)`. |
| `.Vec3` | Type alias for `Vector(3, Self)`. |

### `Vector(len, Q)`

| Method | Description |
|---|---|
| `.add(rhs)` / `.sub(rhs)` | Element-wise add / subtract. |
| `.mul(rhs)` / `.div(rhs)` | Element-wise multiply / divide (both operands are Vectors). |
| `.mulScalar(s)` / `.divScalar(s)` | Scale every component by a single `Scalar`, `T`, `comptime_int`, or `comptime_float`. |
| `.dot(rhs)` | Dot product → `Scalar` with combined dimensions. |
| `.cross(rhs)` | Cross product → `Vector(3, …)`. Vec3 only. |
| `.abs()` | Element-wise absolute value. |
| `.pow(exp)` | Element-wise `comptime_int` power. Dimension exponents scaled. |
| `.sqrt()` | Element-wise square root. |
| `.product()` | Multiply all components → `Scalar` with dimensions × `len`. |
| `.negate()` | Negate all components. |
| `.length()` | Euclidean length (returns `T`). |
| `.lengthSqr()` | Sum of squared components (returns `T`). Cheaper than `length`. |
| `.eq(rhs)` / `.ne(rhs)` | Element-wise comparison → `[len]bool`. |
| `.gt(rhs)` / `.gte(rhs)` / `.lt(rhs)` / `.lte(rhs)` | Element-wise ordered comparisons → `[len]bool`. |
| `.eqAll(rhs)` / `.neAll(rhs)` | Whole-vector equality / inequality → `bool`. |
| `.eqScalar(s)` / `.neScalar(s)` | Broadcast scalar comparison → `[len]bool`. |
| `.gtScalar(s)` / `.gteScalar(s)` / `.ltScalar(s)` / `.lteScalar(s)` | Broadcast ordered scalar comparisons → `[len]bool`. |
| `.to(DestQ)` | Convert all components to a compatible scalar type. |

### `dma.Base` — Pre-built quantities

Call `.Of(T)` for base-unit scalars, `.Scaled(T, scales)` for custom scales:

`Meter`, `Second`, `Gramm`, `Kelvin`, `ElectricCurrent`, `Speed`, `Acceleration`, `Inertia`, `Force`, `Pressure`, `Energy`, `Power`, `Area`, `Volume`, `Density`, `Frequency`, `Viscosity`, `ElectricCharge`, `ElectricPotential`, `ElectricResistance`, `MagneticFlux`, `ThermalCapacity`, `ThermalConductivity`, and more.

### `Scales` — SI and Imperial Units

| Tag | Factor (Relative to Base) | Type |
|---|---|---|
| `.P` ... `.f` | $10^{15}$ ... $10^{-15}$ | SI Prefixes |
| `.min`, `.hour`, `.year` | 60, 3600, 31,536,000 | Time |
| **`.inch`** | **0.0254** | Imperial Length (m) |
| **`.ft`** | **0.3048** | Imperial Length (m) |
| **`.yd`** | **0.9144** | Imperial Length (m) |
| **`.mi`** | **1609.344** | Imperial Length (m)  |
| **`.oz`** | **28.3495231** | Imperial Mass (g) |
| **`.lb`** | **453.59237** | Imperial Mass (g)  |
| **`.st`** | **6350.29318** | Imperial Mass (g)  |

Scale entries for dimensions with exponent `0` are ignored — multiplying a dimensionless value by a kilometre-scale value no longer accidentally inherits the `k` prefix.

---

## Running Tests and Benchmarks

```sh
zig build test
zig build benchmark
```

Benchmark results are very welcome — feel free to share yours!

---

## Roadmap / Known Limitations

- SIMD acceleration for `Vector` operations.
- Some paths may still fall back to runtime computation — optimization ongoing.
- More test coverage.

---

## License

See the repository for license details.
