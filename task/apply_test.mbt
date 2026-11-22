///|
/// Make a repository with a file of three lines.
async fn make_repo() -> String {
  let dir = @fs.tmpdir(prefix="papilot-task")
  let _ = @process.run("git", ["init", "--quiet"], cwd=dir)
  let _ = @process.run(
    "git",
    ["config", "user.email", "test@example.com"],
    cwd=dir,
  )
  let _ = @process.run("git", ["config", "user.name", "Test"], cwd=dir)
  let _ = @fs.write_file(
    dir + "/main.tex",
    "\\section{One}\nthe first line\nthe second line\nthe third line\nthe fourth line\n",
  )
  let _ = @process.run("git", ["add", "."], cwd=dir)
  let _ = @process.run("git", ["commit", "--quiet", "-m", "first"], cwd=dir)
  dir
}

///|
/// A task with a worktree of its own.
async fn make_task(dir : String) -> @task.Task {
  let task = @task.create(
    dir,
    "test-task",
    "main.tex",
    "pdflatex",
    dir + "-tasks",
    ".",
  ) catch {
    _ => fail("the task could not be created")
  }
  task.unwrap()
}

///|
/// The text of a file.
async fn read(path : String) -> String {
  let content = @fs.read_file(path) catch { _ => return "" }
  @utf8.decode_lossy(content.binary())
}

///|
test "a line range is replaced" {
  let content = "one\ntwo\nthree\nfour\n"
  assert_eq(
    @task.replace_lines(content, 2, 1, "TWO"),
    "one\nTWO\nthree\nfour\n",
  )
  assert_eq(@task.replace_lines(content, 2, 2, "TWO"), "one\nTWO\nfour\n")
}

///|
test "an edit is applied and taken back" {
  let base = "one\ntwo\nthree\n"
  let edit = @task.SourceEdit::new("main.tex", 2, 1, 2, 1, "two", "TWO")
  assert_eq(@task.apply_edit(base, edit, true), "one\nTWO\nthree\n")
  assert_eq(
    @task.apply_edit("one\nTWO\nthree\n", edit, false),
    "one\ntwo\nthree\n",
  )
}

///|
async test "accepting an edit puts it into the working tree" {
  let dir = make_repo()
  let task = make_task(dir)
  // The agent changes the second line in its worktree.
  let _ = @fs.write_file(
    task.worktree + "/main.tex",
    "\\section{One}\nthe FIRST line\nthe second line\nthe third line\nthe fourth line\n",
  )
  let edits = @task.edits_of(task)
  assert_eq(edits.length(), 1)
  let applied = @task.accept(task, edits[0])
  assert_true(applied)
  let content = read(dir + "/main.tex")
  assert_true(content.contains("the FIRST line"))
}

///|
async test "accepting an edit keeps the changes of the author" {
  let dir = make_repo()
  let task = make_task(dir)
  // The author changes the third line in the working tree.
  let _ = @fs.write_file(
    dir + "/main.tex",
    "\\section{One}\nthe first line\nthe second line\nthe THIRD line\nthe fourth line\n",
  )
  // The agent changes the second line in its worktree.
  let _ = @fs.write_file(
    task.worktree + "/main.tex",
    "\\section{One}\nthe SECOND line\nthe second line\nthe third line\nthe fourth line\n",
  )
  let edits = @task.edits_of(task)
  assert_eq(edits.length(), 1)
  assert_true(@task.accept(task, edits[0]))
  let content = read(dir + "/main.tex")
  assert_true(content.contains("the SECOND line"))
  assert_true(content.contains("the THIRD line"))
}

///|
async test "rejecting an edit takes it back out of the worktree" {
  let dir = make_repo()
  let task = make_task(dir)
  let _ = @fs.write_file(
    task.worktree + "/main.tex",
    "\\section{One}\nthe FIRST line\nthe second line\nthe third line\nthe fourth line\n",
  )
  let edits = @task.edits_of(task)
  assert_eq(edits.length(), 1)
  assert_true(@task.reject(task, edits[0]))
  let content = read(task.worktree + "/main.tex")
  assert_true(content.contains("the first line"))
  assert_false(content.contains("the FIRST line"))
}

///|
async test "an accepted edit can be taken back" {
  let dir = make_repo()
  let task = make_task(dir)
  let _ = @fs.write_file(
    task.worktree + "/main.tex",
    "\\section{One}\nthe FIRST line\nthe second line\nthe third line\nthe fourth line\n",
  )
  let edits = @task.edits_of(task)
  assert_true(@task.accept(task, edits[0]))
  assert_true(read(dir + "/main.tex").contains("the FIRST line"))
  assert_true(@task.undo_accept(task, edits[0]))
  let content = read(dir + "/main.tex")
  assert_false(content.contains("the FIRST line"))
  assert_true(content.contains("the first line"))
}

///|
async test "a rejected edit can be put back" {
  let dir = make_repo()
  let task = make_task(dir)
  let _ = @fs.write_file(
    task.worktree + "/main.tex",
    "\\section{One}\nthe FIRST line\nthe second line\nthe third line\nthe fourth line\n",
  )
  let edits = @task.edits_of(task)
  assert_true(@task.reject(task, edits[0]))
  assert_true(@task.undo_reject(task, edits[0]))
  let content = read(task.worktree + "/main.tex")
  assert_true(content.contains("the FIRST line"))
}

///|
async test "the merge keeps both sides when they do not overlap" {
  let merged = @git.merge_files(
    "one\ntwo\nthree\nfour\nfive\n", "one\nTWO\nthree\nfour\nfive\n", "one\ntwo\nthree\nfour\nFIVE\n",
  ) catch {
    _ => fail("the merge failed")
  }
  assert_eq(merged, Some("one\nTWO\nthree\nfour\nFIVE\n"))
}

///|
async test "the merge fails when the sides overlap" {
  let merged = @git.merge_files(
    "one\ntwo\nthree\n", "one\nTWO\nthree\n", "one\nTWO!\nthree\n",
  ) catch {
    _ => None
  }
  assert_eq(merged, None)
}
