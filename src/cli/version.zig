const std = @import("std");
const zli = @import("zli");
const commit = @import("commit");

pub fn register(init_opts: zli.InitOptions) !*zli.Command {
    return zli.Command.init(init_opts, .{
        .name = "version",
        .shortcut = "v",
        .description = "Show zsat version",
    }, show);
}

fn show(ctx: zli.CommandContext) !void {
    try ctx.root.printVersion();
    try ctx.writer.print("{s}\n", .{commit.commit});
}
