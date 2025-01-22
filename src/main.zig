const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const slog = sokol.log;
const sglue = sokol.glue;

const shader = @import("shaders/cube.glsl.zig");

const zlm = @import("zlm");
const zlm_i32 = zlm.SpecializeOn(i32);

const Chunk = @import("chunk.zig");
const ChunkManager = @import("chunk_manager.zig");
const Camera = @import("camera.zig");

const state = @import("state.zig").state;

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
        .buffer_pool_size = 10000, 
    });

    state.chunk_manager = ChunkManager.init(std.heap.page_allocator);

    state.camera = Camera.new(zlm.Vec3.all(Chunk.CHUNK_SIZE + 2).add(zlm.Vec3.new(@floatFromInt(Chunk.CHUNK_SIZE * 3), @floatFromInt(Chunk.CHUNK_SIZE * 3), 0.0)));

    // find a more async way to load in chunks around the player at runtime
    for (0..15) |x| {
        for (0..15) |y| {
            for (0..15) |z| {
                const chunk_pos = zlm_i32.Vec3.new(@intCast(x), @intCast(y), @intCast(z)).sub(zlm_i32.Vec3.new(0, 5, 0));
                _ = state.chunk_manager.generate_chunk(chunk_pos) catch return;
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

    state.chunk_manager.render(&state.camera);

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
