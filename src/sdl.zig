
const std = @import("std");
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const EventType = enum (c.SDL_EventType) {
    invalid,
    quit = c.SDL_QUIT,
    keydown = c.SDL_KEYDOWN,
    keyup = c.SDL_KEYUP,
    _,
};

pub const Event = union(EventType) {
    invalid: void,
    quit: c.SDL_QuitEvent,
    keydown: c.SDL_KeyboardEvent,
    keyup: c.SDL_KeyboardEvent,
};

pub fn pollEvent() ?Event {
    var e: c.SDL_Event = undefined;
    return if (c.SDL_PollEvent(&e) != 0) switch (@as(EventType, @enumFromInt(e.type))) {
        .quit => .{ .quit = e.quit },
        .keydown => .{ .keydown = e.key },
        .keyup => .{ .keyup = e.key },
        else => .{ .invalid = {} },
    } else null;
}

pub fn vsync() error{FailedVsync}!void {
    if (c.SDL_GL_SetSwapInterval(1) < 0) return error.FailedVsync; 
}

pub fn init() void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) unreachable;
}

pub fn deinit() void {
    c.SDL_Quit();
}

pub const Window = struct {
    handle: *c.SDL_Window,

    const WindowInitOptions = struct {
        title: [:0]const u8,
        position: struct {
            x: c_int,
            y: c_int,
        } = .{
            .x = c.SDL_WINDOWPOS_UNDEFINED,
            .y = c.SDL_WINDOWPOS_UNDEFINED,
        },
        size: struct {
            width: c_int,
            height: c_int,
        },
        flags: u32 = 0,
    };

    pub fn init(desc: WindowInitOptions) ?Window {
        return .{
            .handle = c.SDL_CreateWindow(
                desc.title,
                desc.position.x,
                desc.position.y,
                desc.size.width,
                desc.size.height,
                desc.flags,
            ) orelse return null,
        };
    }

    pub fn deinit(self: Window) void {
        c.SDL_DestroyWindow(self.handle);
    }

    pub fn context(self: Window) ?c.SDL_GLContext {
        return c.SDL_GL_CreateContext(self.handle);
    }

    pub fn swap(self: Window) void {
        c.SDL_GL_SwapWindow(self.handle);
    }
};

pub fn fail(msg: []const u8) noreturn {
    std.log.scoped(.sdl2).err("{s}: {s}\n", .{ msg, c.SDL_GetError() });
    std.os.exit(1);
}
