# Papilot for MoonBit
[![CI](https://github.com/V1GreenSummer/papilot-mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/V1GreenSummer/papilot-mbt/actions/workflows/ci.yml)


**An AI facing LaTeX editor engine, written in MoonBit.**

The idea comes from [Papilot](https://github.com/PapilotAI/papilot): *do not
read or write `.tex`, work on the PDF.* The author marks a place on the
typeset page and says what should change there. The engine finds the source of
that place, compiles the accepted text and the proposal, compares the two PDFs
and shows the difference on the page. The author accepts, rejects or comments
on each change; only the accepted changes reach the working tree.

This repository is the engine, written from scratch in MoonBit.

## Why MoonBit

The engine is a pile of text processing: reading LaTeX, reading a PDF, reading
a SyncTeX file, comparing words, and keeping the record of what the author
decided. That is exactly the kind of code MoonBit is good at:

- Pattern matching over deeply nested data (the content operators of a PDF, the
  records of a SyncTeX file, the tree of a LaTeX document).
- Errors as values, so a broken paper never stops the engine.
- A native compiler, so the engine starts in milliseconds.

The PDF is read with [`moonbitlang/pdflite`](https://mooncakes.io), the file
system, the processes and the HTTP server come from
[`moonbitlang/async`](https://mooncakes.io), and the word comparison comes
from the standard library.

## What it does

```
latex    what the source says          LaTeX sections, labels, includes
pdftext  what the page says            every glyph of every page, with its place
synctex  where the page comes from     the source of a place on the page
diff     what is different             word differences, moved passages
compare  the two together              the areas of the page that changed
git      the work, kept apart          worktrees and snapshots
build    the typeset result            latexmk, reproducibly
task     one round of one task         the edits of the agent and where they belong
journal  what the author decided       the append only record of the decisions
server   the interface                 HTTP, on 127.0.0.1
```

## The flow

```
agent:  edit the worktree ─▶ publish ─▶ the changes appear on the page
                                          │
author:                       accept · reject · comment
```

- **Publish** compiles the accepted text (the working tree of the author, in a
  copy of the sources) and the proposal (the worktree of the agent), compares
  the two PDFs and reports the areas of the page that changed, each with the
  source line it comes from.
- **Accept** merges the edit of the agent into the working tree of the author
  with a three way merge, so that the changes of the author that do not touch
  the edit are kept.
- **Reject** takes the edit back out of the worktree of the agent.
- Every decision is written to an append only journal.

## Using it

```sh
moon build --target native
./_build/native/debug/build/cmd/main/main.exe --help
```

```
Usage: papilot [command]

An AI facing LaTeX editor: work on the PDF, not the .tex.

Commands:
  serve    Run the review engine for a repository.
  publish  Publish a round of a task and show what changed.
  compare  Compare two PDFs and report what changed.
  synctex  Show where a point of the page comes from.
  source   Show the structure of a LaTeX document.
```

### The structure of a document

```sh
$ papilot source sections/01-introduction.tex
4 sections
  level 2: Introduction
  level 3: Three commitments
  level 3: What this paper does
  level 3: A note on this document
```

### A round of a task

```sh
$ papilot publish --repo /path/to/paper --task my-task
{
  "round": 1,
  "changes": [
    {
      "page": 1,
      "rect": { "x": 92.01, "y": 683.3, "width": 60.69, "height": 13.87 },
      "old_text": "{Hi}hello",
      "new_text": "{Hello}the second line",
      "edit": 0,
      "source": { "file": ".../main.tex", "line": 2 }
    }
  ]
}
```


### The demo, without a Te distribution

```sh
$ moon build --target native
$ sh examples/demo.sh
== round 1: nothing has changed ==
{ "round": 1, "changes": [] }

== the agent changes a line in the worktree ==

== round 2: the change appears on the page ==
{
  "round": 2,
  "changes": [
    {
      "page": 1,
      "rect": { "x": 127.36, "y": 683.3, "width": 17.34, "height": 13.87 },
      "old_text": "brown",
      "new_text": "red",
      "edit": 0,
      "source": { "file": ".../main.tex", "line": 2 }
    }
  ]
}
```

The demo uses `examples/fake-latexmk`, a stand-in for `latexmk` that typesets
the document with a small PDF writer of its own, so the whole flow runs
anywhere.

### Where a point of the page comes from

```sh
$ papilot synctex --file main.synctex.gz --page 1 --x 300 --y 400
main.tex:31
```

### The interface

```sh
$ papilot serve --repo /path/to/paper --port 8765
```

| Endpoint | What it does |
| --- | --- |
| `GET /health` | Is the engine alive? |
| `GET /tasks` | The tasks that exist. |
| `POST /tasks` | Create a task. |
| `GET /tasks/:id` | The task and its last round. |
| `POST /tasks/:id/publish` | Compile both versions and report the changes. |
| `GET /tasks/:id/changes` | The changes of the last round. |
| `POST /tasks/:id/decisions` | Accept, reject or comment on a change. |
| `POST /tasks/:id/undo` | Take a decision back. |


### The review page

The engine renders every page as vector SVG from the places of the glyphs,
and serves a small review page — two renderings of the page, before and after,
with the changes highlighted, and a button for each decision:

```
http://localhost:8765/                  → the index of the endpoints
http://localhost:8765/tasks/t1/view     → the review page of the task
http://localhost:8765/tasks/t1/page/1/after.svg  → one page, as vectors
```

## The idea, in code

Marking a place on the page and finding its source is three lines:

```moonbit
// The page says something different than before.
let changes = @compare.compare(before, after)

// The change is at a place on the page.
let change = changes[0]

// The place on the page has a source.
let located = @compare.locate(page, synctex, change.page, change.rect)
```

The author then decides, and the decision is applied and written down:

```moonbit
@journal.Entry::Decided(task, round, 0, @journal.Decision::Accepted)
```

## Status

The engine is complete and tested; the editor around it is not part of this
repository. The parsers, the comparison, the locator and the journal are pure
MoonBit and need neither Git nor a Te distribution. The build and the worktrees
talk to `latexmk` and to `git` at runtime.

`examples/fake-latexmk/latexmk` stands in for `latexmk` so that the whole flow
can be exercised without a Te distribution.

See [AGENTS.md](AGENTS.md) for the development guide.

## License

MIT.
