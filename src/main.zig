const std = @import("std");
const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", {});
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_opengl.h");
    @cInclude("GL/gl.h");
});

const ShaderType = enum(u32) {
    vertex = c.GL_VERTEX_SHADER,
    fragment = c.GL_FRAGMENT_SHADER,
};

pub fn Shader(comptime shader_type: ShaderType) type {
    return struct {
        id: u32,

        const Self = @This();

        pub const Error = error{
            InvalidOperation,
            CompilationFailed,
        };

        const log = std.log.scoped(.opengl);

        pub fn init(source: [:0]const u8) Error!Self {
            const id = c.glCreateShader(@intFromEnum(shader_type));
            if (id == 0) return switch (c.glGetError()) {
                c.GL_INVALID_OPERATION => Error.InvalidOperation,
                else => unreachable,
            };

            c.glShaderSource(id, 1, @ptrCast(&source), null);
            c.glCompileShader(id);

            var compiled: c.GLint = undefined;
            c.glGetShaderiv(id, c.GL_COMPILE_STATUS, &compiled);

            if (compiled == c.GL_FALSE) {
                var length: c_int = 0;
                var buffer = [_]u8{0} ** 1024;

                c.glGetShaderInfoLog(id, buffer.len, &length, @ptrCast(&buffer));
                log.info("Shader: {s}\n", .{buffer[0..@intCast(length)]});

                return Error.CompilationFailed;
            }

            return .{ .id = id };
        }
    };
}

const Program = struct {
    id: u32,
    fragment: Shader(.fragment),
    vertex: Shader(.vertex),

    pub const Error = error{ LinkageFailed, InvalidOperation, InvalidValue };

    const Self = @This();

    pub fn use(self: Self) void {
        c.glUseProgram(self.id);
    }

    pub fn getAttribute(self: Self, name: [:0]const u8, comptime T: type) error{BadAttribute}!Attribute(T) {
        comptime std.debug.assert(std.meta.trait.is(.Struct)(T));
        const fields = std.meta.fields(T);
        inline for (fields) |field| {
            if (field.type != fields[0].type) @compileError("Struct fields must be all the same type.");
        }

        const attribute = c.glGetAttribLocation(self.id, name);
        if (attribute < 0) return error.BadAttribute;

        return .{ .id = @intCast(attribute) };
    }

    pub fn getUniform(self: Self, name: [:0]const u8, comptime T: type) Uniform(T) {
        return .{ .id = c.glGetUniformLocation(self.id, name) };
    }

    const log = std.log.scoped(.opengl);

    pub fn init(vertex: Shader(.vertex), fragment: Shader(.fragment)) Error!Program {
        const id = c.glCreateProgram();

        c.glAttachShader(id, vertex.id);
        switch (c.glGetError()) {
            c.GL_INVALID_VALUE => return error.InvalidValue,
            c.GL_INVALID_OPERATION => return error.InvalidOperation,
            else => {},
        }

        c.glAttachShader(id, fragment.id);
        switch (c.glGetError()) {
            c.GL_INVALID_VALUE => return error.InvalidValue,
            c.GL_INVALID_OPERATION => return error.InvalidOperation,
            else => {},
        }

        c.glLinkProgram(id);

        var linked: c.GLint = undefined;
        c.glGetProgramiv(id, c.GL_LINK_STATUS, &linked);

        if (linked != c.GL_TRUE) {
            var length: c_int = undefined;
            var buffer = [_]u8{0} ** 1024;

            c.glGetProgramInfoLog(id, buffer.len, &length, @ptrCast(&buffer));
            log.info("{s}\n", .{buffer[0..@intCast(length)]});

            return error.LinkageFailed;
        }

        return Program{
            .id = id,
            .fragment = fragment,
            .vertex = vertex,
        };
    }
};

const BufferTarget = enum(u32) {
    array = c.GL_ARRAY_BUFFER,
    element = c.GL_ELEMENT_ARRAY_BUFFER,
};

pub fn Buffer(comptime target: BufferTarget) type {
    return struct {
        id: u32,

        const Self = @This();

        pub const Usage = enum(u32) {
            stream_draw = c.GL_STREAM_DRAW,
            stream_read = c.GL_STREAM_READ,
            stream_copy = c.GL_STREAM_COPY,
            static_draw = c.GL_STATIC_DRAW,
            static_read = c.GL_STATIC_READ,
            static_copy = c.GL_STATIC_COPY,
            dynamic_draw = c.GL_DYNAMIC_DRAW,
            dynamic_read = c.GL_DYNAMIC_READ,
            dynamic_copy = c.GL_DYNAMIC_COPY,
        };

        pub fn init() Self {
            var id: c.GLuint = undefined;
            c.glGenBuffers(1, &id);

            return .{ .id = id };
        }

        pub fn deinit(self: Self) void {
            c.glGenBuffers(1, @constCast(&self.id));
        }

        pub fn data(self: Self, comptime T: type, slice: []const T, usage: Usage) void {
            self.bind();
            c.glBufferData(@intFromEnum(target), @intCast(@sizeOf(T) * slice.len), slice.ptr, @intFromEnum(usage));
            unbind(target);
        }

        pub fn bind(self: Self) void {
            c.glBindBuffer(@intFromEnum(target), self.id);
        }
    };
}

