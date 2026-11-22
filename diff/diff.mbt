///|
pub extend ChangeKind with Eq::{not_equal, equal}

///|
pub extend ChangeKind with @debug.Debug::{to_repr}

///|
pub extend Difference with Eq::{not_equal, equal}

///|
pub extend Difference with @debug.Debug::{to_repr}

///|
pub extend LineDifference with Eq::{not_equal, equal}

///|
pub extend LineDifference with @debug.Debug::{to_repr}

///|
pub extend MovedPassage with Eq::{not_equal, equal}

///|
pub extend MovedPassage with @debug.Debug::{to_repr}

///|
/// What a difference does to the text.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum ChangeKind {
  /// Words only exist in the old text.
  Removed
  /// Words only exist in the new text.
  Added
  /// Words were replaced by different words.
  Replaced
}

///|
pub fn ChangeKind::to_string(self : ChangeKind) -> String {
  match self {
    Removed => "Removed"
    Added => "Added"
    Replaced => "Replaced"
  }
}

///|
/// A difference between two sequences of words.
#derive(Eq)
#derive(@debug.Debug)
pub struct Difference {
  kind : ChangeKind
  /// The words that are only in the old text.
  removed : Array[Word]
  /// The words that are only in the new text.
  added : Array[Word]
  /// The index in the old word sequence where the difference starts.
  old_start : Int32
  /// The index in the new word sequence where the difference starts.
  new_start : Int32
}

///|
pub fn Difference::old_start(self : Difference) -> Int32 {
  self.old_start
}

///|
pub fn Difference::new_start(self : Difference) -> Int32 {
  self.new_start
}

///|
pub fn Difference::removed(self : Difference) -> Array[Word] {
  self.removed
}

///|
pub fn Difference::added(self : Difference) -> Array[Word] {
  self.added
}

///|
pub fn Difference::kind(self : Difference) -> ChangeKind {
  self.kind
}

///|
/// The old text of the difference, as it appears in the original.
pub fn Difference::old_text(self : Difference) -> String {
  join_words(self.removed)
}

///|
/// The new text of the difference, as it appears in the proposal.
pub fn Difference::new_text(self : Difference) -> String {
  join_words(self.added)
}

///|
pub fn Difference::to_string(self : Difference) -> String {
  "\{self.kind.to_string()}: -\{self.old_text()} +\{self.new_text()}"
}

///|
/// Join words back into readable text.
pub fn join_words(words : Array[Word]) -> String {
  let out = StringBuilder()
  let mut first = true
  for w in words {
    let full = w.full()
    if !first && needs_space(out.to_string(), full) {
      out.write_char(' ')
    }
    out.write_string(full)
    first = false
  }
  out.to_string()
}

///|
/// Punctuation that closes a bracket or a quotation and takes no space after.
fn is_closing_bracket(c : Char) -> Bool {
  c == ')' || c == ']' || c == '}' || c == '>' || c == '"' || c == '\u{201D}'
}

///|
/// Whether a space is needed between the text so far and the next word.
fn needs_space(so_far : String, next : String) -> Bool {
  if so_far.is_empty() || next.is_empty() {
    return false
  }
  let last = so_far.get_char(so_far.length() - 1).unwrap_or(' ')
  let first = next.get_char(0).unwrap_or(' ')
  if is_opening_punctuation(first) {
    return false
  }
  if is_closing_bracket(last) {
    return false
  }
  true
}

///|
/// Compare two sequences of words and return the differences between them.
///
/// Adjacent deletions and insertions are merged into a single `Replaced`
/// difference, so that a rewritten sentence reads as one change instead of a
/// deletion followed by an insertion.
pub fn diff_words(old : Array[Word], new : Array[Word]) -> Array[Difference] {
  let old_keys = word_keys(old)
  let new_keys = word_keys(new)
  let differences = []
  let d = @corelib.Diff::Diff(old=old_keys, new=new_keys)
  let edits = d.edits()
  let i = Ref(0)
  while i.val < edits.length() {
    let edit = edits[i.val]
    match edit {
      @corelib.Edit::Equal(_) => i.val = i.val + 1
      @corelib.Edit::Delete(old_index~, old_len~, new_index~) => {
        let removed = slice_words(old, old_index, old_index + old_len)
        // A deletion that is followed by an insertion is a replacement.
        let mut added = []
        let mut new_cursor = new_index
        let mut j = i.val + 1
        while j < edits.length() {
          match edits[j] {
            @corelib.Edit::Insert(old_index~, new_index~, new_len~) => {
              // The insertion stands at the same place of the old text.
              let _ = old_index
              added = slice_words(new, new_index, new_index + new_len)
              new_cursor = new_index
              j = j + 1
              break
            }
            _ => break
          }
        }
        let kind = if added.is_empty() {
          ChangeKind::Removed
        } else {
          ChangeKind::Replaced
        }
        differences.push(Difference::{
          kind,
          removed,
          added,
          old_start: old_index,
          new_start: new_cursor,
        })
        i.val = j
      }
      @corelib.Edit::Insert(old_index~, new_index~, new_len~) => {
        let added = slice_words(new, new_index, new_index + new_len)
        // An insertion that is followed by a deletion is a replacement.
        let mut removed = []
        let mut j = i.val + 1
        while j < edits.length() {
          match edits[j] {
            @corelib.Edit::Delete(old_index~, old_len~, ..) => {
              removed = slice_words(old, old_index, old_index + old_len)
              j = j + 1
              break
            }
            _ => break
          }
        }
        let kind = if removed.is_empty() {
          ChangeKind::Added
        } else {
          ChangeKind::Replaced
        }
        differences.push(Difference::{
          kind,
          removed,
          added,
          old_start: old_index,
          new_start: new_index,
        })
        i.val = j
      }
    }
  }
  differences
}

