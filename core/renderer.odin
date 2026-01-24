package term_renderer
import "core:fmt"
import "core:image/png"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sys/posix"

@(private)
Pixel :: struct {
	r, g, b, a: u8,
}

Options :: struct {
	x:        int `args:"name=x"`,
	y:        int `args:"name=y"`,
	width:    int `args:"name=width"`,
	height:   int `args:"name=height"`,
	file:     string `args:"name=file, required"`,
	absolute: bool `args:"name=absolute,ind=a"`,
}

//optimizations i want to do: 
// 1. do not emit reset after every pixel, but rather after each line or sth.
// dont emit color change if color between 2 pixels stays the same
render_png :: proc(opts := Options{}) -> (ok: bool) {

	err: png.Error
	img: ^png.Image
	png_opts := png.Options{.return_metadata, .alpha_add_if_missing}

	img, err = png.load(opts.file, png_opts)
	defer png.destroy(img)


	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	target_width := img.width
	target_height := img.height

	if opts.width != 0 {
		target_width = opts.width
		scale_x := f32(target_width) / f32(img.width)
	}
	if opts.height != 0 {
		target_height = opts.height
		scale_y := f32(target_height) / f32(img.height)
	}

	estimated_size := target_width * ((target_height + 1) / 2) * 50
	strings.builder_grow(&b, estimated_size)

	pixels := generate_pixels(img, target_height, target_width)
	build_ansi_output(&b, pixels, opts, target_height, target_width)

	output := strings.to_string(b)
	data := transmute([]u8)output
	total_written := 0
	for total_written < len(data) {
		n, err := os.write(os.stdout, data[total_written:])
		if err != os.ERROR_NONE || n <= 0 {
			break
		}
		total_written += n
	}
	return true
}

generate_pixels :: proc(img: ^png.Image, height, width: int) -> []Pixel {
	original_pixels := ([^]Pixel)(raw_data(img.pixels.buf))[:len(img.pixels.buf) / 4]
	pixels: []Pixel
	if width != img.width || height != img.height {
		pixel_length := width * height
		//where do I free this?
		pixels = make([]Pixel, pixel_length)
		for y in 0 ..< height {
			for x in 0 ..< width {
				idx := (y * width) + x
				u := f32(x) / f32(width)
				v := f32(y) / f32(height)

				src_x := min(i32(u * f32(img.width)), i32(img.width - 1))
				src_y := min(i32(v * f32(img.height)), i32(img.height - 1))
				src_idx := (src_y * i32(img.width)) + src_x

				pixels[idx] = original_pixels[src_idx]

			}
		}

	} else {
		pixels = original_pixels
	}
	return pixels
}

build_ansi_output :: proc(
	b: ^strings.Builder,
	pixels: []Pixel,
	opts: Options,
	height, width: int,
) {

	terminal_rows := (height + 2 - 1) / 2

	if !opts.absolute {
		for i in 1 ..= terminal_rows {
			if opts.x > 0 {
				fmt.sbprintf(b, "\033[%dC", opts.x)
			}

			for j in 0 ..< width {
				png_pixel_row := i * 2 - 1
				pixel_1 := pixels[j + (png_pixel_row - 1) * width]

				if height % 2 != 0 && i == terminal_rows {
					draw_pixel_relative(pixel_1, true, b) // upper only
				} else {
					png_pixel_row += 1
					pixel_2 := pixels[j + (png_pixel_row - 1) * width]
					draw_combined_pixels_relative(pixel_1, pixel_2, b)
				}
			}

			if i < terminal_rows {
				fmt.sbprintln(b)
			}
		}
		fmt.sbprintln(b)
	} else {
		for i in 1 ..= terminal_rows {
			for j in 0 ..< width {
				png_pixel_row := i * 2 - 1
				pixel_1 := pixels[j + (png_pixel_row - 1) * width]

				if height % 2 != 0 && i == terminal_rows {
					draw_upper_quadrant_only(j + 1 + opts.x, i + opts.y, pixel_1, b)
				} else {
					png_pixel_row += 1
					pixel_2 := pixels[j + (png_pixel_row - 1) * width]
					draw_combined_pixels_absolute(j + 1 + opts.x, i + opts.y, pixel_1, pixel_2, b)
				}
			}
		}
		fmt.println()
	}
}

