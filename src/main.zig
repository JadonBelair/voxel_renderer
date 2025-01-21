const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;

const shader = @import("shaders/cube.glsl.zig");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const chunk_manager = struct {
    var chunks: std.AutoHashMap(zlm_i32.Vec3, Chunk) = std.AutoHashMap(zlm_i32.Vec3, Chunk).init(std.heap.page_allocator);

    fn generate_chunk(pos: zlm_i32.Vec3) !Chunk {
        var chunk = Chunk.generate_chunk(pos);
        try chunk.generate_mesh();
        try chunks.put(pos, chunk);
        return chunk;
    }

    fn render(view: *const zlm.Mat4, projection: *const zlm.Mat4) void {
        var chunks_iter = chunks.valueIterator();
        while (chunks_iter.next()) |chunk| {
            chunk.draw(view, projection);
        }
    }

    fn cleanup() void {
        chunks.deinit();
    }
};

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};

    var camera_pos: zlm.Vec3 = zlm.Vec3.all(35.0);
    var camera_front: zlm.Vec3 = zlm.Vec3.unitZ.neg();
    var camera_up: zlm.Vec3 = zlm.Vec3.unitY;

    var yaw: f32 = -90.0;
    var pitch: f32 = 0.0;
};

const Direction = enum {
    UP,
    DOWN,
    LEFT,
    RIGHT,
    FORWARD,
    BACK,
};

/// Vertex layout: pos_x, pos_y, pos_z, normal_z, normal_y, normal_z
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

const Chunk = struct {
    pos: zlm_i32.Vec3,
    blocks: [32*32*32]bool,
    verticies: []f32,
    indicies: []u32,
    vbo: sg.Buffer,
    ibo: sg.Buffer,

    fn generate_chunk(pos: zlm_i32.Vec3) Chunk {
        var blocks: [32*32*32]bool = [_]bool{false} ** (32*32*32);


        if (pos.y <= 0) {
            const seed = (pos.z * 32 * 32) + (pos.y * 32) + pos.x;
            var rand = std.Random.DefaultPrng.init(@intCast(@as(i64, @intCast(std.math.maxInt(i32))) + seed));
            const rng = rand.random();

            for (0..32) |current_x| {
                for (0..32) |current_y| {
                    for (0..32) |current_z| {
                        const index = 32 * 32 * current_z + 32 * current_y + current_x;
                        blocks[index] = rng.boolean();
                    }
                }
            }
        }

        return .{
            .pos = pos,
            .blocks = blocks,
            .verticies = undefined,
            .indicies = undefined,
            .vbo = .{ .id = 0 },
            .ibo = .{ .id = 0 },
        };
    }

    fn get_voxel(this: *Chunk, pos: zlm_i32.Vec3) bool {
        if (pos.x >= 0 and pos.x < 32 and pos.y >= 0 and pos.y < 32 and pos.z >= 0 and pos.z < 32) {
            const voxel_x = @as(usize, @intCast(pos.x));
            const voxel_y = @as(usize, @intCast(pos.y));
            const voxel_z = @as(usize, @intCast(pos.z));

            const index = 32 * 32 * voxel_z + 32 * voxel_y + voxel_x;
            return this.blocks[index];
        } else {
            return false;
        }
    }

    fn draw(this: *const Chunk, view: *const zlm.Mat4, projection: *const zlm.Mat4) void {
            if (this.vbo.id == 0 or this.ibo.id == 0) {
                return;
            }

            const model = zlm.Mat4.createTranslation(zlm.Vec3.new(@floatFromInt(this.pos.x), @floatFromInt(this.pos.y), @floatFromInt(this.pos.z)).scale(32));
            const uniform: shader.VsParams = .{
                .mvp = @bitCast(model.mul(view.*).mul(projection.*)),
            };

            state.bind.vertex_buffers[0] = this.vbo;
            state.bind.index_buffer = this.ibo;

            sg.applyUniforms(shader.UB_vs_params, sg.asRange(&uniform));
            sg.applyBindings(state.bind);

            sg.draw(0, @intCast(this.indicies.len), 1);
    }

    fn generate_mesh(this: *Chunk) !void {
        var vertecies = std.ArrayList(f32).init(std.heap.page_allocator);
        defer vertecies.deinit();

        var indicies = std.ArrayList(u32).init(std.heap.page_allocator);
        defer indicies.deinit();

        var face_count: u32 = 0;

        for (0..32) |x| {
            for (0..32) |z| {
                for (0..32) |y| {
                    const voxel_pos = zlm_i32.Vec3.new(@intCast(x), @intCast(y), @intCast(z));

                    const index = 32 * 32 * z + 32 * y + x;
                    if (this.blocks[index]) {
                        if (!this.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, 0, 1)))) {
                            try vertecies.appendSlice(&generate_face(voxel_pos, .FORWARD));
                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (!this.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(1, 0, 0)))) {
                            try vertecies.appendSlice(&generate_face(voxel_pos, .RIGHT));
                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (!this.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, -1, 0)))) {
                            try vertecies.appendSlice(&generate_face(voxel_pos, .DOWN));
                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (!this.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(-1, 0, 0)))) {
                            try vertecies.appendSlice(&generate_face(voxel_pos, .LEFT));
                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (!this.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, 1, 0)))) {
                            try vertecies.appendSlice(&generate_face(voxel_pos, .UP));
                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (!this.get_voxel(voxel_pos.add(zlm_i32.Vec3.new(0, 0, -1)))) {
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

        if (this.indicies.len == 0) {
            return;
        }

        this.vbo = sg.makeBuffer(.{
            .data = sg.asRange(this.verticies),
            .type = .VERTEXBUFFER,
        });
        this.ibo = sg.makeBuffer(.{
            .data = sg.asRange(this.indicies),
            .type = .INDEXBUFFER,
        });
    }

};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
        .buffer_pool_size = 10000, 
    });

    // find a more async way to load in chunks around the player at runtime
    for (0..5) |x| {
        for (0..5) |y| {
            for (0..5) |z| {
                const chunk_pos = zlm_i32.Vec3.new(@intCast(x), @intCast(y), @intCast(z));
                // subtract 5 so that there is more than one chunk on the y-axis
                _ = chunk_manager.generate_chunk(chunk_pos.sub(zlm_i32.Vec3.new(0, 4, 0))) catch return;
            }
        }
    }
    var pipe_desc: sg.PipelineDesc = .{
        .shader = sg.makeShader(shader.cubeShaderDesc(sg.queryBackend())),
        .index_type = .UINT32,
        .cull_mode = .BACK,
        .face_winding = .CW,
        .depth = .{
            .compare = .LESS,
            .write_enabled = true,
        },
    };

    pipe_desc.layout.attrs[0].format = .FLOAT3;
    pipe_desc.layout.attrs[1].format = .FLOAT3;

    state.pip = sg.makePipeline(pipe_desc);

    state.pass_action.colors[0] = .{
        .clear_value = .{ .r = 0.1, .g = 0.2, .b = 0.3, .a = 1.0 },
        .load_action = .CLEAR,
    };
}

