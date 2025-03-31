const std = @import("std");
const vk = @import("vulkan");

const Device = @import("vk-toolbox").Device;

pub const Image = struct {
    handle: vk.Image,
    memory: vk.DeviceMemory,
    image_create_info: vk.ImageCreateInfo,

    view: ?vk.ImageView = null,
    view_subresource_range: ?vk.ImageSubresourceRange = null,
    view_create_info: ?vk.ImageViewCreateInfo = null,

    memory_requirements: vk.MemoryRequirements,
    memory_flags: vk.MemoryPropertyFlags,

    format: vk.Format,
    width: u32,
    height: u32,
    extent: vk.Extent2D,
    flags: u8, //texture_flag_bits
    mip_levels: u32,
    has_views: bool,

    pub fn init(
        device: Device,
        width: u32,
        height: u32,
        format: vk.Format,
        tiling: vk.ImageTiling,
        usage: vk.ImageUsageFlags,
        memory_flags: vk.MemoryPropertyFlags,
        create_view: bool,
        view_aspect_flags: vk.ImageAspectFlags,
        mip_levels: u32,
    ) !Image {
        const mip_levels_checked: u32 = if (mip_levels < 1) 1 else mip_levels;
        var image: Image = std.mem.zeroInit(Image, .{
            .width = width,
            .height = height,
            .extent = vk.Extent2D{ .width = width, .height = height },
            .memory_flags = memory_flags,
            .mip_levels = mip_levels_checked,
            .format = format,
            .has_views = create_view,
        });

        image.image_create_info = vk.ImageCreateInfo{
            .extent = .{ .width = width, .height = height, .depth = 1 },
            .mip_levels = image.mip_levels,
            .array_layers = 1,
            .format = format,
            .tiling = tiling,
            .initial_layout = vk.ImageLayout.preinitialized,
            .usage = usage,
            .samples = .{ .@"1_bit" = true },
            .sharing_mode = vk.SharingMode.exclusive,
            .image_type = vk.ImageType.@"2d",
        };

        image.handle = try device.proxy.createImage(&image.image_create_info, null);
        image.memory_requirements = device.proxy.getImageMemoryRequirements(image.handle);

        // Get memory requirements.
        const memory_type_index = try device.findMemoryTypeIndex(image.memory_requirements.memory_type_bits, memory_flags);
        if (memory_type_index == -1) {
            std.log.err("Required memory type not found. Image not valid", .{});
        }

        // Allocate memory
        const mem_alloc_info: vk.MemoryAllocateInfo = .{
            .allocation_size = image.memory_requirements.size,
            .memory_type_index = memory_type_index,
        };

        image.memory = try device.proxy.allocateMemory(&mem_alloc_info, null);

        try device.proxy.bindImageMemory(image.handle, image.memory, 0);

        if (create_view) {
            image.view = .null_handle;
            image.view_subresource_range = .{
                .aspect_mask = view_aspect_flags,
                .base_mip_level = 0,
                .level_count = image.mip_levels,
                .layer_count = 1,
                .base_array_layer = 0,
            };
            image.view_create_info = vk.ImageViewCreateInfo{
                .image = image.handle,
                .view_type = .@"2d",
                .format = format,
                .subresource_range = image.view_subresource_range.?,
                .components = std.mem.zeroes(vk.ComponentMapping),
            };
            image.view = try device.proxy.createImageView(&image.view_create_info.?, null);
        }
        return image;
    }

    pub fn deinit(self: *const Image, device: Device) void {
        if (self.view) |view| {
            device.device.destroyImageView(view, null);
        }

        if (self.memory != .null_handle) {
            device.device.freeMemory(self.memory, null);
        }

        if (self.handle != .null_handle) {
            device.device.destroyImage(self.handle, deinit);
        }
    }

    // pub fn recreate(self: *const VulkanImage) !void {}

    // pub fn transition_layout(
    //     self: *VulkanImage,
    //     cmd: vk.CommandBuffer,
    //     format: vk.Format,
    //     old_layout: vk.ImageLayout,
    //     new_layout: vk.ImageLayout,
    // ) !void {}
};
