const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;

const shader = @import("shaders/cube.glsl.zig");

const zlm = @import("zlm");

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};

    var chunks: [25]Chunk = undefined;

    var camera_pos: zlm.Vec3 = zlm.Vec3.all(35.0);
    var camera_front: zlm.Vec3 = zlm.Vec3.unitZ.neg();
    var camera_up: zlm.Vec3 = zlm.Vec3.unitY;

    var yaw: f32 = -90.0;
    var pitch: f32 = 0.0;
};

const Chunk = struct {
    x: i32,
    y: i32,
    z: i32,
    vertex_count: u32,
    blocks: [32][32][32]bool,
    vbo: sg.Buffer,
    ibo: sg.Buffer,

    fn draw(this: @This(), view: *const zlm.Mat4, projection: *const zlm.Mat4) void {
        state.bind.vertex_buffers[0] = this.vbo;
        state.bind.index_buffer = this.ibo;

        const model = zlm.Mat4.createTranslation(zlm.Vec3.new(@floatFromInt(this.x), @floatFromInt(this.y), @floatFromInt(this.z)).scale(32.0));

        const uniform: shader.VsParams = .{
            .mvp = @bitCast(model.mul(view.*).mul(projection.*)),
        };

        sg.applyUniforms(shader.UB_vs_params, sg.asRange(&uniform));
        sg.applyBindings(state.bind);

        sg.draw(0, this.vertex_count, 1);
    }

    fn generate_chunk(x: i32, y: i32, z: i32) Chunk {
        var blocks: [32][32][32]bool = undefined;

        const seed = (z * 32 * 32) + (y * 32) + x;

        var rand = std.Random.DefaultPrng.init(@intCast(seed));
        const rng = rand.random();

        for (0..32) |current_x| {
            for (1..31) |current_y| {
                for (0..32) |current_z| {
                    blocks[current_x][current_y][current_z] = rng.boolean();
                }
            }
        }

        return .{
            .x = x,
            .y = y,
            .z = z,
            .blocks = blocks,
            .vertex_count = 0,
            .vbo = undefined,
            .ibo = undefined,
        };
    }
    
    fn generate_mesh(this: *Chunk) !void {
        var vertecies = std.ArrayList(f32).init(std.heap.page_allocator);
        defer vertecies.deinit();

        var indicies = std.ArrayList(u32).init(std.heap.page_allocator);
        defer indicies.deinit();

        var face_count: u32 = 0;

        for (0..32) |x| {
            const float_x: f32 = @floatFromInt(x);
            for (0..32) |z| {
                const float_z: f32 = @floatFromInt(z);
                for (0..32) |y| {
                    const float_y: f32 = @floatFromInt(y);
                    const val = this.blocks[x][y][z];

                    if (val) {
                        if (z != 31 and !this.blocks[x][y][z+1]) {
                            try vertecies.appendSlice(&Chunk.generate_front_face(float_x, float_y, float_z));
                            this.vertex_count += 24;

                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (x != 31 and !this.blocks[x+1][y][z]) {
                            try vertecies.appendSlice(&Chunk.generate_right_face(float_x, float_y, float_z));
                            this.vertex_count += 24;

                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (y != 0 and !this.blocks[x][y-1][z]) {
                            try vertecies.appendSlice(&Chunk.generate_bottom_face(float_x, float_y, float_z));
                            this.vertex_count += 24;

                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (x != 0 and !this.blocks[x-1][y][z]) {
                            try vertecies.appendSlice(&Chunk.generate_left_face(float_x, float_y, float_z));
                            this.vertex_count += 24;

                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (y != 31 and !this.blocks[x][y+1][z]) {
                            try vertecies.appendSlice(&Chunk.generate_top_face(float_x, float_y, float_z));
                            this.vertex_count += 24;

                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }

                        if (z != 0 and !this.blocks[x][y][z-1]) {
                            try vertecies.appendSlice(&Chunk.generate_back_face(float_x, float_y, float_z));
                            this.vertex_count += 24;

                            try indicies.appendSlice(&[6]u32 {face_count, face_count + 1, face_count + 2, face_count + 1, face_count + 3, face_count + 2});
                            face_count += 4;
                        }
                    }
                }
            }
        }

        const mesh = try vertecies.toOwnedSlice();
        const indicies_slice = try indicies.toOwnedSlice();

        this.vbo = sg.makeBuffer(.{
            .data = sg.asRange(mesh),
            .type = .VERTEXBUFFER,
        });

        this.ibo = sg.makeBuffer(.{
            .data = sg.asRange(indicies_slice),
            .type = .INDEXBUFFER,
        });
    }

    fn generate_top_face(x: f32, y: f32, z: f32) [24]f32 {
        return [24]f32 {
            0.0 + x, 1.0 + y, 0.0 + z,    0.0,  1.0,  0.0,
            1.0 + x, 1.0 + y, 0.0 + z,    0.0,  1.0,  0.0,
            0.0 + x, 1.0 + y, 1.0 + z,    0.0,  1.0,  0.0,
            1.0 + x, 1.0 + y, 1.0 + z,    0.0,  1.0,  0.0,
        };
    }

    fn generate_bottom_face(x: f32, y: f32, z: f32) [24]f32 {
        return [24]f32 {
            0.0 + x, 0.0 + y, 1.0 + z,    0.0, -1.0,  0.0,
            1.0 + x, 0.0 + y, 1.0 + z,    0.0, -1.0,  0.0,
            0.0 + x, 0.0 + y, 0.0 + z,    0.0, -1.0,  0.0,
            1.0 + x, 0.0 + y, 0.0 + z,    0.0, -1.0,  0.0,
        };
    }

    fn generate_left_face(x: f32, y: f32, z: f32) [24]f32 {
        return [24]f32 {
            0.0 + x, 1.0 + y, 0.0 + z,   -1.0,  0.0,  0.0,
            0.0 + x, 1.0 + y, 1.0 + z,   -1.0,  0.0,  0.0,
            0.0 + x, 0.0 + y, 0.0 + z,   -1.0,  0.0,  0.0,
            0.0 + x, 0.0 + y, 1.0 + z,   -1.0,  0.0,  0.0,
        };
    }

    fn generate_right_face(x: f32, y: f32, z: f32) [24]f32 {
        return [24]f32 {
            1.0 + x, 1.0 + y, 1.0 + z,    1.0,  0.0,  0.0,
            1.0 + x, 1.0 + y, 0.0 + z,    1.0,  0.0,  0.0,
            1.0 + x, 0.0 + y, 1.0 + z,    1.0,  0.0,  0.0,
            1.0 + x, 0.0 + y, 0.0 + z,    1.0,  0.0,  0.0,
        };
    }

    fn generate_front_face(x: f32, y: f32, z: f32) [24]f32 {
        return [24]f32 {
            0.0 + x, 1.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
            1.0 + x, 1.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
            0.0 + x, 0.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
            1.0 + x, 0.0 + y, 1.0 + z,    0.0,  0.0,  1.0,
        };
    }

    fn generate_back_face(x: f32, y: f32, z: f32) [24]f32 {
        return [24]f32 {
            1.0 + x, 1.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
            0.0 + x, 1.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
            1.0 + x, 0.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
            0.0 + x, 0.0 + y, 0.0 + z,    0.0,  0.0, -1.0,
        };
    }
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    for (0..5) |x| {
        for (0..5) |z| {
            const index = z * 5 + x;

            state.chunks[index] = Chunk.generate_chunk(@intCast(x), 0, @intCast(z));
            state.chunks[index].generate_mesh() catch {};
        }
    }
    var pipe_desc: sg.PipelineDesc = .{
        .shader = sg.makeShader(shader.cubeShaderDesc(sg.queryBackend())),
        .index_type = .UINT32,
        .cull_mode = .BACK,
        .face_winding = .CW,
        .depth = .{
            .compare = .LESS_EQUAL,
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
    const projection = zlm.Mat4.createPerspective(std.math.degreesToRadians(90.0), sapp.widthf() / sapp.heightf(), 0.1, 100.0);
    const view = zlm.Mat4.createLookAt(state.camera_pos, state.camera_pos.add(state.camera_front), state.camera_up);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });

    sg.applyPipeline(state.pip);

    for (state.chunks) |chunk| {
        chunk.draw(&view, &projection);
    }

    sg.endPass();
    sg.commit();
}

var first_mouse = true;
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

        if (ev.*.key_code == .ESCAPE) {
            sapp.showMouse(!sapp.mouseShown());
            sapp.lockMouse(!sapp.mouseLocked());
        }
    }

    if (ev.*.type == .MOUSE_MOVE) {
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
