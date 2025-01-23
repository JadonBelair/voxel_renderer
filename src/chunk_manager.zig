const std = @import("std");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const Chunk = @import("chunk.zig");
const Camera = @import("camera.zig");

const ChunkManager = @This();

chunks: std.AutoArrayHashMap(zlm_i32.Vec3, Chunk),

to_load: std.ArrayList(zlm_i32.Vec3),

pub fn init(allocator: std.mem.Allocator) ChunkManager {
    return .{
        .chunks = std.AutoArrayHashMap(zlm_i32.Vec3, Chunk).init(allocator),
        .to_load = std.ArrayList(zlm_i32.Vec3).init(allocator),
    };
}

pub fn load_around(this: *ChunkManager, position: zlm_i32.Vec3, radius: usize) !void {
    const i_radius: i32 = @intCast(radius);

    var chunk_iter = this.chunks.iterator();
    while (chunk_iter.next()) |entry| {
        const chunk = entry.value_ptr;
        const diff = position.sub(chunk.pos);
        if (diff.length2() > i_radius * i_radius) {
            chunk.destroy_mesh();
            _ = this.chunks.swapRemove(chunk.pos);
        }
    }

    for (0..(radius+radius)) |x| {
        const scaled_x = @as(i32, @intCast(x)) - i_radius + position.x;
        for (0..(radius+radius)) |y| {
            const scaled_y = @as(i32, @intCast(y)) - i_radius + position.y;
            for (0..(radius+radius)) |z| {
                const scaled_z = @as(i32, @intCast(z)) - i_radius + position.z;

                const chunk_pos = zlm_i32.Vec3.new(scaled_x, scaled_y, scaled_z);
                const diff = position.sub(chunk_pos);

                if (diff.length2() < i_radius * i_radius and !this.chunks.contains(chunk_pos)) {
                    try this.to_load.append(chunk_pos);
                }
            }
        }
    }
}

pub fn process_load(this: *ChunkManager, amount: usize) !void {
    for (0..amount) |_| {
        if (this.to_load.popOrNull()) |chunk_pos| {
            _ = try this.generate_chunk(chunk_pos);
        }
    }
}

pub fn generate_chunk(this: *ChunkManager, pos: zlm_i32.Vec3) !Chunk {
    var chunk = Chunk.generate_chunk(pos);
    try chunk.generate_mesh();
    try this.chunks.put(pos, chunk);
    return chunk;
}

pub fn render(this: *ChunkManager, camera: *const Camera) void {
    var chunks_iter = this.chunks.iterator();
    while (chunks_iter.next()) |entry| {
        entry.value_ptr.draw(camera);
    }
}

pub fn cleanup(this: *ChunkManager) void {
    this.chunks.deinit();
    this.to_load.deinit();
}