///|
/// Compare two texts word by word.
pub fn diff_text(old : String, new : String) -> Array[Difference] {
  diff_words(tokenize_words(old), tokenize_words(new))
}

///|
/// The words of `words` between two indices.
fn slice_words(words : Array[Word], start : Int32, end : Int32) -> Array[Word] {
  let out = []
  let from = if start < 0 { 0 } else { start }
  let to = if end > words.length() { words.length() } else { end }
  let mut i = from
  while i < to {
    out.push(words[i])
    i = i + 1
  }
  out
}

///|
/// A passage that appears in both texts, at different places.
#derive(Eq)
#derive(@debug.Debug)
pub struct MovedPassage {
  /// The words of the passage.
  words : Array[Word]
  /// Where the passage starts in the old text.
  old_start : Int32
  /// Where the passage starts in the new text.
  new_start : Int32
  /// How many words the passage has.
  length : Int32
}

///|
pub fn MovedPassage::to_string(self : MovedPassage) -> String {
  "Moved(\{self.old_start} -> \{self.new_start}, \{self.length} words)"
}

///|
/// The number of letters and digits in a passage.
///
/// Moved passages need enough substance to be worth reporting; a handful of
/// common words that happen to reappear is not a move.
pub fn MovedPassage::substance(self : MovedPassage) -> Int32 {
  let count = Ref(0)
  for w in self.words {
    for c in w.word {
      if c.is_ascii_alphabetic() || c.is_ascii_digit() {
        count.val = count.val + 1
      }
    }
  }
  count.val
}

///|
/// Find passages that moved.
///
/// A passage is a run of words that both texts share, but at different
/// positions relative to the surrounding text. Only passages with enough
/// letters and digits are reported, so that ordinary re-wrapping is not
/// mistaken for a move.
pub fn find_moves(
  old : Array[Word],
  new : Array[Word],
  min_substance~ : Int32 = 20,
) -> Array[MovedPassage] {
  let old_keys = word_keys(old)
  let new_keys = word_keys(new)
  let d = @corelib.Diff::Diff(old=old_keys, new=new_keys)
  let edits = d.edits()
  let moves = []
  for edit in edits {
    match edit {
      @corelib.Edit::Equal(old_index~, new_index~, len~) => {
        // The run is in the same relative place when the number of words
        // before it is the same in both texts.
        let aligned = old_index == new_index
        if !aligned && len > 0 {
          let words = slice_words(old, old_index, old_index + len)
          let passage = MovedPassage::{
            words,
            old_start: old_index,
            new_start: new_index,
            length: len,
          }
          if passage.substance() >= min_substance {
            moves.push(passage)
          }
        }
      }
      _ => ()
    }
  }
  moves
}

///|
/// A difference between two sequences of lines.
#derive(Eq)
#derive(@debug.Debug)
pub struct LineDifference {
  /// The lines that are only in the old text.
  removed : Array[String]
  /// The lines that are only in the new text.
  added : Array[String]
  /// The line number in the old text where the difference starts.
  old_start : Int32
  /// The line number in the new text where the difference starts.
  new_start : Int32
}

///|
pub fn LineDifference::to_string(self : LineDifference) -> String {
  "Lines(-=\{self.removed.length()} +=\{self.added.length()})"
}

///|
/// Compare two texts line by line.
pub fn diff_lines(old : String, new : String) -> Array[LineDifference] {
  let old_lines = split_lines(old)
  let new_lines = split_lines(new)
  let differences = []
  let d = @corelib.Diff::Diff(old=old_lines, new=new_lines)
  let edits = d.edits()
  let i = Ref(0)
  while i.val < edits.length() {
    match edits[i.val] {
      @corelib.Edit::Equal(_) => i.val = i.val + 1
      @corelib.Edit::Delete(old_index~, old_len~, new_index~) => {
        let removed = []
        let mut k = 0
        while k < old_len {
          removed.push(old_lines[old_index + k])
          k = k + 1
        }
        let added = []
        let mut j = i.val + 1
        let mut new_cursor = new_index
        while j < edits.length() {
          match edits[j] {
            @corelib.Edit::Insert(old_index~, new_index~, new_len~) => {
              // The insertion stands at the same place of the old text.
              let _ = old_index
              let mut m = 0
              while m < new_len {
                added.push(new_lines[new_index + m])
                m = m + 1
              }
              new_cursor = new_index
              j = j + 1
              break
            }
            _ => break
          }
        }
        differences.push(LineDifference::{
          removed,
          added,
          old_start: old_index,
          new_start: new_cursor,
        })
        i.val = j
      }
      @corelib.Edit::Insert(old_index~, new_index~, new_len~) => {
        let added = []
        let mut k = 0
        while k < new_len {
          added.push(new_lines[new_index + k])
          k = k + 1
        }
        differences.push(LineDifference::{
          removed: [],
          added,
          old_start: old_index,
          new_start: new_index,
        })
        i.val = i.val + 1
      }
    }
  }
  differences
}

///|
/// Split text into lines, keeping empty lines.
pub fn split_lines(text : String) -> Array[String] {
  let lines = []
  let current = StringBuilder()
  for c in text.to_array() {
    if c == '\n' {
      lines.push(current.to_string())
      current.reset()
    } else {
      current.write_char(c)
    }
  }
  lines.push(current.to_string())
  lines
}
