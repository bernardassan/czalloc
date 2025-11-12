const std = @import("std");

pub const LibOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    use_lld: bool,
    use_llvm: bool,
    pie: bool,
    want_lto: bool,
    strip: bool,
};

pub fn lib(b: *std.Build, options: LibOptions) struct { *std.Build.Module, *std.Build.Step.Compile } {
    const lib_mod = b.addModule("czalloc", .{
        .root_source_file = b.path("src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = true,
        .sanitize_c = .full,
        .stack_check = true,
        .strip = options.strip,
    });

    const lib_comp = b.addLibrary(.{
        .name = "czalloc",
        .linkage = options.linkage,
        .root_module = lib_mod,
        .use_lld = options.use_lld,
        .use_llvm = options.use_llvm,
    });
    lib_comp.pie = options.use_llvm;
    lib_comp.want_lto = options.want_lto;

    return .{ lib_mod, lib_comp };
}
