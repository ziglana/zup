const std = @import("std");
const clap = @import("clap");
const commands = @import("commands.zig");
const Package = @import("package.zig").Package;
const Registry = @import("registry.zig").Registry;
const Lock = @import("lock.zig").Lock;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help        Display this help and exit.
        \\-v, --version     Display version and exit.
        \\-r, --registry    Specify registry URL (default: zup.sh)
        \\<command>         Command to execute
        \\<args>...         Command arguments
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help) {
        try commands.printUsage();
        return;
    }

    if (res.args.version) {
        try std.io.getStdOut().writer().print("zup v0.1.0\n", .{});
        return;
    }

    if (res.positionals.len == 0) {
        try commands.printUsage();
        return;
    }

    var registry = try Registry.init(allocator, res.args.registry orelse "https://zup.sh");
    defer registry.deinit();

    try commands.dispatch(allocator, &registry, res.positionals[0], res.positionals[1..]);
}