const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const register_path = b.option(LazyPath, "register path", "Vulkan register path (vk.xml)");

    const toolbox_mod = b.createModule(.{
        .root_source_file = b.path("src/vk_toolbox.zig"),
        .target = target,
        .optimize = optimize,
    });

    const toolbox = b.addLibrary(.{
        .linkage = .static,
        .name = "vk_toolbox",
        .root_module = toolbox_mod,
    });

    if (register_path) |registry| {
        addVulkanZig(toolbox, b, registry);
    } else {
        const reg_path = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
        addVulkanZig(toolbox, b, reg_path);
    }

    b.installArtifact(toolbox);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = toolbox_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}

fn addVulkanZig(vk_toolbox: *std.Build.Step.Compile, b: *std.Build, registry_path: LazyPath) void {
    const vulkan = b.dependency("vulkan", .{
        .registry = registry_path,
    }).module("vulkan-zig");

    vk_toolbox.root_module.addImport("vulkan", vulkan);
}
