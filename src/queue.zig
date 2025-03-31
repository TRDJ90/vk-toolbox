const std = @import("std");
const vk = @import("vulkan");

const InstanceProxy = vk.InstanceProxy;

const QueueFamilyProperties = vk.QueueFamilyProperties;
const QueueFlags = vk.QueueFlags;

pub const QueueErrors = error{
    InstanceArgsMissing,
    PhysicalDeviceArgsMissing,
    SurfaceArgsMissing,
    IndexNotFound,
};

pub const QueueType = enum {
    present,
    graphics,
    compute,
    transfer,
};
// get_queue_index
pub fn getQueueIndex(
    queue_type: QueueType,
    families: []vk.QueueFamilyProperties,
    instance: ?InstanceProxy,
    physical_device: ?vk.PhysicalDevice,
    surface: ?vk.SurfaceKHR,
) !u32 {
    switch (queue_type) {
        .graphics => {
            return filterFirstQueueIndex(families, .{ .graphics_bit = true }) catch {
                return error.GraphicsUnavailable;
            };
        },
        .present => {
            const inst: InstanceProxy = instance orelse return QueueErrors.InstanceArgsMissing;
            const pdev: vk.PhysicalDevice = physical_device orelse return QueueErrors.PhysicalDeviceArgsMissing;
            const surf: vk.SurfaceKHR = surface orelse return QueueErrors.SurfaceArgsMissing;

            return filterPresentQueueIndex(inst, families, pdev, surf) catch {
                return error.PresentUnavailable;
            };
        },
        .compute => {
            return filterSeperateQueueIndex(families, .{ .compute_bit = true }, .{ .transfer_bit = true }) catch {
                return error.ComputeUnavailable;
            };
        },
        .transfer => {
            return filterSeperateQueueIndex(families, .{ .transfer_bit = true }, .{ .compute_bit = true }) catch {
                return error.TransferUnavailable;
            };
        },
    }
    return QueueErrors.IndexNotFound;
}

// get_dedicated_queue_index
pub fn getDedicatedQueueIndex(families: []vk.QueueFamilyProperties, queue_type: QueueType) !u32 {
    switch (queue_type) {
        .compute => {
            return filterDedicatedQueueIndex(families, .{ .compute_bit = true }, .{ .transfer_bit = true }) catch {
                return error.ComputeUnavailable;
            };
        },
        .transfer => {
            return filterDedicatedQueueIndex(families, .{ .transfer_bit = true }, .{ .compute_bit = true }) catch {
                return error.TransferUnavailable;
            };
        },
        else => {
            return error.InvalidQueueFamilyIndex;
        },
    }
    return QueueErrors.IndexNotFound;
}

// Filtering functions to find the Queue family index.
fn filterFirstQueueIndex(
    families: []QueueFamilyProperties,
    desired_flags: QueueFlags,
) !u32 {
    for (families, 0..) |qfp, i| {
        if (qfp.queue_flags.contains(desired_flags)) {
            return @as(u32, @intCast(i));
        }
    }
    return QueueErrors.IndexNotFound;
}

fn filterSeperateQueueIndex(
    families: []QueueFamilyProperties,
    desired_flags: QueueFlags,
    undesired_flags: QueueFlags,
) !u32 {
    const max_index_value = std.math.maxInt(u32);
    var index: u32 = max_index_value;
    for (families, 0..) |qfp, i| {
        if (qfp.queue_flags.contains(desired_flags) and (!qfp.queue_flags.contains(.{ .graphics_bit = true }))) {
            if (qfp.queue_flags.contains(undesired_flags)) {
                return @intCast(i);
            }
        } else {
            index = @intCast(i);
        }
    }

    if (index != max_index_value) {
        return index;
    }

    return QueueErrors.IndexNotFound;
}

fn filterDedicatedQueueIndex(
    families: []QueueFamilyProperties,
    desired_flags: QueueFlags,
    undesired_flags: QueueFlags,
) !u32 {
    for (families, 0..) |qfp, i| {
        if (qfp.queue_flags.contains(desired_flags)) {
            const isGraphisQueue = qfp.queue_flags.contains(.{ .graphics_bit = true });
            const isUndesiredQueue = qfp.queue_flags.contains(undesired_flags);

            if (!isGraphisQueue and !isUndesiredQueue) {
                return @intCast(i);
            }
        }
    }

    return QueueErrors.IndexNotFound;
}

fn filterPresentQueueIndex(
    instance: InstanceProxy,
    families: []QueueFamilyProperties,
    device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) !u32 {
    for (families, 0..) |_, i| {
        var present_support: vk.Bool32 = vk.FALSE;
        if (surface != .null_handle) {
            present_support = instance.getPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), surface) catch {
                return QueueErrors.IndexNotFound;
            };
        }

        if (present_support == vk.TRUE) {
            return @intCast(i);
        }
    }

    return QueueErrors.IndexNotFound;
}
