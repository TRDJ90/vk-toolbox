const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

const VulkanLoader = @import("loader.zig");

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const InstanceProxy = vk.InstanceProxy;

const makeVersion = @import("utils.zig").makeVersion;

pub const vk_api_version_1_0_0: vk.Version = makeVersion(1, 0, 0);
pub const vk_api_version_1_1_0: vk.Version = makeVersion(1, 1, 0);
pub const vk_api_version_1_2_0: vk.Version = makeVersion(1, 2, 0);
pub const vk_api_version_1_3_0: vk.Version = makeVersion(1, 3, 0);

const validation_layers = [_][*:0]const u8{
    "VK_LAYER_KHRONOS_validation",
};

pub const InstanceConfig = struct {
    application_name: [*:0]const u8 = "",
    application_version: vk.Version = makeVersion(0, 0, 1),
    engine_name: [*:0]const u8 = "",
    engine_version: vk.Version = makeVersion(0, 0, 1),
    desired_api_version: vk.Version = makeVersion(1, 2, 0),
    debug: bool = false,
    debug_callback: ?vk.PfnDebugUtilsMessengerCallbackEXT = null,
    required_extensions: []const [*:0]const u8 = &.{},
    alloc_cb: ?*vk.AllocationCallbacks = null,
    custom_load_pfn: vk.PfnGetInstanceProcAddr,
};

pub const Instance = struct {
    handle: vk.Instance,
    wrapper: *InstanceWrapper,
    proxy: InstanceProxy,
    vkb: BaseWrapper,
    debug_messenger: ?vk.DebugUtilsMessengerEXT = null,

    instance_version: vk.Version = vk_api_version_1_2_0,
    api_version: vk.Version = vk_api_version_1_2_0,

    pub fn init(allocator: std.mem.Allocator, config: InstanceConfig) !Instance {

        //TODO: check out if we need to store this in the Instance struct for debugging stuff.
        var vkb: BaseWrapper = BaseWrapper.load(config.custom_load_pfn);

        // Add desired and minimal version checks.
        var instance_version: vk.Version = vk_api_version_1_0_0;
        var api_version = makeVersion(1, 0, 0);
        if (config.desired_api_version.minor > makeVersion(1, 0, 0).minor) {
            api_version = @bitCast(try vkb.enumerateInstanceVersion());
            std.log.info("Instance version supported  {d}.{d}.{d}", .{ api_version.major, api_version.minor, api_version.patch });
            if (api_version.minor < config.desired_api_version.minor) {
                std.log.err("Requested api version not supported. Desired version: 1.{d}.x and supported version: 1.{d}.x", .{ config.desired_api_version.minor, api_version.minor });
                return error.ApiVersionNotSupported;
            }
            instance_version = config.desired_api_version;
        }
        std.log.info("Instance version set to  {d}.{d}.{d}", .{ instance_version.major, instance_version.minor, instance_version.patch });

        const enable_validation = config.debug;

        // Get Instance Info and validate required layers and extensions
        const info = try InstanceInfo.init(allocator, vkb);
        defer info.deinit(allocator);

        var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, config.required_extensions.len);
        defer extensions.deinit();

        for (config.required_extensions) |ext| {
            if (!info.extensionExists(ext)) {
                std.log.err("Extension not supported: {s}", .{ext});
                //return error.ExtensionNotPresent;
            }
            try extensions.append(ext);
        }

        if (enable_validation) {
            for (validation_layers) |layer| {
                if (!info.layerExists(layer)) {
                    std.log.err("Layer not supported: {s}", .{layer});
                    return error.ValidationLayerNotPresent;
                }
            }
        }

        // Create application and instance create info
        const app_info = vk.ApplicationInfo{
            .p_application_name = config.application_name,
            .application_version = @bitCast(config.application_version),
            .p_engine_name = config.engine_name,
            .engine_version = @bitCast(config.engine_version),
            .api_version = @bitCast(instance_version),
        };

        var instance_ci: vk.InstanceCreateInfo = .{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(extensions.items.len),
            .pp_enabled_extension_names = @ptrCast(extensions.items),
            .enabled_layer_count = @intCast(validation_layers.len),
            .pp_enabled_layer_names = @ptrCast(&validation_layers),
            .flags = .{},
        };

        if (builtin.target.os.tag == .macos) {
            instance_ci.flags = .{ .enumerate_portability_bit_khr = true };
        }

        // TODO: setup debug stuff.

        // Create instance dispatcher, proxy etc.
        const handle = try vkb.createInstance(@ptrCast(&instance_ci), null);
        const wrapper = try allocator.create(vk.InstanceWrapper);
        errdefer allocator.destroy(wrapper);

        wrapper.* = vk.InstanceWrapper.load(handle, vkb.dispatch.vkGetInstanceProcAddr.?);
        const proxy: InstanceProxy = InstanceProxy.init(handle, wrapper);

        return Instance{
            .handle = handle,
            .proxy = proxy,
            .wrapper = wrapper,
            .vkb = vkb,
            .api_version = api_version,
            .instance_version = instance_version,
            .debug_messenger = null,
        };
    }
    pub fn deinit(self: *const Instance, allocator: std.mem.Allocator) void {
        // Free the instance function tables
        allocator.destroy(self.wrapper);
    }
};

