const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;

const shader = @import("shaders/cube.glsl.zig");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const Camera = @import("camera.zig");

const ChunkMesh = @import("chunk_mesh.zig");

const state = @import("state.zig").state;

pub const CHUNK_SIZE: usize = 32;
pub const CHUNK_SPHERE_RADIUS: f32 = (@as(f32, @floatFromInt(CHUNK_SIZE)) * std.math.sqrt(3.0)) / 2.0;

const Chunk = @This();

pos: zlm_i32.Vec3,
blocks: [CHUNK_SIZE*CHUNK_SIZE*CHUNK_SIZE]bool,
mesh: ChunkMesh,

fn is_on_frustum(this: *const Chunk, camera: *const Camera) bool {
    const sphere_vec = this.center().sub(camera.position);

    const sz = sphere_vec.dot(camera.front);
    if (!(camera.near - CHUNK_SPHERE_RADIUS < sz and sz < camera.far + CHUNK_SPHERE_RADIUS)) {
        return false;
    }

    const half_y = std.math.degreesToRadians(camera.get_v_fov() * 0.5);
    const factor_y = 1.0 / @cos(half_y);
    const tan_y = @tan(half_y);

    const half_x = std.math.degreesToRadians(camera.fov * 0.5);
    const factor_x = 1.0 / @cos(half_x);
    const tan_x = @tan(half_x);

    const sy = sphere_vec.dot(camera.up);
    const dist_y = factor_y * CHUNK_SPHERE_RADIUS + sz * tan_y;
    if (!(-dist_y < sy and sy < dist_y)) {
        return false;
    }

    const sx = sphere_vec.dot(camera.front.cross(zlm.Vec3.unitY).normalize());
    const dist_x = factor_x * CHUNK_SPHERE_RADIUS + sz * tan_x;
    if (!(-dist_x < sx and sx < dist_x)) {
        return false;
    }

    return true;
}

fn center(this: *const Chunk) zlm.Vec3 {
    const global_pos = this.global_position();
    return global_pos.add(zlm.Vec3.all(@as(f32, @floatFromInt(CHUNK_SIZE)) / 2.0));
}

fn global_position(this: *const Chunk) zlm.Vec3 {
    return zlm.Vec3.new(@floatFromInt(this.pos.x), @floatFromInt(this.pos.y), @floatFromInt(this.pos.z)).scale(CHUNK_SIZE);
}

pub fn generate_chunk(pos: zlm_i32.Vec3) Chunk {
    var blocks: [CHUNK_SIZE*CHUNK_SIZE*CHUNK_SIZE]bool= [_]bool{false} ** (CHUNK_SIZE*CHUNK_SIZE*CHUNK_SIZE);

    if (pos.y <= 0) {
        const chunk_size = @as(i32, @intCast(CHUNK_SIZE));
        const seed = (pos.z * (chunk_size*chunk_size)) + (pos.y * chunk_size) + pos.x;
        var rand = std.Random.DefaultPrng.init(@intCast(@as(i64, @intCast(std.math.maxInt(i32))) + seed));
        const rng = rand.random();

        for (0..CHUNK_SIZE) |current_x| {
            for (0..CHUNK_SIZE) |current_y| {
                for (0..CHUNK_SIZE) |current_z| {
                    const index = CHUNK_SIZE * CHUNK_SIZE * current_z + CHUNK_SIZE * current_y + current_x;
                    blocks[index] = rng.boolean();
                }
            }
        }
    }

    return .{
        .pos = pos,
        .blocks = blocks,
        .mesh = .{},
    };
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
