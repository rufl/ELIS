const std = @import("std");
const c = @import("native.zig").c;

const player_count = 3;
pub const button_count = 16;
const axis_direction_count = 4;
pub const scancode_count = 512;
const axis_dead_zone = 8_000;
const text_capacity = 256;

/// Stable, user-facing actions. Games still receive the original Lupi button
/// constants; this layer only decides which physical control activates each
/// virtual console action.
pub const Action = enum(usize) {
    up,
    down,
    left,
    right,
    primary,
    secondary,
    face_x,
    face_y,
    shoulder_l,
    shoulder_r,
    select,
    start,
};

pub const action_count = @typeInfo(Action).@"enum".fields.len;
pub const keyboard_slot_count = 3;
pub const unbound: c_int = -1;

pub const Bindings = struct {
    keyboard: [action_count][keyboard_slot_count]c_int,
    gamepad: [action_count]c_int,

    pub fn defaults() Bindings {
        var result = Bindings{
            .keyboard = .{.{unbound} ** keyboard_slot_count} ** action_count,
            .gamepad = .{unbound} ** action_count,
        };
        result.keyboard[@intFromEnum(Action.up)] = .{ c.SDL_SCANCODE_W, c.SDL_SCANCODE_UP, unbound };
        result.keyboard[@intFromEnum(Action.down)] = .{ c.SDL_SCANCODE_S, c.SDL_SCANCODE_DOWN, unbound };
        result.keyboard[@intFromEnum(Action.left)] = .{ c.SDL_SCANCODE_A, c.SDL_SCANCODE_LEFT, unbound };
        result.keyboard[@intFromEnum(Action.right)] = .{ c.SDL_SCANCODE_D, c.SDL_SCANCODE_RIGHT, unbound };
        result.keyboard[@intFromEnum(Action.primary)] = .{ c.SDL_SCANCODE_K, c.SDL_SCANCODE_Z, c.SDL_SCANCODE_SPACE };
        result.keyboard[@intFromEnum(Action.secondary)] = .{ c.SDL_SCANCODE_J, c.SDL_SCANCODE_X, unbound };
        result.keyboard[@intFromEnum(Action.face_x)] = .{ c.SDL_SCANCODE_M, unbound, unbound };
        result.keyboard[@intFromEnum(Action.face_y)] = .{ c.SDL_SCANCODE_L, unbound, unbound };
        result.keyboard[@intFromEnum(Action.shoulder_l)] = .{ c.SDL_SCANCODE_G, unbound, unbound };
        result.keyboard[@intFromEnum(Action.shoulder_r)] = .{ c.SDL_SCANCODE_H, unbound, unbound };
        result.keyboard[@intFromEnum(Action.select)] = .{ c.SDL_SCANCODE_TAB, c.SDL_SCANCODE_BACKSPACE, unbound };
        result.keyboard[@intFromEnum(Action.start)] = .{ c.SDL_SCANCODE_RETURN, c.SDL_SCANCODE_KP_ENTER, unbound };

        result.gamepad[@intFromEnum(Action.up)] = c.SDL_CONTROLLER_BUTTON_DPAD_UP;
        result.gamepad[@intFromEnum(Action.down)] = c.SDL_CONTROLLER_BUTTON_DPAD_DOWN;
        result.gamepad[@intFromEnum(Action.left)] = c.SDL_CONTROLLER_BUTTON_DPAD_LEFT;
        result.gamepad[@intFromEnum(Action.right)] = c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT;
        result.gamepad[@intFromEnum(Action.primary)] = c.SDL_CONTROLLER_BUTTON_A;
        result.gamepad[@intFromEnum(Action.secondary)] = c.SDL_CONTROLLER_BUTTON_B;
        result.gamepad[@intFromEnum(Action.face_x)] = c.SDL_CONTROLLER_BUTTON_X;
        result.gamepad[@intFromEnum(Action.face_y)] = c.SDL_CONTROLLER_BUTTON_Y;
        result.gamepad[@intFromEnum(Action.shoulder_l)] = c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER;
        result.gamepad[@intFromEnum(Action.shoulder_r)] = c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER;
        result.gamepad[@intFromEnum(Action.select)] = c.SDL_CONTROLLER_BUTTON_BACK;
        result.gamepad[@intFromEnum(Action.start)] = c.SDL_CONTROLLER_BUTTON_START;
        return result;
    }
};

