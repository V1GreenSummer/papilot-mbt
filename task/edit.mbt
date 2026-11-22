///|
pub extend SourceEdit with Eq::{not_equal, equal}

///|
pub extend SourceEdit with @debug.Debug::{to_repr}

///|
/// An edit of a source file, as the agent made it.
///
/// The edit is a range of lines of the base version and the lines that
/// replace it. It is the unit that is accepted or rejected, so it has to be
/// exact.
#derive(Eq)
#derive(@debug.Debug)
pub struct SourceEdit {
  /// The path of the file, relative to the repository.
  file : String
  /// The first line of the range in the base version.
  base_start : Int32
  /// The number of lines the range has in the base version.
  base_len : Int32
  /// The first line of the range in the new version.
  new_start : Int32
  /// The number of lines the range has in the new version.
  new_len : Int32
  /// The lines of the range in the base version.
  old_text : String
  /// The lines of the range in the new version.
  new_text : String
}

///|
pub fn SourceEdit::new(
  file : String,
  base_start : Int32,
  base_len : Int32,
  new_start : Int32,
  new_len : Int32,
  old_text : String,
  new_text : String,
) -> SourceEdit {
  { file, base_start, base_len, new_start, new_len, old_text, new_text, }
}

///|
pub fn SourceEdit::to_string(self : SourceEdit) -> String {
  "SourceEdit(\{self.file}:\{self.base_start}+\{self.base_len})"
}

///|
/// The last line of the range in the base version.
pub fn SourceEdit::base_end(self : SourceEdit) -> Int32 {
  self.base_start + self.base_len
}

///|
/// Whether the edit touches a line of a file, in the version the edit was
/// made against.
pub fn SourceEdit::covers(
  self : SourceEdit,
  file : String,
  line : Int32,
) -> Bool {
  if !same_file(self.file, file) {
    return false
  }
  line >= self.base_start && line < self.base_start + self.base_len
}

///|
/// Whether the edit touches a line of a file, in the version the edit
/// produced.
///
/// The SyncTeX file of the proposal knows the lines of the new version, so
/// this is the one that answers where a change of the page comes from.
pub fn SourceEdit::covers_new(
  self : SourceEdit,
  file : String,
  line : Int32,
) -> Bool {
  if !same_file(self.file, file) {
    return false
  }
  let length = if self.new_len > 0 { self.new_len } else { 1 }
  line >= self.new_start && line < self.new_start + length
}

///|
/// Whether two paths name the same file.
///
/// The edits of a task name the files the way the repository does, and the
/// SyncTeX file names them the way the compiler did, which is not always the
/// same.
pub fn same_file(a : String, b : String) -> Bool {
  basename(a) == basename(b)
}

///|
/// The last part of a path.
pub fn basename(path : String) -> String {
  match path.rev_find("/") {
    Some(index) =>
      path.clamped_view(start=index + 1, end=path.length()).to_owned()
    None => path
  }
}

///|
/// The line a change of a file belongs to.
pub fn SourceEdit::line_of(
  self : SourceEdit,
  file : String,
  line : Int32,
) -> Int32? {
  if self.covers(file, line) {
    Some(line)
  } else {
    None
  }
}
