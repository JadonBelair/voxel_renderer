const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;

const shader = @import("shaders/cube.glsl.zig");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const zigimg = @import("zigimg");

const Chunk = @import("chunk.zig");
const ChunkManager = @import("chunk_manager.zig");
const Camera = @import("camera.zig");

const state = @import("state.zig");

const PLAYER_SPEED: f32 = 75.0;
const RENDER_DIST: usize = 6;

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
        .buffer_pool_size = 15000, 
    });

    state.chunk_manager = ChunkManager.init(std.heap.page_allocator);

    state.camera = Camera.new(zlm.Vec3.zero.add(zlm.Vec3.new(0.0, @floatFromInt(Chunk.CHUNK_SIZE * 2), 0.0)));

    state.chunk_manager.load_around(Chunk.to_chunk_position(state.camera.position), RENDER_DIST) catch {};

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

    const prev_pos = state.camera.position;
    var velocity = zlm.Vec3.zero;
    const camera_speed = @as(f32, @floatCast(sapp.frameDuration())) * PLAYER_SPEED;
    if (state.input_manager.is_down(.W)) {
        velocity = velocity.add(state.camera.front);
    }

    if (state.input_manager.is_down(.S)) {
        velocity = velocity.sub(state.camera.front);
    }

    const camera_right = state.camera.front.cross(zlm.Vec3.unitY).normalize();
    if (state.input_manager.is_down(.A)) {
        velocity = velocity.sub(camera_right);
    }

    if (state.input_manager.is_down(.D)) {
        velocity = velocity.add(camera_right);
    }

    if (state.input_manager.is_down(.SPACE)) {
        velocity.y += 1.0;
    }

    if (state.input_manager.is_down(.LEFT_SHIFT)) {
        velocity.y -= 1.0;
    }

    state.camera.position = state.camera.position.add(velocity.normalize().scale(camera_speed));
    const new_pos = state.camera.position;

    const prev_chunk = Chunk.to_chunk_position(prev_pos);
    const new_chunk = Chunk.to_chunk_position(new_pos);

    if (!prev_chunk.eql(new_chunk)) {
        state.chunk_manager.load_around(new_chunk, RENDER_DIST) catch {};
    }

    state.chunk_manager.process_load(3) catch {};

    state.chunk_manager.render(&state.camera);

    sg.endPass();
    sg.commit();
}

export fn event(ev: [*c]const sapp.Event) void {
    state.input_manager.handle_event(ev);

    if (ev.*.type == .KEY_DOWN) {
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
    state.chunk_manager.cleanup();
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
