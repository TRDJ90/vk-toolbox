const std = @import("std");
const vk = @import("vulkan");

const InstanceProxy = vk.InstanceProxy;
const DeviceProxy = vk.DeviceProxy;

// Swapchain creation logic.
pub const SwapchainConfig = struct {
    instance: InstanceProxy,
    //physical_device: vk.PhysicalDevice,
    graphics_queue_family: u32,
    present_queue_family: u32,

    device: DeviceProxy,
    p_device: vk.PhysicalDevice,

    desired_format: vk.Format = .b8g8r8a8_srgb,
    desired_colorspace: vk.ColorSpaceKHR = .srgb_nonlinear_khr,
    surface: vk.SurfaceKHR,

    old_swapchain: ?vk.SwapchainKHR = null,
    vsync: bool = false,
    triple_buffer: bool = false,
    extent: vk.Extent2D,
    alloc_cb: ?*vk.AllocationCallbacks = null,
};

pub const Swapchain = struct {
    handle: vk.SwapchainKHR = .null_handle,
    images: []vk.Image = &.{},
    image_views: []vk.ImageView = &.{},
    format: vk.Format = undefined,
    extent: vk.Extent2D = undefined,

    pub fn deinit(self: *const Swapchain, allocator: std.mem.Allocator) void {
        allocator.free(self.image_views);
        allocator.free(self.images);
    }
};

pub fn createSwapchain(allocator: std.mem.Allocator, config: SwapchainConfig) !Swapchain {
    const support_info = try SwapchainSupportInfo.init(allocator, config.instance, config.p_device, config.surface);
    defer support_info.deinit(allocator);

    const caps = support_info.capabilities;
    const format = pickSwapchainFormat(support_info.formats, config.desired_format, config.desired_colorspace);
    const present_mode = pickSwapchainPresentMode(support_info.present_modes, config.vsync, config.triple_buffer);
    const actual_extent = makeSwapchainExtent(support_info.capabilities, config.extent);

    var image_count = caps.min_image_count + 1;
    if (caps.max_image_count > 0) {
        image_count = @min(image_count, caps.max_image_count);
    }

    const qfi = [_]u32{ config.graphics_queue_family, config.present_queue_family };
    const sharing_mode: vk.SharingMode = if (config.graphics_queue_family != config.present_queue_family)
        .concurrent
    else
        .exclusive;

    var old_swapchain_handle: vk.SwapchainKHR = .null_handle;
    if (config.old_swapchain) |old_swapchain| {
        // destroy the old swapchain.
        config.device.destroySwapchainKHR(old_swapchain, null);
        old_swapchain_handle = old_swapchain;
    }

    var swapchain_ci: vk.SwapchainCreateInfoKHR = .{
        .surface = config.surface,
        .min_image_count = image_count,
        .image_format = format.format,
        .image_color_space = format.color_space,
        .image_extent = actual_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = qfi.len,
        .p_queue_family_indices = &qfi,
        .pre_transform = caps.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .old_swapchain = old_swapchain_handle,
        .clipped = vk.TRUE,
    };

    const handle = try config.device.createSwapchainKHR(&swapchain_ci, null);
    errdefer config.device.destroySwapchainKHR(handle, null);

    const images = try config.device.getSwapchainImagesAllocKHR(handle, allocator);
    errdefer allocator.free(images);

    // Create image views for the swapchain images
    const image_views = try allocator.alloc(vk.ImageView, images.len);
    errdefer allocator.free(image_views);

    for (images, image_views) |image, *view| {
        view.* = try config.device.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = format.format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer config.device.destroyImageView(view, null);
    }

    return Swapchain{
        .handle = handle,
        .images = images,
        .image_views = image_views,
        .format = format.format,
        .extent = actual_extent,
    };
}

fn pickSwapchainFormat(formats: []const vk.SurfaceFormatKHR, desired_format: vk.Format, desired_colorspace: vk.ColorSpaceKHR) vk.SurfaceFormatKHR {
    for (formats) |format| {
        if (format.format == desired_format and format.color_space == desired_colorspace) {
            return format;
        }
    }

    // No match return first format, because there must always be at least one supported surface format.
    return formats[0];
}

fn pickSwapchainPresentMode(modes: []const vk.PresentModeKHR, vsync: bool, triple_buffer: bool) vk.PresentModeKHR {
    if (vsync == false) {
        for (modes) |mode| {
            if (mode == .immediate_khr) {
                return mode;
            }
        }
        // log something..
    }

    for (modes) |mode| {
        if (mode == .mailbox_khr and triple_buffer) {
            return mode;
        }
    }

    // If no match, we can always return fifo
    return vk.PresentModeKHR.fifo_khr;
}

fn makeSwapchainExtent(capabilities: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) vk.Extent2D {
    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        return capabilities.current_extent;
    }

    return vk.Extent2D{
        .width = std.math.clamp(extent.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
        .height = std.math.clamp(extent.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
    };
}

pub const SwapchainSupportInfo = struct {
    capabilities: vk.SurfaceCapabilitiesKHR = undefined,
    formats: []vk.SurfaceFormatKHR = &.{},
    present_modes: []vk.PresentModeKHR = &.{},

    pub fn init(allocator: std.mem.Allocator, instance: InstanceProxy, p_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !SwapchainSupportInfo {
        const capabilities: vk.SurfaceCapabilitiesKHR = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(p_device, surface);
        const formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(p_device, surface, allocator);
        const present_modes = try instance.getPhysicalDeviceSurfacePresentModesAllocKHR(p_device, surface, allocator);

        return .{
            .capabilities = capabilities,
            .formats = formats,
            .present_modes = present_modes,
        };
    }

    pub fn deinit(self: *const SwapchainSupportInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.formats);
        allocator.free(self.present_modes);
    }
};
