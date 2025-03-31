const std = @import("std");
const builtin = @import("builtin");

const zglfw = @import("zglfw");

const vk = @import("vulkan");
const vktb = @import("vk-toolbox");

const Loader = vktb.Loader;
const Instance = vktb.Instance;
const PhysicalDevice = vktb.PhysicalDevice;
const PhysicalDeviceSelector = vktb.PhysicalDeviceSelector;
const PhysicalDeviceSelectorConfig = vktb.PhysicalDeviceSelectorConfig;
const utils = vktb.utils;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try Loader.loadVulkan();
    defer Loader.unloadVulkan();

    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHint(zglfw.WindowHint.client_api, zglfw.ClientApi.no_api);

    const window = try zglfw.createWindow(1280, 720, "testbed", null);
    defer zglfw.destroyWindow(window);

    var instance_extensions = std.ArrayList([*:0]const u8).init(allocator);
    defer instance_extensions.deinit();

    try vktb.getInstanceSurfaceExtensions(&instance_extensions);

    const use_debug: bool = false;
    if (use_debug) {
        try instance_extensions.append(vk.extensions.ext_debug_utils.name);
    }
    try instance_extensions.append(vk.extensions.khr_surface.name);

    const instance = try Instance.init(
        allocator,
        .{
            .required_extensions = instance_extensions.items,
            .desired_api_version = utils.makeVersion(1, 2, 0),
            .custom_load_pfn = Loader.getInstanceProcAddr(),
        },
    );
    defer instance.deinit(allocator);

    const surface = try createSurface(instance.handle, @ptrCast(window));

    var features: vk.PhysicalDeviceFeatures2 = vk.PhysicalDeviceFeatures2{
        .features = .{},
    };
    var features11: vk.PhysicalDeviceVulkan11Features = .{};
    var features12: vk.PhysicalDeviceVulkan12Features = .{};
    var dynamic_rendering: vk.PhysicalDeviceDynamicRenderingFeaturesKHR = .{};
    var sync2: vk.PhysicalDeviceSynchronization2FeaturesKHR = .{ .synchronization_2 = vk.TRUE };

    features.p_next = &features11;
    features11.p_next = &features12;
    features12.p_next = &dynamic_rendering;
    dynamic_rendering.p_next = &sync2;

    var device_extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, 4);
    defer device_extensions.deinit();

    try device_extensions.appendSlice(&.{
        vk.extensions.khr_swapchain.name,
        vk.extensions.khr_dynamic_rendering.name,
        vk.extensions.ext_descriptor_indexing.name,
        vk.extensions.khr_synchronization_2.name,
        vk.extensions.khr_copy_commands_2.name,
    });

    if (builtin.target.os.tag == .macos) {
        try device_extensions.append(vk.extensions.khr_portability_subset.name);
    }

    const select_config: PhysicalDeviceSelectorConfig = .{
        .instance = instance,
        .surface = surface,
        .require_separate_compute_queue = true,
        .require_separate_transfer_queue = true,
        .required_features = &features,
        .required_extensions = &.{}, //@ptrCast(&device_extensions),
    };

    const p_device_selector = try PhysicalDeviceSelector.init(allocator, select_config);

    const pdev = p_device_selector.suitable_devices.items[0];
    _ = pdev;

    while (!window.shouldClose()) {
        zglfw.pollEvents();
        window.swapBuffers();
    }
}

// Should be moved to platform layer.
fn createSurface(instance: vk.Instance, window: *zglfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    if (glfwCreateWindowSurface(instance, window, null, &surface) != .success) {
        return error.SurfaceInitFailed;
    }

    return surface;
}

pub extern fn glfwCreateWindowSurface(instance: vk.Instance, window: *zglfw.Window, allocation_callbacks: ?*const vk.AllocationCallbacks, surface: *vk.SurfaceKHR) vk.Result;
