const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;

const Camera = @import("camera.zig");
const ChunkManager = @import("chunk_manager.zig");

pub const state = struct {
    pub var pass_action: sg.PassAction = .{};
    pub var bind: sg.Bindings = .{};
    pub var pip: sg.Pipeline = .{};

    pub var camera: Camera = .{};

    pub var chunk_manager: ChunkManager = undefined;
};
