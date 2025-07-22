// This is based on Bjoern Hoehrmann's famous UTF-8 decoder

const std = @import("std");

pub const Utf8Iterator = struct {
    input: []const u8,
    index: usize,
    state: u8,
    codepoint: u32,

    pub fn init(input: []const u8) Utf8Iterator {
        return Utf8Iterator{
            .input = input,
            .index = 0,
            .state = UTF8_ACCEPT,
            .codepoint = 0,
        };
    }

    pub fn next(self: *Utf8Iterator) ?u32 {
        while (self.index < self.input.len) {
            const byte = self.input[self.index];
            self.index += 1;

            const new_state = decode(&self.state, &self.codepoint, byte);

            if (new_state == UTF8_REJECT) {
                self.state = UTF8_ACCEPT;
                return REPLACEMENT;
            }

            if (new_state == UTF8_ACCEPT) return self.codepoint;

            // Continue if in the middle of a multi-byte sequence
        }

        // If we ended in an incomplete sequence, emit replacement
        if (self.state != UTF8_ACCEPT) {
            self.state = UTF8_ACCEPT;
            return REPLACEMENT;
        }

        return null; // Exhausted
    }
};

pub fn bytesToCodepoints(input: []const u8, buffer: *std.ArrayList(u32)) !void {
    buffer.clearRetainingCapacity();
    try buffer.ensureTotalCapacity(input.len);

    var state: u8 = UTF8_ACCEPT;
    var codepoint: u32 = 0;

    for (input) |b| {
        const new_state = decode(&state, &codepoint, b);

        if (new_state == UTF8_REJECT) {
            buffer.appendAssumeCapacity(REPLACEMENT);
            state = UTF8_ACCEPT;
        } else if (new_state == UTF8_ACCEPT) {
            buffer.appendAssumeCapacity(codepoint);
        }
    }

    // If we ended in an incomplete sequence, emit replacement
    if (state != UTF8_ACCEPT) buffer.appendAssumeCapacity(REPLACEMENT);
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
    const alloc = std.testing.allocator;

    var result = std.ArrayList(u32).init(alloc);
    defer result.deinit();

    try bytesToCodepoints(input, &result);

    try std.testing.expectEqualSlices(u32, expected, result.items);
}

test "overlong sequence" {
    const input = "\xC0\xAF";
    const expected = &[_]u32{ REPLACEMENT, REPLACEMENT };
    const alloc = std.testing.allocator;

    var result = std.ArrayList(u32).init(alloc);
    defer result.deinit();

    try bytesToCodepoints(input, &result);

    try std.testing.expectEqualSlices(u32, expected, result.items);
}

test "truncated 3-byte sequence" {
    const input = "\xE2\x82";
    const expected = &[_]u32{REPLACEMENT};
    const alloc = std.testing.allocator;

    var result = std.ArrayList(u32).init(alloc);
    defer result.deinit();

    try bytesToCodepoints(input, &result);

    try std.testing.expectEqualSlices(u32, expected, result.items);
}

test "bad continuation" {
    const input = "\xE2\x28\xA1";
    const expected = &[_]u32{ REPLACEMENT, REPLACEMENT };
    const alloc = std.testing.allocator;

    var result = std.ArrayList(u32).init(alloc);
    defer result.deinit();

    try bytesToCodepoints(input, &result);

    try std.testing.expectEqualSlices(u32, expected, result.items);
}

test "U+10FFFF round-trip" {
    const input = "\xF4\x8F\xBF\xBF";
    const expected = &[_]u32{0x10FFFF};
    const alloc = std.testing.allocator;

    var result = std.ArrayList(u32).init(alloc);
    defer result.deinit();

    try bytesToCodepoints(input, &result);

    try std.testing.expectEqualSlices(u32, expected, result.items);
}
