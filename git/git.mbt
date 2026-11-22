///|
/// The result of running a command.
pub struct Output {
  /// The exit code of the command.
  code : Int32
  /// What the command wrote to standard output.
  stdout : String
  /// What the command wrote to standard error.
  stderr : String
}

///|
pub fn Output::to_string(self : Output) -> String {
  "exit=\{self.code}"
}

///|
/// Whether the command succeeded.
pub fn Output::ok(self : Output) -> Bool {
  self.code == 0
}

///|
/// The text of a command, with the trailing newline removed.
pub fn Output::text(self : Output) -> String {
  trim_end(self.stdout)
}

///|
/// Remove the trailing newline of a text.
fn trim_end(text : String) -> String {
  let mut last = text.length()
  while last > 0 {
    let c = text.get_char(last - 1).unwrap_or(' ')
    if c == '\n' || c == '\r' {
      last = last - 1
    } else {
      break
    }
  }
  text.clamped_view(start=0, end=last).to_owned()
}

///|
/// Run a git command in a directory.
///
/// Git writes its progress to standard error, so only standard output is
/// returned as the result.
pub async fn git(
  dir : String,
  args : Array[String],
  index~ : String = "",
) -> Output {
  let env = Map([])
  if index != "" {
    env.set("GIT_INDEX_FILE", index)
  }
  let (code, stdout, stderr) = @process.collect_output(
    "git",
    args,
    extra_env=env,
    cwd=dir,
  )
  Output::{ code, stdout: decode(stdout), stderr: decode(stderr), }
}

///|
/// Turn the bytes of a stream into text.
fn decode(data : &@io.Data) -> String {
  @utf8.decode_lossy(data.binary())
}

///|
/// The name of the branch a task works on.
pub fn branch_of(id : String) -> String {
  "papilot/" + id
}

///|
/// The root of the repository that contains `dir`.
pub async fn repo_root(dir : String) -> String? {
  let output = git(dir, ["rev-parse", "--show-toplevel"])
  if output.ok() {
    Some(output.text())
  } else {
    None
  }
}

///|
/// Whether the directory belongs to a git repository.
pub async fn is_repository(dir : String) -> Bool {
  let output = git(dir, ["rev-parse", "--git-dir"])
  output.ok()
}

///|
/// The current commit of the repository.
pub async fn head(dir : String) -> String? {
  let output = git(dir, ["rev-parse", "HEAD"])
  if output.ok() {
    Some(output.text())
  } else {
    None
  }
}

///|
/// The commit of a branch or reference.
pub async fn rev_parse(dir : String, reference : String) -> String? {
  let output = git(dir, ["rev-parse", reference])
  if output.ok() {
    Some(output.text())
  } else {
    None
  }
}

///|
/// The files that differ between the working tree and a commit.
pub async fn changed_files(dir : String, reference : String) -> Array[String] {
  let output = git(dir, ["diff", "--name-only", reference])
  if !output.ok() {
    return []
  }
  let files = []
  for line in output.text().split("\n") {
    let name = line.trim().to_owned()
    if !name.is_empty() {
      files.push(name)
    }
  }
  files
}

///|
/// The content of a file at a commit.
pub async fn show_file(
  dir : String,
  reference : String,
  file : String,
) -> String? {
  let output = git(dir, ["show", reference + ":" + file])
  if output.ok() {
    Some(output.stdout)
  } else {
    None
  }
}

///|
/// The worktrees of the repository.
pub async fn worktrees(dir : String) -> Array[String] {
  let output = git(dir, ["worktree", "list", "--porcelain"])
  if !output.ok() {
    return []
  }
  let paths = []
  for line in output.text().split("\n") {
    let text = line.trim().to_owned()
    if text.has_prefix("worktree ") {
      paths.push(text.clamped_view(start=9, end=text.length()).to_owned())
    }
  }
  paths
}

