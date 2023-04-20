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
    const table = std.ComptimeStringMap(CmdType, .{
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
    const name = args.next() orelse unreachable;
    const token = args.next() orelse unreachable;

    var p = Provider{ .name = name, .token = token };
    try storage.put(p);
    try storage.commit();
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
    const arg_name = args.next() orelse unreachable;

    if (storage.get(arg_name)) |p| {
        const code: u32 = try totp.generate(p.token);
        var buf: [6]u8 = undefined;
        const output = try std.fmt.bufPrint(&buf, "{d}", .{code});
        try write_stdout(output);
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
        println(help);
        std.process.exit(0);
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
        else => println(help),
    }
}

pub fn main() !void {
    var args = process.args();
    if (args.inner.count <= 1) {
        println(help);
        goodbye("Missing arguments", .{});
    }
    _ = args.next(); // program name

    const a: []const u8 = args.next() orelse unreachable;
    try start_cli(&args, a);
}

const help =
    "Usage: zotp [command] [options]\n" ++ "\t-h Prints this message\n" ++ "\nOptions: list generate add delete uninstall\n";

fn println(text: []const u8) void {
    std.debug.print("{s}\n", .{text});
}

fn write_stdout(msg: []const u8) !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const writer = bw.writer();

    try writer.print("{s}\n", .{msg});
    try bw.flush();
}

fn goodbye(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}
