const std = @import("std");
const Image = @import("qoiz").Image;
pub const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", {});
    @cInclude("GL/gl.h");
});

pub const Texture = struct {
    id: c.GLuint,

    pub const WrapType = enum (c.GLint) {
        clamp_to_edge = c.GL_CLAMP_TO_EDGE,
        mirrored_repeat = c.GL_MIRRORED_REPEAT,
        repeat = c.GL_REPEAT,
    };

    pub const MagType = enum (c.GLint) {
        nearest = c.GL_NEAREST,
        linear = c.GL_LINEAR,
    };

    pub const MinType = enum (c.GLint) {
        nearest = c.GL_NEAREST,
        linear = c.GL_LINEAR,
    };

    pub const Format = enum (c.GLint) {
        alpha = c.GL_ALPHA,
        rgb = c.GL_RGB,
        rgba = c.GL_RGBA,
        luminance = c.GL_LUMINANCE,
        luminance_alpha = c.GL_LUMINANCE_ALPHA,
    };

    pub const TextureInitOptions = struct {
        filter: struct {
            min: MinType = .nearest,
            mag: MagType = .nearest,
        } = .{ .min = .nearest, .mag = .nearest },
        wrap: struct {
            s: WrapType = .clamp_to_edge,
            t: WrapType = .clamp_to_edge,
        } = .{ .s = .clamp_to_edge, .t = .clamp_to_edge },
        image: *Image(.rgba),
    };

    pub fn init(options: TextureInitOptions) !Texture {
        var id: c.GLuint = undefined;
        c.glGenTextures(1, &id);

        c.glActiveTexture(c.GL_TEXTURE0);
        c.glBindTexture(c.GL_TEXTURE_2D, id);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, @intFromEnum(options.filter.min));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, @intFromEnum(options.filter.mag));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_S, @intFromEnum(options.wrap.s));
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_WRAP_T, @intFromEnum(options.wrap.t));

        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA,
            @intCast(options.image.width),
            @intCast(options.image.height),
            0,
            c.GL_RGBA,
            enumFromType(u8),
            @ptrCast(options.image.pixels),
        );

        return .{
            .id = id,
        };
    }
};

pub const ShaderType = enum(u32) {
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

            var buffer = gpa.allocator().alloc(u8, @intCast(iv(id, .info_log_length))) catch unreachable;
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

pub const Program = struct {
    id: u32,
    fragment: Shader(.fragment),
    vertex: Shader(.vertex),

    pub const Error = error{
        LinkageFailed,
        InvalidOperation,
        InvalidValue,
    };

    pub inline fn use(self: Program) void {
        c.glUseProgram(self.id);
    }

    pub fn getAttribute(self: Program, name: [:0]const u8, comptime T: type) ?Attribute(T) {
        const attribute = c.glGetAttribLocation(self.id, name);
        return if (attribute < 0) null else .{ .id = @intCast(attribute) };
    }

    pub fn uniform(self: Program, uniforms: anytype) void {
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

pub const BufferTarget = enum(u32) {
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

pub fn Attribute(comptime T: type) type {
    const child, const length = blk: {
        switch (@typeInfo(T)) {
            .Vector => |Vector| break :blk .{ Vector.child, Vector.len },
            .Array => |Array| break :blk .{ Array.child, Array.len },
            else => @compileError("Expected array or vector, found " ++ @typeName(T)),
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

pub const DrawMode = enum(c.GLenum) {
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

pub fn enumFromType(comptime T: type) c.GLenum {
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

pub fn clearColor(r: f32, g: f32, b: f32, a: f32) void {
    c.glClearColor(r, g, b, a);
}

pub fn clear() void {
    c.glClear(c.GL_COLOR_BUFFER_BIT);
}
