package cli

import renderer "../core"
import "core:flags"
import "core:fmt"
import "core:os"

main :: proc() {
	opts: renderer.Options
	file: string
	style: flags.Parsing_Style = .Unix
	parse_err := flags.parse(&opts, os.args[1:], style)
	if parse_err != nil {
		fmt.panicf("Error parsing flags: %v", parse_err)
	}

	renderer.render_png(opts)

}
