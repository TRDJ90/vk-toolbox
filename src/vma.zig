const std = @import("std");
const vma = @import("vma").vma;
const vk = @import("vulkan");

pub const VMAConfig = struct {
    instance: vk.Instance,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    getInstanceProcAddr: ?vk.PfnGetInstanceProcAddr,
    getDeviceProcAddr: ?vk.PfnGetDeviceProcAddr,
};

var vma_allocator: vma.VmaAllocator = undefined;

pub fn init(config: VMAConfig) void {
    const vulkan_functions: vma.VmaVulkanFunctions = std.mem.zeroInit(vma.VmaVulkanFunctions, .{
        .vkGetInstanceProcAddr = @as(vma.PFN_vkGetInstanceProcAddr, @ptrCast(config.getInstanceProcAddr.?)),
        .vkGetDeviceProcAddr = @as(vma.PFN_vkGetDeviceProcAddr, @ptrCast(config.getDeviceProcAddr.?)),
    });

    const alloc_info: vma.VmaAllocatorCreateInfo = std.mem.zeroInit(vma.VmaAllocatorCreateInfo, .{
        .instance = @as(vma.VkInstance, @ptrFromInt(@intFromEnum(config.instance))),
        .physicalDevice = @as(vma.VkPhysicalDevice, @ptrFromInt(@intFromEnum(config.physical_device))),
        .device = @as(vma.VkDevice, @ptrFromInt(@intFromEnum(config.device))),
        .pVulkanFunctions = &vulkan_functions,
    });

    _ = vma.vmaCreateAllocator(&alloc_info, &vma_allocator);
}
