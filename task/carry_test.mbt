///|
async test "a decision that was started but not finished is found" {
  let dir = @fs.tmpdir(prefix="papilot-journal")
  let journal = @journal.Journal::new(dir + "/journal.ndjson")
  let _ = journal.append(
    @journal.Entry::Deciding("task", 1, 0, @journal.Decision::Accepted),
  )
  let _ = journal.append(
    @journal.Entry::Deciding("task", 1, 1, @journal.Decision::Rejected),
  )
  let _ = journal.append(
    @journal.Entry::Decided("task", 1, 1, @journal.Decision::Rejected),
  )
  let unfinished = journal.unfinished() catch { _ => [] }
  assert_eq(unfinished.length(), 1)
  let (task, round, change, decision) = unfinished[0]
  assert_eq(task, "task")
  assert_eq(round, 1)
  assert_eq(change, 0)
  assert_eq(decision, @journal.Decision::Accepted)
}

///|
async test "a decision survives a round trip" {
  let entry = @journal.Entry::Deciding(
    "task",
    1,
    2,
    @journal.Decision::Commented("why"),
  )
  let back = @journal.Entry::from_json(entry.to_json()).unwrap()
  assert_eq(back, entry)
}

///|
async test "a change continues the change it replaces" {
  let old = @compare.Change::new(
    1,
    @synctex.Rect::new(10.0, 20.0, 30.0, 40.0),
    "the old words",
    "the new words",
  )
  let revised = @compare.Change::new(
    1,
    @synctex.Rect::new(10.0, 20.0, 30.0, 40.0),
    "the old words",
    "other new words",
  )
  let elsewhere = @compare.Change::new(
    2,
    @synctex.Rect::new(10.0, 20.0, 30.0, 40.0),
    "the old words",
    "the new words",
  )
  assert_true(@task.continues(old, revised))
  assert_false(@task.continues(old, elsewhere))
}

///|
async test "a change that adds text continues nothing" {
  let added = @compare.Change::new(
    1,
    @synctex.Rect::new(10.0, 20.0, 30.0, 40.0),
    "",
    "the new words",
  )
  let same = @compare.Change::new(
    1,
    @synctex.Rect::new(10.0, 20.0, 30.0, 40.0),
    "",
    "other words",
  )
  assert_false(@task.continues(added, same))
}

///|
async test "a task survives a round trip" {
  let task = @task.Task::new(
    "t1", "/repo", "/worktrees/t1", "papilot/t1", "abc123", "main.tex", "pdflatex",
  )
  let back = @task.Task::from_json(task.to_json()).unwrap()
  assert_eq(back.id, task.id)
  assert_eq(back.repo, task.repo)
  assert_eq(back.worktree, task.worktree)
  assert_eq(back.branch, task.branch)
  assert_eq(back.base, task.base)
  assert_eq(back.main, task.main)
  assert_eq(back.engine, task.engine)
}

///|
async test "a change survives a round trip" {
  let change = @compare.Change::new(
    3,
    @synctex.Rect::new(10.0, 20.0, 30.0, 40.0),
    "the old words",
    "the new words",
  )
  let back = @compare.Change::from_json(change.to_json()).unwrap()
  assert_eq(back.page, change.page)
  assert_eq(back.old_text, change.old_text)
  assert_eq(back.new_text, change.new_text)
  assert_true(back.rect.x > 9.9 && back.rect.x < 10.1)
  assert_true(back.rect.width > 29.9 && back.rect.width < 30.1)
}