pub fn unbind(target: BufferTarget) void {
    c.glBindBuffer(@intFromEnum(target), 0);
}

fn sdlFail(msg: []const u8) noreturn {
    std.log.scoped(.sdl2).err("{s}: {s}\n", .{ msg, c.SDL_GetError() });
    std.os.exit(1);
}

const WindowDesc = struct {
    title: [:0]const u8,
    position: struct {
        x: c_int,
        y: c_int,
    } = .{ .x = c.SDL_WINDOWPOS_UNDEFINED, .y = c.SDL_WINDOWPOS_UNDEFINED},
    size: struct {
        w: c_int,
        h: c_int,
    },
    flags: u32 = 0,
};

pub fn Attribute(comptime T: type) type {
    return struct {
        id: c.GLuint,

        const Self = @This();

        pub fn enable(self: Self) void {
            c.glEnableVertexAttribArray(self.id);
        }

        pub fn buffer(self: Self, buf: Buffer(.array)) void {
            const fields = std.meta.fields(T);

            buf.bind();
            c.glVertexAttribPointer(self.id, fields.len, enumFromType(fields[0].type), c.GL_FALSE, @sizeOf(T), null);
            unbind(.array);
        }
    };
}

pub fn Uniform(comptime _: type) type {
    return struct {
        id: c.GLint,
    };
}

fn sdlCreateWindow(args: WindowDesc) ?*c.SDL_Window {
    return @call(.auto, c.SDL_CreateWindow, .{
        args.title,
        args.position.x,
        args.position.y,
        args.size.w,
        args.size.h,
        args.flags
    });
}

fn enumFromType(comptime T: type) c.GLenum {
    return switch (T) {
        u8 => c.GL_UNSIGNED_BYTE,
        i8 => c.GL_BYTE,
        u16 => c.GL_UNSIGNED_SHORT,
        i16 => c.GL_SHORT,
        u32 => c.GL_UNSIGNED_INT,
        i32 => c.GL_INT,
        f32 => c.GL_FLOAT,
        f64 => c.GL_DOUBLE,
        else => @compileError(@typeName(T) ++ "not valid OpenGL type.")
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 16);

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) unreachable;
    defer c.SDL_Quit();

    const win = sdlCreateWindow(.{
        .title = "Zig Test",
        .size = .{ .w = 500, .h = 500 },
        .flags = c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_ALLOW_HIGHDPI,
    }) orelse sdlFail("Failed to create window");
    defer c.SDL_DestroyWindow(win);

    if (c.SDL_GL_CreateContext(win) == null) sdlFail("Failed to create glcontext");
    if (c.SDL_GL_SetSwapInterval(1) < 0) sdlFail("Failed to set Vsync");

    c.glEnable(c.GL_MULTISAMPLE);

    const vs = try Shader(.vertex).init(
        \\#version 150 core
        \\
        \\in vec2 position;
        \\in vec2 uv;
        \\
        \\out vec4 vcolor;
        \\
        \\void main() {
        \\    gl_Position = vec4(position * 2 - 1, 0.0, 1.0);
        \\    vcolor = vec4(uv, 0.0, 1.0);
        \\}
    );

    const fs = try Shader(.fragment).init(
        \\#version 150 core
        \\
        \\uniform float elapsed;
        \\in vec4 vcolor;
        \\
        \\void main() {
        \\    gl_FragColor = vcolor * (elapsed);
        \\}
    );

    const program = try Program.init(vs, fs);

    const index = Buffer(.element).init();
    defer index.deinit();
    index.data(i32, &[_]i32{ 0, 2, 3, 0, 1, 3 }, .static_read);
    index.bind(); // if not present, the program segfaults

    const Position = struct { f32, f32 };
    const Uv = struct { f32, f32 };

    const pos = Buffer(.array).init();
    defer pos.deinit();
    pos.data(f32, &[_]f32{ 0, 0, 1, 0, 0, 1, 1, 1 }, .static_draw);

    const apos = try program.getAttribute("position", Position);
    apos.buffer(pos);

    const uv = Buffer(.array).init();
    defer uv.deinit();
    uv.data(f32, &[_]f32{ 0, 0, 1, 0, 0, 1, 1, 1 }, .static_draw);

    const auv = try program.getAttribute("uv", Uv);
    auv.buffer(uv);

    apos.enable();
    auv.enable();

    const elapsed = program.getUniform("elapsed", struct{f32});

    var ev: c.SDL_Event = undefined;
    main: while (true) {
        while (c.SDL_PollEvent(&ev) != 0) switch (ev.type) {
            c.SDL_QUIT => break :main,
            else => {},
        };

        c.glClearColor(0, 0, 0, 255);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        program.use();
        c.glUniform1f(elapsed.id, std.math.tau);
        c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);

        c.SDL_GL_SwapWindow(win);
    }
}
