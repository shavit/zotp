const std = @import("std");
const path = std.fs.path;
const mem = std.mem;
const io = std.io;
const fs = std.fs;
const os = std.os;
const StringHashMap = std.StringHashMap;

pub const Provider = struct {
    name: []const u8,
    token: []const u8,
};

pub const Storage = struct {
    allocator: mem.Allocator,
    providers: StringHashMap(Provider),
    config_path: []const u8,

    pub fn init(allocator: mem.Allocator, config_path: []const u8) !Storage {
        var storage = Storage{
            .allocator = allocator,
            .providers = StringHashMap(Provider).init(allocator),
            .config_path = config_path,
        };
        errdefer storage.providers.deinit();
        try storage.integrity();
        try storage.load();

        return storage;
    }

    fn load(self: *Storage) !void {
        var f = try fs.cwd().openFile(self.config_path, .{ .mode = .read_only });
        defer f.close();

        var buf: [1024]u8 = undefined;
        var readerwrp = f.reader(&buf);
        const reader = &readerwrp.interface;
        while (true) {
            const l = reader.takeDelimiterExclusive('\n') catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            const line = try self.allocator.alloc(u8, l.len);
            @memcpy(line, l);

            const p = try parse_fs_line(line);
            try self.providers.put(p.name, p);

            if (line.len == 0) break;
        }
    }

    fn integrity(self: *Storage) !void {
        var f = try fs.cwd().openFile(self.config_path, .{ .mode = .read_only });
        defer f.close();
        const fstat = try f.stat();
        if (fstat.mode & 0o077 != 0) {
            return error.InsecureFilePermissions;
        }

        const pstat = try std.posix.fstat(f.handle);
        if (pstat.uid != std.posix.getuid()) {
            return error.FileOwnershipMismatch;
        }
    }

    pub fn find_config(allocator: mem.Allocator) ![]const u8 {
        const HOME = getenv("HOME") orelse "~";
        const config_dir = try std.fmt.allocPrint(allocator, "{s}{u}{s}{u}{s}", .{ HOME, path.sep, ".config", path.sep, "zotp" });
        defer allocator.free(config_dir);

        const config_path = try path.join(allocator, &.{ config_dir, "zotp.conf" });
        // const config_path = try std.fmt.allocPrint(allocator, "{s}{u}{s}", .{ config_dir, path.sep, "zotp.conf" });
        _ = fs.cwd().statFile(config_path) catch blk: {
            _ = fs.makeDirAbsolute(config_dir) catch {};
            _ = fs.cwd().createFile(config_path, .{ .mode = 0o600 }) catch {};
            break :blk try fs.cwd().statFile(config_path);
        };

        return config_path;
    }

    fn parse_fs_line(line: []const u8) !Provider {
        var it = mem.splitSequence(u8, line, ":");
        const provider = it.next() orelse unreachable;
        if (line.len <= provider.len + 1) return error.CorruptedFile;

        return Provider{
            .name = provider,
            .token = line[(provider.len + 1)..(line.len)],
        };
    }

    fn getenv(key: []const u8) ?[]const u8 {
        for (os.environ) |env| {
            var it = mem.splitSequence(u8, env[0..mem.len(env)], "=");
            const index = mem.indexOf(u8, it.next().?, key) orelse 1;
            if (index == 0) return it.next().?;
        }

        return null;
    }

    pub fn get(self: *Storage, name: []const u8) ?Provider {
        return self.providers.get(name);
    }

    pub fn put(self: *Storage, p: Provider) !void {
        try self.providers.put(p.name, p);
    }

    pub fn delete(self: *Storage, p: *Provider) !void {
        _ = self.providers.remove(p.name);
    }

    pub fn list_print(self: *Storage) void {
        var it = self.providers.iterator();
        var i: u8 = 1;
        while (it.next()) |x| {
            std.debug.print("{d}/{d}: {s}\n", .{ i, self.providers.count(), x.key_ptr.* });
            i += 1;
        }
        it.index = 0;
    }

    pub fn commit(self: *Storage) !void {
        try self.integrity();
        if (self.config_path.len == 0) {
            return error.NoConfigPath;
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

        try fs.cwd().writeFile(.{ .sub_path = self.config_path, .data = buf[0..i] });
    }
};
