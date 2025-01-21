const std = @import("std");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const Chunk = @import("chunk.zig");
const Camera = @import("camera.zig");

const ChunkManager = @This();

chunks: std.AutoHashMap(zlm_i32.Vec3, Chunk),

pub fn init(allocator: std.mem.Allocator) ChunkManager {
    return .{
        .chunks = std.AutoHashMap(zlm_i32.Vec3, Chunk).init(allocator),
    };
}

pub fn generate_chunk(this: *ChunkManager, pos: zlm_i32.Vec3) !Chunk {
    var chunk = Chunk.generate_chunk(pos);
    try chunk.generate_mesh();
    try this.chunks.put(pos, chunk);
    return chunk;
}

pub fn render(this: *ChunkManager, camera: *const Camera) void {
    var chunks_iter = this.chunks.valueIterator();
    while (chunks_iter.next()) |chunk| {
        chunk.draw(camera);
    }
}

pub fn cleanup(this: *ChunkManager) void {
    this.chunks.deinit();
}
