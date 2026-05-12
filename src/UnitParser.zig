const std = @import("std");
const Dimensions = @import("Dimensions.zig");
const Scales = @import("Scales.zig");

/// A container returning the separated arguments needed to construct a Tensor.
pub const ParsedUnit = struct {
    dims: Dimensions.ArgOpts = .{},
    scales: Scales.ArgOpts = .{},
};

pub const UnitParseError = error{
    UnknownBaseUnit,
    UnknownPrefix,
    InvalidExponent,
    EmptyStr,
};

/// Parses strings like "km/s^2", "m", "kg*m/s^2", "1/min".
/// Evaluates entirely at comptime.
pub fn parseUnit(str: []const u8) !ParsedUnit {
    if (str.len == 0) return UnitParseError.EmptyStr;

    var parsed: ParsedUnit = .{ .dims = .{}, .scales = .{} };

    // We need to track if we are after a '/' to flip exponents to negative
    var is_denominator = false;

    // Manual iteration to handle '/' properly
    var cursor: usize = 0;
    while (cursor < str.len) {
        // Find the next segment
        const segment_start = cursor;
        while (cursor < str.len and str[cursor] != '/' and str[cursor] != '.' and str[cursor] != '*') : (cursor += 1) {}
        const segment = str[segment_start..cursor];

        if (segment.len > 0) {
            try parseSegment(segment, &parsed, is_denominator);
        }

        if (cursor < str.len) {
            if (str[cursor] == '/') {
                is_denominator = true;
            }
            cursor += 1; // skip the separator
        }
    }

    return parsed;
}

fn parseSegment(segment: []const u8, parsed: *ParsedUnit, is_denominator: bool) !void {
    var scale: Scales.UnitScale = .none;
    var found_scale = false;
    var active_dim: ?Dimensions.Dimension = null;

    // 1. Try to find a Scale + Dimension pair (e.g., "mm", "km")
    inline for (std.enums.values(Scales.UnitScale)) |sca| {
        const s_str = sca.str();
        if (s_str.len > 0 and std.mem.startsWith(u8, segment, s_str)) {
            // Check if it's a "Unit-as-Scale" (hour, min) or a prefix (k, m, c)
            switch (sca) {
                .hour, .min, .year => {
                    // These are dimensions themselves (Time)
                    if (segment.len == s_str.len or (segment.len > s_str.len and (segment[s_str.len] == '^' or (segment[s_str.len] >= '0' and segment[s_str.len] <= '9')))) {
                        scale = sca;
                        active_dim = .T;
                        found_scale = true;
                    }
                },
                else => {
                    // Standard prefixes: Must be followed by a valid dimension unit
                    inline for (std.enums.values(Dimensions.Dimension)) |dim| {
                        if (std.mem.startsWith(u8, segment[s_str.len..], dim.unit())) {
                            scale = sca;
                            active_dim = dim;
                            found_scale = true;
                            break;
                        }
                    }
                },
            }
        }
        if (found_scale) break;
    }

    // 2. If no scale prefix was found, try identifying as a pure Dimension (e.g., "m", "s")
    if (!found_scale) {
        inline for (std.enums.values(Dimensions.Dimension)) |dim| {
            if (std.mem.startsWith(u8, segment, dim.unit())) {
                active_dim = dim;
                break;
            }
        }
    }

    const dimen = active_dim orelse return UnitParseError.UnknownBaseUnit;

    // 3. Determine where the exponent starts
    // If it was a Time Scale (like 'h'), the exponent starts after 'h'
    // If it was a Prefix + Dim (like 'km'), it starts after 'km'
    const unit_part_len = if (found_scale)
        (if (scale == .hour or scale == .min or scale == .year) scale.str().len else scale.str().len + dimen.unit().len)
    else
        dimen.unit().len;

    const expo_str = segment[unit_part_len..];

    // 4. Parse Exponent
    var expo: i32 = 1;
    if (expo_str.len > 0) {
        const cleaned_expo = if (expo_str[0] == '^') expo_str[1..] else expo_str;
        expo = std.fmt.parseInt(i32, cleaned_expo, 10) catch return UnitParseError.InvalidExponent;
    }

    if (is_denominator) expo *= -1;

    // 5. Assign to struct
    inline for (std.meta.fields(Dimensions.ArgOpts)) |f| {
        if (std.mem.eql(u8, f.name, @tagName(dimen))) {
            @field(parsed.dims, f.name) += expo;
            @field(parsed.scales, f.name) = scale;
        }
    }
}

inline fn testParser(
    comptime str: []const u8,
    comptime expected_dims: Dimensions.ArgOpts,
    comptime expected_scales: Scales.ArgOpts,
) !void {
    const unit = comptime try parseUnit(str);
    if (comptime !Dimensions.init(expected_dims).eql(Dimensions.init(unit.dims))) return error.WrongDims;
    if (comptime !Scales.init(expected_scales).eql(Scales.init(unit.scales))) return error.WrongScales;
}

test "parseUnit" {
    @setEvalBranchQuota(10000);
    try testParser("m", .{ .L = 1 }, .{});
    try testParser("s", .{ .T = 1 }, .{});
    try testParser("mm", .{ .L = 1 }, .{ .L = .m });
    try testParser("m/s", .{ .L = 1, .T = -1 }, .{});
    try testParser("m1/s2/kg", .{ .L = 1, .T = -2, .M = -1 }, .{ .M = .k });
    try testParser("km/h", .{ .L = 1, .T = -1 }, .{ .L = .k, .T = .hour });
    try testParser("m.s^-1", .{ .L = 1, .T = -1 }, .{});
}
