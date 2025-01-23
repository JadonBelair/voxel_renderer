const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;

const shader = @import("shaders/cube.glsl.zig");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const znoise = @import("znoise");

const Camera = @import("camera.zig");

const ChunkMesh = @import("chunk_mesh.zig");

const state = @import("state.zig").state;

pub const CHUNK_SIZE: usize = 32;
pub const CHUNK_SPHERE_RADIUS: f32 = (@as(f32, @floatFromInt(CHUNK_SIZE)) * std.math.sqrt(3.0)) / 2.0;

const Chunk = @This();

pos: zlm_i32.Vec3,
blocks: [CHUNK_SIZE*CHUNK_SIZE*CHUNK_SIZE]bool,
mesh: ChunkMesh = .{},

fn is_on_frustum(this: *const Chunk, camera: *const Camera) bool {
    const sphere_vec = this.center().sub(camera.position);

    const sz = sphere_vec.dot(camera.front);
    if (!(camera.near - CHUNK_SPHERE_RADIUS <= sz and sz <= camera.far + CHUNK_SPHERE_RADIUS)) {
        return false;
    }

    const half_y = std.math.degreesToRadians(camera.get_v_fov() * 0.5);
    const factor_y = 1.0 / @cos(half_y);
    const tan_y = @tan(half_y);

    // both this and the get_v_fov() function return incorrect results,
    // but i prefer it to the culling being too agressive
    const focal_length = camera.far - camera.near;
    const fov = std.math.radiansToDegrees(2.0 * std.math.atan(sapp.widthf() / (focal_length / 2.0)));

    const half_x = std.math.degreesToRadians(fov * 0.5);
    const factor_x = 1.0 / @cos(half_x);
    const tan_x = @tan(half_x);

    const sy = sphere_vec.dot(camera.up);
    const dist_y = factor_y * CHUNK_SPHERE_RADIUS + sz * tan_y;
    if (!(-dist_y <= sy and sy <= dist_y)) {
        return false;
    }

    const sx = sphere_vec.dot(camera.front.cross(zlm.Vec3.unitY).normalize());
    const dist_x = factor_x * CHUNK_SPHERE_RADIUS + sz * tan_x;
    if (!(-dist_x <= sx and sx <= dist_x)) {
        return false;
    }

    return true;
}

pub fn center(this: *const Chunk) zlm.Vec3 {
    const global_pos = this.global_position();
    return global_pos.add(zlm.Vec3.all(@as(f32, @floatFromInt(CHUNK_SIZE)) / 2.0));
}

pub fn global_position(this: *const Chunk) zlm.Vec3 {
    return zlm.Vec3.new(@floatFromInt(this.pos.x), @floatFromInt(this.pos.y), @floatFromInt(this.pos.z)).scale(CHUNK_SIZE);
}

pub fn to_chunk_position(pos: zlm.Vec3) zlm_i32.Vec3 {
    const x: i32 = @intFromFloat(@divFloor(pos.x, CHUNK_SIZE));
    const y: i32 = @intFromFloat(@divFloor(pos.y, CHUNK_SIZE));
    const z: i32 = @intFromFloat(@divFloor(pos.z, CHUNK_SIZE));

    return zlm_i32.Vec3.new(x, y, z);
}

pub fn generate_chunk(pos: zlm_i32.Vec3) Chunk {
    var chunk: Chunk = .{
        .blocks = [_]bool{false} ** (CHUNK_SIZE*CHUNK_SIZE*CHUNK_SIZE),
        .pos = pos,
    };

    const gen = znoise.FnlGenerator{
        .noise_type = .opensimplex2s,
    };
    
    const global_pos = chunk.global_position();

    for (0..CHUNK_SIZE) |x| {
        for (0..CHUNK_SIZE) |y| {
            for (0..CHUNK_SIZE) |z| {
                const voxel_global_pos = global_pos.add(zlm.Vec3.new(@floatFromInt(x), @floatFromInt(y), @floatFromInt(z)));
                const index = CHUNK_SIZE * CHUNK_SIZE * z + CHUNK_SIZE * y + x;
                const noise_val = gen.noise2(voxel_global_pos.x, voxel_global_pos.z);
                chunk.blocks[index] = noise_val * 50.0 > voxel_global_pos.y;
            }
        }
    }

    return chunk;
}

pub fn get_voxel(this: *const Chunk, pos: zlm_i32.Vec3) bool {
    const chunk_size = @as(i32, @intCast(CHUNK_SIZE));
    if (pos.x >= 0 and pos.x < chunk_size and pos.y >= 0 and pos.y < chunk_size and pos.z >= 0 and pos.z < chunk_size) {
        const voxel_x = @as(usize, @intCast(pos.x));
        const voxel_y = @as(usize, @intCast(pos.y));
        const voxel_z = @as(usize, @intCast(pos.z));

        const index = CHUNK_SIZE * CHUNK_SIZE * voxel_z + CHUNK_SIZE * voxel_y + voxel_x;
        return this.blocks[index];
    } else {
        return false;
    }
}

pub fn draw(this: *const Chunk, camera: *const Camera) void {
    if (this.is_on_frustum(camera)) {
        this.mesh.draw(camera, this.pos);
    }
}

pub fn generate_mesh(this: *Chunk) !void {
    this.mesh = try ChunkMesh.generate(this);
}

pub fn destroy_mesh(this: *const Chunk) void {
    this.mesh.destroy();
}
