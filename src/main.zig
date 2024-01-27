const std = @import("std");
const gl = @import("gl.zig");
const sdl = @import("sdl.zig");
const qoi = @import("qoiz");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    sdl.init();
    defer sdl.deinit();

    const win = sdl.Window.init(.{
        .title = "Zig OpenGL",
        .size = .{ .width = 500, .height = 500 },
        .flags = sdl.c.SDL_WINDOW_OPENGL | sdl.c.SDL_WINDOW_ALLOW_HIGHDPI,
    }) orelse sdl.fail("Failed to create window");
    defer win.deinit();

    if (win.context() == null) sdl.fail("Failed to create glcontext");
    sdl.vsync() catch sdl.fail("Failed to set Vsync");

    const vs = try gl.Shader(.vertex).init(
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
        \\    // gl_Position = vec4(
        \\    //     vec3(position + vec2(cos(elapsed/5), sin(elapsed/5)) * 0.5, 0.0) * 0.5 * matrix,
        \\    //     1.0);
        \\    gl_Position = vec4((position * 2) , 1, 1);
        \\    vcolor = vec4(uv, 0.0, 1.0);
        \\}
    );
    defer vs.deinit();

    const fs = try gl.Shader(.fragment).init(
        \\#version 150 core
        \\
        \\uniform float elapsed;
        \\in vec4 vcolor;
        \\
        \\uniform sampler2D tex;
        \\
        \\void main() {
        \\    gl_FragColor = texture(tex, vcolor.xy); // * vcolor * (sin(elapsed*2)+1)/2;
        \\}
    );
    defer vs.deinit();

    const program = try gl.Program.init(vs, fs);
    defer program.deinit();

    const file = @embedFile("zero.qoi");
    var image = try qoi.Image(.rgba).init(gpa.allocator(), file);

    image.flipY();
    defer image.deinit();

    gl.enable(.{ .blend = true });
    gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

    var texture = try gl.Texture.init(0, .{
        .filter = .{ .min = .linear, .mag = .linear },
        .image = &image,
    });
    defer texture.deinit();

    const index = gl.Buffer(.element).init();
    defer index.deinit();
    index.data(u32, &[_]u32{ 0, 2, 3, 0, 1, 3 }, .static_read);

    const Position = @Vector(2, f32);
    const Uv = @Vector(2, f32);

    const pos = gl.Buffer(.array).init();
    defer pos.deinit();
    pos.data(f32, &[_]f32{ -0.5, -0.5, 0.5, -0.5, -0.5, 0.5, 0.5, 0.5 }, .static_draw);

    const apos = program.getAttribute("position", Position).?;
    apos.buffer(pos);

    const uv = gl.Buffer(.array).init();
    defer uv.deinit();
    uv.data(f32, &[_]f32{ 0, 0, 1, 0, 0, 1, 1, 1 }, .static_draw);

    const auv = program.getAttribute("uv", Uv).?;
    auv.buffer(uv);

    apos.enable();
    auv.enable();

    var timer = try std.time.Timer.start();

    main: while (true) {
        while (sdl.pollEvent()) |e| switch (e) {
            .quit => break :main,
            .keyup => |k| switch (k.keysym.sym) {
                sdl.c.SDLK_ESCAPE => break :main,
                else => {},
            },
            else => {},
        };

        gl.clearColor(0xff, 0xff, 0xff, 0xff);
        gl.clear();

        const elapsed: f32 = std.math.lossyCast(f32, timer.read()) / std.time.ns_per_s;
        const cos = std.math.cos;
        const sin = std.math.sin;

        program.use();
        program.uniform(.{
            .elapsed = elapsed,
            .tex = texture,
            .matrix = [3][3]f32{
                .{ cos(elapsed), sin(elapsed), 0 },
                .{ sin(elapsed), -cos(elapsed), 0 },
                .{ 0, 0, 1 },
            },
        });
        gl.drawElements(.triangles, 6, .u32, index);

        win.swap();
    }
}
