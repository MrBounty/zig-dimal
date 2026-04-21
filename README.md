# dimal — Dimensional Analysis for Zig

A comptime-first dimensional analysis module for Zig. If you try to add meters to seconds, **it won't compile**. That's the point.

Born from a space simulation where `i128` positions were needed to avoid float imprecision far from the origin, this module grew into a full physical-unit type system with zero runtime overhead.

> **Source:** [git.bouvais.lu/adrien/zig-dimal](https://git.bouvais.lu/adrien/zig-dimal)  
> **Minimum Zig version:** `0.16.0`

---

## Features

- **100% comptime** — all dimension and unit tracking happens at compile time. No added memory, *almost* native performance.
- **Compile-time dimension errors** — adding `Meter` to `Second` is a compile error, not a runtime panic.
- **Automatic unit conversion** — use `.to()` to convert between compatible units (e.g. `km/h` → `m/s`). Scale factors are resolved at comptime.
- **Full SI prefix support** — `pico`, `nano`, `micro`, `milli`, `centi`, `deci`, `kilo`, `mega`, `giga`, `tera`, `peta`, and more.
- **Time scale support** — `min`, `hour`, `year` built in.
- **Scalar and Vector types** — operate on individual values or fixed-size arrays with the same dimensional safety.
- **Built-in physical quantities** — `dma.Base` provides ready-made types for `Velocity`, `Acceleration`, `Force`, `Energy`, `Pressure`, `ElectricCharge`, `ThermalConductivity`, and many more.
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
zig fetch --save git+https://git.bouvais.lu/adrien/zig-dimal#b9647e04266e3f395cfd26b41622b0c119a1e5be
```

This will add the following to your `build.zig.zon` automatically:

```zig
.dependencies = .{
    .dimal = .{
        .url = "git+https://git.bouvais.lu/adrien/zig-dimal#b9647e04266e3f395cfd26b41622b0c119a1e5be",
        .hash = "dimal-0.1.0-WNhSHvomAQAX1ISvq9ZBal-Gam6078y8hE67aC82l63V",
    },
},
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

A `Scalar` type is parameterized by three things: the numeric type (`f64`, `i128`, …), the dimensions (which physical quantities, and their exponents), and the scales (SI prefixes or custom time units).

```zig
const Meter     = Scalar(f64, .init(.{ .L = 1 }),            .init(.{}));
const NanoMeter = Scalar(i64, .init(.{ .L = 1 }),            .init(.{ .L = .n }));
const KiloMeter = Scalar(f64, .init(.{ .L = 1 }),            .init(.{ .L = .k }));
const Second    = Scalar(f64, .init(.{ .T = 1 }),            .init(.{}));
const Velocity  = Scalar(f64, .init(.{ .L = 1, .T = -1 }),  .init(.{}));
const Kmh       = Scalar(f64, .init(.{ .L = 1, .T = -1 }),  .init(.{ .L = .k, .T = .hour }));
```

Or use the pre-built helpers from `dma.Base`:

```zig
const Acceleration = dma.Base.Acceleration.Of(f64);
const KmhSpeed     = dma.Base.Speed.Scaled(f64, Scales.init(.{ .L = .k, .T = .hour }));
```

### Kinematics example

```zig
const v0    = Velocity{ .value = 10.0 };  // 10 m/s
const accel = Acceleration{ .value = 9.81 }; // 9.81 m/s²
const time  = Second{ .value = 5.0 };     // 5 s

// d = v₀t + ½at²
const d1 = v0.mulBy(time);                     // → Meter
const d2 = accel.mulBy(time.mulBy(time)).scale(0.5); // → Meter
const dist = d1.add(d2);

const v_final = v0.add(accel.mulBy(time));

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

### Working with Vectors

Every `Scalar` type exposes a `.Vec3` and a generic `.Vec(n)`:

```zig
const Vec3Meter = Meter.Vec3; // or: Vector(3, Meter)

const pos = Vec3Meter{ .data = .{ 100, 200, 300 } };
const t   = Second{ .value = 10 };

const vel = pos.divByScalar(t); // → Vec3 of Velocity (m/s)

std.debug.print("{d}\n", .{vel}); // (10, 20, 30)m.s⁻¹
```

Vectors support: `add`, `sub`, `mulBy`, `divBy`, `mulByScalar`, `divByScalar`, `negate`, `to`, `length`, `lengthSqr`.

---

## API Reference

### `Scalar(T, dims, scales)`

| Method | Description |
|---|---|
| `.add(rhs)` | Add two quantities of the same dimension. Auto-converts scales. |
| `.sub(rhs)` | Subtract. Auto-converts scales. |
| `.mulBy(rhs)` | Multiply — dimensions are **summed**. `m * s⁻¹` → `m·s⁻¹`. |
| `.divBy(rhs)` | Divide — dimensions are **subtracted**. `m / s` → `m·s⁻¹`. |
| `.to(DestType)` | Convert to another unit of the same dimension. Compile error on mismatch. |
| `.vec3()` | Wrap the value in a `Vec3` of the same type. |
| `.Vec(n)` | Get the `Vector(n, Self)` type. |

### `dma.Base` — Pre-built quantities

A selection of what's available (call `.Of(T)` for base units, `.Scaled(T, scales)` for custom scales):

`Meter`, `Second`, `Gramm`, `Kelvin`, `ElectricCurrent`, `Speed`, `Acceleration`, `Inertia`, `Force`, `Pressure`, `Energy`, `Power`, `Area`, `Volume`, `Density`, `Frequency`, `Viscosity`, `ElectricCharge`, `ElectricPotential`, `ElectricResistance`, `MagneticFlux`, `ThermalCapacity`, `ThermalConductivity`, and more.

### `Scales` — SI prefixes

| Tag | Factor |
|---|---|
| `.P` | 10¹⁵ |
| `.T` | 10¹² |
| `.G` | 10⁹ |
| `.M` | 10⁶ |
| `.k` | 10³ |
| `.none` | 1 |
| `.c` | 10⁻² |
| `.m` | 10⁻³ |
| `.u` | 10⁻⁶ |
| `.n` | 10⁻⁹ |
| `.p` | 10⁻¹² |
| `.f` | 10⁻¹⁵ |
| `.min` | 60 |
| `.hour` | 3600 |
| `.year` | 31 536 000 |

---

## Running Tests and Benchmarks

```sh
zig build test
zig build benchmark
```

Benchmark results are very welcome — feel free to share yours!

---

## Roadmap / Known Limitations

- More operations beyond `add`, `sub`, `mulBy`, `divBy` (e.g. `pow`, `sqrt`).
- SIMD acceleration for `Vector` operations.
- Some paths may still fall back to runtime computation — optimization ongoing.
- More test coverage.

---

## License

See the repository for license details.
