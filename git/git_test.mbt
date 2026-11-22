///|
/// Make a repository with one file in a temporary folder.
async fn make_repo() -> String {
  let dir = @fs.tmpdir(prefix="papilot-test")
  let _ = @process.run("git", ["init", "--quiet"], cwd=dir)
  let _ = @process.run(
    "git",
    ["config", "user.email", "test@example.com"],
    cwd=dir,
  )
  let _ = @process.run("git", ["config", "user.name", "Test"], cwd=dir)
  let _ = @fs.write_file(dir + "/main.tex", "\\section{Hello}\n")
  let _ = @process.run("git", ["add", "."], cwd=dir)
  let _ = @process.run("git", ["commit", "--quiet", "-m", "first"], cwd=dir)
  dir
}

///|
async test "a repository is found from a folder inside it" {
  let dir = make_repo()
  assert_true(@git.is_repository(dir))
  let root = @git.repo_root(dir)
  assert_true(root is Some(_))
}

///|
async test "the head of a repository is read" {
  let dir = make_repo()
  let head = @git.head(dir)
  assert_true(head is Some(_))
  assert_eq(head.unwrap().length(), 40)
}

///|
async test "the files that changed are listed" {
  let dir = make_repo()
  let head = @git.head(dir).unwrap()
  let _ = @fs.write_file(
    dir + "/main.tex",
    "\\section{Hello}\\n\\section{More}\n",
  )
  let changed = @git.changed_files(dir, head)
  assert_eq(changed.length(), 1)
  assert_eq(changed[0], "main.tex")
}

///|
async test "the content of a file at a commit is read" {
  let dir = make_repo()
  let head = @git.head(dir).unwrap()
  let content = @git.show_file(dir, head, "main.tex")
  assert_eq(content, Some("\\section{Hello}\n"))
}

///|
async test "a snapshot does not touch the branch" {
  let dir = make_repo()
  let head = @git.head(dir).unwrap()
  let index = dir + "/private-index"
  let _ = @fs.write_file(dir + "/main.tex", "\\section{Changed}\n")
  let snapshot = @git.snapshot(dir, index, "a snapshot")
  assert_true(snapshot is Some(_))
  // The commit of the repository is untouched.
  assert_eq(@git.head(dir).unwrap(), head)
}

///|
async test "a worktree is added and removed" {
  let dir = make_repo()
  let worktree = dir + "-worktree"
  let output = @git.add_worktree(dir, worktree, "papilot/test")
  assert_true(output.ok())
  assert_true(@fs.exists(worktree))
  let worktrees = @git.worktrees(dir)
  assert_true(worktrees.length() >= 2)
  let _ = @git.remove_worktree(dir, worktree, "papilot/test")
  assert_false(@fs.exists(worktree))
}

///|
async test "the edits between two commits are found" {
  let dir = make_repo()
  let head = @git.head(dir).unwrap()
  let _ = @fs.write_file(
    dir + "/main.tex",
    "\\section{Hello}\n\\section{More}\n",
  )
  let _ = @process.run("git", ["add", "."], cwd=dir)
  let _ = @process.run("git", ["commit", "--quiet", "-m", "second"], cwd=dir)
  let edits = @task.edits_between(dir, head, "HEAD")
  assert_eq(edits.length(), 1)
  assert_eq(edits[0].file, "main.tex")
  assert_true(edits[0].new_text.contains("More"))
}
