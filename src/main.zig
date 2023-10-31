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

        pub const Parameter = enum(c.GLenum) {
            shader_type = c.GL_SHADER_TYPE,
            delete_status = c.GL_DELETE_STATUS,
            compile_status = c.GL_COMPILE_STATUS,
            info_log_length = c.GL_INFO_LOG_LENGTH,
            shader_source_length = c.GL_SHADER_SOURCE_LENGTH,
        };

        const log = std.log.scoped(.opengl);

        pub fn iv(id: c.GLuint, p: Parameter) c.GLint {
            var ret: c.GLint = undefined;
            c.glGetShaderiv(id, @intFromEnum(p), &ret);
            return ret;
        }

        pub fn infoLog(id: c.GLuint) void {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer std.debug.assert(gpa.deinit() == .ok);

            var buffer: []u8 = gpa.allocator().alloc(u8, @intCast(iv(id, .info_log_length))) catch unreachable;
            defer gpa.allocator().free(buffer);

            var length: c.GLint = 0;

            c.glGetShaderInfoLog(
                id,
                @intCast(buffer.len),
                &length,
                @ptrCast(buffer),
            );

            log.info("{s}: {s}\n", .{
                std.enums.tagName(ShaderType, shader_type).?,
                buffer,
            });
        }

        pub fn init(source: [:0]const u8) Error!Self {
            const id = c.glCreateShader(@intFromEnum(shader_type));

            c.glShaderSource(id, 1, @ptrCast(&source), null);
            c.glCompileShader(id);

            // TODO: make iv return different types based on param, or separate into a bunch of functions.
            if (!switch (iv(id, .compile_status)) {
                c.GL_TRUE => true,
                c.GL_FALSE => false,
                else => unreachable,
            }) {
                infoLog(id);
                return error.CompilationFailed;
            }

            return .{ .id = id };
        }
    };
}

const Program = struct {
    id: u32,
    fragment: Shader(.fragment),
    vertex: Shader(.vertex),

    pub const Error = error{
        LinkageFailed,
        InvalidOperation,
        InvalidValue,
    };

    const Self = @This();

    pub inline fn use(self: Self) void {
        c.glUseProgram(self.id);
    }

    pub fn getAttribute(self: Self, name: [:0]const u8, comptime T: type) ?Attribute(T) {
        const attribute = c.glGetAttribLocation(self.id, name);
        return if (attribute < 0) null else .{ .id = @intCast(attribute) };
    }

    pub fn uniform(self: Self, uniforms: anytype) void {
        const fields = @typeInfo(@TypeOf(uniforms)).Struct.fields;
        inline for (fields) |field| {
            const id = c.glGetUniformLocation(self.id, @as([:0]const u8, field.name ++ "\x00"));
            const v = @field(uniforms, field.name);

            switch (field.type) {
                i32 => c.glUniform1i(id, v),
                f32 => c.glUniform1f(id, v),

                [1]i32, @Vector(1, i32) => c.glUniform1i(id, v[0]),
                [2]i32, @Vector(2, i32) => c.glUniform2i(id, v[0], v[1]),
                [3]i32, @Vector(3, i32) => c.glUniform3i(id, v[0], v[1], v[2]),
                [4]i32, @Vector(4, i32) => c.glUniform4i(id, v[0], v[1], v[2], v[3]),

                [1]f32, @Vector(1, f32) => c.glUniform1f(id, v[0]),
                [2]f32, @Vector(2, f32) => c.glUniform2f(id, v[0], v[1]),
                [3]f32, @Vector(3, f32) => c.glUniform3f(id, v[0], v[1], v[2]),
                [4]f32, @Vector(4, f32) => c.glUniform4f(id, v[0], v[1], v[2], v[3]),

                [2][2]f32 => c.glUniformMatrix2fv(id, 1, c.GL_FALSE, @ptrCast(&v)),
                [3][3]f32 => c.glUniformMatrix3fv(id, 1, c.GL_FALSE, @ptrCast(&v)),
                [4][4]f32 => c.glUniformMatrix4fv(id, 1, c.GL_FALSE, @ptrCast(&v)),
                else => @compileError(@typeName(field.type) ++ " not a valid uniform type."),
            }
        }
    }

    const log = std.log.scoped(.opengl);

    pub fn init(vertex: Shader(.vertex), fragment: Shader(.fragment)) Error!Program {
        const id = c.glCreateProgram();

        c.glAttachShader(id, vertex.id);
        c.glAttachShader(id, fragment.id);
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

        pub inline fn deinit(self: Self) void {
            c.glDeleteBuffers(1, @constCast(&self.id));
        }

        pub inline fn bind(self: Self) void {
            c.glBindBuffer(@intFromEnum(target), self.id);
        }

        pub inline fn debind(_: Self) void {
            c.glBindBuffer(@intFromEnum(target), 0);
        }

        pub fn data(self: Self, comptime T: type, slice: []const T, usage: Usage) void {
            self.bind();
            defer self.debind();

            c.glBufferData(@intFromEnum(target), @intCast(@sizeOf(T) * slice.len), slice.ptr, @intFromEnum(usage));
        }
    };
}

