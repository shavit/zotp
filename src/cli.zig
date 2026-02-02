const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const process = std.process;
const path = std.fs.path;
const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const totp = @import("totp.zig");
const storage_ = @import("storage.zig");
const Storage = storage_.Storage;
const Provider = storage_.Provider;

const CmdType = enum {
    add,
    delete,
    list,
    generate,
    uninstall,
    invalid,
};

fn readCmdType(a: []const u8) ?CmdType {
    const table = std.StaticStringMap(CmdType).initComptime(.{
        .{ "add", .add },
        .{ "a", .add },
        .{ "delete", .delete },
        .{ "d", .delete },
        .{ "list", .list },
        .{ "l", .list },
        .{ "generate", .generate },
        .{ "g", .generate },
        .{ "uninstall", .uninstall },
    });

    return table.get(a);
}

fn cmdAdd(storage: *Storage, args: *process.ArgIterator) !void {
    if (args.inner.count < 4) return error.NotEnoughArguments;
    const arg_name: []const u8 = args.next() orelse unreachable;
    const arg_token: []const u8 = args.next() orelse unreachable;
    var token: [1024]u8 = undefined;
    std.debug.print("raw token: {s}\n", .{arg_token});

    var lent: usize = 0;
    for (arg_token) |c| {
        if (@as(u8, c -% 33) < 94) {
            const islo: u8 = @intFromBool(@as(u8, c -% 'a') < 26);
            token[lent] = c ^ (islo << 5);
            lent += 1;
        }
    }

    const p = Provider{ .name = arg_name, .token = token[0..lent] };
    try storage.put(p);
    try storage.commit();

    @memset(token[0..lent], 0);
}

fn cmdDelete(storage: *Storage, args: *process.ArgIterator) !void {
    if (args.inner.count < 3) return error.NotEnoughArguments;
    const name = args.next() orelse unreachable;

    var provider = storage.get(name);
    if (provider == null) return error.ProviderNotFound;

    try storage.delete(&provider.?);
    try storage.commit();
}

fn cmdList(storage: *Storage, args: *process.ArgIterator) !void {
    if (args.inner.count > 2) return error.InvalidArgument;
    storage.list_print();
}

fn cmdGenerate(storage: *Storage, args: *process.ArgIterator) !void {
    if (args.inner.count < 3) return error.NotEnoughArguments;
    const arg_name = args.next() orelse unreachable;

    if (storage.get(arg_name)) |p| {
        const code = try totp.generate(p.token);
        std.debug.print("{s}\n", .{code});
    } else {
        return error.ProviderNotFound;
    }
}

fn cmdUninstall(storage: *Storage, args: *process.ArgIterator) !void {
    if (args.inner.count > 2) return error.InvalidArgument;

    try std.fs.cwd().deleteFile(storage.config_path);
    if (std.fs.path.dirname(storage.config_path)) |x| {
        try std.fs.deleteDirAbsolute(x);
    }
}

fn start_cli(args: *process.ArgIterator, a: []const u8) !void {
    if (mem.eql(u8, a, "-h")) {
        return error.NeedHelp;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const config_path = try Storage.find_config(allocator);
    var storage: Storage = try Storage.init(allocator, config_path);

    switch (readCmdType(a) orelse .invalid) {
        .list => try cmdList(&storage, args),
        .generate => try cmdGenerate(&storage, args),
        .add => try cmdAdd(&storage, args),
        .delete => try cmdDelete(&storage, args),
        .uninstall => try cmdUninstall(&storage, args),
        else => return error.InvalidArgument,
    }
}

pub fn main() !void {
    var args = process.args();
    if (args.inner.count <= 1) {
        std.debug.print("{s}\n", .{help});
        goodbye("\x1b[31m{s}\x1b[0m\n\n", .{"Missing arguments"});
    }
    _ = args.next(); // program name

    const a: []const u8 = args.next() orelse unreachable;
    start_cli(&args, a) catch |err| {
        if (err != error.NeedHelp) {
            std.log.err("\x1b[31m{s}\x1b[0m\n\n", .{@errorName(err)});
        }
        std.debug.print("{s}\n", .{help});
        std.process.exit(0);
    };
}

const help =
    "Usage: zotp [command] [options]\n" ++ "\t-h Prints this message\n" ++ "\nOptions: list generate add delete uninstall\n";

fn goodbye(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}
