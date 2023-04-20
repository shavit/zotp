const std = @import("std");
const path = std.fs.path;
const mem = std.mem;
const io = std.io;
const fs = std.fs;
const StringHashMap = std.StringHashMap;

pub const Provider = struct {
    name: []const u8,
    token: []const u8,
};

pub const Storage = struct {
    const Self = @This();

    allocator: mem.Allocator,
    providers: StringHashMap(Provider),
    config_path: []const u8,

    pub fn init(allocator: mem.Allocator, config_path: []const u8) !Self {
        var storage = Self{
            .allocator = allocator,
            .providers = StringHashMap(Provider).init(allocator),
            .config_path = config_path,
        };
        errdefer storage.providers.deinit();
        try storage.load();

        return storage;
    }

    fn load(self: *Self) !void {
        var f = try fs.cwd().openFile(self.config_path, .{ .mode = .read_only });
        defer f.close();

        var reader = io.bufferedReader(f.reader());
        var stream = reader.reader();
        var buf: [1024]u8 = undefined;
        while (try stream.readUntilDelimiterOrEof(&buf, '\n')) |l| {
            var line = try self.allocator.alloc(u8, l.len);
            @memcpy(line, l);

            const p = try parse_fs_line(line);
            try self.providers.put(p.name, p);
        }
    }

    pub fn find_config(allocator: mem.Allocator) ![]const u8 {
        const HOME = std.os.getenv("HOME") orelse "~";
        const config_dir = try std.fmt.allocPrint(allocator, "{s}{u}{s}{u}{s}", .{ HOME, path.sep, ".config", path.sep, "zotp" });
        defer allocator.free(config_dir);

        const config_path = try std.fmt.allocPrint(allocator, "{s}{u}{s}", .{ config_dir, path.sep, "zotp.conf" });
        _ = fs.cwd().statFile(config_path) catch blk: {
            _ = fs.makeDirAbsolute(config_dir) catch {};
            _ = fs.cwd().createFile(config_path, .{ .truncate = true }) catch {};
            break :blk try fs.cwd().statFile(config_path);
        };

        return config_path;
    }

    fn parse_fs_line(line: []const u8) !Provider {
        var it = mem.split(u8, line, ":");
        const provider = it.next() orelse unreachable;
        if (line.len <= provider.len + 1) return error.CorruptedFile;

        return Provider{
            .name = provider,
            .token = line[(provider.len + 1)..(line.len)],
        };
    }

    pub fn get(self: *Self, name: []const u8) ?Provider {
        return self.providers.get(name);
    }

    pub fn put(self: *Self, p: Provider) !void {
        try self.providers.put(p.name, p);
    }

    pub fn delete(self: *Self, p: *Provider) !void {
        _ = self.providers.remove(p.name);
    }

    pub fn list_print(self: *Self) void {
        var it = self.providers.iterator();
        var i: u8 = 1;
        while (it.next()) |x| {
            std.debug.print("{d}/{d}: {s}\n", .{ i, self.providers.count(), x.key_ptr.* });
            i += 1;
        }
        it.index = 0;
    }

    pub fn commit(self: *Self) !void {
        if (self.config_path.len == 0) {
            std.debug.print("no config path is set\n", .{});
        }

        const mem_req = self.providers.count() * 128;
        var buf: []u8 = try self.allocator.alloc(u8, mem_req);
        var it = self.providers.iterator();
        var i: usize = 0;
        while (it.next()) |p| {
            const pv = p.value_ptr.*;
            @memcpy(buf[i .. i + pv.name.len], pv.name);
            i += pv.name.len;
            @memcpy(buf[i .. i + 1], ":");
            i += 1;
            @memcpy(buf[i .. i + pv.token.len], pv.token);
            i += pv.token.len;

            @memcpy(buf[i .. i + 1], "\n");
            i += 1;
        }

        try fs.cwd().writeFile(self.config_path, buf[0..i]);
    }
};
