const std = @import("std");

pub const Scalar = @import("Scalar.zig").Scalar;
pub const Vector = @import("Vector.zig").Vector;
pub const Dimensions = @import("Dimensions.zig");
pub const Scales = @import("Scales.zig");
pub const Base = @import("Base.zig");

test {
    _ = @import("Scalar.zig");
    // _ = @import("Vector.zig");
    // _ = @import("Dimensions.zig");
    // _ = @import("Scales.zig");
    // _ = @import("Base.zig");
    // _ = @import("helper.zig");
}
