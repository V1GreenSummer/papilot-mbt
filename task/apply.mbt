///|
/// The text of a file with a range of lines replaced.
///
/// The lines are counted from one, the way a diff counts them.
pub fn replace_lines(
  content : String,
  start : Int32,
  length : Int32,
  text : String,
) -> String {
  let lines = split_lines(content)
  let replacement = split_lines(text)
  let out = StringBuilder()
  let mut index = 0
  while index < lines.length() {
    if index == start - 1 {
      // The range that is replaced.
      let mut r = 0
      while r < replacement.length() {
        out.write_string(replacement[r])
        out.write_char('\n')
        r = r + 1
      }
      index = index + length
      continue
    }
    out.write_string(lines[index])
    out.write_char('\n')
    index = index + 1
  }
  out.to_string()
}

///|
/// Split text into lines, without the newline at the end of each line.
pub fn split_lines(content : String) -> Array[String] {
  let lines = []
  let current = StringBuilder()
  for c in content.to_array() {
    if c == '\n' {
      lines.push(current.to_string())
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  if current.to_string().length() > 0 {
    lines.push(current.to_string())
  }
  lines
}

///|
/// The text of a file with the edit applied, in the version of the edit.
///
/// An edit replaces the lines of the base version with new ones. The reverse
/// puts the old lines back.
pub fn apply_edit(content : String, edit : SourceEdit, to_new : Bool) -> String {
  if to_new {
    replace_lines(content, edit.base_start, edit.base_len, edit.new_text)
  } else {
    replace_lines(content, edit.new_start, edit.new_len, edit.old_text)
  }
}

///|
/// Accept an edit: put it into the working tree of the author.
///
/// The merge keeps the changes of the author that do not touch the edit, so
/// that accepting one change does not lose the others. When both sides touch
/// the same lines the merge fails and the change is not applied.
pub async fn accept(task : Task, edit : SourceEdit) -> Bool {
  let path = task.repo + "/" + edit.file
  let base = match @git.show_file(task.repo, task.base, edit.file) {
    Some(content) => content
    None => return false
  }
  let ours = match read_file(path) {
    Some(content) => content
    None => return false
  }
  // The version of the file with the edit, built on the base of the task.
  let theirs = apply_edit(base, edit, true)
  let merged = merge(base, ours, theirs)
  match merged {
    Some(content) => write_file(path, content)
    None => false
  }
}

///|
/// Reject an edit: take it back out of the worktree of the agent.
///
/// The rejection is done in the worktree, so that the next round shows the
/// proposal without the change the author turned down.
pub async fn reject(task : Task, edit : SourceEdit) -> Bool {
  let path = task.worktree + "/" + edit.file
  let current = match read_file(path) {
    Some(content) => content
    None => return false
  }
  let reverted = apply_edit(current, edit, false)
  write_file(path, reverted)
}

///|
/// Undo an accepted edit: take it back out of the working tree.
pub async fn undo_accept(task : Task, edit : SourceEdit) -> Bool {
  let path = task.repo + "/" + edit.file
  let base = match @git.show_file(task.repo, task.base, edit.file) {
    Some(content) => content
    None => return false
  }
  let ours = match read_file(path) {
    Some(content) => content
    None => return false
  }
  let theirs = apply_edit(base, edit, true)
  let merged = merge(theirs, ours, base)
  match merged {
    Some(content) => write_file(path, content)
    None => false
  }
}

///|
/// Undo a rejected edit: put it back into the worktree of the agent.
pub async fn undo_reject(task : Task, edit : SourceEdit) -> Bool {
  let path = task.worktree + "/" + edit.file
  let current = match read_file(path) {
    Some(content) => content
    None => return false
  }
  let restored = apply_edit(current, edit, true)
  write_file(path, restored)
}

///|
/// Merge two versions of a file with the version they share in common.
///
/// The merge is done by Git, which keeps the changes that do not overlap and
/// reports the ones that do.
pub async fn merge(base : String, ours : String, theirs : String) -> String? {
  let merged = @git.merge_files(base, ours, theirs)
  match merged {
    Some(content) => Some(content)
    None => None
  }
}

///|
/// Read a file.
pub async fn read_file(path : String) -> String? {
  let content = @fs.read_file(path) catch { _ => return None }
  Some(@utf8.decode_lossy(content.binary()))
}

///|
/// Write a file.
pub async fn write_file(path : String, content : String) -> Bool {
  @fs.write_file(path, @utf8.encode(content)) catch {
    _ => return false
  }
  true
}
