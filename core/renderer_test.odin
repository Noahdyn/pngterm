package term_renderer

import "core:image/png"
import "core:strings"
import "core:testing"

@(test)
test_draw_pixel_relative_transparent :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	draw_pixel_relative(Pixel{0, 0, 0, 0}, true, &b)
	testing.expect_value(t, strings.to_string(b), " ")
}

@(test)
test_draw_pixel_relative_colored :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	draw_pixel_relative(Pixel{255, 0, 0, 255}, true, &b)
	testing.expect_value(t, strings.to_string(b), "\033[38;2;255;0;0m▀\033[0m")
}

@(test)
test_draw_combined_pixels_both_transparent :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	draw_combined_pixels_relative(Pixel{0, 0, 0, 0}, Pixel{0, 0, 0, 0}, &b)
	testing.expect_value(t, strings.to_string(b), " ")
}

@(test)
test_generate_ansi_output_for_different_scales :: proc(t: ^testing.T) {
	Expected_Fixture :: struct {
		width, height: int,
		data:          string,
	}

	fixtures := [?]Expected_Fixture {
		{2, 2, #load("../fixtures/2x2.expected", string)},
		{4, 4, #load("../fixtures/4x4.expected", string)},
		{5, 5, #load("../fixtures/5x5.expected", string)},
		{8, 8, #load("../fixtures/8x8.expected", string)},
	}

	png_opts := png.Options{.return_metadata}
	test_img, err := png.load("fixtures/4x4_test_fixture.png", png_opts)
	if err != nil {
		testing.fail(t)
		return
	}
	defer png.destroy(test_img)

	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)

	for fixture in fixtures {
		opts := Options {
			width  = fixture.width,
			height = fixture.height,
		}
		pixels := generate_pixels(test_img, fixture.height, fixture.width)
		build_ansi_output(&b, pixels, opts, fixture.height, fixture.width)

		testing.expect_value(t, strings.to_string(b), fixture.data)
		strings.builder_reset(&b)
	}
}