const AxisDirection = enum(usize) { up, down, left, right };

/// A controller and its low-level joystick handle must never occupy separate
/// player slots. The tagged union makes that invariant explicit and prevents
/// input from two physical devices being merged accidentally.
const Device = union(enum) {
    none,
    controller: *c.SDL_GameController,
    joystick: *c.SDL_Joystick,
};

pub const Input = struct {
    bindings: Bindings = Bindings.defaults(),
    keys: [scancode_count]bool = .{false} ** scancode_count,
    key_pressed: [scancode_count]bool = .{false} ** scancode_count,
    buttons: [player_count][button_count]bool = .{.{false} ** button_count} ** player_count,
    button_pressed: [player_count][button_count]bool = .{.{false} ** button_count} ** player_count,
    axes: [player_count][axis_direction_count]bool = .{.{false} ** axis_direction_count} ** player_count,
    previous_axes: [player_count][axis_direction_count]bool = .{.{false} ** axis_direction_count} ** player_count,
    devices: [player_count]Device = .{.none} ** player_count,
    text: [text_capacity]u8 = undefined,
    text_len: usize = 0,
    confirm_pressed: bool = false,
    cancel_pressed: bool = false,

    pub fn init(self: *Input) void {
        const count = c.SDL_NumJoysticks();
        if (count <= 0) return;
        for (0..@intCast(count)) |index| self.openDevice(@intCast(index));
    }

    pub fn deinit(self: *Input) void {
        for (&self.devices) |*device| {
            switch (device.*) {
                .controller => |value| c.SDL_GameControllerClose(value),
                .joystick => |value| c.SDL_JoystickClose(value),
                .none => {},
            }
            device.* = .none;
        }
        self.clearState();
    }

    /// Clears edge-triggered state while preserving held buttons and keys.
    pub fn beginFrame(self: *Input) void {
        @memset(&self.key_pressed, false);
        for (&self.button_pressed) |*row| @memset(row, false);
        self.previous_axes = self.axes;
        self.confirm_pressed = false;
        self.cancel_pressed = false;
    }

    pub fn handleEvent(self: *Input, event: *const c.SDL_Event) void {
        switch (event.type) {
            c.SDL_KEYDOWN => if (event.key.repeat == 0) {
                const scancode: usize = @intCast(event.key.keysym.scancode);
                if (scancode < scancode_count) {
                    self.keys[scancode] = true;
                    self.key_pressed[scancode] = true;
                }
                if (isConfirmKey(event.key.keysym.scancode)) self.confirm_pressed = true;
                if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) self.cancel_pressed = true;
            },
            c.SDL_KEYUP => {
                const scancode: usize = @intCast(event.key.keysym.scancode);
                if (scancode < scancode_count) self.keys[scancode] = false;
            },
            c.SDL_TEXTINPUT => {
                const bytes = event.text.text;
                var length: usize = 0;
                while (length < bytes.len and bytes[length] != 0) : (length += 1) {}
                const available = text_capacity - self.text_len;
                const copied = @min(length, available);
                if (copied > 0) {
                    @memcpy(self.text[self.text_len..][0..copied], bytes[0..copied]);
                    self.text_len += copied;
                }
            },
            c.SDL_CONTROLLERDEVICEADDED => self.openDevice(event.cdevice.which),
            c.SDL_CONTROLLERDEVICEREMOVED => self.closeDevice(event.cdevice.which),
            c.SDL_JOYDEVICEADDED => if (c.SDL_IsGameController(event.jdevice.which) == 0)
                self.openDevice(event.jdevice.which),
            c.SDL_JOYDEVICEREMOVED => self.closeDevice(event.jdevice.which),
            c.SDL_CONTROLLERBUTTONDOWN => self.setControllerButton(event.cbutton.which, event.cbutton.button, true),
            c.SDL_CONTROLLERBUTTONUP => self.setControllerButton(event.cbutton.which, event.cbutton.button, false),
            c.SDL_JOYBUTTONDOWN => self.setJoystickButton(event.jbutton.which, event.jbutton.button, true),
            c.SDL_JOYBUTTONUP => self.setJoystickButton(event.jbutton.which, event.jbutton.button, false),
            c.SDL_WINDOWEVENT => if (event.window.event == c.SDL_WINDOWEVENT_FOCUS_LOST) self.clearHeldState(),
            else => {},
        }
    }

    /// Poll analog axes once per frame. Button state remains event-driven.
    pub fn refreshAxes(self: *Input) void {
        for (self.devices, 0..) |device, slot| {
            const values = switch (device) {
                .controller => |value| .{
                    c.SDL_GameControllerGetAxis(value, c.SDL_CONTROLLER_AXIS_LEFTX),
                    c.SDL_GameControllerGetAxis(value, c.SDL_CONTROLLER_AXIS_LEFTY),
                },
                .joystick => |value| .{
                    c.SDL_JoystickGetAxis(value, 0),
                    c.SDL_JoystickGetAxis(value, 1),
                },
                .none => .{ 0, 0 },
            };
            self.axes[slot][@intFromEnum(AxisDirection.left)] = values[0] < -axis_dead_zone;
            self.axes[slot][@intFromEnum(AxisDirection.right)] = values[0] > axis_dead_zone;
            self.axes[slot][@intFromEnum(AxisDirection.up)] = values[1] < -axis_dead_zone;
            self.axes[slot][@intFromEnum(AxisDirection.down)] = values[1] > axis_dead_zone;
        }
    }

    pub fn held(self: *const Input, button: i32, requested_player: i32) bool {
        const action = actionForVirtualButton(button) orelse return false;
        const physical = self.bindings.gamepad[@intFromEnum(action)];
        var value = false;
        if (playerSlot(requested_player)) |player| {
            value = validButton(physical) and self.buttons[player][@intCast(physical)];
            if (axisDirection(physical)) |direction| value = value or self.axes[player][@intFromEnum(direction)];
        }
        return value or self.keyboardHeld(action);
    }

    pub fn pressed(self: *const Input, button: i32, requested_player: i32) bool {
        const action = actionForVirtualButton(button) orelse return false;
        const physical = self.bindings.gamepad[@intFromEnum(action)];
        var value = false;
        if (playerSlot(requested_player)) |player| {
            value = validButton(physical) and self.button_pressed[player][@intCast(physical)];
            if (axisDirection(physical)) |direction| {
                const axis = @intFromEnum(direction);
                value = value or (self.axes[player][axis] and !self.previous_axes[player][axis]);
            }
        }
        return value or self.keyboardPressed(action);
    }

    pub fn setBindings(self: *Input, bindings: Bindings) void {
        self.bindings = bindings;
    }

    pub fn resetBindings(self: *Input) void {
        self.bindings = Bindings.defaults();
    }

    pub fn firstKeyPressed(self: *const Input) ?c_int {
        for (self.key_pressed, 0..) |pressed_value, scancode| {
            if (pressed_value) return @intCast(scancode);
        }
        return null;
    }

    pub fn firstButtonPressed(self: *const Input) ?c_int {
        for (self.button_pressed) |row| {
            for (row, 0..) |pressed_value, button| {
                if (pressed_value) return @intCast(button);
            }
        }
        return null;
    }

    pub fn keyboardConflict(self: *const Input, value: c_int, action: Action, slot: usize) ?Action {
        if (!validScancode(value)) return null;
        for (self.bindings.keyboard, 0..) |row, action_index| {
            for (row, 0..) |candidate, candidate_slot| {
                if (action_index == @intFromEnum(action) and candidate_slot == slot) continue;
                if (candidate == value) return @enumFromInt(action_index);
            }
        }
        return null;
    }

    pub fn gamepadConflict(self: *const Input, value: c_int, action: Action) ?Action {
        if (!validButton(value)) return null;
        for (self.bindings.gamepad, 0..) |candidate, action_index| {
            if (action_index != @intFromEnum(action) and candidate == value) return @enumFromInt(action_index);
        }
        return null;
    }

    pub fn bindKeyboard(self: *Input, action: Action, slot: usize, value: c_int) bool {
        if (slot >= keyboard_slot_count or (value != unbound and !validScancode(value))) return false;
        self.bindings.keyboard[@intFromEnum(action)][slot] = value;
        return true;
    }

    pub fn bindGamepad(self: *Input, action: Action, value: c_int) bool {
        if (value != unbound and !validButton(value)) return false;
        self.bindings.gamepad[@intFromEnum(action)] = value;
        return true;
    }

    pub fn anyKeyPressed(self: *const Input, scancode: c_int) bool {
        return scancode >= 0 and scancode < scancode_count and self.key_pressed[@intCast(scancode)];
    }

    pub fn anyButtonPressed(self: *const Input, button: c_int) bool {
        if (!validButton(button)) return false;
        for (self.button_pressed) |row| if (row[@intCast(button)]) return true;
        if (axisDirection(button)) |direction| {
            const axis = @intFromEnum(direction);
            for (self.axes, self.previous_axes) |current, previous| {
                if (current[axis] and !previous[axis]) return true;
            }
        }
        return false;
    }

    /// Returns the first complete UTF-8 codepoint queued by SDL text input.
    /// Invalid or incomplete input is consumed one byte at a time so a broken
    /// event can never stall the queue.
    pub fn peekText(self: *const Input) ?[]const u8 {
        if (self.text_len == 0) return null;
        const first = self.text[0];
        const expected: usize = if (first < 0x80) 1 else if (first & 0xe0 == 0xc0) 2 else if (first & 0xf0 == 0xe0) 3 else if (first & 0xf8 == 0xf0) 4 else 1;
        return self.text[0..@min(expected, self.text_len)];
    }

    pub fn consumeText(self: *Input, count: usize) void {
        const consumed = @min(count, self.text_len);
        if (consumed == 0) return;
        std.mem.copyForwards(u8, self.text[0 .. self.text_len - consumed], self.text[consumed..self.text_len]);
        self.text_len -= consumed;
    }

    pub fn clearText(self: *Input) void {
        self.text_len = 0;
    }

    fn openDevice(self: *Input, device_index: c_int) void {
        const slot = self.emptySlot() orelse return;
        if (c.SDL_IsGameController(device_index) != 0) {
            if (c.SDL_GameControllerOpen(device_index)) |controller| {
                self.devices[slot] = .{ .controller = controller };
                return;
            }
        }
        if (c.SDL_JoystickOpen(device_index)) |joystick| self.devices[slot] = .{ .joystick = joystick };
    }

    fn closeDevice(self: *Input, instance: c.SDL_JoystickID) void {
        const slot = self.slotForInstance(instance) orelse return;
        switch (self.devices[slot]) {
            .controller => |value| c.SDL_GameControllerClose(value),
            .joystick => |value| c.SDL_JoystickClose(value),
            .none => return,
        }
        self.devices[slot] = .none;
        @memset(&self.buttons[slot], false);
        @memset(&self.button_pressed[slot], false);
        @memset(&self.axes[slot], false);
        @memset(&self.previous_axes[slot], false);
    }

    fn setControllerButton(self: *Input, instance: c.SDL_JoystickID, button: u8, down: bool) void {
        const slot = self.slotForInstance(instance) orelse return;
        self.setButton(slot, button, down);
    }

    fn setJoystickButton(self: *Input, instance: c.SDL_JoystickID, raw_button: u8, down: bool) void {
        const slot = self.slotForInstance(instance) orelse return;
        if (self.devices[slot] != .joystick) return;
        const button = genericButton(raw_button) orelse return;
        self.setButton(slot, @intCast(button), down);
    }

    fn setButton(self: *Input, slot: usize, button: u8, down: bool) void {
        if (button >= button_count) return;
        self.buttons[slot][button] = down;
        if (down) self.button_pressed[slot][button] = true;
        if (down and button == c.SDL_CONTROLLER_BUTTON_A) self.confirm_pressed = true;
        if (down and button == c.SDL_CONTROLLER_BUTTON_B) self.cancel_pressed = true;
    }

    fn slotForInstance(self: *const Input, instance: c.SDL_JoystickID) ?usize {
        for (self.devices, 0..) |device, slot| {
            const candidate = switch (device) {
                .controller => |value| c.SDL_GameControllerGetJoystick(value),
                .joystick => |value| value,
                .none => null,
            } orelse continue;
            if (c.SDL_JoystickInstanceID(candidate) == instance) return slot;
        }
        return null;
    }

    fn emptySlot(self: *const Input) ?usize {
        for (self.devices, 0..) |device, slot| if (device == .none) return slot;
        return null;
    }

    fn keyboardHeld(self: *const Input, action: Action) bool {
        for (self.bindings.keyboard[@intFromEnum(action)]) |scancode| {
            if (validScancode(scancode) and self.keys[@intCast(scancode)]) return true;
        }
        return false;
    }

    fn keyboardPressed(self: *const Input, action: Action) bool {
        for (self.bindings.keyboard[@intFromEnum(action)]) |scancode| {
            if (validScancode(scancode) and self.key_pressed[@intCast(scancode)]) return true;
        }
        return false;
    }

    fn clearHeldState(self: *Input) void {
        @memset(&self.keys, false);
        for (&self.buttons) |*row| @memset(row, false);
        for (&self.axes) |*row| @memset(row, false);
    }

    fn clearState(self: *Input) void {
        self.clearHeldState();
        @memset(&self.key_pressed, false);
        for (&self.button_pressed) |*row| @memset(row, false);
        for (&self.previous_axes) |*row| @memset(row, false);
        self.confirm_pressed = false;
        self.cancel_pressed = false;
        self.text_len = 0;
    }
};

