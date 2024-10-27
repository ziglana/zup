const std = @import("std");
const Package = @import("package.zig").Package;
const Registry = @import("registry.zig").Registry;

pub const Lock = struct {
    allocator: std.mem.Allocator,
    packages: std.StringHashMap(struct {
        version: []const u8,
        checksum: []const u8,
    }),

    pub fn init(allocator: std.mem.Allocator) !Lock {
        var lock = Lock{
            .allocator = allocator,
            .packages = std.StringHashMap(struct {
                version: []const u8,
                checksum: []const u8,
            }).init(allocator),
        };

        // Try to load existing lock file
        const file = std.fs.cwd().openFile("zup.lock", .{}) catch |err| switch (err) {
            error.FileNotFound => return lock,
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(content);

        var parser = std.json.Parser.init(allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(content);
        defer tree.deinit();

        const root = tree.root.Object;
        var iter = root.iterator();
        while (iter.next()) |entry| {
            const pkg_info = entry.value_ptr.*.Object;
            try lock.packages.put(
                try allocator.dupe(u8, entry.key_ptr.*),
                .{
                    .version = try allocator.dupe(u8, pkg_info.get("version").?.String),
                    .checksum = try allocator.dupe(u8, pkg_info.get("checksum").?.String),
                },
            );
        }

        return lock;
    }

    pub fn deinit(self: *Lock) void {
        var iter = self.packages.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*.version);
            self.allocator.free(entry.value_ptr.*.checksum);
        }
        self.packages.deinit();
    }

    pub fn save(self: *Lock) !void {
        var json = std.json.Value{
            .Object = std.json.ObjectMap.init(self.allocator),
        };
        defer json.deinit();

        var iter = self.packages.iterator();
        while (iter.next()) |entry| {
            var pkg_info = std.json.Value{
                .Object = std.json.ObjectMap.init(self.allocator),
            };
            try pkg_info.Object.put("version", .{ .String = entry.value_ptr.*.version });
            try pkg_info.Object.put("checksum", .{ .String = entry.value_ptr.*.checksum });
            try json.Object.put(entry.key_ptr.*, pkg_info);
        }

        const file = try std.fs.cwd().createFile("zup.lock", .{});
        defer file.close();

        try std.json.stringify(json, .{ .whitespace = .indent_4 }, file.writer());
    }

    pub fn installAll(self: *Lock, registry: *Registry, pkg: *const Package) !void {
        var iter = pkg.dependencies.iterator();
        while (iter.next()) |entry| {
            try self.installPackage(registry, entry.key_ptr.*);
        }
    }

    pub fn installPackage(self: *Lock, registry: *Registry, name: []const u8) !void {
        const version = try registry.getLatestVersion(name);
        try self.packages.put(
            try self.allocator.dupe(u8, name),
            .{
                .version = try self.allocator.dupe(u8, version),
                .checksum = try self.allocator.dupe(u8, ""), // TODO: Calculate actual checksum
            },
        );
    }

    pub fn updateAll(self: *Lock, registry: *Registry, pkg: *const Package) !void {
        try self.installAll(registry, pkg);
    }

    pub fn listDependencies(self: *Lock) !std.ArrayList(struct {
        name: []const u8,
        version: []const u8,
    }) {
        var list = std.ArrayList(struct {
            name: []const u8,
            version: []const u8,
        }).init(self.allocator);

        var iter = self.packages.iterator();
        while (iter.next()) |entry| {
            try list.append(.{
                .name = try self.allocator.dupe(u8, entry.key_ptr.*),
                .version = try self.allocator.dupe(u8, entry.value_ptr.*.version),
            });
        }

        return list;
    }
};