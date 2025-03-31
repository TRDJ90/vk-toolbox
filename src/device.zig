const std = @import("std");
const vk = @import("vulkan");

const Instance = vk.InstanceProxy;
const DeviceWrapper = vk.DeviceWrapper;
const DeviceProxy = vk.DeviceProxy;
const QueueProxy = vk.QueueProxy;
const QueueUtil = @import("queue.zig");

// pub const VulkanDeviceConfig = struct {
//     allocator: std.mem.Allocator,
//     instance: Instance,
// };

pub const Device = struct {
    // api_major: u32 = 1,
    // api_minor: u32 = 0,
    // api_path: u32 = 0,

    physical_device_handle: vk.PhysicalDevice,
    handle: vk.Device,
    wrapper: *vk.DeviceWrapper,
    proxy: DeviceProxy,

    graphics_queue_index: ?u32 = null,
    present_queue_index: ?u32 = null,
    transfer_queue_index: ?u32 = null,
    compute_queue_index: ?u32 = null,

    has_dedicated_compute: bool = false,
    has_dedicated_transfer: bool = false,

    // graphics_queue: ?Queue = null,
    // present_queue: ?Queue = null,
    // transfer_queue: ?Queue = null,
    // compute_queue: ?Queue = null,

    properties: vk.PhysicalDeviceProperties,
    features: *vk.PhysicalDeviceFeatures2,
    memory_properties: vk.PhysicalDeviceMemoryProperties,
    supports_device_local_host_visible: bool,
    // depth_format: vk.Format,
    // depth_channel_count: u8,

    pub fn init(
        allocator: std.mem.Allocator,
        instance: Instance,
        physical_device: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        extensions: []const [*:0]const u8,
        features: *vk.PhysicalDeviceFeatures2,
    ) !Device {
        // Arena allocator for the short lived objects
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        // Setup queue create infos
        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, arena);
        var queue_create_infos = try std.ArrayList(vk.DeviceQueueCreateInfo).initCapacity(arena, 8);
        defer queue_create_infos.deinit();

        const queue_priorities = [_]f32{1.0};
        for (queue_families, 0..) |_, i| {
            try queue_create_infos.append(vk.DeviceQueueCreateInfo{
                .queue_family_index = @intCast(i),
                .queue_count = 1,
                .p_queue_priorities = &queue_priorities,
            });
        }

        // Queury physical device properties and features.
        const pdev_props = instance.getPhysicalDeviceProperties(physical_device);
        const pdev_memory_properties = instance.getPhysicalDeviceMemoryProperties(physical_device);

        // Setup device extensions.
        var device_extensions = try std.ArrayList([*:0]const u8).initCapacity(arena, extensions.len);
        for (extensions) |ext| {
            try device_extensions.append(ext);
        }

        // Setup DeviceCreateInfo we can use to create the vulkan logical device.
        var device_create_info: vk.DeviceCreateInfo = .{
            .p_next = features,
            .queue_create_info_count = @intCast(queue_create_infos.items.len),
            .p_queue_create_infos = queue_create_infos.items.ptr,
            .enabled_extension_count = @intCast(device_extensions.items.len),
            .pp_enabled_extension_names = device_extensions.items.ptr,
            .p_enabled_features = null,
        };

        // Find the different Queue indices.
        const graphics_index: ?u32 = QueueUtil.getQueueIndex(.graphics, queue_families, instance, physical_device, surface) catch null;
        const present_index: ?u32 = QueueUtil.getQueueIndex(.present, queue_families, instance, physical_device, surface) catch null;
        var transfer_index: ?u32 = QueueUtil.getQueueIndex(.transfer, queue_families, instance, physical_device, surface) catch null;
        var compute_index: ?u32 = QueueUtil.getQueueIndex(.compute, queue_families, instance, physical_device, surface) catch null;

        var has_dedicated_compute: bool = false;
        var has_dedicated_transfer: bool = false;

        // Check if device has dedicated compute and transfer queue,
        compute_index = compute: {
            const index = QueueUtil.getDedicatedQueueIndex(queue_families, .compute) catch {
                break :compute compute_index;
            };

            has_dedicated_compute = true;
            break :compute index;
        };

        transfer_index = transfer: {
            const index = QueueUtil.getDedicatedQueueIndex(queue_families, .transfer) catch {
                break :transfer transfer_index;
            };

            has_dedicated_transfer = true;
            break :transfer index;
        };

        const handle: vk.Device = try instance.createDevice(physical_device, &device_create_info, null);

        const device_wrapper = try allocator.create(DeviceWrapper);
        errdefer allocator.destroy(device_wrapper);
        device_wrapper.* = DeviceWrapper.load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);

        const device_proxy = DeviceProxy.init(handle, device_wrapper);

        return Device{
            .handle = handle,
            .wrapper = device_wrapper,
            .proxy = device_proxy,
            .physical_device_handle = physical_device,

            .graphics_queue_index = graphics_index,
            .present_queue_index = present_index,
            .transfer_queue_index = transfer_index,
            .compute_queue_index = compute_index,

            .has_dedicated_compute = has_dedicated_compute,
            .has_dedicated_transfer = has_dedicated_transfer,

            .supports_device_local_host_visible = false,
            .properties = pdev_props,
            .features = features,
            .memory_properties = pdev_memory_properties,
        };
    }

    pub fn deinit(
        self: *const Device,
        allocator: std.mem.Allocator,
    ) void {
        allocator.destroy(self.wrapper);
    }

    pub fn getQueue(self: *const Device, index: u32) vk.Queue {
        return self.proxy.getDeviceQueue2(&vk.DeviceQueueInfo2{
            .queue_family_index = index,
            .queue_index = 0,
        });
    }

    pub fn findMemoryTypeIndex(self: *const Device, type_filter: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.memory_properties.memory_types[0..self.memory_properties.memory_type_count], 0..) |mem_type, i| {
            if (type_filter & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }
        return error.NoSuitableMemoryType;
    }
};