fn isConfirmKey(scancode: c_uint) bool {
    return scancode == c.SDL_SCANCODE_RETURN or
        scancode == c.SDL_SCANCODE_KP_ENTER or
        scancode == c.SDL_SCANCODE_SPACE;
}

fn playerSlot(requested: i32) ?usize {
    return if (requested >= 0 and requested < player_count) @intCast(requested) else null;
}

fn validButton(button: i32) bool {
    return button >= 0 and button < button_count;
}

pub fn validScancode(scancode: i32) bool {
    return scancode >= 0 and scancode < scancode_count;
}

pub fn validGamepadButton(button: i32) bool {
    return validButton(button);
}

fn actionForVirtualButton(button: i32) ?Action {
    return switch (button) {
        c.SDL_CONTROLLER_BUTTON_DPAD_UP => .up,
        c.SDL_CONTROLLER_BUTTON_DPAD_DOWN => .down,
        c.SDL_CONTROLLER_BUTTON_DPAD_LEFT => .left,
        c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT => .right,
        c.SDL_CONTROLLER_BUTTON_A => .primary,
        c.SDL_CONTROLLER_BUTTON_B => .secondary,
        c.SDL_CONTROLLER_BUTTON_X => .face_x,
        c.SDL_CONTROLLER_BUTTON_Y => .face_y,
        c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER => .shoulder_l,
        c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER => .shoulder_r,
        c.SDL_CONTROLLER_BUTTON_BACK => .select,
        c.SDL_CONTROLLER_BUTTON_START => .start,
        else => null,
    };
}

fn axisDirection(button: i32) ?AxisDirection {
    return switch (button) {
        c.SDL_CONTROLLER_BUTTON_DPAD_UP => .up,
        c.SDL_CONTROLLER_BUTTON_DPAD_DOWN => .down,
        c.SDL_CONTROLLER_BUTTON_DPAD_LEFT => .left,
        c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT => .right,
        else => null,
    };
}

fn genericButton(button: u8) ?i32 {
    return switch (button) {
        0 => c.SDL_CONTROLLER_BUTTON_A,
        1 => c.SDL_CONTROLLER_BUTTON_B,
        2 => c.SDL_CONTROLLER_BUTTON_X,
        3 => c.SDL_CONTROLLER_BUTTON_Y,
        4 => c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER,
        5 => c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER,
        6 => c.SDL_CONTROLLER_BUTTON_BACK,
        7 => c.SDL_CONTROLLER_BUTTON_START,
        else => null,
    };
}
