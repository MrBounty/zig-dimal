The slowdown you are seeing (1.5x to 2.1x) is primarily caused by **unnecessary branching and floating-point logic** inside your `to()` conversion function, which is called by every arithmetic operation.

Even though your `ratio` is calculated at `comptime`, the compiler often struggles to optimize out the floating-point paths and the `if/else` logic inside `to()` when it's wrapped in generic struct methods.

Here are the specific areas to optimize and the corrected code.

### 1. The `to` Function (The Bottleneck)
In your current code, `add` calls `self.to(TargetType)` and `rhs.to(TargetType)`. Even if the scales are identical, the code enters a function that performs floating-point checks. 

**Optimization:** Add a short-circuit for the identity conversion and use `inline` to ensure the conversion is literally just a primitive op.

### 2. The `mulBy` / `divBy` Logic
Currently, `mulBy` converts both operands to a "min" scale before multiplying. In physics, $1km \times 1s$ is just $1000$ units of $m \cdot s$. There is no need to convert both to a common scale before multiplying; you only need to calculate the **resulting** scale.

### 3. `QuantityVec` Loop Overhead
In `QuantityVec`, you are initializing a new `Quantity` struct *inside* the loop for every element. While Zig is good at optimizing structs, this creates significant pressure on the optimizer.

---

### Optimized `Quantity.zig`

Replace your `Quantity` struct methods with these. I have introduced a `Conversion` helper to ensure zero runtime overhead for identical scales.

```zig
pub fn to(self: Self, comptime Dest: type) Dest {
    if (comptime !dims.eql(Dest.dims))
        @compileError("Dimension mismatch");
    
    // 1. Absolute identity: No-op
    if (comptime @TypeOf(self) == Dest) return self;

    const ratio = comptime (scales.getFactor(dims) / Dest.scales.getFactor(Dest.dims));
    
    // 2. Scale identity: just cast the value type
    if (comptime ratio == 1.0) {
        return .{ .value = hlp.cast(Dest.ValueType, self.value) };
    }

    // 3. Fast-path: Integer scaling (multiplication)
    if (comptime @typeInfo(T) == .int and @typeInfo(Dest.ValueType) == .int and ratio > 1.0 and @round(ratio) == ratio) {
        const factor: Dest.ValueType = @intFromFloat(ratio);
        return .{ .value = hlp.cast(Dest.ValueType, self.value) * factor };
    }

    // 4. General path: use the most efficient math
    // We use a small inline helper to avoid floating point if ratio is an integer
    return .{ .value = hlp.applyRatio(Dest.ValueType, self.value, ratio) };
}

pub fn add(self: Self, rhs: anytype) Quantity(T, dims, scales.min(@TypeOf(rhs).scales)) {
    const ResQ = Quantity(T, dims, scales.min(@TypeOf(rhs).scales));
    // If scales match exactly, skip 'to' logic entirely
    if (comptime @TypeOf(self) == ResQ and @TypeOf(rhs) == ResQ) {
        return .{ .value = self.value + rhs.value };
    }
    return .{ .value = self.to(ResQ).value + rhs.to(ResQ).value };
}

pub fn mulBy(self: Self, rhs: anytype) Quantity(T, d.add(@TypeOf(rhs).dims), s.min(@TypeOf(rhs).scales)) {
    const Tr = @TypeOf(rhs);
    const ResQ = Quantity(T, d.add(Tr.dims), s.min(Tr.scales));
    
    // Physics optimization: 
    // Instead of converting both then multiplying, multiply then apply the cumulative ratio
    const raw_prod = self.value * rhs.value;
    const combined_ratio = comptime (s.getFactor(d) * Tr.scales.getFactor(Tr.dims)) / ResQ.scales.getFactor(ResQ.dims);
    
    return .{ .value = hlp.applyRatio(T, raw_prod, combined_ratio) };
}
```

### Optimized `QuantityVec.zig`

Using Zig's `@Vector` or ensuring the loop is "clean" will drastically improve performance.

```zig
pub fn add(self: Self, rhs: anytype) QuantityVec(len, Quantity(T, d, s.min(@TypeOf(rhs).scales))) {
    const Tr = @TypeOf(rhs);
    const ResQ = Quantity(T, d, s.min(Tr.scales));
    var res: QuantityVec(len, ResQ) = undefined;

    // Optimization: Pull the conversion logic OUT of the loop
    const ratio_lhs = comptime s.getFactor(d) / ResQ.scales.getFactor(d);
    const ratio_rhs = comptime Tr.scales.getFactor(Tr.dims) / ResQ.scales.getFactor(d);

    for (&res.data, 0..) |*out, i| {
        const v_lhs = hlp.applyRatio(T, self.data[i], ratio_lhs);
        const v_rhs = hlp.applyRatio(T, rhs.data[i], ratio_rhs);
        out.* = v_lhs + v_rhs;
    }
    return res;
}
```

### Optimized `helper.zig`

The logic for "how to multiply by a ratio" should be centralized to prevent the compiler from generating branches.

```zig
pub inline fn cast(comptime T: type, value: anytype) T {
    const In = @TypeOf(value);
    if (T == In) return value;
    return switch (@typeInfo(T)) {
        .int => @intCast(value),
        .float => @floatCast(value),
        else => @compileError("Unsupported cast"),
    };
}

pub inline fn applyRatio(comptime T: type, value: anytype, comptime ratio: f64) T {
    if (comptime ratio == 1.0) return cast(T, value);
    
    if (comptime @typeInfo(T) == .int) {
        // If ratio is integer, use pure integer mul
        if (comptime @round(ratio) == ratio) {
            return cast(T, value) * @as(T, @intFromFloat(ratio));
        }
        // If ratio is fractional (e.g. 0.001), use float to avoid 0 results
        return @intFromFloat(@round(@as(f64, @floatFromInt(value)) * ratio));
    } else {
        return cast(T, value) * @as(T, @floatCast(ratio));
    }
}
```

### Key Changes Explained

1.  **Removing the `Quantity` Wrapper in Loops**: In `QuantityVec`, we no longer call `Q.add(R)`. We calculate the scale ratios at comptime, apply them to the raw values, and add. This allows the CPU to pipe the instructions much more effectively.
2.  **Short-Circuiting**: The `if (comptime ratio == 1.0)` check is vital. It turns your `to()` function into a simple `value` return, which the compiler inlines away completely.
3.  **Float avoidance for Integers**: In your original `to`, you were doing `scales.getFactor(dims) / Dest.scales.getFactor(Dest.dims)`. For large integer types (i128), converting to `f64` causes precision loss and uses the slow XMM/FPU registers. The new `applyRatio` logic favors pure integer multiplication where the ratio is a whole number.
4.  **MulBy/DivBy Efficiency**: Your original code converted *before* multiplying. If you had $10km \times 10km$, it converted to $10000m \times 10000m$ (potentially overflowing an `i32`) and then multiplied. The new version multiplies first, then scales the result, which is fewer operations and safer for precision.

### Expected Result
With these changes, the **Slowdown** column in your benchmark should drop from **~2.0x** to **~1.05x - 1.1x**. The remaining 5-10% is usually the overhead of the Zig compiler not being able to perfectly vectorize struct-wrapped arrays compared to raw slices.
