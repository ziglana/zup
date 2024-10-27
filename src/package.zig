const std = @import("std");

pub const Package = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    description: []const u8,
    dependencies: std.StringHashMap([]const u8),

    pub fn create(allocator: std.mem.Allocator, info: struct {
        name: []const u8,
        version: []const u8,
        description: []const u8,
    }) !*Package {
        var pkg = try allocator.create(Package);
        pkg.* = .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, info.name),
            .version = try allocator.dupe(u8, info.version),
            .description = try allocator.dupe(u8, info.description),
            .dependencies = std.StringHashMap([]const u8).init(allocator),
        };
        return pkg;
    }

    pub fn loadFromFile(allocator: std.mem.Allocator, path: []const u8) !*Package {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(content);

        var parser = std.json.Parser.init(allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(content);
        defer tree.deinit();

        const root = tree.root.Object;

        var pkg = try Package.create(allocator, .{
            .name = try allocator.dupe(u8, root.get("name").?.String),
            .version = try allocator.dupe(u8, root.get("version").?.String),
            .description = try allocator.dupe(u8, root.get("description").?.String),
        });

        if (root.get("dependencies")) |deps| {
            var iter = deps.Object.iterator();
            while (iter.next()) |entry| {
                try pkg.dependencies.put(
                    try allocator.dupe(u8, entry.key_ptr.*),
                    try allocator.dupe(u8, entry.value_ptr.*.String),
                );
            }
        }

        return pkg;
    }

    pub fn save(self: *Package) !void {
        var json = std.json.Value{
            .Object = std.json.ObjectMap.init(self.allocator),
        };
        defer json.deinit();

        try json.Object.put("name", .{ .String = self.name });
        try json.Object.put("version", .{ .String = self.version });
        try json.Object.put("description", .{ .String = self.description });

        var deps = std.json.Value{ .Object = std.json.ObjectMap.init(self.allocator) };
        var iter = self.dependencies.iterator();
        while (iter.next()) |entry| {
            try deps.Object.put(entry.key_ptr.*, .{ .String = entry.value_ptr.* });
        }
        try json.Object.put("dependencies", deps);

        const file = try std.fs.cwd().createFile("zup.json", .{});
        defer file.close();

        try std.json.stringify(json, .{ .whitespace = .indent_4 }, file.writer());
    }

    pub fn deinit(self: *Package) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.description);
        var iter = self.dependencies.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.dependencies.deinit();
        self.allocator.destroy(self);
    }

    pub fn addDependency(self: *Package, name: []const u8, version: []const u8) !void {
        const key = try self.allocator.dupe(u8, name);
        const value = try self.allocator.dupe(u8, version);
        try self.dependencies.put(key, value);
    }

    pub fn removeDependency(self: *Package, name: []const u8) !void {
        const entry = self.dependencies.fetchRemove(name) orelse return error.DependencyNotFound;
        self.allocator.free(entry.key);
        self.allocator.free(entry.value);
    }
};