export fn frame() void {
    const projection = zlm.Mat4.createPerspective(std.math.degreesToRadians(75.0), sapp.widthf() / sapp.heightf(), 0.1, 320.0);
    const view = zlm.Mat4.createLookAt(state.camera_pos, state.camera_pos.add(state.camera_front), state.camera_up);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);

    chunk_manager.render(&view, &projection);

    sg.endPass();
    sg.commit();
}

export fn event(ev: [*c]const sapp.Event) void {
    const camera_speed = @as(f32, @floatCast(sapp.frameDuration())) * 100.0;
    if (ev.*.type == .KEY_DOWN) {
        if (ev.*.key_code == .W) {
            state.camera_pos = state.camera_pos.add(state.camera_front.scale(camera_speed));
        }

        if (ev.*.key_code == .S) {
            state.camera_pos = state.camera_pos.sub(state.camera_front.scale(camera_speed));
        }

        if (ev.*.key_code == .A) {
            state.camera_pos = state.camera_pos.sub(state.camera_front.cross(state.camera_up).normalize().scale(camera_speed));
        }
        
        if (ev.*.key_code == .D) {
            state.camera_pos = state.camera_pos.add(state.camera_front.cross(state.camera_up).normalize().scale(camera_speed));
        }

        if (ev.*.key_code == .SPACE) {
            state.camera_pos.y += camera_speed;
        }

        if (ev.*.key_code == .LEFT_SHIFT) {
            state.camera_pos.y -= camera_speed;
        }

        if (ev.*.key_code == .ESCAPE) {
            sapp.showMouse(!sapp.mouseShown());
            sapp.lockMouse(!sapp.mouseLocked());
        }
    }

    if (ev.*.type == .MOUSE_MOVE and sapp.mouseLocked()) {
        const sensitivity = 0.1;

        const x_offset = ev.*.mouse_dx * sensitivity;
        const y_offset = ev.*.mouse_dy * sensitivity;

        state.yaw += x_offset;
        state.pitch -= y_offset;


        if (state.pitch > 89.0) {
            state.pitch = 89.0;
        } else if (state.pitch < -89.0) {
            state.pitch = -89.0;
        }

        const direcion = zlm.Vec3.new(
            @cos(std.math.degreesToRadians(state.yaw)) * @cos(std.math.degreesToRadians(state.pitch)),
            @sin(std.math.degreesToRadians(state.pitch)),
            @sin(std.math.degreesToRadians(state.yaw)) * @cos(std.math.degreesToRadians(state.pitch)),
        );

        state.camera_front = direcion.normalize();
    }

    if (ev.*.type == .UNFOCUSED) {
        sapp.lockMouse(false);
        sapp.showMouse(true);
    }

    if (ev.*.type == .FOCUSED) {
        sapp.lockMouse(true);
        sapp.showMouse(false);
    }
}

export fn cleanup() void {
    sg.shutdown();
    chunk_manager.cleanup();
}

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .event_cb = event,
        .cleanup_cb = cleanup,
        .width = 1280,
        .height = 720,
        .window_title = "Voxel Engine",
        .icon = .{ .sokol_default = true },
    });
}
