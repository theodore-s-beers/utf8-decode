// This is based on Bjoern Hoehrmann's famous UTF-8 decoder

const std = @import("std");

pub fn bytesToCodepoints(input: []const u8, allocator: std.mem.Allocator) ![]u32 {
    var codepoints = try std.ArrayList(u32).initCapacity(allocator, input.len);
    defer codepoints.deinit();

    var state: u8 = UTF8_ACCEPT;
    var codepoint: u32 = 0;

    for (input) |b| {
        const new_state = decode(&state, &codepoint, b);

        if (new_state == UTF8_REJECT) {
            try codepoints.append(REPLACEMENT);
            state = UTF8_ACCEPT;
        } else if (new_state == UTF8_ACCEPT) {
            try codepoints.append(codepoint);
        }
    }

    // If we ended in an incomplete sequence, emit replacement
    if (state != UTF8_ACCEPT) {
        try codepoints.append(REPLACEMENT);
    }

    return codepoints.toOwnedSlice();
}

const UTF8_ACCEPT: u8 = 0;
const UTF8_REJECT: u8 = 12;

const REPLACEMENT: u32 = 0xFFFD;

const utf8d = [_]u8{
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,  9,
    7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,  7,
    8,  8,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,  2,
    10, 3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  4,  3,  3,  11, 6,  6,  6,  5,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,  8,

    0,  12, 24, 36, 60, 96, 84, 12, 12, 12, 48, 72, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 0,  12, 12, 12, 12, 12, 0,
    12, 0,  12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 24, 12, 12, 12, 12, 12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 24, 12, 12,
    12, 12, 12, 12, 12, 24, 12, 12, 12, 12, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12, 12, 36, 12, 12, 12, 12, 12, 36, 12, 36, 12, 12,
    12, 36, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
};

inline fn decode(state: *u8, cp: *u32, byte: u8) u8 {
    const class = utf8d[byte];

    cp.* = if (state.* != UTF8_ACCEPT)
        (byte & 0x3F) | (cp.* << 6)
    else
        ((@as(u8, 0xFF) >> @truncate(class)) & byte);

    const idx = @as(usize, 256) + state.* + class;
    state.* = utf8d[idx];

    return state.*;
}

//
// Tests
//

test "valid string" {
    const input = "Hello world";
    const expected = &[_]u32{ 0x0048, 0x0065, 0x006C, 0x006C, 0x006F, 0x0020, 0x0077, 0x006F, 0x0072, 0x006C, 0x0064 };
    const allocator = std.testing.allocator;

    const result = bytesToCodepoints(input, allocator) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u32, expected, result);
}

test "overlong sequence" {
    const input = "\xC0\xAF";
    const expected = &[_]u32{ REPLACEMENT, REPLACEMENT };
    const allocator = std.testing.allocator;

    const result = bytesToCodepoints(input, allocator) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u32, expected, result);
}

test "truncated 3-byte sequence" {
    const input = "\xE2\x82";
    const expected = &[_]u32{REPLACEMENT};
    const allocator = std.testing.allocator;

    const result = bytesToCodepoints(input, allocator) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u32, expected, result);
}

test "bad continuation" {
    const input = "\xE2\x28\xA1";
    const expected = &[_]u32{ REPLACEMENT, REPLACEMENT };
    const allocator = std.testing.allocator;

    const result = bytesToCodepoints(input, allocator) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u32, expected, result);
}

test "U+10FFFF round-trip" {
    const input = "\xF4\x8F\xBF\xBF";
    const expected = &[_]u32{0x10FFFF};
    const allocator = std.testing.allocator;

    const result = bytesToCodepoints(input, allocator) catch unreachable;
    defer allocator.free(result);

    try std.testing.expectEqualSlices(u32, expected, result);
}
