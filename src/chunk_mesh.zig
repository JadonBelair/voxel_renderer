const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const shader = @import("shaders/cube.glsl.zig");

const Camera = @import("camera.zig");
const Chunk = @import("chunk.zig");

const state = @import("state.zig").state;

const ChunkMesh = @This();

const CHUNK_SIZE = Chunk.CHUNK_SIZE;

verticies: []f32 = undefined,
indicies: []u32 = undefined,
vbo: sg.Buffer = .{},
ibo: sg.Buffer = .{},

pub fn draw(this: *const ChunkMesh, camera: *const Camera, pos: zlm_i32.Vec3) void {
    if (this.vbo.id == 0 or this.ibo.id == 0) {
        return;
    }

    const projection = camera.get_projection();
    const view = camera.get_view();

    const model = zlm.Mat4.createTranslation(zlm.Vec3.new(@floatFromInt(pos.x), @floatFromInt(pos.y), @floatFromInt(pos.z)).scale(CHUNK_SIZE));
    const uniform: shader.VsParams = .{
        .mvp = @bitCast(model.mul(view).mul(projection)),
    };

    state.bind.vertex_buffers[0] = this.vbo;
    state.bind.index_buffer = this.ibo;

    sg.applyUniforms(shader.UB_vs_params, sg.asRange(&uniform));
    sg.applyBindings(state.bind);

    sg.draw(0, @intCast(this.indicies.len), 1);
}

pub fn destroy(this: *const ChunkMesh) void {
    sg.destroyBuffer(this.vbo);
    sg.destroyBuffer(this.ibo);
}

pub fn generate(chunk: *const Chunk) !ChunkMesh {
    var this: ChunkMesh = .{};

    var vertecies = std.ArrayList(f32).init(std.heap.page_allocator);
    defer vertecies.deinit();

    var indicies = std.ArrayList(u32).init(std.heap.page_allocator);
    defer indicies.deinit();

    var face_count: u32 = 0;

    for (0..CHUNK_SIZE) |x| {
        for (0..CHUNK_SIZE) |z| {
            for (0..CHUNK_SIZE) |y| {
                const voxel_pos = zlm_i32.Vec3.new(@intCast(x), @intCast(y), @intCast(z));

                const index = CHUNK_SIZE * CHUNK_SIZE * z + CHUNK_SIZE * y + x;
                if (chunk.blocks[index]) {
                    if (!chunk.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, 0, 1)))) {
                        try vertecies.appendSlice(&generate_face(voxel_pos, .FORWARD));
                        try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                        face_count += 4;
                    }

                    if (!chunk.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(1, 0, 0)))) {
                        try vertecies.appendSlice(&generate_face(voxel_pos, .RIGHT));
                        try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                        face_count += 4;
                    }

                    if (!chunk.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, -1, 0)))) {
                        try vertecies.appendSlice(&generate_face(voxel_pos, .DOWN));
                        try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                        face_count += 4;
                    }

                    if (!chunk.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(-1, 0, 0)))) {
                        try vertecies.appendSlice(&generate_face(voxel_pos, .LEFT));
                        try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                        face_count += 4;
                    }

                    if (!chunk.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, 1, 0)))) {
                        try vertecies.appendSlice(&generate_face(voxel_pos, .UP));
                        try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                        face_count += 4;
                    }

                    if (!chunk.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, 0, -1)))) {
                        try vertecies.appendSlice(&generate_face(voxel_pos, .BACK));
                        try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                        face_count += 4;
                    }
                }
            }
        }
    }

    this.verticies = try vertecies.toOwnedSlice();
    this.indicies = try indicies.toOwnedSlice();

    if (this.indicies.len != 0) {
        this.vbo = sg.makeBuffer(.{
            .data = sg.asRange(this.verticies),
            .type = .VERTEXBUFFER,
        });
        this.ibo = sg.makeBuffer(.{
            .data = sg.asRange(this.indicies),
            .type = .INDEXBUFFER,
        });
    }

    return this;
}

const Direction = enum {
    UP,
    DOWN,
    LEFT,
    RIGHT,
    FORWARD,
    BACK,
};

/// Vertex layout: pos_x, pos_y, pos_z, normal_x, normal_y, normal_z, tex_x, tex_y
fn generate_face(position: zlm_i32.Vec3, direction: Direction) [24]f32 {
    const x = @as(f32, @floatFromInt(position.x));
    const y = @as(f32, @floatFromInt(position.y));
    const z = @as(f32, @floatFromInt(position.z));

    switch (direction) {
        .UP => {
            return [24]f32 {
                0.0 + x, 1.0 + y, 0.0 + z,    0.0,  1.0,  0.0,
                1.0 + x, 1.0 + y, 0.0 + z,    0.0,  1.0,  0.0,
                0.0 + x, 1.0 + y, 1.0 + z,    0.0,  1.0,  0.0,
                1.0 + x, 1.0 + y, 1.0 + z,    0.0,  1.0,  0.0,
            };
        },
        .DOWN => {
            return [24]f32 {
                0.0 + x, 0.0 + y, 1.0 + z,    0.0, -1.0,  0.0,
                1.0 + x, 0.0 + y, 1.0 + z,    0.0, -1.0,  0.0,
                0.0 + x, 0.0 + y, 0.0 + z,    0.0, -1.0,  0.0,
                1.0 + x, 0.0 + y, 0.0 + z,    0.0, -1.0,  0.0,
            };
        },
        .LEFT => {
            return [24]f32 {
                0.0 + x, 1.0 + y, 0.0 + z,   -1.0,  0.0,  0.0,
                0.0 + x, 1.0 + y, 1.0 + z,   -1.0,  0.0,  0.0,
                0.0 + x, 0.0 + y, 0.0 + z,   -1.0,  0.0,  0.0,
                0.0 + x, 0.0 + y, 1.0 + z,   -1.0,  0.0,  0.0,
            };
        },
        .RIGHT => {
            return [24]f32 {
                1.0 + x, 1.0 + y, 1.0 + z,    1.0,  0.0,  0.0,
                1.0 + x, 1.0 + y, 0.0 + z,    1.0,  0.0,  0.0,
                1.0 + x, 0.0 + y, 1.0 + z,    1.0,  0.0,  0.0,
                1.0 + x, 0.0 + y, 0.0 + z,    1.0,  0.0,  0.0,
            };
        },
        .FORWARD => {
            return [24]f32 {
                0.0 + x, 1.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
                1.0 + x, 1.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
                0.0 + x, 0.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
                1.0 + x, 0.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
            };
        },
        .BACK => {
            return [24]f32 {
                1.0 + x, 1.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
                0.0 + x, 1.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
                1.0 + x, 0.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
                0.0 + x, 0.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
            };
        },
    }
}
