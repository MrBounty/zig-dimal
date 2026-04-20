# zig_units

**Compile-time dimensional analysis for Zig.**

`zig_units` lets you attach physical units to numeric values so that
dimension mismatches become *compile errors* rather than silent bugs.
At runtime a `Quantity` is nothing but a single number — zero overhead.

```
velocity = distance / time   →  L¹T⁻¹  ✓
force    = mass + velocity   →  compile error: M¹ ≠ L¹T⁻¹
```

Requires **Zig 0.16** or later.

---

## Features

- Seven SI base dimensions (`L M T I Tp N J`)
- Full SI prefix support (`P T G M k h da d c m u n p f`)
- Custom time aliases (`.min`, `.hour`, `.year`)
- Automatic scale conversion on add/sub (finer unit wins)
- `Quantity(T, dims, scales)` — scalar, any numeric backing type
- `QuantityVec3` — three-component vector with the same guarantees
- Unicode superscript formatting (`9.81m.s⁻²`)
- Integer-safe square root for `Vec3.length()`
- All dimension tracking happens at `comptime` — no runtime cost

---

## Installation

### Add as a Zig dependency

```bash
zig fetch --save https://github.com/YOUR_USERNAME/zig_units/archive/refs/heads/main.tar.gz
```

This adds an entry to your `build.zig.zon`.  Then wire it up in your
`build.zig`:

```zig
const zig_units = b.dependency("zig_units", .{
    .target  = target,
    .optimize = optimize,
});
my_module.addImport("zig_units", zig_units.module("zig_units"));
```

### Local path (monorepo / development)

```zig
// build.zig.zon
.dependencies = .{
    .zig_units = .{ .path = "../zig_units" },
},
```

---

## Quick start

```zig
const units     = @import("zig_units");
const Quantity  = units.Quantity;
const Dims      = units.Dimensions;
const Scales    = units.Scales;

// Define named unit types
const Meter    = Quantity(f32, Dims.init(.{ .L = 1 }),           Scales.init(.{}));
const KiloMeter= Quantity(f32, Dims.init(.{ .L = 1 }),           Scales.init(.{ .L = .k }));
const Second   = Quantity(f32, Dims.init(.{ .T = 1 }),           Scales.init(.{}));
const MPerSec  = Quantity(f32, Dims.init(.{ .L = 1, .T = -1 }), Scales.init(.{}));

const dist = Meter{ .value = 100.0 };
const t    = Second{ .value = 5.0 };

// Dimension is tracked automatically — vel has type L¹T⁻¹
const vel = dist.divBy(t);

// Convert to an explicit type (same dims required, compile error otherwise)
const vel2 = vel.to(MPerSec);

// Cross-scale addition: km + m → result in metres (finer scale)
const km  = KiloMeter{ .value = 1.0 };
const sum = km.add(dist);   // 1100 m
```

---

## API reference

### `Quantity(T, dims, scales)`

| Member | Kind | Description |
|---|---|---|
| `value` | field | The raw numeric value |
| `ValueType` | comptime | Alias for `T` |
| `dims` | comptime | The `Dimensions` of this type |
| `scales` | comptime | The `Scales` of this type |
| `Vec3` | comptime | The matching `QuantityVec3` type |
| `add(rhs)` | fn | Same-dimension addition, finer scale |
| `sub(rhs)` | fn | Same-dimension subtraction, finer scale |
| `mulBy(rhs)` | fn | Multiplication, dims are added |
| `divBy(rhs)` | fn | Division, dims are subtracted |
| `scale(s: T)` | fn | Dimensionless scalar multiply |
| `to(Dest)` | fn | Convert to another `Quantity` type (same dims) |
| `vec3()` | fn | Broadcast scalar to a `Vec3` |
| `format(writer)` | fn | Print `value + unit string` |

### `QuantityVec3`

Obtained via `SomeQuantity.Vec3`.

| Member | Kind | Description |
|---|---|---|
| `x, y, z` | fields | The three components |
| `zero` | comptime | `(0, 0, 0)` |
| `one` | comptime | `(1, 1, 1)` |
| `initDefault(v)` | fn | Broadcast scalar to all components |
| `add(rhs)` | fn | Component-wise addition |
| `sub(rhs)` | fn | Component-wise subtraction |
| `mulBy(rhs)` | fn | Component-wise element-wise multiply |
| `divBy(rhs)` | fn | Component-wise element-wise divide |
| `mulByScalar(q)` | fn | Multiply by a scalar `Quantity` |
| `divByScalar(q)` | fn | Divide by a scalar `Quantity` |
| `scale(s: T)` | fn | Dimensionless scalar multiply |
| `negate()` | fn | Negate all components |
| `to(DestQ)` | fn | Convert to another vector quantity type |
| `lengthSqr()` | fn | Squared Euclidean length (no sqrt) |
| `length()` | fn | Euclidean length (integer-safe) |
| `format(writer)` | fn | Print `(x, y, z) + unit string` |

### `Dimensions`

A comptime struct storing a signed exponent per SI base dimension.

```zig
const Dims = @import("zig_units").Dimensions;

// Acceleration: L¹ T⁻²
const accel_dims = Dims.init(.{ .L = 1, .T = -2 });
```

