///|
/// Join lines with newlines.
fn lines_of(items : Array[String]) -> String {
  items.join("\n")
}

///|
test "a unified diff is read as source edits" {
  let diff = lines_of([
    "diff --git a/main.tex b/main.tex", "--- a/main.tex", "+++ b/main.tex", "@@ -10,3 +10,4 @@",
    " context", "-old line", "+new line", "+another new line", " trailing", "",
  ])
  let edits = @task.parse_unified_diff(diff)
  assert_eq(edits.length(), 1)
  let edit = edits[0]
  assert_eq(edit.file, "main.tex")
  assert_eq(edit.base_start, 10)
  assert_eq(edit.base_len, 3)
  assert_eq(edit.new_start, 10)
  assert_eq(edit.new_len, 4)
  assert_true(edit.old_text.contains("old line"))
  assert_true(edit.new_text.contains("another new line"))
}

///|
test "an edit knows the lines it covers" {
  let diff = lines_of([
    "--- a/main.tex", "+++ b/main.tex", "@@ -10,2 +10,2 @@", "-one", "+two", "",
  ])
  let edits = @task.parse_unified_diff(diff)
  let edit = edits[0]
  assert_true(edit.covers("main.tex", 10))
  assert_true(edit.covers("main.tex", 11))
  assert_false(edit.covers("main.tex", 12))
  assert_false(edit.covers("other.tex", 10))
}

///|
test "several hunks become several edits" {
  let diff = lines_of([
    "--- a/main.tex", "+++ b/main.tex", "@@ -1,1 +1,1 @@", "-a", "+b", "@@ -20,1 +20,2 @@",
    "-c", "+d", "+e", "",
  ])
  let edits = @task.parse_unified_diff(diff)
  assert_eq(edits.length(), 2)
  assert_eq(edits[0].base_start, 1)
  assert_eq(edits[1].base_start, 20)
  assert_eq(edits[1].new_len, 2)
}

///|
test "an empty diff has no edits" {
  assert_eq(@task.parse_unified_diff("").length(), 0)
  assert_eq(@task.parse_unified_diff("no hunks here\n").length(), 0)
}

///|
test "a branch and a worktree are named after the task" {
  assert_eq(@task.branch_of("abc"), "papilot/abc")
  assert_eq(@task.worktree_of("/tmp/tasks", "abc"), "/tmp/tasks/abc")
}
