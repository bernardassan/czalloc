const std = @import("std");
const create = @import("../build/create.zig");

pub const CaseOptions = struct {
    optimization_modes: []const std.builtin.OptimizeMode,
    cflags: []const []const u8,
    lib_options: create.LibOptions,
};

pub fn addCase(
    b: *std.Build,
    tests_step: *std.Build.Step,
    options: CaseOptions,
) !void {
    const lib_options = options.lib_options;
    const czalloc_libs = blk: {
        var libs: [4]*std.Build.Step.Compile = undefined;
        for (options.optimization_modes, 0..) |mode, index| {
            _, const lib = create.lib(b, .{
                .optimize = mode,
                .strip = lib_options.strip,
                .target = lib_options.target,
                .linkage = lib_options.linkage,
                .want_lto = lib_options.want_lto,
                .use_lld = lib_options.use_lld,
                .use_llvm = lib_options.use_llvm,
                .pie = lib_options.use_llvm,
            });
            libs[index] = lib;
        }
        break :blk libs[0..options.optimization_modes.len];
    };

    const run_step = b.step("run-cases", "Run the test cases");
    tests_step.dependOn(run_step);

    var dir = b.build_root.handle.openDir("test/cases", .{ .iterate = true }) catch |err| {
        const fail_step = b.addFail(b.fmt("unable to open test/cases: {s}\n", .{@errorName(err)}));
        run_step.dependOn(&fail_step.step);
        return;
    };
    defer dir.close();

    const max_file_size = std.fmt.parseIntSizeSuffix("1MiB", 10) catch unreachable;

    var it = try dir.walk(b.allocator);
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;

        const src_input = try dir.readFileAlloc(b.allocator, entry.path, max_file_size);
        const write_src = b.addWriteFiles();
        const file_source = write_src.add("tmp.c", src_input);

        for (options.optimization_modes, czalloc_libs) |mode, lib| {
            const annotated_case_name = b.fmt(
                "run-{s}-{s}",
                .{ entry.basename, @tagName(mode) },
            );

            const c_module = b.createModule(.{
                .target = lib_options.target,
                .optimize = mode,
                .strip = lib_options.strip,
                .link_libc = true,
                .sanitize_c = .full,
                .stack_check = true,
                .stack_protector = true,
            });
            c_module.linkLibrary(lib);
            c_module.addCSourceFile(.{
                .file = file_source,
                .flags = options.cflags,
                .language = .c,
            });
            if (lib_options.target.result.isGnuLibC()) {
                switch (mode) {
                    .Debug => {},
                    else => {
                        c_module.addCMacro("_FORTIFY_SOURCE", "3");
                    },
                }
            }

            const c_exe = b.addExecutable(.{
                .name = annotated_case_name,
                .root_module = c_module,
                .use_lld = lib_options.use_lld,
                .use_llvm = lib_options.use_llvm,
            });
            c_exe.pie = lib_options.pie;
            c_exe.want_lto = lib_options.want_lto;
            c_exe.step.name = b.fmt("{s} test", .{annotated_case_name});

            const run_exe = b.addRunArtifact(c_exe);
            run_exe.step.name = b.fmt("{s} run", .{annotated_case_name});
            _ = run_exe.captureStdErr(); //ignore output
            run_exe.expectExitCode(0);
            run_exe.skip_foreign_checks = true;

            run_step.dependOn(&run_exe.step);
        }
    }
}
