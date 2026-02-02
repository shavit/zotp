const std = @import("std");
const testing = std.testing;
const hmac = std.crypto.auth.hmac;
const time = std.time;
const base32 = @import("base32");
const mem = std.mem;
const math = std.math;

const DIGITS_LIMIT: u32 = 1000000;
const STRIDE = 30;

pub fn generate(key: []const u8) ![6]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var b32 = base32.Base32Encoder.init(allocator);
    const decoded = try b32.decode(key);

    const counter: u64 = @as(u64, @intCast(@divFloor(time.timestamp(), STRIDE)));
    var msg: [8]u8 = undefined;
    std.mem.writeInt(u64, &msg, counter, .big);
    var hash: [hmac.HmacSha1.mac_length]u8 = undefined;
    hmac.HmacSha1.create(&hash, &msg, decoded);

    const offset = hash[hash.len - 1] & 0xf;
    const ho0: u32 = @as(u32, (hash[offset]) & 0x7f) << 24;
    const ho1: u32 = @as(u32, (hash[offset + 1]) & 0xff) << 16;
    const ho2: u32 = @as(u32, (hash[offset + 2]) & 0xff) << 8;
    const ho3: u32 = @as(u32, (hash[offset + 3]) & 0xff);
    const ho4: u32 = (ho0 | ho1 | ho2 | ho3);
    const code = padNumber(ho4 % DIGITS_LIMIT);

    return code;
}

test "totp generate" {}

fn padNumber(number: u32) [6]u8 {
    var output: [6]u8 = [_]u8{'0'} ** 6;
    var n: u8 = 1;
    var rem: u32 = number;

    while (rem / 10 > 0) {
        rem /= 10;
        n += 1;
    }

    var divisor: u32 = math.pow(u32, 10, n - 1);
    var digit: u8 = 0;
    var i: u8 = 0;
    rem = number;
    while (divisor > 0) : (i += 1) {
        digit = @intCast(rem / divisor);
        output[output.len - n + i] = digit + '0';
        rem %= divisor;
        divisor /= 10;
    }

    return output;
}

test "totp code padding" {
    const TestCase = struct {
        code: u32,
        padded: [6]u8,
    };

    const testCases = [_]TestCase{
        .{ .code = 0, .padded = .{ '0', '0', '0', '0', '0', '0' } },
        .{ .code = 1, .padded = .{ '0', '0', '0', '0', '0', '1' } },
        .{ .code = 11, .padded = .{ '0', '0', '0', '0', '1', '1' } },
        .{ .code = 900, .padded = .{ '0', '0', '0', '9', '0', '0' } },
        .{ .code = 1212, .padded = .{ '0', '0', '1', '2', '1', '2' } },
        .{ .code = 12345, .padded = .{ '0', '1', '2', '3', '4', '5' } },
        .{ .code = 123456, .padded = .{ '1', '2', '3', '4', '5', '6' } },
    };

    for (testCases) |t| {
        const result = padNumber(t.code);
        try testing.expect(mem.eql(u8, &result, &t.padded));
    }
}
