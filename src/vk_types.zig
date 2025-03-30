const vk = @import("vulkan");

// TODO: Add some default api definitions.
pub const apis: []const vk.ApiInfo = &.{
    .{
        .instance_commands = vk.InstanceCommandFlags{},
        .device_commands = vk.DeviceCommandFlags{
            .cmdPipelineBarrier2KHR = true,
            .queueSubmit2KHR = true,
        },
    },
    vk.features.version_1_0,
    vk.features.version_1_1,
    vk.features.version_1_2,
    vk.extensions.khr_swapchain,
    vk.extensions.khr_surface,
    vk.extensions.khr_copy_commands_2,
    vk.extensions.khr_dynamic_rendering,
};

pub const BaseWrapper = vk.BaseWrapper(apis);
pub const InstanceWrapper = vk.InstanceWrapper(apis);
pub const DeviceWrapper = vk.DeviceWrapper(apis);

pub const InstanceProxy = vk.InstanceProxy(apis);
pub const DeviceProxy = vk.DeviceProxy(apis);

pub const CommandBufferProxy = vk.CommandBufferProxy(apis);
pub const QueueProxy = vk.QueueProxy(apis);
