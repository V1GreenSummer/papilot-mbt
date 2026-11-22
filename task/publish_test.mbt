///|
/// The stand-in for latexmk, as an absolute path.
///
/// The tests run in the folder of the package, so the path of the stand-in is
/// built from the working directory.
fn fake_latexmk() -> String {
  let here = @env.current_dir().unwrap_or(".")
  here + "/../examples/fake-latexmk/latexmk"
}

///|
/// Whether the stand-in can be used.
async fn have_fake_latexmk() -> Bool {
  @fs.exists(fake_latexmk())
}

///|
/// A repository with a document of two lines.
async fn make_publish_repo() -> String {
  let dir = @fs.tmpdir(prefix="papilot-publish")
  let _ = @process.run("git", ["init", "--quiet"], cwd=dir)
  let _ = @process.run(
    "git",
    ["config", "user.email", "test@example.com"],
    cwd=dir,
  )
  let _ = @process.run("git", ["config", "user.name", "Test"], cwd=dir)
  let _ = @fs.write_file(
    dir + "/main.tex",
    "\\section{Hello}\nthe first line\n",
  )
  let _ = @process.run("git", ["add", "."], cwd=dir)
  let _ = @process.run("git", ["commit", "--quiet", "-m", "first"], cwd=dir)
  dir
}

///|
/// Publish a round with the stand-in for latexmk.
async fn publish_with(
  task : @task.Task,
) -> Result[@task.Round, @task.PublishError] {
  let result = @task.publish(
    task,
    1,
    task.worktree + "-build",
    compiler=fake_latexmk(),
  ) catch {
    _ => Err(@task.PublishError::ProposalBuildFailed("the engine stopped"))
  }
  match result {
    Ok(published) => Ok(published.round)
    Err(reason) => Err(reason)
  }
}

///|
async test "a round reports the change of the agent" {
  if !have_fake_latexmk() {
    return
  }
  let dir = make_publish_repo()
  let task = @task.create(
    dir,
    "publish-task",
    "main.tex",
    "pdflatex",
    dir + "-tasks",
    ".",
  ) catch {
    _ => fail("the task could not be created")
  }
  let task = task.unwrap()
  // The agent changes the second line of the document.
  let _ = @fs.write_file(
    task.worktree + "/main.tex",
    "\\section{Hello}\nthe second line\n",
  )
  let published = publish_with(task) catch {
    _ => fail("the round could not be published")
  }
  let round = match published {
    Ok(round) => round
    Err(reason) => fail(reason.to_string())
  }
  assert_eq(round.number, 1)
  assert_eq(round.changes.length(), 1)
  let change = round.changes[0]
  assert_eq(change.change.old_text, "the first line")
  assert_eq(change.change.new_text, "the second line")
  assert_eq(change.change.page, 1)
}

///|
async test "a round finds the source of the change" {
  if !have_fake_latexmk() {
    return
  }
  let dir = make_publish_repo()
  let task = @task.create(
    dir,
    "publish-task",
    "main.tex",
    "pdflatex",
    dir + "-tasks",
    ".",
  ) catch {
    _ => fail("the task could not be created")
  }
  let task = task.unwrap()
  let _ = @fs.write_file(
    task.worktree + "/main.tex",
    "\\section{Hello}\nthe second line\n",
  )
  let published = publish_with(task) catch {
    _ => fail("the round could not be published")
  }
  let round = match published {
    Ok(round) => round
    Err(reason) => fail(reason.to_string())
  }
  let change = round.changes[0]
  // The change points at the second line of the document.
  assert_eq(change.source is Some(_), true)
  let source = change.source.unwrap()
  assert_eq(source.line, 2)
  assert_eq(@task.basename(source.file), "main.tex")
  // And it belongs to the edit of the agent.
  assert_eq(change.edit, Some(0))
}

///|
async test "a round without a change has no change" {
  if !have_fake_latexmk() {
    return
  }
  let dir = make_publish_repo()
  let task = @task.create(
    dir,
    "publish-task",
    "main.tex",
    "pdflatex",
    dir + "-tasks",
    ".",
  ) catch {
    _ => fail("the task could not be created")
  }
  let task = task.unwrap()
  let published = publish_with(task) catch {
    _ => fail("the round could not be published")
  }
  let round = match published {
    Ok(round) => round
    Err(reason) => fail(reason.to_string())
  }
  assert_eq(round.changes.length(), 0)
}
