const std = @import("std");
const vk = @import("vulkan");

const InstanceWrapper = vk.InstanceWrapper;
const InstanceProxy = vk.InstanceProxy;
const Instance = @import("instance.zig").Instance;

const makeVersion = @import("utils.zig").makeVersion;
const Queue = @import("queue.zig");
const Swapchain = @import("swapchain.zig").Swapchain;
const SwapchainSupportInfo = @import("swapchain.zig").SwapchainSupportInfo;

pub const PreferredDeviceType = enum {
    Other,
    // Integrated,
    Discrete,
    // VirtualGPU,
    // Cpu,
};

pub const PhysicalDeviceSelectorConfig = struct {
    instance: Instance,
    surface: vk.SurfaceKHR,
    preferred_type: PreferredDeviceType = PreferredDeviceType.Discrete,

    require_present: bool = true,
    require_dedicated_compute_queue: bool = false,
    require_dedicated_transfer_queue: bool = false,
    require_separate_compute_queue: bool = false,
    require_separate_transfer_queue: bool = false,

    required_features: *vk.PhysicalDeviceFeatures2 = undefined,
    // defer_surface_initialization: bool = false,
    // use_first_gpu_unconditionally: bool = false,
    enable_portability_subset: bool = true,

    required_mem_size: vk.DeviceSize = 0,

    min_api_version: vk.Version = makeVersion(1, 0, 0),
    required_extensions: []const [*:0]const u8 = &.{},
};

pub const PhysicalDeviceSelector = struct {
    suitable_devices: std.ArrayList(PhysicalDevice),

    pub fn init(allocator: std.mem.Allocator, config: PhysicalDeviceSelectorConfig) !PhysicalDeviceSelector {
        const instance: InstanceProxy = config.instance.proxy;
        const physical_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
        defer allocator.free(physical_devices);

        var suitable_devices: std.ArrayList(PhysicalDevice) = std.ArrayList(PhysicalDevice).init(allocator);
        for (physical_devices) |pdev| {
            const physical_device = try PhysicalDevice.init(allocator, instance, pdev, config.surface, config.required_features);
            //const suitable_dev: bool = isPhysicalDeviceSuitable(allocator, instance, physical_device, config) catch continue;

            //if (suitable_dev) {
            try suitable_devices.append(physical_device);
            //}
        }

        if (suitable_devices.items.len == 0) {
            return error.NoSuitablePhysicalDeviceFound;
        }

        return PhysicalDeviceSelector{
            .suitable_devices = suitable_devices,
        };
    }

    pub fn deinit(self: *const PhysicalDeviceSelector, allocator: std.mem.Allocator) void {
        for (self.suitable_devices.items) |pdev| {
            pdev.deinit(allocator);
        }

        self.suitable_devices.deinit();
    }
};

pub const PhysicalDevice = struct {
    handle: vk.PhysicalDevice = .null_handle,
    surface: vk.SurfaceKHR = .null_handle,

    properties: vk.PhysicalDeviceProperties = undefined,
    features: *vk.PhysicalDeviceFeatures2 = undefined,
    memory_properties: vk.PhysicalDeviceMemoryProperties = undefined,
    available_extensions: []vk.ExtensionProperties,
    queue_family_properties: []vk.QueueFamilyProperties,

    pub fn init(
        allocator: std.mem.Allocator,
        instance: InstanceProxy,
        device: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        features: *vk.PhysicalDeviceFeatures2,
    ) !PhysicalDevice {
        const props = instance.getPhysicalDeviceProperties(device);
        const memory_properties = instance.getPhysicalDeviceMemoryProperties(device);
        const extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(device, null, allocator);
        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, allocator);

        instance.getPhysicalDeviceFeatures2(device, features);

        return PhysicalDevice{
            .handle = device,
            .surface = surface,
            .properties = props,
            .features = features,
            .memory_properties = memory_properties,
            .available_extensions = extensions,
            .queue_family_properties = queue_families,
        };
    }

    pub fn deinit(self: *const PhysicalDevice, allocator: std.mem.Allocator) void {
        allocator.free(self.available_extensions);
        allocator.free(self.queue_family_properties);
    }

    // has a dedicated queue family that supports compute operations.
    pub fn hasDedicatedComputeQueue(self: *const PhysicalDevice) bool {
        _ = Queue.getDedicatedQueueIndex(self.queue_family_properties, .compute) catch {
            return false;
        };
        return true;
    }

    // Has a dedicated queue family that supports transfer operations.
    pub fn hasDedicatedTransferQueue(self: *const PhysicalDevice) bool {
        _ = Queue.getDedicatedQueueIndex(self.queue_family_properties, .transfer) catch {
            return false;
        };
        return true;
    }
};

