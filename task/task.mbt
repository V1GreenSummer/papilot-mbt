///|
/// A task: one document that an agent works on.
///
/// The agent never touches the working tree of the author. It works in a
/// worktree of its own, and every change it makes is reviewed before it goes
/// anywhere.
#derive(Eq)
#derive(@debug.Debug)
pub struct Task {
  /// The name of the task.
  id : String
  /// The repository the task belongs to.
  repo : String
  /// The worktree the agent works in.
  worktree : String
  /// The branch of the worktree.
  branch : String
  /// The commit the task started from.
  base : String
  /// The root document, relative to the source folder.
  main : String
  /// The engine the document is compiled with.
  engine : String
  /// The folder that holds the sources.
  source_dir : String
}

///|
pub extend Task with Eq::{not_equal, equal}

///|
pub extend Task with @debug.Debug::{to_repr}

///|
pub fn Task::new(
  id : String,
  repo : String,
  worktree : String,
  branch : String,
  base : String,
  main : String,
  engine : String,
) -> Task {
  { id, repo, worktree, branch, base, main, engine, source_dir: ".", }
}

///|
pub fn Task::to_string(self : Task) -> String {
  "Task(\{self.id})"
}

///|
/// A task as the client sees it.
pub fn Task::to_json(self : Task) -> Json {
  Json::object({
    "id": Json::string(self.id),
    "repo": Json::string(self.repo),
    "worktree": Json::string(self.worktree),
    "branch": Json::string(self.branch),
    "base": Json::string(self.base),
    "main": Json::string(self.main),
    "engine": Json::string(self.engine),
  })
}

///|
/// The task of a JSON object.
pub fn Task::from_json(json : Json) -> Task? {
  let id = @jsonx.text(json, "id")
  if id.is_empty() {
    return None
  }
  Some(Task::{
    id,
    repo: @jsonx.text(json, "repo"),
    worktree: @jsonx.text(json, "worktree"),
    branch: @jsonx.text(json, "branch"),
    base: @jsonx.text(json, "base"),
    main: @jsonx.text(json, "main"),
    engine: @jsonx.text(json, "engine"),
    source_dir: ".",
  })
}

///|
/// The state of a task after a round was published.
pub struct Round {
  /// The number of the round, starting at one.
  number : Int32
  /// The changes the round produced.
  changes : Array[TaskChange]
  /// The edits of the source that the round contains.
  edits : Array[SourceEdit]
}

///|
pub fn Round::new(
  number : Int32,
  changes : Array[TaskChange],
  edits : Array[SourceEdit],
) -> Round {
  { number, changes, edits, }
}

///|
pub fn Round::to_string(self : Round) -> String {
  "Round(\{self.number}, \{self.changes.length()} changes)"
}

///|
/// The round of a JSON object.
pub fn Round::from_json(json : Json) -> Round? {
  let number = @jsonx.number(json, "round")
  let changes = []
  for item in @jsonx.items(json, "changes") {
    match TaskChange::from_json(item) {
      Some(change) => changes.push(change)
      None => ()
    }
  }
  Some(Round::new(number, changes, []))
}

///|
/// A round as the client sees it.
pub fn Round::to_json(self : Round) -> Json {
  let changes = []
  for change in self.changes {
    changes.push(change.to_json())
  }
  Json::object({
    "round": Json::number(self.number.to_double()),
    "changes": Json::array(changes),
  })
}

///|
/// The edit of the source that a change belongs to, and where it is.
///
/// The change is on a page of the proposal, and the SyncTeX file of the
/// proposal says which lines produced it. The edit that covers those lines is
/// the edit the author is accepting or rejecting.
pub fn edit_of_change(
  edits : Array[SourceEdit],
  synctex : @synctex.SynctexFile,
  change : @compare.Change,
) -> (Int32?, @synctex.SourceLocation?) {
  let locations = synctex.lines_at(change.page, change.rect)
  for location in locations {
    let mut index = 0
    while index < edits.length() {
      if edits[index].covers(location.file, location.line) {
        return (Some(index), Some(location))
      }
      index = index + 1
    }
  }
  (None, None)
}

///|
/// The name of the branch of a task.
pub fn branch_of(id : String) -> String {
  "papilot/" + id
}

///|
/// The path of the worktree of a task.
pub fn worktree_of(directory : String, id : String) -> String {
  directory + "/" + id
}

///|
/// Create a task.
///
/// The task starts from the current commit of the repository. The branch and
/// the worktree are new, so the branch and the working tree of the author are
/// never touched.
pub async fn create(
  repo : String,
  id : String,
  main : String,
  engine : String,
  worktree_directory : String,
  source_dir : String,
) -> Task? {
  let base = match @git.head(repo) {
    Some(b) => b
    None => return None
  }
  let branch = branch_of(id)
  let worktree = worktree_of(worktree_directory, id)
  // A task that is already there is taken up again, so that the next round
  // of the same task works in the same worktree.
  if @fs.exists(worktree) {
    let base = match @git.head(repo) {
      Some(commit) => commit
      None => return None
    }
    return Some(Task::{
      id,
      repo,
      worktree,
      branch,
      base,
      main,
      engine,
      source_dir,
    })
  }
  // The folder of the worktrees has to exist before Git puts one in it.
  @fs.mkdir(worktree_directory, recursive=true) catch {
    _ => ()
  }
  let output = @git.add_worktree(repo, worktree, branch)
  if !output.ok() {
    return None
  }
  Some(Task::{ id, repo, worktree, branch, base, main, engine, source_dir, })
}

///|
/// The edits the agent made, compared with the base of the task.
pub async fn edits_of(task : Task) -> Array[SourceEdit] {
  let output = @git.git(task.worktree, ["diff", "--unified=0", task.base, "--"])
  if !output.ok() {
    return []
  }
  parse_unified_diff(output.stdout)
}

///|
/// The edit of the source that a change belongs to.
///
/// The change is on a page of the proposal, and the SyncTeX file of the
/// proposal says which lines produced it. The edit that covers those lines is
/// the edit the author is accepting or rejecting.
pub fn edit_of(
  edits : Array[SourceEdit],
  synctex : @synctex.SynctexFile,
  change : @compare.Change,
) -> SourceEdit? {
  let locations = synctex.lines_at(change.page, change.rect)
  for location in locations {
    for edit in edits {
      if edit.covers(location.file, location.line) {
        return Some(edit)
      }
    }
  }
  None
}

///|
/// The number of the edit a change belongs to.
pub fn index_of_edit(
  edits : Array[SourceEdit],
  synctex : @synctex.SynctexFile,
  change : @compare.Change,
) -> Int32? {
  let locations = synctex.lines_at(change.page, change.rect)
  for location in locations {
    let mut index = 0
    while index < edits.length() {
      if edits[index].covers(location.file, location.line) {
        return Some(index)
      }
      index = index + 1
    }
  }
  None
}
