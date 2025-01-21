const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;

const shader = @import("shaders/cube.glsl.zig");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const CHUNK_SIZE: usize = 32;
const CHUNK_SPHERE_RADIUS: f32 = (@as(f32, @floatFromInt(CHUNK_SIZE)) * std.math.sqrt(3.0)) / 2.0;

const chunk_manager = struct {
    var chunks: std.AutoHashMap(zlm_i32.Vec3, Chunk) = std.AutoHashMap(zlm_i32.Vec3, Chunk).init(std.heap.page_allocator);

    fn generate_chunk(pos: zlm_i32.Vec3) !Chunk {
        var chunk = Chunk.generate_chunk(pos);
        try chunk.generate_mesh();
        try chunks.put(pos, chunk);
        return chunk;
    }

    fn render(camera: *const Camera) void {
        var chunks_iter = chunks.valueIterator();
        while (chunks_iter.next()) |chunk| {
            chunk.draw(camera);
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

    var camera: Camera = .{};
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
    blocks: [CHUNK_SIZE*CHUNK_SIZE*CHUNK_SIZE]bool,
    verticies: []f32,
    indicies: []u32,
    vbo: sg.Buffer,
    ibo: sg.Buffer,

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

    fn generate_chunk(pos: zlm_i32.Vec3) Chunk {
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
            .verticies = undefined,
            .indicies = undefined,
            .vbo = .{},
            .ibo = .{},
        };
    }

    fn get_voxel(this: *Chunk, pos: zlm_i32.Vec3) bool {
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

    fn draw(this: *const Chunk, camera: *const Camera) void {
            if (this.vbo.id == 0 or this.ibo.id == 0 or !this.is_on_frustum(camera)) {
                return;
            }

            const projection = camera.get_projection();
            const view = camera.get_view();

            const model = zlm.Mat4.createTranslation(zlm.Vec3.new(@floatFromInt(this.pos.x), @floatFromInt(this.pos.y), @floatFromInt(this.pos.z)).scale(CHUNK_SIZE));
            const uniform: shader.VsParams = .{
                .mvp = @bitCast(model.mul(view).mul(projection)),
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

        for (0..CHUNK_SIZE) |x| {
            for (0..CHUNK_SIZE) |z| {
                for (0..CHUNK_SIZE) |y| {
                    const voxel_pos = zlm_i32.Vec3.new(@intCast(x), @intCast(y), @intCast(z));

                    const index = CHUNK_SIZE * CHUNK_SIZE * z + CHUNK_SIZE * y + x;
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

const Camera = struct {
    fov: f32 = 75.0,
    position: zlm.Vec3 = zlm.Vec3.zero,
    front: zlm.Vec3 = zlm.Vec3.unitZ.neg(),
    up: zlm.Vec3 = zlm.Vec3.unitY,
    yaw: f32 = -90.0,
    pitch: f32 = 0.0,

    near: f32 = 0.1,
    far: f32 = 320.0,

    fn new(position: zlm.Vec3) Camera {
        return .{
            .position = position,
        };
    }

    fn get_projection(this: *const Camera) zlm.Mat4 {
        return zlm.Mat4.createPerspective(std.math.degreesToRadians(this.fov), sapp.widthf() / sapp.heightf(), this.near, this.far);
    }

    fn get_view(this: *const Camera) zlm.Mat4 {
        return zlm.Mat4.createLookAt(this.position, this.position.add(this.front), zlm.Vec3.unitY);
    }

    fn get_v_fov(this: *const Camera) f32 {
        const half_width = @tan(std.math.degreesToRadians(this.fov/2.0));
        const half_height = sapp.heightf() / sapp.widthf() * half_width;
        return std.math.radiansToDegrees(std.math.atan(half_height) * 2.0);
    }
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
        .buffer_pool_size = 10000, 
    });

    state.camera = Camera.new(zlm.Vec3.all(CHUNK_SIZE + 2));

    // find a more async way to load in chunks around the player at runtime
    for (0..15) |x| {
        for (0..3) |y| {
            for (0..15) |z| {
                const chunk_pos = zlm_i32.Vec3.new(@intCast(x), @intCast(y), @intCast(z));
                _ = chunk_manager.generate_chunk(chunk_pos.sub(zlm_i32.Vec3.new(0, 2, 0))) catch return;
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
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sg.applyPipeline(state.pip);

    chunk_manager.render(&state.camera);

    sg.endPass();
    sg.commit();
}

export fn event(ev: [*c]const sapp.Event) void {
    const camera_speed = @as(f32, @floatCast(sapp.frameDuration())) * 100.0;
    if (ev.*.type == .KEY_DOWN) {
        if (ev.*.key_code == .W) {
            state.camera.position = state.camera.position.add(state.camera.front.scale(camera_speed));
        }

        if (ev.*.key_code == .S) {
            state.camera.position = state.camera.position.sub(state.camera.front.scale(camera_speed));
        }

        const camera_right = state.camera.front.cross(zlm.Vec3.unitY).normalize();
        if (ev.*.key_code == .A) {
            state.camera.position = state.camera.position.sub(camera_right.scale(camera_speed));
        }
        
        if (ev.*.key_code == .D) {
            state.camera.position = state.camera.position.add(camera_right.scale(camera_speed));
        }

        if (ev.*.key_code == .SPACE) {
            state.camera.position.y += camera_speed;
        }

        if (ev.*.key_code == .LEFT_SHIFT) {
            state.camera.position.y -= camera_speed;
        }

        if (ev.*.key_code == .ESCAPE) {
            sapp.showMouse(!sapp.mouseShown());
            sapp.lockMouse(!sapp.mouseLocked());
        }

        if (ev.*.key_code == .F) {
            sapp.toggleFullscreen();
        }
    }

    if (ev.*.type == .MOUSE_MOVE and sapp.mouseLocked()) {
        const sensitivity = 0.1;

        const x_offset = ev.*.mouse_dx * sensitivity;
        const y_offset = ev.*.mouse_dy * sensitivity;

        state.camera.yaw += x_offset;
        state.camera.pitch -= y_offset;


        if (state.camera.pitch > 89.0) {
            state.camera.pitch = 89.0;
        } else if (state.camera.pitch < -89.0) {
            state.camera.pitch = -89.0;
        }

        const direcion = zlm.Vec3.new(
            @cos(std.math.degreesToRadians(state.camera.yaw)) * @cos(std.math.degreesToRadians(state.camera.pitch)),
            @sin(std.math.degreesToRadians(state.camera.pitch)),
            @sin(std.math.degreesToRadians(state.camera.yaw)) * @cos(std.math.degreesToRadians(state.camera.pitch)),
        );

        state.camera.front = direcion.normalize();
        const camera_right = state.camera.front.cross(zlm.Vec3.unitY).normalize();

        state.camera.up = state.camera.front.cross(camera_right).normalize();
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
