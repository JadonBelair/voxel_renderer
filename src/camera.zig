const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const zlm = @import("zlm");

const Camera = @This();

fov: f32 = 75.0,
position: zlm.Vec3 = zlm.Vec3.zero,
front: zlm.Vec3 = zlm.Vec3.unitZ.neg(),
up: zlm.Vec3 = zlm.Vec3.unitY,
yaw: f32 = -90.0,
pitch: f32 = 0.0,

near: f32 = 0.1,
far: f32 = 320.0,

pub fn new(position: zlm.Vec3) Camera {
    return .{
        .position = position,
    };
}

pub fn get_projection(this: *const Camera) zlm.Mat4 {
    return zlm.Mat4.createPerspective(std.math.degreesToRadians(this.fov), sapp.widthf() / sapp.heightf(), this.near, this.far);
}

pub fn get_view(this: *const Camera) zlm.Mat4 {
    return zlm.Mat4.createLookAt(this.position, this.position.add(this.front), zlm.Vec3.unitY);
}

pub fn get_v_fov(this: *const Camera) f32 {
    const half_width = @tan(std.math.degreesToRadians(this.fov/2.0));
    const half_height = sapp.heightf() / sapp.widthf() * half_width;
    return std.math.radiansToDegrees(std.math.atan(half_height) * 2.0);
}

