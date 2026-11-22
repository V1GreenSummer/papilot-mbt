///|
pub extend Span with Eq::{not_equal, equal}

///|
pub extend Span with @debug.Debug::{to_repr}

///|
/// A half-open range of character offsets `[start, end)` inside a source file.
///
/// Offsets are counted in Unicode characters, not bytes or UTF-16 code units,
/// so they index directly into the character array of a `Source`.
#derive(Eq)
#derive(@debug.Debug)
pub struct Span {
  start : Int32
  end : Int32
}

///|
pub fn Span::new(start : Int32, end : Int32) -> Span {
  { start, end, }
}

///|
pub fn Span::len(self : Span) -> Int32 {
  if self.end > self.start {
    self.end - self.start
  } else {
    0
  }
}

///|
pub fn Span::is_empty(self : Span) -> Bool {
  self.end <= self.start
}

///|
pub fn Span::contains(self : Span, offset : Int32) -> Bool {
  offset >= self.start && offset < self.end
}

///|
pub fn Span::contains_span(self : Span, other : Span) -> Bool {
  self.start <= other.start && other.end <= self.end
}

///|
pub fn Span::overlaps(self : Span, other : Span) -> Bool {
  self.start < other.end && other.start < self.end
}

///|
pub fn Span::union(self : Span, other : Span) -> Span {
  let start = if self.start < other.start { self.start } else { other.start }
  let end = if self.end > other.end { self.end } else { other.end }
  Span::new(start, end)
}

///|
pub fn Span::intersect(self : Span, other : Span) -> Span? {
  let start = if self.start > other.start { self.start } else { other.start }
  let end = if self.end < other.end { self.end } else { other.end }
  if start < end {
    Some(Span::new(start, end))
  } else {
    None
  }
}

///|
pub fn Span::shift(self : Span, delta : Int32) -> Span {
  Span::new(self.start + delta, self.end + delta)
}

///|
pub fn Span::to_string(self : Span) -> String {
  "Span(\{self.start}, \{self.end})"
}

///|
/// A source file kept as characters.
///
/// Spans index characters, and `String::clamped_view` indexes UTF-16 code
/// units, so text is always sliced through the character array.
pub struct Source {
  chars : Array[Char]
}

///|
pub fn Source::new(text : String) -> Source {
  { chars: text.to_array(), }
}

///|
pub fn Source::length(self : Source) -> Int32 {
  self.chars.length()
}

///|
pub fn Source::get(self : Source, offset : Int32) -> Char? {
  if offset >= 0 && offset < self.chars.length() {
    Some(self.chars[offset])
  } else {
    None
  }
}

///|
/// The text covered by `span`.
pub fn Source::text(self : Source, span : Span) -> String {
  String::from_array(self.chars.clamped_view(start=span.start, end=span.end))
}

///|
/// The text between `start` and `end`, without the surrounding braces.
pub fn Source::slice(self : Source, start : Int32, end : Int32) -> String {
  self.text(Span::new(start, end))
}

///|
/// The whole source as a string.
pub fn Source::to_string(self : Source) -> String {
  String::from_array(self.chars)
}
