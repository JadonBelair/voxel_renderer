const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;

const NUM_KEYS: usize = @typeInfo(sapp.Keycode).Enum.fields.len;

const Input = @This();

just_pressed: [NUM_KEYS]bool = [_]bool {false} ** NUM_KEYS,
just_released: [NUM_KEYS]bool = [_]bool {false} ** NUM_KEYS,
down: [NUM_KEYS]bool = [_]bool {false} ** NUM_KEYS,

pub fn handle_event(this: *Input, ev: *const sapp.Event) void {
    switch (ev.type) {
        .KEY_UP => {
            this.down[@intCast(@intFromEnum(ev.key_code))] = false;
            this.just_released[@intCast(@intFromEnum(ev.key_code))] = true;
        },
        .KEY_DOWN => {
            if (!this.down[@intCast(@intFromEnum(ev.key_code))]) {
                this.just_pressed[@intCast(@intFromEnum(ev.key_code))] = true;
            }
            this.down[@intCast(@intFromEnum(ev.key_code))] = true;
        },
        else => {},
    }
}

pub fn end_frame(this: *Input) void {
    this.just_pressed = [_]bool {false} ** NUM_KEYS;
    this.just_released = [_]bool {false} ** NUM_KEYS;
}

pub fn is_down(this: *Input, key_code: sapp.Keycode) bool {
    return this.down[@intCast(@intFromEnum(key_code))];
}

pub fn is_just_pressed(this: *Input, key_code: sapp.Keycode) bool {
    return this.just_pressed[@intCast(@intFromEnum(key_code))];
}

pub fn is_just_released(this: *Input, key_code: sapp.Keycode) bool {
    return this.just_released[@intCast(@intFromEnum(key_code))];
}
