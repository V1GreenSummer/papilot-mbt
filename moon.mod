// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "V1GreenSummer/papilot"

version = "0.1.0"

readme = "README.mbt.md"

repository = ""

license = "MIT"

keywords = [ "latex", "pdf", "editor", "ai", "review" ]

preferred_target = "native"

supported_targets = "native"

description = "An AI-facing LaTeX editor engine: work on the PDF, not the .tex."

import {
  "moonbitlang/pdflite@0.4.2",
  "moonbitlang/async@0.22.9",
}
