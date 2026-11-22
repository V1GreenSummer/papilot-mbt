///|
/// The edits between two versions of a file, taken from a unified diff.
///
/// The diff is parsed without context, so every hunk is exactly the lines that
/// changed. That is what makes it possible to accept one change and leave the
/// rest of the file alone.
pub fn parse_unified_diff(diff : String) -> Array[SourceEdit] {
  let edits = []
  let lines = Array::from_iter(diff.split("\n"))
  let mut file = ""
  let mut index = 0
  while index < lines.length() {
    let line = lines[index].to_owned()
    if line.has_prefix("+++ ") {
      let path = line.clamped_view(start=4, end=line.length()).to_owned()
      file = strip_prefix(path, "b/")
    } else if line.has_prefix("@@") {
      let (base_start, base_len, new_start, new_len) = parse_hunk_header(line)
      let old_lines = []
      let new_lines = []
      let mut cursor = index + 1
      let mut old_seen = 0
      let mut new_seen = 0
      while cursor < lines.length() &&
            (old_seen < base_len || new_seen < new_len) {
        let body = lines[cursor].to_owned()
        let first = body.get_char(0).unwrap_or(' ')
        let content = body.clamped_view(start=1, end=body.length()).to_owned()
        match first {
          '-' => {
            old_lines.push(content)
            old_seen = old_seen + 1
          }
          '+' => {
            new_lines.push(content)
            new_seen = new_seen + 1
          }
          ' ' => {
            old_lines.push(content)
            new_lines.push(content)
            old_seen = old_seen + 1
            new_seen = new_seen + 1
          }
          '\\' => ()
          _ => break
        }
        cursor = cursor + 1
      }
      edits.push(SourceEdit::{
        file,
        base_start,
        base_len,
        new_start,
        new_len,
        old_text: join_lines(old_lines),
        new_text: join_lines(new_lines),
      })
      index = cursor
      continue
    }
    index = index + 1
  }
  edits
}

///|
/// Remove a prefix from a path.
fn strip_prefix(path : String, prefix : String) -> String {
  if path.has_prefix(prefix) {
    path.clamped_view(start=prefix.length(), end=path.length()).to_owned()
  } else {
    path
  }
}

///|
/// Join lines with a newline between them.
fn join_lines(lines : Array[String]) -> String {
  let out = StringBuilder()
  let mut first = true
  for line in lines {
    if !first {
      out.write_char('\n')
    }
    out.write_string(line)
    first = false
  }
  out.to_string()
}

///|
/// The numbers of a hunk header, such as `@@ -10,3 +10,4 @@`.
fn parse_hunk_header(line : String) -> (Int32, Int32, Int32, Int32) {
  let body = line.clamped_view(start=3, end=line.length()).to_owned()
  let body = match body.find("@@") {
    Some(index) => body.clamped_view(start=0, end=index).to_owned()
    None => body
  }
  let parts = []
  for part in body.split(" ") {
    let text = part.trim().to_owned()
    if !text.is_empty() {
      parts.push(text)
    }
  }
  if parts.length() < 2 {
    return (0, 0, 0, 0)
  }
  let old = parse_range(parts[0])
  let new = parse_range(parts[1])
  (old.0, old.1, new.0, new.1)
}

///|
/// The start and the length of a range such as `-10,3` or `-10`.
fn parse_range(text : String) -> (Int32, Int32) {
  let body = match text.get_char(0) {
    Some('-') | Some('+') =>
      text.clamped_view(start=1, end=text.length()).to_owned()
    _ => text
  }
  match body.find(",") {
    Some(index) => {
      let start = @strconv.parse_int(
        body.clamped_view(start=0, end=index).to_owned(),
      ) catch {
        _ => 0
      }
      let length = @strconv.parse_int(
        body.clamped_view(start=index + 1, end=body.length()).to_owned(),
      ) catch {
        _ => 0
      }
      (start, length)
    }
    None => {
      let start = @strconv.parse_int(body) catch { _ => 0 }
      (start, 1)
    }
  }
}

///|
/// The edits between two commits of a repository.
pub async fn edits_between(
  repo : String,
  base : String,
  head : String,
) -> Array[SourceEdit] {
  let output = @git.git(repo, ["diff", "--unified=0", base, head, "--"])
  if !output.ok() {
    return []
  }
  parse_unified_diff(output.stdout)
}

///|
/// The edits of one file between two commits of a repository.
pub async fn edits_of_file(
  repo : String,
  base : String,
  head : String,
  file : String,
) -> Array[SourceEdit] {
  let output = @git.git(repo, ["diff", "--unified=0", base, head, "--", file])
  if !output.ok() {
    return []
  }
  parse_unified_diff(output.stdout)
}