pub inline fn debind(target: BufferTarget) void {
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

pub fn Attribute(comptime T: type) type {
    const child, const length = blk: {
        switch (@typeInfo(T)) {
            .Struct => |Struct| {
                inline for (Struct.fields) |field| {
                    if (field.type != Struct.fields[0].type) {
                        @compileError("Struct fields must be all the same type.");
                    }
                }
                break :blk .{ Struct.fields[0].type, Struct.fields.len };
            },
            .Vector, .Array => |List| break :blk .{ List.child, List.len },
            else => @compileError("Type mus be struct, array or vector."),
        }
    };

    return struct {
        id: c.GLuint,

        const Self = @This();

        pub inline fn enable(self: Self) void {
            c.glEnableVertexAttribArray(self.id);
        }

        pub inline fn disable(self: Self) void {
            c.glDisableVertexAttribArray(self.id);
        }

        pub fn buffer(self: Self, array: Buffer(.array)) void {
            array.bind();
            defer array.debind();

            c.glVertexAttribPointer(self.id, length, enumFromType(child), c.GL_FALSE, @sizeOf(T), null);
        }
    };
}

const DrawMode = enum(c.GLenum) {
    points = c.GL_POINTS,
    line_strip = c.GL_LINE_STRIP,
    line_loop = c.GL_LINE_LOOP,
    lines = c.GL_LINES,
    triangle_strip = c.GL_TRIANGLE_STRIP,
    triangle_fan = c.GL_TRIANGLE_FAN,
    triangles = c.GL_TRIANGLES,
    quad_strip = c.GL_QUAD_STRIP,
    quads = c.GL_QUADS,
    polygon = c.GL_POLYGON,
};

pub fn drawElements(mode: DrawMode, count: c_int, t: enum { u8, u16, u32 }, element: Buffer(.element)) void {
    element.bind();
    defer element.debind();

    c.glDrawElements(@intFromEnum(mode), count, switch (t) {
        .u8 => c.GL_UNSIGNED_BYTE,
        .u16 => c.GL_UNSIGNED_SHORT,
        .u32 => c.GL_UNSIGNED_INT,
    }, null);
}

fn sdlCreateWindow(args: WindowDesc) ?*c.SDL_Window {
    return c.SDL_CreateWindow(
        args.title,
        args.position.x,
        args.position.y,
        args.size.width,
        args.size.height,
        args.flags,
    );
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
        else => @compileError(@typeName(T) ++ " not a valid OpenGL type"),
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) unreachable;
    defer c.SDL_Quit();

    const win = sdlCreateWindow(.{
        .title = "Zig OpenGL",
        .size = .{ .width = 500, .height = 500 },
        .flags = c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_ALLOW_HIGHDPI,
    }) orelse sdlFail("Failed to create window");
    defer c.SDL_DestroyWindow(win);

    if (c.SDL_GL_CreateContext(win) == null) sdlFail("Failed to create glcontext");
    if (c.SDL_GL_SetSwapInterval(1) < 0) sdlFail("Failed to set Vsync");

    const vs = try Shader(.vertex).init(
        \\#version 150 core
        \\
        \\in vec2 position;
        \\in vec2 uv;
        \\
        \\uniform float elapsed;
        \\uniform mat3 matrix;
        \\
        \\out vec4 vcolor;
        \\
        \\void main() {
        \\    gl_Position = vec4(
        \\        vec3(position + vec2(cos(elapsed/5), sin(elapsed/5)) * 0.5, 0.0) * 0.5 * matrix,
        \\        1.0);
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
        \\    gl_FragColor = vcolor * (sin(elapsed*2)+1)/2;
        \\}
    );

    const program = try Program.init(vs, fs);

    const index = Buffer(.element).init();
    defer index.deinit();
    index.data(u32, &[_]u32{ 0, 2, 3, 0, 1, 3 }, .static_read);

    const Position = struct { f32, f32 };
    const Uv = struct { f32, f32 };

    const pos = Buffer(.array).init();
    defer pos.deinit();
    pos.data(f32, &[_]f32{ -0.5, -0.5, 0.5, -0.5, -0.5, 0.5, 0.5, 0.5 }, .static_draw);

    const apos = program.getAttribute("position", Position).?;
    apos.buffer(pos);

    const uv = Buffer(.array).init();
    defer uv.deinit();
    uv.data(f32, &[_]f32{ 0, 0, 1, 0, 0, 1, 1, 1 }, .static_draw);

    const auv = program.getAttribute("uv", Uv).?;
    auv.buffer(uv);

    apos.enable();
    auv.enable();

    const Timer = std.time.Timer;
    var timer = try Timer.start();

    var ev: c.SDL_Event = undefined;
    main: while (true) {
        while (c.SDL_PollEvent(&ev) != 0) switch (ev.type) {
            c.SDL_QUIT => break :main,
            else => {},
        };

        c.glClearColor(0, 0, 0, 255);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        const time: f32 = std.math.lossyCast(f32, timer.read()) / std.time.ns_per_s;
        program.use();
        program.uniform(.{
            .elapsed = time,
            .matrix = [3][3]f32{
                .{ std.math.cos(time), std.math.sin(time), 0 },
                .{ std.math.sin(time), -std.math.cos(time), 0 },
                .{ 0, 0, 1 },
            },
        });
        drawElements(.triangles, 6, .u32, index);

        c.SDL_GL_SwapWindow(win);
    }
}
