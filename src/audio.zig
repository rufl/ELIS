const std = @import("std");
const c = @import("native.zig").c;

const sample_rate = 44_100;
const channel_count = 2;
const voice_count = 12;

const Voice = struct {
    phase: f32 = 0,
    step: f32 = 0,
    gain_left: f32 = 0,
    gain_right: f32 = 0,
    remaining: usize = 0,
    waveform: u2 = 0,
};

/// Small host-side mixer for the Lupi `sfx` API. Music is decoded by
/// libsndfile and mixed with lightweight procedural voices for the console's
/// numbered effects. All mutable fields are protected by SDL's device lock.
pub const Audio = struct {
    device: c.SDL_AudioDeviceID = 0,
    music: ?*c.SNDFILE = null,
    music_info: c.SF_INFO = std.mem.zeroes(c.SF_INFO),
    volume: f32 = 1,
    voices: [voice_count]Voice = [_]Voice{.{}} ** voice_count,

    pub fn available(self: *const Audio) bool {
        return self.device != 0;
    }

    pub fn init(self: *Audio) bool {
        var desired = std.mem.zeroes(c.SDL_AudioSpec);
        var obtained = std.mem.zeroes(c.SDL_AudioSpec);
        desired.freq = sample_rate;
        desired.format = c.AUDIO_F32SYS;
        desired.channels = channel_count;
        desired.samples = 1024;
        desired.callback = audioCallback;
        desired.userdata = self;
        self.device = c.SDL_OpenAudioDevice(null, 0, &desired, &obtained, 0);
        if (self.device == 0) return false;
        c.SDL_PauseAudioDevice(self.device, 0);
        return true;
    }

    pub fn deinit(self: *Audio) void {
        if (self.device == 0) return;
        c.SDL_LockAudioDevice(self.device);
        self.closeMusicUnlocked();
        c.SDL_UnlockAudioDevice(self.device);
        c.SDL_CloseAudioDevice(self.device);
        self.device = 0;
    }

    pub fn playMusic(self: *Audio, path: [:0]const u8) bool {
        if (self.device == 0) return false;
        c.SDL_LockAudioDevice(self.device);
        defer c.SDL_UnlockAudioDevice(self.device);
        self.closeMusicUnlocked();
        self.music_info = std.mem.zeroes(c.SF_INFO);
        self.music = c.sf_open(path.ptr, c.SFM_READ, &self.music_info);
        if (self.music == null) return false;
        if (self.music_info.samplerate != sample_rate or self.music_info.channels < 1 or
            self.music_info.channels > 8)
        {
            self.closeMusicUnlocked();
            return false;
        }
        return true;
    }

    pub fn stopMusic(self: *Audio) void {
        if (self.device == 0) return;
        c.SDL_LockAudioDevice(self.device);
        defer c.SDL_UnlockAudioDevice(self.device);
        self.closeMusicUnlocked();
    }

    pub fn setVolume(self: *Audio, value: f32) void {
        if (self.device == 0) return;
        c.SDL_LockAudioDevice(self.device);
        self.volume = std.math.clamp(value, 0, 1);
        c.SDL_UnlockAudioDevice(self.device);
    }

    pub fn playEffect(self: *Audio, sample_id: i32, midi_note: i32, pan_value: f32) void {
        if (self.device == 0) return;
        c.SDL_LockAudioDevice(self.device);
        defer c.SDL_UnlockAudioDevice(self.device);
        var slot: *Voice = &self.voices[0];
        for (&self.voices) |*candidate| {
            if (candidate.remaining == 0) {
                slot = candidate;
                break;
            }
            if (candidate.remaining < slot.remaining) slot = candidate;
        }
        const note = std.math.clamp(midi_note, 0, 127);
        const frequency = 440.0 * std.math.pow(f32, 2.0, (@as(f32, @floatFromInt(note)) - 69.0) / 12.0);
        const pan = std.math.clamp(pan_value, 0, 1);
        slot.* = .{
            .step = frequency / sample_rate,
            .gain_left = (1.0 - pan) * 0.22,
            .gain_right = pan * 0.22,
            .remaining = @intCast(sample_rate / 14 + @mod(sample_id, 5) * (sample_rate / 70)),
            .waveform = @intCast(@mod(sample_id, 3)),
        };
    }

    fn closeMusicUnlocked(self: *Audio) void {
        if (self.music) |music| _ = c.sf_close(music);
        self.music = null;
        self.music_info = std.mem.zeroes(c.SF_INFO);
    }

    fn mix(self: *Audio, samples: []f32) void {
        @memset(samples, 0);
        const frames = samples.len / channel_count;
        self.mixMusic(samples, frames);
        for (&self.voices) |*voice| {
            if (voice.remaining == 0) continue;
            const count = @min(frames, voice.remaining);
            for (0..count) |frame| {
                const wave = switch (voice.waveform) {
                    0 => @sin(voice.phase * std.math.tau),
                    1 => if (voice.phase < 0.5) @as(f32, 1) else -1,
                    else => 2.0 * @abs(2.0 * voice.phase - 1.0) - 1.0,
                };
                samples[frame * 2] += wave * voice.gain_left;
                samples[frame * 2 + 1] += wave * voice.gain_right;
                voice.phase = @mod(voice.phase + voice.step, 1.0);
            }
            voice.remaining -= count;
        }
        for (samples) |*sample| sample.* = std.math.clamp(sample.* * self.volume, -1, 1);
    }

    fn mixMusic(self: *Audio, output: []f32, frames: usize) void {
        const music = self.music orelse return;
        const source_channels: usize = @intCast(@max(self.music_info.channels, 1));
        if (source_channels > 8) return;
        var decoded: [1024 * 8]f32 = undefined;
        var destination_frame: usize = 0;
        while (destination_frame < frames) {
            const wanted = @min(frames - destination_frame, 1024);
            var got = c.sf_readf_float(music, &decoded, @intCast(wanted));
            if (got == 0) {
                if (c.sf_seek(music, 0, c.SEEK_SET) < 0) break;
                got = c.sf_readf_float(music, &decoded, @intCast(wanted));
            }
            if (got <= 0) break;
            for (0..@intCast(got)) |frame| {
                const left = decoded[frame * source_channels];
                const right = if (source_channels > 1) decoded[frame * source_channels + 1] else left;
                output[(destination_frame + frame) * 2] += left;
                output[(destination_frame + frame) * 2 + 1] += right;
            }
            destination_frame += @intCast(got);
        }
    }
};

fn audioCallback(userdata: ?*anyopaque, stream: [*c]u8, length: c_int) callconv(.c) void {
    const self: *Audio = @ptrCast(@alignCast(userdata orelse return));
    const byte_count: usize = @intCast(@max(length, 0));
    const samples: [*]f32 = @ptrCast(@alignCast(stream));
    self.mix(samples[0 .. byte_count / @sizeOf(f32)]);
}
