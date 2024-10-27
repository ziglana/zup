const std = @import("std");
const Package = @import("package.zig").Package;
const Registry = @import("registry.zig").Registry;
const Lock = @import("lock.zig").Lock;

const Command = enum {
    install,
    add,
    remove,
    init,
    search,
    publish,
    update,
    list,
};

pub fn dispatch(allocator: std.mem.Allocator, registry: *Registry, cmd_str: []const u8, args: []const []const u8) !void {
    const cmd = std.meta.stringToEnum(Command, cmd_str) orelse {
        std.debug.print("Unknown command: {s}\n", .{cmd_str});
        return error.InvalidCommand;
    };

    switch (cmd) {
        .install => try handleInstall(allocator, registry, args),
        .add => try handleAdd(allocator, registry, args),
        .remove => try handleRemove(allocator, registry, args),
        .init => try handleInit(allocator, args),
        .search => try handleSearch(allocator, registry, args),
        .publish => try handlePublish(allocator, registry, args),
        .update => try handleUpdate(allocator, registry),
        .list => try handleList(allocator),
    }
}

pub fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\⚡️ zup - Blazingly Fast Zig Package Manager ⚡️
        \\
        \\Usage: zup [options] <command> [args...]
        \\
        \\Commands:
        \\  install     Install all dependencies
        \\  add         Add a package dependency
        \\  remove      Remove a package dependency
        \\  init        Initialize a new package
        \\  search      Search for packages
        \\  publish     Publish a package
        \\  update      Update dependencies
        \\  list        List installed packages
        \\
        \\Options:
        \\  -h, --help        Display this help and exit
        \\  -v, --version     Display version and exit
        \\  -r, --registry    Specify registry URL (default: zup.sh)
        \\
    );
}

fn handleInstall(allocator: std.mem.Allocator, registry: *Registry, args: []const []const u8) !void {
    var lock = try Lock.init(allocator);
    defer lock.deinit();

    const pkg = try Package.loadFromFile(allocator, "zup.json");
    defer pkg.deinit();

    if (args.len == 0) {
        try lock.installAll(registry, pkg);
    } else {
        for (args) |name| {
            try lock.installPackage(registry, name);
        }
    }
    try lock.save();
}

fn handleAdd(allocator: std.mem.Allocator, registry: *Registry, args: []const []const u8) !void {
    if (args.len == 0) return error.MissingPackageName;

    var pkg = try Package.loadFromFile(allocator, "zup.json");
    defer pkg.deinit();

    for (args) |name| {
        const version = try registry.getLatestVersion(name);
        try pkg.addDependency(name, version);
        std.debug.print("Added {s}@{s}\n", .{ name, version });
    }

    try pkg.save();
}

fn handleRemove(allocator: std.mem.Allocator, registry: *Registry, args: []const []const u8) !void {
    if (args.len == 0) return error.MissingPackageName;

    var pkg = try Package.loadFromFile(allocator, "zup.json");
    defer pkg.deinit();

    for (args) |name| {
        try pkg.removeDependency(name);
        std.debug.print("Removed {s}\n", .{name});
    }

    try pkg.save();
}

fn handleInit(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const name = if (args.len > 0) args[0] else "new-package";
    var pkg = try Package.create(allocator, .{
        .name = name,
        .version = "0.1.0",
        .description = "A new Zig package",
    });
    defer pkg.deinit();
    try pkg.save();
    std.debug.print("Initialized new package: {s}\n", .{name});
}

fn handleSearch(allocator: std.mem.Allocator, registry: *Registry, args: []const []const u8) !void {
    if (args.len == 0) return error.MissingSearchTerm;

    for (args) |term| {
        const results = try registry.search(term);
        defer results.deinit();

        std.debug.print("Search results for '{s}':\n", .{term});
        for (results.items) |result| {
            std.debug.print("  {s}@{s} - {s}\n", .{ result.name, result.version, result.description });
        }
    }
}

fn handlePublish(allocator: std.mem.Allocator, registry: *Registry, args: []const []const u8) !void {
    _ = args;
    var pkg = try Package.loadFromFile(allocator, "zup.json");
    defer pkg.deinit();

    try registry.publish(&pkg);
    std.debug.print("Published {s}@{s}\n", .{ pkg.name, pkg.version });
}

fn handleUpdate(allocator: std.mem.Allocator, registry: *Registry) !void {
    var pkg = try Package.loadFromFile(allocator, "zup.json");
    defer pkg.deinit();

    var lock = try Lock.init(allocator);
    defer lock.deinit();

    try lock.updateAll(registry, &pkg);
    try lock.save();
    std.debug.print("Updated all dependencies\n", .{});
}

fn handleList(allocator: std.mem.Allocator) !void {
    var lock = try Lock.init(allocator);
    defer lock.deinit();

    const deps = try lock.listDependencies();
    defer deps.deinit();

    std.debug.print("Installed packages:\n", .{});
    for (deps.items) |dep| {
        std.debug.print("  {s}@{s}\n", .{ dep.name, dep.version });
    }
}