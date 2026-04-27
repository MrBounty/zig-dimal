# dimal — Dimensional Analysis for Zig

A dimensional analysis library for Zig with a unified `Tensor` API for scalars, vectors, matrices, and higher-dimensional data. All dimension and unit tracking happens at compile time—zero runtime overhead—and all operations use SIMD intrinsics.

If you try to add meters to seconds, it won't compile. That's the point.

> **Source:** [git.bouvais.lu/adrien/zig-dimal](https://git.bouvais.lu/adrien/zig-dimal)  
> **Minimum Zig version:** `0.16.0`

---

## Background

Started because I needed `i128` positions for a space simulation to avoid floating-point precision loss far from the origin. Grew into a type system for tracking physical dimensions at compile time. It's been useful enough to share.

- **Compile-time dimension checking** — catch unit mismatches before runtime.
- **Unified `Tensor` API** — same interface for scalars, vectors, matrices, and higher-rank tensors.
- **SIMD operations** — vector and matrix code automatically uses SIMD instructions.
- **Zero runtime cost** — all dimension and scale tracking is erased at compile time.
- **Supports `i128`** — useful for high-precision fixed-point integer math.

---

## Features

- **Compile-time dimension checking** — all physical-unit tracking happens at compile time.
- **Automatic unit conversion** — use `.to()` to convert between compatible units (e.g. `km/h` → `m/s`). Scale factors are resolved at comptime.
- **Unified `Tensor` API** — one type for scalars `{1}`, vectors `{N}`, matrices `{M, N}`, and higher-rank tensors.
- **SIMD operations** — vector and matrix code compiles to SIMD instructions automatically.
- **Tensor contraction** — `.contract(other, axis_a, axis_b)` for dot products, matrix multiplication, and general tensor contractions.
- **Full SI prefix support** — `pico` through `peta`, plus Imperial units and time scales.
- **Physical constants** — Planck, Boltzmann, speed of light, gravitational constant, etc.
- **Pre-built quantities** — `Velocity`, `Acceleration`, `Force`, `Energy`, `Pressure`, `Charge`, and more.
- **Basic vector operations** — cross product, length/magnitude, element-wise arithmetic.
- **Formatting** — values print with units: `9.81m.s⁻²`, `0.172km`.

### Current Limitations

- GPU support not implemented.
- Performance on small tensors is limited by Zig's vector width.

---

## The 7 SI Base Dimensions

| Symbol | Dimension            | SI Unit |
|--------|----------------------|---------|
| `L`    | Length               | `m`     |
| `M`    | Mass                 | `g`     |
| `T`    | Time                 | `s`     |
| `I`    | Electric Current     | `A`     |
| `Tr`   | Temperature          | `K`     |
| `N`    | Amount of Substance  | `mol`   |
| `J`    | Luminous Intensity   | `cd`    |

---

## Installation

### 1. Add the dependency (Zig 0.14+)

```sh
zig fetch --save git+https://git.bouvais.lu/adrien/zig-dimal#0.2.0
```

### 2. Wire it up in `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    const dimal = b.dependency("dimal", .{
        .target = target,
        .optimize = optimize,
    }).module("dimal");

    const exe = b.addExecutable(.{
        .name = "my_app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("dimal", dimal);
    b.installArtifact(exe);
}
```

### 3. Import and use

```zig
const dma = @import("dimal");
const Tensor = dma.Tensor;
const Base = dma.Base;
```

---

## Quick Example: Lunar Descent

Simulate a spacecraft descending to the Moon with correct physics and type safety:

```zig
const std = @import("std");
const dma = @import("dimal");
const Tensor = dma.Tensor;

pub fn main() void {
    // Define types: m/s² acceleration, m/s velocity, m distance
    const Acceleration = dma.Base.Acceleration.Of(f64);
    const Velocity = dma.Base.Velocity.Of(f64);
    const Distance = dma.Base.Meter.Of(f64);
    const Time = dma.Base.Second.Of(f64);

    // Initial conditions
    const g_moon: Acceleration = .{ .data = @splat(1.62) };
    const v_initial: Velocity = .{ .data = @splat(100.0) };
    const h_initial: Distance = .{ .data = @splat(10000.0) };
    const dt: Time = .{ .data = @splat(1.0) };

    var h = h_initial;
    var v = v_initial;
    var t: f64 = 0;

    // Simulate descent
    while (h.data[0] > 0 and t < 1000) : (t += 1.0) {
        // a = -g (gravity pulls down)
        const a = g_moon.mul(-1.0);

        // Update: v = v₀ + at
        v = v.add(a.mul(dt));

        // Update: h = h₀ + vt
        h = h.add(v.mul(dt));

        if (@mod(t, 100.0) == 0) {
            std.debug.print("t={d:.0}s | h={d:.1} | v={d:.1}\n", .{
                t,
                h,
                v,
            });
        }
    }

    std.debug.print("Landed in {d:.1}s at h={d:.1}\n", .{ t, h });
}
```

**Output:**
```
t=0s | h=10000m | v=100m.s⁻¹
t=100s | h=8019m | v=-61.8m.s⁻¹
t=200s | h=4174.4m | v=-223.6m.s⁻¹
...
Landed in 323.5s at h=-0.01m
```

---

## API Overview

### Tensors

A **`Tensor`** is parameterized by:
- **`T`** — numeric type: `f32`, `f64`, `i128`, etc.
- **`dims`** — physical dimensions (struct literal): `.{.L = 1, .T = -1}` means length/time (velocity).
- **`scales`** — SI prefixes or custom scales: `.{.L = .k, .T = .hour}` means km/h.
- **`shape`** — array shape: `&.{1}` is a scalar, `&.{3}` is a 3-vector, `&.{3, 3}` is a 3×3 matrix.

```zig
// Scalar: 1-element tensor
const Meter = Tensor(f64, .{.L = 1}, .{}, &.{1});
const m = Meter{ .data = @splat(5.0) };

// Vector: N-element tensor (SIMD)
const Vec3Meter = Tensor(f64, .{.L = 1}, .{}, &.{3});
const v = Vec3Meter{ .data = @shuffle(f64, [_]f64{1, 2, 3}, [_]f64 undefined, [_]i32{0, 1, 2, 0, 0, 0}) };

// Matrix: M×N tensor (SIMD-accelerated)
const Mat3x3Velocity = Tensor(f32, .{.L = 1, .T = -1}, .{}, &.{3, 3});
const m_vel = Mat3x3Velocity{ .data = @splat(10.0) };

// Higher-rank tensor
const Rank4 = Tensor(f64, .{.M = 1}, .{}, &.{2, 3, 4, 5});
```

### Common Operations

| Operation | Description |
|-----------|-------------|
| `.add(rhs)` | Element-wise addition. Auto-converts scales. |
| `.sub(rhs)` | Element-wise subtraction. |
| `.mul(rhs)` | Multiply; dimensions are summed. `rhs` can be a tensor or bare number. |
| `.div(rhs)` | Divide; dimensions are subtracted. |
| `.contract(other, axis_a, axis_b)` | Tensor contraction: dot product, matrix multiply, or general N-D contraction. |
| `.cross(rhs)` | Cross product (3-vectors only). Returns a 3-vector. |
| `.length()` / `.lengthSqr()` | Euclidean length (or squared length) of a vector. Returns a scalar `T`. |
| `.product()` | Multiply all elements. Returns a scalar with combined dimensions. |
| `.abs()` | Element-wise absolute value. Dimensions unchanged. |
| `.pow(exp)` | Raise to comptime exponent. Dimension exponents multiplied by `exp`. |
| `.sqrt()` | Element-wise square root. Compile error if any dimension exponent is odd. |
| `.to(DestType)` | Convert to another unit of the same dimension. Comptime error on mismatch. |
| `.eq(rhs)` / `.ne(rhs)` | Element-wise equality/inequality. |
| `.gt(rhs)` / `.gte(rhs)` | Greater-than comparisons. |
| `.lt(rhs)` / `.lte(rhs)` | Less-than comparisons. |

### Pre-built Types (via `dma.Base`)

Use `.Of(T)` for base units, `.Scaled(T, scales)` for custom scales:

```zig
const Velocity = dma.Base.Velocity.Of(f64);
const Kmh = dma.Base.Velocity.Scaled(f64, .{.L = .k, .T = .hour});
const Force = dma.Base.Force.Of(f32);
const Energy = dma.Base.Energy.Of(f64);
```

Also available: `Acceleration`, `Inertia`, `Pressure`, `Power`, `Area`, `Volume`, `Density`, `Frequency`, `Viscosity`, `Charge`, `Potential`, `Resistance`, `MagneticFlux`, `ThermalCapacity`, `ThermalConductivity`, and many more.

---

## SIMD Performance

Operations on vectors and matrices use Zig's `@Vector` intrinsics, which compile to SIMD instructions on most platforms. This makes vector operations faster than equivalent scalar loops, but don't expect miracles—SIMD is still limited by memory bandwidth and CPU cache.

Run the included benchmarks to see what you get on your hardware:
```sh
zig build benchmark
```

---

## Next Steps

- **GPU support** — eventually, for large tensor operations. WebGPU is a target.
- **Toy physics language** — I've been sketching ideas for a language optimized for numerical physics (tentatively called Éclat). It would use dimal as the foundation. No timeline yet; this is a long-term experiment.

---

## Testing & Benchmarks

```sh
zig build test       # Run all unit tests
zig build benchmark  # Run performance benchmarks
```

---

## License

See the repository for license details.
