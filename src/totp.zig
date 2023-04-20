const std = @import("std");
const testing = std.testing;
const hmac = std.crypto.auth.hmac;
const time = std.time;
const base32 = @import("base32");

const DIGITS_POWER = [9]u32{
    1,
    10,
    100,
    1000,
    10000,
    100000,
    1000000,
    10000000,
    100000000,
};

const STRIDE = 30;

pub fn generate(key: []const u8) !u32 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var b32 = base32.Base32Encoder.init(allocator);
    const decoded = try b32.decode(key);

    const counter: u64 = @intCast(u32, time.timestamp()) / STRIDE;
    const digits = std.PackedIntArrayEndian(u64, .Big, 1);
    var digits_data = @as(digits, undefined);
    digits_data.set(0, counter);
    const hash = hmac_sha(&digits_data.bytes, decoded);

    const offset = hash[hash.len - 1] & 0x0f;
    const ho0: u32 = @as(u32, (hash[offset]) & 0x7f) << 24;
    const ho1: u32 = @as(u32, (hash[offset + 1]) & 0xff) << 16;
    const ho2: u32 = @as(u32, (hash[offset + 2]) & 0xff) << 8;
    const ho3: u32 = @as(u32, (hash[offset + 3]) & 0xff);
    const code: u32 = (ho0 | ho1 | ho2 | ho3) % DIGITS_POWER[6];

    return code;
}

fn hmac_sha(msg: []const u8, key: []const u8) []u8 {
    const l = hmac.HmacSha1.mac_length;
    var out: [l]u8 = undefined;
    hmac.HmacSha1.create(out[0..], msg, key);

    return &out;
}

test "totp generate" {}
