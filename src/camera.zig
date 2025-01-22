const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const zlm = @import("zlm");

const Camera = @This();
const CHUNK_SIZE = @import("chunk.zig").CHUNK_SIZE;

const RENDER_DISTANCE: usize = 20;

fov: f32 = 75.0,
position: zlm.Vec3 = zlm.Vec3.zero,
front: zlm.Vec3 = zlm.Vec3.unitZ,
up: zlm.Vec3 = zlm.Vec3.unitY,
yaw: f32 = 90.0,
pitch: f32 = 0.0,

near: f32 = 0.1,
far: f32 = @floatFromInt(RENDER_DISTANCE * CHUNK_SIZE),

pub fn new(position: zlm.Vec3) Camera {
    return .{
        .position = position,
    };
}

pub fn get_projection(this: *const Camera) zlm.Mat4 {
    return zlm.Mat4.createPerspective(std.math.degreesToRadians(this.fov), sapp.widthf() / sapp.heightf(), this.near, @floatFromInt(CHUNK_SIZE * RENDER_DISTANCE));
}

pub fn get_view(this: *const Camera) zlm.Mat4 {
    return zlm.Mat4.createLookAt(this.position, this.position.add(this.front), zlm.Vec3.unitY);
}

pub fn get_v_fov(this: *const Camera) f32 {
    const focal_length = this.far - this.near;
    return std.math.radiansToDegrees(2.0 * std.math.atan(sapp.heightf() / (focal_length / 2.0)));
}

