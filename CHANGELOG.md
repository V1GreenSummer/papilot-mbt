# Changelog

## [0.1.1] - 2026-11-22

### Added

- `render`: every page renders as a vector SVG, from the places of the
  glyphs, with the fonts they were set in.
- `GET /tasks/:id/view`: a review page with the before and after of the page,
  the changes highlighted, and a button for each decision.
- `GET /tasks/:id/page/:page/before.svg` and `.../after.svg`: one page as
  vectors.
- `GET /` lists the endpoints and the tasks.

### Fixed

- The area of a change was empty when the page held words the word tokenizer
  would split differently (a `\section` heading, a formula): the comparison
  now works on the words of the page directly.
- `Content-Length` was counted in characters; HTTP counts bytes. An answer
  with a non-ASCII character (a change of the paper can hold any) crashed the
  server.

## [0.1.0] - 2026-11-22

The first release of the engine.

### The idea

The author works on the PDF and never opens a `.tex` file. The engine finds
the source of a place on the page, compiles the accepted text and the
proposal, compares the two PDFs and shows the difference on the page. The
author accepts, rejects or comments on each change; only the accepted changes
reach the working tree.

### Added

- `latex`: the LaTeX reader (sections, labels, references, included files,
  environments).
- `pdftext`: the PDF reader (the text of every page with the place of every
  glyph).
- `synctex`: the SyncTeX reader (the source of a place on the page).
- `diff`: the word comparison (differences and moved passages).
- `compare`: the PDF comparison (the areas of the page that changed and the
  source they come from).
- `git`: the Git operations (worktrees, snapshots, three way merges).
- `build`: the LaTeX build (`latexmk`, reproducible).
- `task`: the lifecycle of a task (the edits of the agent, the rounds).
- `journal`: the decision journal (append only).
- `server`: the HTTP interface (on 127.0.0.1).
- `cli`: the command line (`source`, `synctex`, `compare`, `publish`, `serve`).

### The flow that works

1. A task is a Git worktree of the repository.
2. The agent edits the worktree; the author never sees a `.tex` file.
3. Publishing a round compiles the accepted text and the proposal and shows
   the changes on the page, each with the source line it comes from.
4. Accepting a change merges the edit into the working tree of the author.
   Rejecting a change takes it back out of the worktree of the agent.
5. The author decides while the next round compiles; the undecided changes of
   the last round carry over to the next one.
6. The state of the engine lives in `.git/papilot/` of the repository, so a
   restart finds the tasks and the rounds again. A decision that was
   interrupted is made again when the engine starts.

[0.1.0]: https://github.com/PapilotAI/papilot-mbt/releases/tag/v0.1.0