///|
/// Add a worktree for a branch.
///
/// The branch is created when it does not exist yet, so that a task can start
/// from the current commit without touching the branch of the user.
pub async fn add_worktree(
  repo : String,
  path : String,
  branch : String,
) -> Output {
  git(repo, ["worktree", "add", "-b", branch, path])
}

///|
/// Remove a worktree and the branch that belongs to it.
pub async fn remove_worktree(
  repo : String,
  path : String,
  branch : String,
) -> Output {
  let _ = git(repo, ["worktree", "remove", "--force", path])
  git(repo, ["branch", "-D", branch])
}

///|
/// The result of a snapshot.
pub struct Snapshot {
  /// The commit that was created.
  commit : String
  /// The tree the commit points at.
  tree : String
}

///|
/// Take a snapshot of the working tree without touching the branch or the
/// staging area.
///
/// The snapshot uses a private index file, so the index of the user is never
/// written to and no uncommitted change of the user can end up in the
/// snapshot.
pub async fn snapshot(
  repo : String,
  index_file : String,
  message : String,
) -> Snapshot? {
  let _ = git(
    repo,
    ["--git-dir", git_dir(repo), "--work-tree", repo, "read-tree", "HEAD"],
    index=index_file,
  )
  let _ = git(
    repo,
    ["--git-dir", git_dir(repo), "--work-tree", repo, "add", "-A", "--", "."],
    index=index_file,
  )
  let tree_output = git(
    repo,
    ["--git-dir", git_dir(repo), "write-tree"],
    index=index_file,
  )
  if !tree_output.ok() {
    return None
  }
  let tree = tree_output.text()
  let commit_output = git(
    repo,
    ["--git-dir", git_dir(repo), "commit-tree", tree, "-m", message],
    index=index_file,
  )
  if !commit_output.ok() {
    return None
  }
  Some(Snapshot::{ commit: commit_output.text(), tree, })
}

///|
/// The git directory of a repository.
fn git_dir(repo : String) -> String {
  repo + "/.git"
}

///|
/// Merge a file into the working tree with a three-way merge.
///
/// The base is the version the change was made against, `ours` is the current
/// content of the working tree and `theirs` is the change. The merge keeps
/// both sides when they do not overlap, and reports a conflict when they do.
pub async fn merge_file(
  repo : String,
  base : String,
  ours : String,
  theirs : String,
) -> Bool {
  let result = git(repo, ["merge-file", "-p", ours, base, theirs])
  result.ok()
}

///|
/// The lines of a file that differ from a commit.
pub async fn diff_lines(
  repo : String,
  reference : String,
  file : String,
) -> Array[String] {
  let output = git(repo, ["diff", reference, "--", file])
  if !output.ok() {
    return []
  }
  let lines = []
  for line in output.text().split("\n") {
    lines.push(line.to_owned())
  }
  lines
}

///|
/// Merge two versions of a file with the version they share in common.
///
/// The three versions are written to temporary files and merged by Git, which
/// keeps the changes that do not overlap and reports the ones that do. The
/// result is `None` when the two sides touch the same lines.
pub async fn merge_files(
  base : String,
  ours : String,
  theirs : String,
) -> String? {
  let dir = @fs.tmpdir(prefix="papilot-merge")
  let base_path = dir + "/base"
  let ours_path = dir + "/ours"
  let theirs_path = dir + "/theirs"
  write_file(base_path, base)
  write_file(ours_path, ours)
  write_file(theirs_path, theirs)
  let output = git(dir, ["merge-file", "-p", ours_path, base_path, theirs_path])
  let merged = if output.ok() { Some(output.stdout) } else { None }
  @fs.remove(base_path) catch {
    _ => ()
  }
  @fs.remove(ours_path) catch {
    _ => ()
  }
  @fs.remove(theirs_path) catch {
    _ => ()
  }
  @fs.remove(dir) catch {
    _ => ()
  }
  merged
}

///|
/// Write a file with the given text.
async fn write_file(path : String, content : String) -> Unit {
  @fs.write_file(path, @utf8.encode(content)) catch {
    _ => ()
  }
}