pub fn createInstance(allocator: std.mem.Allocator, config: InstanceConfig) !Instance {
    //TODO: check out if we need to store this in the Instance struct for debugging stuff.
    const vkb = try BaseWrapper.load(config.loader);

    // Add desired and minimal version checks.
    var instance_version = vk_api_version_1_0_0;
    var api_version = makeVersion(1, 0, 0);
    if (config.desired_api_version > makeVersion(1, 0, 0)) {
        api_version = try vkb.enumerateInstanceVersion();
        if (api_version < config.desired_api_version) {
            std.log.err("Requested api version not supported. Desired version: {d} and supported version: {d}", .{ config.desired_api_version, api_version });
            return error.ApiVersionNotSupported;
        }
        instance_version = config.desired_api_version;
    }

    const enable_validation = config.debug;

    // Get Instance Info and validate required layers and extensions
    const info = try InstanceInfo.init(allocator, vkb);
    defer info.deinit(allocator);

    var extensions = try std.ArrayList([*:0]const u8).initCapacity(allocator, config.required_extensions.len);
    defer extensions.deinit();

    for (config.required_extensions) |ext| {
        if (!info.extensionExists(ext)) {
            std.log.err("Extension not supported: {s}", .{ext});
            //return error.ExtensionNotPresent;
        }
        try extensions.append(ext);
    }

    if (enable_validation) {
        for (validation_layers) |layer| {
            if (!info.layerExists(layer)) {
                std.log.err("Layer not supported: {s}", .{layer});
                return error.ValidationLayerNotPresent;
            }
        }
    }

    // Create application and instance create info
    const app_info = vk.ApplicationInfo{
        .p_application_name = config.application_name,
        .application_version = config.application_version,
        .p_engine_name = config.engine_name,
        .engine_version = config.engine_version,
        .api_version = instance_version,
    };

    var instance_ci: vk.InstanceCreateInfo = .{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(extensions.items),
        .enabled_layer_count = @intCast(validation_layers.len),
        .pp_enabled_layer_names = @ptrCast(&validation_layers),
        .flags = .{ .enumerate_portability_bit_khr = true },
    };

    // TODO: setup debug stuff.

    // Create instance dispatcher, proxy etc.
    const handle = try vkb.createInstance(@ptrCast(&instance_ci), null);
    const instance = try allocator.create(InstanceWrapper);
    instance.* = try InstanceWrapper.load(handle, vkb.dispatch.vkGetInstanceProcAddr);
    errdefer allocator.destroy(instance);

    return Instance{
        .handle = handle,
        .proxy = instance,
        .api_version = api_version,
        .instance_version = instance_version,
        .debug_messenger = null,
    };
}

const InstanceInfo = struct {
    layers: []vk.LayerProperties = &.{},
    extensions: []vk.ExtensionProperties = &.{},

    pub fn init(allocator: std.mem.Allocator, base_dispatcher: BaseWrapper) !InstanceInfo {
        const layers = try base_dispatcher.enumerateInstanceLayerPropertiesAlloc(allocator);
        const extensions = try base_dispatcher.enumerateInstanceExtensionPropertiesAlloc(null, allocator);

        return InstanceInfo{
            .layers = layers,
            .extensions = extensions,
        };
    }

    pub fn deinit(self: *const InstanceInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.layers);
        allocator.free(self.extensions);
    }

    pub fn extensionExists(self: *const InstanceInfo, extension_name: [*:0]const u8) bool {
        for (self.extensions) |ext| {
            if (std.mem.startsWith(u8, &ext.extension_name, std.mem.span(extension_name))) {
                return true;
            }
        }
        return false;
    }

    pub fn layerExists(self: *const InstanceInfo, layer_name: [*:0]const u8) bool {
        for (self.layers) |layer| {
            if (std.mem.startsWith(u8, &layer.layer_name, std.mem.span(layer_name))) {
                return true;
            }
        }
        return false;
    }
};

pub fn getInstanceSurfaceExtensions(extensions_list: *std.ArrayList([*:0]const u8)) !void {
    // Add OS specific instance extensions.
    switch (builtin.target.os.tag) {
        .macos => {
            try extensions_list.append(vk.extensions.ext_metal_surface.name);
            try extensions_list.append(vk.extensions.khr_portability_enumeration.name);
        },
        .windows => {
            try extensions_list.append(vk.extensions.khr_win_32_surface.name);
        },
        .linux => {
            try extensions_list.append(vk.extensions.khr_xcb_surface.name);
            try extensions_list.append(vk.extensions.khr_xlib_surface.name);
            try extensions_list.append(vk.extensions.khr_wayland_surface.name);
        },
        else => {
            std.log.err("Unsupported platform/os", .{});
        },
    }
}
