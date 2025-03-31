const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_bed = b.addExecutable(.{
        .name = "testbed",
        .root_source_file = b.path("testbed.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(test_bed);

    // const vulkan_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");
    // const vulkan_gen_cmd = b.addRunArtifact(vulkan_gen);
    // vulkan_gen_cmd.addFileArg(registry_path);

    // const vulkan_zig = b.addModule("vulkan", .{
    //     .root_source_file = vulkan_gen_cmd.addOutputFileArg("vk.zig"),
    // });

    // toolbox_mod.addImport("vulkan", vulkan_zig);

    // Set testbed dependency.
    const zglfw = b.dependency("zglfw", .{});
    const vk_toolbox = b.dependency("vulkan_toolbox", .{});

    test_bed.root_module.addImport("vk-toolbox", vk_toolbox.module("root"));
    test_bed.root_module.addImport("zglfw", zglfw.module("root"));
    test_bed.root_module.addImport("vulkan", vk_toolbox.module("vulkan"));

    if (target.result.os.tag != .emscripten) {
        test_bed.linkLibrary(zglfw.artifact("glfw"));
    }

    const run_cmd = b.addRunArtifact(test_bed);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
