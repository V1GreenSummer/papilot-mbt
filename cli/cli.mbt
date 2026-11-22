///|
/// The command line of the tool.
fn command() -> @argparse.Command {
  @argparse.Command(
    "papilot",
    about="An AI facing LaTeX editor: work on the PDF, not the .tex.",
    subcommands=[
      @argparse.Command(
        "serve",
        about="Run the review engine for a repository.",
        options=[
          @argparse.OptionArg(
            "repo",
            long="repo",
            about="The repository to serve.",
            default_values=["."],
          ),
          @argparse.OptionArg(
            "port",
            long="port",
            about="The port to listen on.",
            default_values=["8765"],
          ),
        ],
      ),
      @argparse.Command(
        "compare",
        about="Compare two PDFs and report what changed.",
        positionals=[
          @argparse.PositionArg("old", about="The PDF before the change."),
          @argparse.PositionArg("new", about="The PDF after the change."),
        ],
      ),
      @argparse.Command(
        "synctex",
        about="Show where a point of the page comes from.",
        options=[
          @argparse.OptionArg(
            "file",
            long="file",
            about="The SyncTeX file.",
            required=true,
          ),
          @argparse.OptionArg(
            "page",
            long="page",
            about="The page, starting at one.",
            default_values=["1"],
          ),
          @argparse.OptionArg(
            "x",
            long="x",
            about="The horizontal position in points.",
            default_values=["0"],
          ),
          @argparse.OptionArg(
            "y",
            long="y",
            about="The vertical position in points.",
            default_values=["0"],
          ),
        ],
      ),
      @argparse.Command(
        "publish",
        about="Publish a round of a task and show what changed.",
        options=[
          @argparse.OptionArg(
            "repo",
            long="repo",
            about="The repository of the task.",
            default_values=["."],
          ),
          @argparse.OptionArg(
            "task",
            long="task",
            about="The name of the task.",
            default_values=["task"],
          ),
          @argparse.OptionArg("main", long="main", about="The root document.", default_values=[
            "main.tex",
          ]),
          @argparse.OptionArg(
            "engine",
            long="engine",
            about="The engine of the document.",
            default_values=["pdflatex"],
          ),
          @argparse.OptionArg(
            "round",
            long="round",
            about="The number of the round.",
            default_values=["1"],
          ),
        ],
      ),
      @argparse.Command(
        "source",
        about="Show the structure of a LaTeX document.",
        positionals=[
          @argparse.PositionArg("file", about="The .tex file to read."),
        ],
      ),
    ],
  )
}

///|
/// The value of an option of the matches.
fn option(matches : @argparse.Matches, name : String) -> String {
  match matches.values.get(name) {
    Some(values) =>
      match values {
        [value, ..] => value
        [] => ""
      }
    None => ""
  }
}

///|
/// The value of a positional argument of the matches.
fn positional(matches : @argparse.Matches, name : String) -> String {
  option(matches, name)
}

///|
/// Run the tool.
pub async fn run_cli() -> Unit {
  let argv = match @env.args() {
    [_, .. rest] => rest
    [] => []
  }
  let matches = @argparse.Command::parse_outcome(command(), argv~)
  match matches {
    @argparse.ParseOutcome::Parsed(m) => run_command(m)
    @argparse.ParseOutcome::Help(text) => println("\{text}")
    @argparse.ParseOutcome::Version(text) => println("\{text}")
    @argparse.ParseOutcome::Failed(err) => println("\{err}")
  }
}

///|
/// Run the command that was asked for.
async fn run_command(matches : @argparse.Matches) -> Unit {
  match matches.subcommand {
    Some(("serve", sub)) => {
      let repo = option(sub, "repo")
      let port = option(sub, "port")
      let port = @strconv.parse_int(port) catch { _ => 8765 }
      let worktrees = repo + "-tasks"
      let journal = @journal.Journal::new(repo + "/.git/papilot/journal.ndjson")
      let app = @server.App::new(repo, worktrees, journal)
      println("papilot serves \{repo} on 127.0.0.1:\{port}")
      @server.serve(app, port) catch {
        err => println("the server stopped: \{err}")
      }
    }
    Some(("compare", sub)) => {
      let old = @fs.read_file(positional(sub, "old")) catch {
        _ => {
          println("the first PDF could not be read")
          return
        }
      }
      let new = @fs.read_file(positional(sub, "new")) catch {
        _ => {
          println("the second PDF could not be read")
          return
        }
      }
      let old_text = @pdftext.extract(old.binary()) catch {
        _ => {
          println("the first PDF could not be read")
          return
        }
      }
      let new_text = @pdftext.extract(new.binary()) catch {
        _ => {
          println("the second PDF could not be read")
          return
        }
      }
      let changes = @compare.compare(old_text, new_text)
      println("\{changes.length()} changes")
      for change in changes {
        println("page \{change.page}: \{change.old_text} -> \{change.new_text}")
      }
    }
    Some(("synctex", sub)) => {
      let path = option(sub, "file")
      let content = @fs.read_file(path) catch {
        _ => {
          println("the SyncTeX file could not be read")
          return
        }
      }
      let bytes = content.binary()
      let text = if bytes.length() > 2 &&
        bytes[0] == 0x1FU.to_byte() &&
        bytes[1] == 0x8BU.to_byte() {
        let raw = @gzip.decompress(bytes, max_output=64 * 1024 * 1024) catch {
          _ => {
            println("the SyncTeX file could not be read")
            return
          }
        }
        @utf8.decode_lossy(raw)
      } else {
        @utf8.decode_lossy(bytes)
      }
      let file = @synctex.parse(text)
      let page = @strconv.parse_int(option(sub, "page")) catch { _ => 1 }
      let x = @strconv.parse_double(option(sub, "x")) catch { _ => 0.0 }
      let y = @strconv.parse_double(option(sub, "y")) catch { _ => 0.0 }
      // Look a small area around the point, so that a point between two
      // lines still finds the line it belongs to.
      let rect = @synctex.Rect::new(x - 4.0, y - 4.0, 8.0, 8.0)
      match file.source_at(page, rect) {
        Some(location) => println("\{location.to_string()}")
        None => println("nothing at that point")
      }
    }
    Some(("publish", sub)) => {
      let repo = option(sub, "repo")
      let name = option(sub, "task")
      let main = option(sub, "main")
      let engine = option(sub, "engine")
      let round = @strconv.parse_int(option(sub, "round")) catch { _ => 1 }
      let worktrees = repo + "-tasks"
      let task = @task.create(repo, name, main, engine, worktrees, ".") catch {
        _ => None
      }
      match task {
        Some(t) => {
          let published = @task.publish(t, round, t.worktree + "-build") catch {
            _ =>
              Err(@task.PublishError::ProposalBuildFailed("the engine stopped"))
          }
          match published {
            Ok(result) => println(result.round.to_json().stringify(indent=2))
            Err(reason) => println(reason.to_string())
          }
        }
        None => println("the task could not be created")
      }
    }
    Some(("source", sub)) => {
      let path = positional(sub, "file")
      let content = @fs.read_file(path) catch {
        _ => {
          println("the file could not be read")
          return
        }
      }
      let text = @utf8.decode_lossy(content.binary())
      let document = @latex.parse_text(text)
      println("\{document.sections.length()} sections")
      for section in document.sections {
        println("  level \{section.level}: \{section.title}")
      }
    }
    _ => println(command().render_help())
  }
}