| Function | Description |
|---|---|
| `init(struct_literal)` | Create from named exponents; unset dims default to 0 |
| `initFill(val: i8)` | Set all exponents to `val` |
| `get(dim)` | Read a single exponent |
| `set(dim, val)` | Write a single exponent |
| `add(a, b)` | Component-wise sum (for `mulBy`) |
| `sub(a, b)` | Component-wise difference (for `divBy`) |
| `eql(a, b)` | Equality check |
| `str()` | Comptime human-readable string, e.g. `"L1T-2"` |

### `Scales`

A comptime struct storing a `UnitScale` per SI base dimension.

```zig
const Scales = @import("zig_units").Scales;

// Kilometres per nanosecond
const spd_scales = Scales.init(.{ .L = .k, .T = .n });
```

| `UnitScale` variant | Factor |
|---|---|
| `.P` | ×10¹⁵ |
| `.T` | ×10¹² |
| `.G` | ×10⁹ |
| `.M` | ×10⁶ |
| `.k` | ×10³ |
| `.h` | ×10² |
| `.da` | ×10¹ |
| `.none` | ×1 |
| `.d` | ×10⁻¹ |
| `.c` | ×10⁻² |
| `.m` | ×10⁻³ |
| `.u` | ×10⁻⁶ |
| `.n` | ×10⁻⁹ |
| `.p` | ×10⁻¹² |
| `.f` | ×10⁻¹⁵ |
| `.min` | ×60 (seconds) |
| `.hour` | ×3 600 |
| `.year` | ×31 536 000 |

---

## Examples

### Kinematics

```zig
const Meter  = Quantity(f64, Dims.init(.{ .L = 1 }),           Scales.init(.{}));
const Second = Quantity(f64, Dims.init(.{ .T = 1 }),           Scales.init(.{}));

const pos  = Meter{ .value = 200.0 };
const time = Second{ .value = 8.0 };

const vel  = pos.divBy(time);        // L¹T⁻¹  — 25 m/s
const accel = vel.divBy(time);       // L¹T⁻²  — 3.125 m/s²
```

### Cross-scale addition

```zig
const KM = Quantity(i64, Dims.init(.{ .L = 1 }), Scales.init(.{ .L = .k }));
const M  = Quantity(i64, Dims.init(.{ .L = 1 }), Scales.init(.{}));

const a = KM{ .value = 2 };   // 2 km
const b = M{ .value = 500 };  // 500 m

const sum = a.add(b);          // result scale = metres (finer) → 2500 m
```

### Time conversion

```zig
const Hour   = Quantity(i64, Dims.init(.{ .T = 1 }), Scales.init(.{ .T = .hour }));
const Minute = Quantity(i64, Dims.init(.{ .T = 1 }), Scales.init(.{ .T = .min  }));
const Second = Quantity(i64, Dims.init(.{ .T = 1 }), Scales.init(.{}));

const h   = Hour{ .value = 2 };
const min = h.to(Minute);     // 120
const sec = min.to(Second);   // 7200
```

### Vec3 velocity

```zig
const Meter  = Quantity(f32, Dims.init(.{ .L = 1 }), Scales.init(.{}));
const Second = Quantity(f32, Dims.init(.{ .T = 1 }), Scales.init(.{}));

const pos  = Meter.Vec3{ .x = 30.0, .y = 60.0, .z = 90.0 };
const time = Second{ .value = 3.0 };

const vel  = pos.divByScalar(time);   // Vec3 with dims L¹T⁻¹
const dist = vel.length();            // Euclidean length
```

### Dimension mismatch — compile error

```zig
const Meter  = Quantity(f32, Dims.init(.{ .L = 1 }), Scales.init(.{}));
const Second = Quantity(f32, Dims.init(.{ .T = 1 }), Scales.init(.{}));

const d = Meter{ .value = 5.0 };
const t = Second{ .value = 2.0 };

// This will NOT compile:
const bad = d.add(t);  // error: Dimension mismatch in add: L1 vs T1
```

---

## Running the tests

```bash
zig build test
```

The test suite covers scalar and vector arithmetic, cross-scale operations,
conversion chains, negative values, formatting, and an optional benchmark
(`"Comprehensive Benchmark: All Ops × All Types"`).

---

## Project layout

```
zig_units/
├── build.zig          # Build script; exposes the "zig_units" module
├── build.zig.zon      # Package manifest
├── src/
│   ├── main.zig       # Quantity, QuantityVec3, tests
│   ├── Dimensions.zig # SI base dimensions + comptime arithmetic
│   ├── Scales.zig     # SI prefixes + scale helpers
│   └── helper.zig     # Internal utilities (isInt, printSuperscript)
└── README.md
```

---

## Design notes

**Why comptime parameters?**  Zig's `comptime` means the compiler can
evaluate all dimension arithmetic before any machine code is generated.
Two quantities with mismatched dimensions simply fail to compile —
there is no runtime overhead and no need for exception handling.

**Scale selection on arithmetic.**  When two operands have different
scales (e.g. km and m), `zig_units` automatically picks the finer
(smaller-factor) scale for the result.  This prevents silent precision
loss at the cost of an automatic rescaling of both operands.

**Integer backing types.**  Division uses an `f64` intermediate and
rounds back to the integer type.  For best accuracy, prefer `f32`/`f64`
for quantities that will be divided frequently.

---

## License

MIT — see `LICENSE` for details.
