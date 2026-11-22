# Papilot development guide

This is a [MoonBit](https://docs.moonbitlang.com) project. The engine behind an
AI facing LaTeX editor: the author works on the PDF and never opens a `.tex`
file.

## What the project is

The author marks a place on the typeset page and writes what should change
there. The engine finds the source of that place, compiles the accepted text
and the proposal, compares the two PDFs and shows the difference on the page.
The author accepts, rejects or comments on each change; only the accepted
changes reach the working tree.

The whole flow is built out of small, testable parts:

```
latex    what the source says
pdftext  what the page says
synctex  where the page comes from
diff     what is different
compare  the two together
git      the work, kept apart
build    the typeset result
task     one round of one task
journal  what the author decided
server   the interface
```

## Repository map

| Area | Location |
| --- | --- |
| The LaTeX reader | `latex/` |
| The word comparison | `diff/` |
| The SyncTeX reader | `synctex/` |
| The PDF reader | `pdftext/` |
| The PDF comparison and the locator | `compare/` |
| Git worktrees and snapshots | `git/` |
| The LaTeX build | `build/` |
| Tasks, source edits and rounds | `task/` |
| The decision journal | `journal/` |
| The HTTP interface | `server/` |
| The command line | `cli/`, `cmd/main/` |
| A stand-in for `latexmk` | `examples/fake-latexmk/` |

## Coding conventions

- MoonBit code is organised in block style: every block is separated by `///|`.
- A package owns its types. The functions that belong to a type are methods of
  that type, so `Span::text` reads better than `text_of_span`.
- Keep the public API small. A helper that only one package needs stays
  private to it.
- Every public type that is compared or printed derives `Eq` and
  `@debug.Debug`.
- Errors are values, not panics: a paper under review is usually broken
  somewhere, and the engine has to keep working on the parts that are fine.
- The parsers never reject their input. They record what they recognise and
  ignore the rest.

## Checks

```sh
moon check --target native   # type check
moon test --target native    # run the tests
moon build --target native   # build the command line tool
moon fmt                     # format the code
moon info                    # update the generated interfaces
```

Run the checks for the scope you changed. A change in `latex/` needs the tests
of `latex/`; a change in `server/` needs the tests of `server/` and of
`task/`, because the server drives the tasks.

## Testing

- The tests live next to the code, in `<package>_test.mbt` for the public
  behaviour and `<package>_wbtest.mbt` for the internals.
- A test that needs the file system or a process is an `async test`; the
  packages `moonbitlang/async/fs` and `moonbitlang/async/process` are imported
  for the tests only.
- The tests must not need a Te distribution. The LaTeX build is the one part
  that cannot be tested without one, so `examples/fake-latexmk/latexmk` stands
  in for it: it typesets a `.tex` file with a small PDF writer of its own and
  writes a SyncTeX file next to it. The tests of `task/` use it to publish a
  round without a Te distribution.
- The parsers are tested against real files. A `synctex` file of a real paper
  found the pages, the inputs and the coordinates of the reference
  implementation; keep that check honest when the format handling changes.

## Things to know

- The `synctex` coordinates of nested boxes are relative to their parent. The
  reader recovers the position of a place on the page by matching the reading
  order of the typeset output with the reading order of the file, not by
  adding up the offsets. Keep this in mind before changing the reader.
- The build is reproducible: `SOURCE_DATE_EPOCH` is set to noon UTC of the day
  of the build, so a document does not change because it was compiled again.
- The journal is append only. An interrupted write can be cut short without
  losing what came before it, and the server can finish an unfinished decision
  when it starts.
- A change on the page is found twice: the area of the page comes from the
  comparison of the two PDFs, and the source of the change comes from the
  SyncTeX file of the proposal. The two are joined by the reading order of the
  page, so a document that grew a sentence still lines up.
- Accepting a change merges the edit of the agent into the working tree of the
  author with a three way merge, so that the changes of the author that do not
  touch the edit are kept. Rejecting a change takes the edit back out of the
  worktree of the agent.

## Dependencies

- `moonbitlang/pdflite` reads the PDF.
- `moonbitlang/async` provides the file system, the processes and the HTTP
  server.
- `moonbitlang/core/diff` provides the word comparison.
- The engine talks to `git` and to `latexmk` at runtime.
