const vk = @import("vulkan");

pub fn makeVersion(major: u8, minor: u8, patch: u16) vk.Version {
    return vk.makeApiVersion(0, @intCast(major), @intCast(minor), @intCast(patch));
}