fn isPhysicalDeviceSuitable(
    allocator: std.mem.Allocator,
    instance: InstanceProxy,
    physical_device: PhysicalDevice,
    config: PhysicalDeviceSelectorConfig,
) !bool {
    if (physical_device.properties.api_version < @as(u32, @bitCast(config.min_api_version))) {
        return false;
    }

    const swapchain_support = try SwapchainSupportInfo.init(allocator, instance, physical_device.handle, config.surface);
    defer swapchain_support.deinit(allocator);

    if (swapchain_support.formats.len == 0 or swapchain_support.present_modes.len == 0) {
        return false;
    }

    if (config.required_extensions.len > 0) {
        const device_extensions: []vk.ExtensionProperties = try instance.enumerateDeviceExtensionPropertiesAlloc(physical_device.handle, null, allocator);
        defer allocator.free(device_extensions);

        for (config.required_extensions) |ext| {
            var found: bool = false;
            for (device_extensions) |dev_ext| {
                if (std.mem.startsWith(u8, &dev_ext.extension_name, std.mem.span(ext))) {
                    found = true;
                }
            }
            if (!found) {
                return false;
            }
        }
    }

    // TODO: Check device features.
    // if (config.required_features_10) |feats10| {
    //     const required_features_10: vk.PhysicalDeviceFeatures = feats10;
    //     const supported_features_10: vk.PhysicalDeviceFeatures = physical_device.features;
    //     inline for (std.meta.fields(vk.PhysicalDeviceFeatures)) |field| {
    //         if (@field(required_features_10, field.name) == vk.TRUE and !(@field(supported_features_10, field.name) == vk.TRUE)) {
    //             std.log.err("Missing feature: {s}", .{field.name});
    //             return false;
    //         }
    //     }
    // }

    // if (config.required_features_11) |feats11| {
    //     const required_features_11: vk.PhysicalDeviceFeatures = feats11;
    //     const supported_features_11: vk.PhysicalDeviceFeatures = physical_device.features2;
    //     inline for (std.meta.fields(vk.PhysicalDeviceFeatures)) |field| {
    //         if (@field(required_features_11, field.name) == vk.TRUE and !(@field(supported_features_11, field.name) == vk.TRUE)) return false;
    //     }
    // }

    // if (config.required_features_12) |feats12| {
    //     const required_features_12: vk.PhysicalDeviceFeatures = feats12;
    //     const supported_features_12: vk.PhysicalDeviceFeatures = physical_device.features;
    //     inline for (std.meta.fields(vk.PhysicalDeviceFeatures)) |field| {
    //         if (@field(required_features_10, field.name) == vk.TRUE and !(@field(supported_features_10, field.name) == vk.TRUE)) return false;
    //     }
    // }

    // if (config.required_features_10) |feats10| {
    //     const required_features_10: vk.PhysicalDeviceFeatures = feats10;
    //     const supported_features_10: vk.PhysicalDeviceFeatures = physical_device.features;
    //     inline for (std.meta.fields(vk.PhysicalDeviceFeatures)) |field| {
    //         if (@field(required_features_10, field.name) == vk.TRUE and !(@field(supported_features_10, field.name) == vk.TRUE)) return false;
    //     }
    // }

    // Check if physical device has a present queue.
    if (config.require_present) {
        _ = Queue.getQueueIndex(
            .present,
            physical_device.queue_family_properties,
            instance,
            physical_device.handle,
            config.surface,
        ) catch {
            // No present queue index found return false.
            return false;
        };
    }

    // Check if physical device has a separate compute queue.
    // if (config.require_separate_compute_queue) {
    //     const has_seperate_compute: bool = physical_device.hasSeperateComputeQueue();
    //     if (!has_seperate_compute) {
    //         return false;
    //     }
    // }
    // Check if physical device has a separate transfer queue.
    // if (config.require_separate_transfer_queue) {
    //     const has_seperate_transfer: bool = physical_device.hasSeperateTransferQueue();
    //     if (!has_seperate_transfer) {
    //         return false;
    //     }
    // }

    // Check if physical device has a dedicated compute queue.
    if (config.require_dedicated_compute_queue) {
        const has_dedicated_compute: bool = physical_device.hasDedicatedComputeQueue();
        if (!has_dedicated_compute) {
            return false;
        }
    }

    // Check if physical device has a dedicated transfer queue.
    if (config.require_dedicated_transfer_queue) {
        const has_dedicated_transfer: bool = physical_device.hasDedicatedComputeQueue();
        if (!has_dedicated_transfer) {
            return false;
        }
    }

    return true;
}

// const FeatureNode = extern struct {
//     s_type: vk.StructureType = .physical_device_features_2,
//     p_next: ?*anyopaque = null,
//     fields: [256]vk.Bool32 = std.mem.zeroes([256]vk.Bool32),

//     fn matchFeature(self: *const FeatureNode, feature: FeatureNode) bool {
//         std.debug.assert(self.s_type != feature.s_type);
//         for (self.fields, feature.fields) |s, f| {
//             if (s and !f) return false;
//         }

//         return true;
//     }
// };

// const FeatureNodeChain = struct {
//     nodes: std.ArrayListUnmanaged(FeatureNode),

//     fn init(allocator: std.mem.Allocator) !FeatureNodeChain {
//         const nodes = try std.ArrayList(FeatureNode).init(allocator);

//         return FeatureNodeChain{
//             .nodes = nodes,
//         };
//     }

//     fn deinit(self: *const FeatureNodeChain) void {
//         self.nodes.deinit();
//     }

//     fn addFeature(self: *const FeatureNodeChain, feature: FeatureNode) !void {
//         try self.nodes.append(feature);
//     }

//     fn matchAllFeatures(self: *const FeatureNodeChain, requested: *const FeatureNodeChain) bool {
//         if (requested.nodes.items.len != self.nodes.items.len) {
//             std.log.err("Feature chain lenght doesn't match the requested feature chain");
//             return false;
//         }

//         for (self.nodes, requested.nodes) |n, rn| {
//             if (!n.matchFeature(rn)) {
//                 return false;
//             }
//         }
//         return true;
//     }
// };

// fn toFeatureNode(comptime T: type, from: T) FeatureNode {
//     var node: FeatureNode = std.mem.zeroes(FeatureNode);
//     std.mem.copyForwards(u8, std.mem.asBytes(&node), std.mem.asBytes(&from));
//     node.s_type = @field(from, "s_type");
//     node.p_next = @field(from, "p_next");

//     return node;
// }

// Going from Vulkan feature to feature node.
