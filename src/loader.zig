const std = @import("std");
const builtin = @import("builtin");

pub const VulkanLoader = struct {
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

    handle: std.DynLib,

    // TODO: extend so dll name or path are customizable.
    pub fn loadVulkan() !VulkanLoader {
        var handle: std.DynLib = undefined;

        for (dll_names) |name| {
            if (std.DynLib.open(name)) |library| {
                handle = library;
                break;
            } else |err| {
                std.log.err("{any}", .{err});
            }
        }
        errdefer handle.close();

        return VulkanLoader{
            .handle = handle,
        };
    }

    pub fn loadVulkanFunction(self: *VulkanLoader, comptime T: type, name: [:0]const u8) T {
        const func: ?T = self.handle.lookup(T, name);
        if (func) |f| {
            return f;
        } else {
            std.log.err("Couldn't load Vulkan function {s}", .{name});
            // TODO: should probably be an error.
            @panic("");
        }
    }
};
