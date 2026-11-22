///|
test "a decision is written as JSON and read back" {
  let entry = @journal.Entry::Decided(
    "task",
    2,
    5,
    @journal.Decision::Commented("please explain"),
  )
  let json = entry.to_json()
  let back = @journal.Entry::from_json(json).unwrap()
  match back {
    @journal.Entry::Decided(task, round, change, decision) => {
      assert_eq(task, "task")
      assert_eq(round, 2)
      assert_eq(change, 5)
      assert_eq(decision, @journal.Decision::Commented("please explain"))
    }
    _ => fail("expected a decision")
  }
}

///|
test "every kind of entry survives the round trip" {
  let entries = [
    @journal.Entry::TaskCreated("task", "/tmp/worktree"),
    @journal.Entry::RoundPublished("task", 1, 7),
    @journal.Entry::Decided("task", 1, 3, @journal.Decision::Accepted),
    @journal.Entry::Decided("task", 1, 4, @journal.Decision::Rejected),
    @journal.Entry::Undone("task", 1, 3),
  ]
  for entry in entries {
    let back = @journal.Entry::from_json(entry.to_json()).unwrap()
    assert_eq(back, entry)
  }
}

///|
test "an entry knows its task" {
  let entry = @journal.Entry::RoundPublished("abc", 2, 3)
  assert_eq(entry.task(), "abc")
}

///|
test "a decision carries its comment" {
  let decision = @journal.Decision::Commented("why?")
  assert_eq(decision.comment(), Some("why?"))
  assert_eq(@journal.Decision::Accepted.comment(), None)
}
