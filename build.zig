const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const maybe_registery = b.option(LazyPath, "registry", "Path to vulkan register (vk.xml)");

    const toolbox_mod = b.addModule("root", .{
        .root_source_file = b.path("src/toolbox.zig"),
        .optimize = optimize,
        .target = target,
    });

    var registry_path: LazyPath = undefined;
    if (maybe_registery) |registry| {
        registry_path = registry;
    } else {
        registry_path = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    }

    const vulkan_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");
    const vulkan_gen_cmd = b.addRunArtifact(vulkan_gen);
    vulkan_gen_cmd.addFileArg(registry_path);

    const vulkan_zig = b.addModule("vulkan", .{
        .root_source_file = vulkan_gen_cmd.addOutputFileArg("vk.zig"),
    });

    const vma = b.dependency("vma", .{});

    toolbox_mod.addImport("vulkan", vulkan_zig);
    toolbox_mod.addImport("vma", vma.module("vma"));

    const lib_unit_tests = b.addTest(.{
        .root_module = toolbox_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
