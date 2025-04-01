const std = @import("std");
const vk = @import("vulkan");

const Device = @import("vulkan_device.zig").VulkanDevice;

pub const BufferType = enum(u8) {
    vertex,
    index,
    uniform,
    staging,
};

pub const VulkanBuffer = struct {
    handle: vk.Buffer,
    usage: vk.BufferUsageFlags,
    memory: vk.DeviceMemory,
    memory_req: vk.MemoryRequirements,
    memory_index: i32,
    memory_property_flags: u32,

    // init
    pub fn init(device: Device, size: u63, usage: vk.BufferUsageFlags, memory_property_flags: vk.MemoryPropertyFlags) !VulkanBuffer {
        const device_proxy = device.device;

        // buffer create info
        const buffer_info = vk.BufferCreateInfo{
            .size = size,
            .usage = usage,
            .sharing_mode = .exclusive, // TODO: make this customizable.
        };

        // Get memory requirements.
        const handle = device_proxy.createBuffer(&buffer_info, null) catch |err| {
            std.log.err("Couldnt create buffer: {s}", .{@tagName(err)});
            return err;
        };

        const memory_req = device_proxy.getBufferMemoryRequirements(handle);
        const memory_index = try device.findMemoryTypeIndex(memory_req.memory_type_bits, memory_property_flags);

        // Allocate memory
        const allocate_info = vk.MemoryAllocateInfo{
            .allocation_size = memory_req.size,
            .memory_type_index = memory_index,
        };

        const memory = device_proxy.allocateMemory(&allocate_info, null) catch |err| {
            std.log.err("Couldn't allocate buffer memory: {s}", .{@tagName(err)});
            return err;
        };

        // TODO: Create away set debug object name

        //const is_device_memory: bool = memory_property_flags.contains(.{ .device_local_bit = true });

        return VulkanBuffer{
            .handle = handle,
            .usage = usage,
            .memory = memory,
            .memory_req = memory_req,
            .memory_index = memory_index,
            .memory_propert_flags = memory_property_flags,
        };
    }

    // deinit
    pub fn deinit(self: *const VulkanBuffer, device: Device) !void {
        const device_proxy = device.device;
        try device_proxy.deviceWaitIdle();

        if (self.memory != .null_handle) {
            device_proxy.freeMemory(self.memory, null);
        }

        if (self.handle != .null_handle) {
            device_proxy.destroyBuffer(self.handle, null);
        }
    }

    // resize
    //pub fn resize(self: *const VulkanBuffer, device: Device) !void {}

    // bind
    pub fn bind(self: *const VulkanBuffer, device: Device, offset: u64) !void {
        const device_proxy = device.device;
        try device_proxy.bindBufferMemory(self.handle, self.memory, offset);
    }

    // unbind
    pub fn unbind(self: *const VulkanBuffer, device: Device, offset: u64) void {
        const device_proxy = device.device;
        device_proxy.un(self.handle, self.memory, offset);
    }
    // resize
    // map
    // unmap
    // flush
};
