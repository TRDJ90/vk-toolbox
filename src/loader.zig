const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vulkan");

const dll_names = switch (builtin.os.tag) {
    .windows => &[_][]const u8{
        "vulkan-1.dll",
    },
    .ios, .macos, .tvos, .watchos => &[_][]const u8{
        "libvulkan.dylib",
        "libvulkan.1.dylib",
        "libMoltenVK.dylib",
    },
    .linux => &[_][]const u8{
        "libvulkan.so.1",
        "libvulkan.so",
    },
    else => &[_][]const u8{
        "libvulkan.so.1",
        "libvulkan.so",
    },
};

var vk_handle: ?std.DynLib = null;

pub fn loadVulkan() !void {
    var handle: std.DynLib = undefined;

    for (dll_names) |name| {
        if (std.DynLib.open(name)) |library| {
            vk_handle = library;
            break;
        } else |err| {
            std.log.err("Couldn't open the vulkan library: {s}, {any} ", .{ name, err });
            vk_handle = null;
            return;
        }
    }
    errdefer handle.close();
}

pub fn unloadVulkan() void {
    if (vk_handle) |*handle| {
        handle.close();
    }
}

pub fn getInstanceProcAddr() vk.PfnGetInstanceProcAddr {
    if (vk_handle) |*handle| {
        const function = handle.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr");
        return function.?;
    } else {
        std.log.err("Vulkan lib not loaded, call the loadVulkan() function first", .{});
        unreachable;
    }
}

pub fn loadVulkanFunction(_: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    if (vk_handle) |*handle| {
        const name_zero: [:0]const u8 = std.mem.span(name);
        const function = handle.lookup(vk.PfnVoidFunction, name_zero).?;
        return function;
    } else {
        std.log.err("Vulkan lib not loaded, call the loadVulkan() function first", .{});
        unreachable;
    }
}

// pub const VulkanLoader = struct {
//     const dll_names = switch (builtin.os.tag) {
//         .windows => &[_][]const u8{
//             "vulkan-1.dll",
//         },
//         .ios, .macos, .tvos, .watchos => &[_][]const u8{
//             "libvulkan.dylib",
//             "libvulkan.1.dylib",
//             "libMoltenVK.dylib",
//         },
//         .linux => &[_][]const u8{
//             "libvulkan.so.1",
//             "libvulkan.so",
//         },
//         else => &[_][]const u8{
//             "libvulkan.so.1",
//             "libvulkan.so",
//         },
//     };

//     handle: std.DynLib,
//     get_instance_proc_addr: ?vk.PfnGetInstanceProcAddr,

//     // TODO: extend so dll name or path are customizable.
//     pub fn loadVulkan() !VulkanLoader {
//         var handle: std.DynLib = undefined;

//         for (dll_names) |name| {
//             if (std.DynLib.open(name)) |library| {
//                 handle = library;
//                 break;
//             } else |err| {
//                 std.log.err("Couldn't open the vulkan library: {s}, {any} ", .{ name, err });
//             }
//         }
//         errdefer handle.close();

//         const instance_proc_result: ?vk.PfnGetInstanceProcAddr = handle.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr");
//         return VulkanLoader{
//             .handle = handle,
//             .get_instance_proc_addr = instance_proc_result,
//         };
//     }

//     pub fn loadVulkanFunction(self: *VulkanLoader, comptime T: type, name: [:0]const u8) T {
//         const func: ?T = self.handle.lookup(T, name);
//         if (func) |f| {
//             return f;
//         } else {
//             std.log.err("Couldn't load Vulkan function {s}", .{name});
//             // TODO: should probably be an error.
//             @panic("");
//         }
//     }
// };
