const std = @import("std");

pub const Tensor = @import("Tensor.zig").Tensor;
pub const Dimensions = @import("Dimensions.zig");
pub const Scales = @import("Scales.zig");
pub const Base = @import("Base.zig");

test {
    _ = @import("Tensor.zig");
    _ = @import("Dimensions.zig");
    _ = @import("Scales.zig");
    _ = @import("Base.zig");
}
