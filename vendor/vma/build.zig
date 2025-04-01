const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vma_mod = b.addModule("vma", .{
        .root_source_file = b.path("src/vma.zig"),
        .optimize = optimize,
        .target = target,
    });

    const env_map = try std.process.getEnvMap(b.allocator);
    if (env_map.get("VULKAN_SDK")) |path| {
        vma_mod.addIncludePath(.{ .cwd_relative = try std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) });
    }

    vma_mod.addIncludePath(b.path("include/"));
    vma_mod.addCSourceFile(.{ .file = b.path("vk_mem_alloc.cpp"), .flags = &.{""} });
    vma_mod.link_libcpp = true;

    // const env_map = std.process.getEnvMap(b.allocator) catch @panic("Couldn't get environment variable map");
    // if (env_map.get("VULKAN_SDK")) |path| {
    //     vma_mod.addIncludePath(.{ .cwd_relative = std.fmt.allocPrint(b.allocator, "{s}/include", .{path}) catch @panic("couldn't alloc vulkan.h path") });
    // }

    const lib_unit_tests = b.addTest(.{
        .root_module = vma_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