@(private)
draw_upper_quadrant_only :: proc(x, y: int, pixel: Pixel, b: ^strings.Builder) {
	if pixel.a == 0 {
		return
	}
	fmt.sbprintf(b, "\033[%v;%vH\033[38;2;%v;%v;%vm▀\033[0m", y, x, pixel.r, pixel.g, pixel.b)

}

@(private)
draw_lower_quadrant_only :: proc(x, y: int, pixel: Pixel, b: ^strings.Builder) {
	if pixel.a == 0 {
		return
	}
	fmt.sbprintf(b, "\033[%v;%vH\033[38;2;%v;%v;%vm▄\033[0m", y, x, pixel.r, pixel.g, pixel.b)
}

@(private)
draw_combined_pixels_absolute :: proc(x, y: int, top, bottom: Pixel, b: ^strings.Builder) {
	if top.a == 0 && bottom.a == 0 {
		// draw nothing
	} else if top.a == 0 {
		draw_lower_quadrant_only(x, y, bottom, b)
	} else if bottom.a == 0 {
		draw_upper_quadrant_only(x, y, top, b)
	} else {
		fmt.sbprintf(
			b,
			"\033[%v;%vH\033[38;2;%v;%v;%vm\033[48;2;%v;%v;%vm▀\033[0m",
			y,
			x,
			top.r,
			top.g,
			top.b,
			bottom.r,
			bottom.g,
			bottom.b,
		)
	}
}

@(private)
draw_pixel_relative :: proc(pixel: Pixel, upper: bool, b: ^strings.Builder) {
	if pixel.a == 0 {
		fmt.sbprintf(b, " ")
	} else {
		char := upper ? "▀" : "▄"
		fmt.sbprintf(b, "\033[38;2;%v;%v;%vm%s\033[0m", pixel.r, pixel.g, pixel.b, char)
	}
}

@(private)
draw_combined_pixels_relative :: proc(top, bottom: Pixel, b: ^strings.Builder) {
	if top.a == 0 && bottom.a == 0 {
		fmt.sbprintf(b, " ")
	} else if top.a == 0 {
		fmt.sbprintf(b, "\033[38;2;%v;%v;%vm▄\033[0m", bottom.r, bottom.g, bottom.b)
	} else if bottom.a == 0 {
		fmt.sbprintf(b, "\033[38;2;%v;%v;%vm▀\033[0m", top.r, top.g, top.b)
	} else {
		fmt.sbprintf(
			b,
			"\033[38;2;%v;%v;%vm\033[48;2;%v;%v;%vm▀\033[0m",
			top.r,
			top.g,
			top.b,
			bottom.r,
			bottom.g,
			bottom.b,
		)
	}
}

get_cursor_position :: proc() -> (x, y: int) {
	when ODIN_OS == .Linux || ODIN_OS == .Darwin {
		old_termios: posix.termios
		posix.tcgetattr(posix.STDIN_FILENO, &old_termios)
		raw_termios := old_termios
		raw_termios.c_lflag &= ~{.ICANON, .ECHO}
		raw_termios.c_cc[posix.Control_Char.VMIN] = 1
		raw_termios.c_cc[posix.Control_Char.VTIME] = 0
		posix.tcsetattr(posix.STDIN_FILENO, .TCSANOW, &raw_termios)
		fmt.printf("\x1b[6n")
		os.flush(os.stdout)
		buf := [32]u8{}
		total_read := 0
		for total_read < len(buf) {
			n := posix.read(posix.STDIN_FILENO, &buf[total_read], uint(len(buf) - total_read))
			if n <= 0 {
				break
			}
			total_read += int(n)
			if total_read > 0 && buf[total_read - 1] == 'R' {
				break
			}
		}
		posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &old_termios)
		if total_read > 2 && buf[0] == 0x1b && buf[1] == '[' {
			response := string(buf[2:total_read - 1])
			row, col: int
			semicolon_idx := -1
			for i := 0; i < len(response); i += 1 {
				if response[i] == ';' {
					semicolon_idx = i
					break
				}
			}
			if semicolon_idx > 0 {
				for i := 0; i < semicolon_idx; i += 1 {
					row = row * 10 + int(response[i] - '0')
				}
				for i := semicolon_idx + 1; i < len(response); i += 1 {
					col = col * 10 + int(response[i] - '0')
				}
				return col, row
			}
		}
	}
	return 0, 0
}
