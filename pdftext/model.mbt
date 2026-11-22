///|
pub extend Glyph with Eq::{not_equal, equal}

///|
pub extend Glyph with @debug.Debug::{to_repr}

///|
pub extend PageText with Eq::{not_equal, equal}

///|
pub extend PageText with @debug.Debug::{to_repr}

///|
pub extend Word with Eq::{not_equal, equal}

///|
pub extend Word with @debug.Debug::{to_repr}

///|
pub extend PdfText with Eq::{not_equal, equal}

///|
pub extend PdfText with @debug.Debug::{to_repr}

///|
/// A glyph placed on a page.
///
/// The position is the lower left corner of the glyph in PDF points, with the
/// origin at the bottom left of the page. The width is the advance width, so
/// that the distance between two neighbouring glyphs tells whether there was a
/// space between them.
#derive(Eq)
#derive(@debug.Debug)
pub struct Glyph {
  /// The text the glyph stands for.
  text : String
  x : Double
  y : Double
  width : Double
  height : Double
  /// The font the glyph was set in.
  font : String
  /// The size the glyph was set at.
  size : Double
}

///|
pub fn Glyph::new(
  text : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  font~ : String = "",
  size~ : Double = 0.0,
) -> Glyph {
  { text, x, y, width, height, font, size, }
}

///|
pub fn Glyph::to_string(self : Glyph) -> String {
  "Glyph(\{self.text} at \{self.x}, \{self.y})"
}

///|
/// The right edge of the glyph.
pub fn Glyph::right(self : Glyph) -> Double {
  self.x + self.width
}

///|
/// The vertical centre of the glyph.
pub fn Glyph::middle_y(self : Glyph) -> Double {
  self.y + self.height / 2.0
}

///|
/// A run of glyphs on one baseline.
pub struct Line {
  /// The text of the line.
  text : String
  /// The left edge of the line.
  x : Double
  /// The bottom of the line.
  y : Double
  /// The width of the line.
  width : Double
  /// The height of the line.
  height : Double
}

///|
/// The text of one page together with the position of every glyph.
#derive(Eq)
#derive(@debug.Debug)
pub struct PageText {
  /// The number of the page, starting at one.
  number : Int32
  /// The width of the page in PDF points.
  width : Double
  /// The height of the page in PDF points.
  height : Double
  /// The glyphs in the order they were drawn.
  glyphs : Array[Glyph]
}

///|
pub fn PageText::new(
  number : Int32,
  width : Double,
  height : Double,
  glyphs : Array[Glyph],
) -> PageText {
  { number, width, height, glyphs, }
}

///|
/// The lines of the page, in reading order.
///
/// Glyphs are grouped by their vertical centre; glyphs that belong to the same
/// line but were drawn out of order are put back in order by their position.
pub fn PageText::lines(self : PageText) -> Array[Line] {
  let glyphs = self.glyphs.filter(fn(g) { !g.text.is_empty() })
  if glyphs.is_empty() {
    return []
  }
  // Group the glyphs into lines by their vertical position.
  let sorted = glyphs.copy()
  sorted.sort_by(fn(a, b) {
    if a.middle_y() != b.middle_y() {
      b.middle_y().compare(a.middle_y())
    } else {
      a.x.compare(b.x)
    }
  })
  let groups = []
  let mut current = []
  let mut current_y = 0.0
  let mut tolerance = 0.0
  for glyph in sorted {
    if current.is_empty() {
      current.push(glyph)
      current_y = glyph.middle_y()
      tolerance = glyph.height * 0.5
      continue
    }
    if (glyph.middle_y() - current_y).abs() <= tolerance {
      current.push(glyph)
    } else {
      groups.push(current)
      current = [glyph]
      current_y = glyph.middle_y()
      tolerance = glyph.height * 0.5
    }
  }
  if !current.is_empty() {
    groups.push(current)
  }
  let lines = []
  for group in groups {
    let ordered = group.copy()
    ordered.sort_by(fn(a, b) { a.x.compare(b.x) })
    let text = StringBuilder()
    let mut previous : Glyph? = None
    let mut min_x = ordered[0].x
    let mut max_x = ordered[0].right()
    let mut min_y = ordered[0].y
    let mut max_y = ordered[0].y + ordered[0].height
    for glyph in ordered {
      match previous {
        Some(p) => {
          let gap = glyph.x - p.right()
          if gap > p.height * 0.12 {
            text.write_char(' ')
          }
        }
        None => ()
      }
      text.write_string(glyph.text)
      if glyph.x < min_x {
        min_x = glyph.x
      }
      if glyph.right() > max_x {
        max_x = glyph.right()
      }
      if glyph.y < min_y {
        min_y = glyph.y
      }
      if glyph.y + glyph.height > max_y {
        max_y = glyph.y + glyph.height
      }
      previous = Some(glyph)
    }
    lines.push(Line::{
      text: text.to_string(),
      x: min_x,
      y: min_y,
      width: max_x - min_x,
      height: max_y - min_y,
    })
  }
  lines
}

///|
/// The text of the page as a single string, one line per row.
pub fn PageText::text(self : PageText) -> String {
  let parts = []
  for line in self.lines() {
    parts.push(line.text)
  }
  parts.join("\n")
}

///|
/// The glyphs of the page that lie inside a rectangle.
pub fn PageText::glyphs_in(
  self : PageText,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Array[Glyph] {
  let found = []
  for glyph in self.glyphs {
    let gx0 = glyph.x
    let gy0 = glyph.y
    let gx1 = glyph.right()
    let gy1 = glyph.y + glyph.height
    if gx0 < x + width && x < gx1 && gy0 < y + height && y < gy1 {
      found.push(glyph)
    }
  }
  found
}

///|
/// All the text of a PDF, page by page.
#derive(Eq)
#derive(@debug.Debug)
pub struct PdfText {
  pages : Array[PageText]
}

///|
pub fn PdfText::new(pages : Array[PageText]) -> PdfText {
  { pages, }
}

///|
/// The number of pages.
pub fn PdfText::page_count(self : PdfText) -> Int32 {
  self.pages.length()
}

///|
/// The text of a page, if it exists.
pub fn PdfText::page(self : PdfText, number : Int32) -> PageText? {
  for p in self.pages {
    if p.number == number {
      return Some(p)
    }
  }
  None
}

///|
/// The whole text of the document.
pub fn PdfText::text(self : PdfText) -> String {
  let parts = []
  for p in self.pages {
    parts.push(p.text())
  }
  parts.join("\n")
}

///|
/// A word of running text with the area it occupies on the page.
#derive(Eq)
#derive(@debug.Debug)
pub struct Word {
  /// The text of the word.
  text : String
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
pub fn Word::to_string(self : Word) -> String {
  "Word(\{self.text})"
}

///|
/// The area the word occupies.
pub fn Word::rect(self : Word) -> @synctex.Rect {
  @synctex.Rect::new(self.x, self.y, self.width, self.height)
}

///|
/// The words of the page, in reading order.
///
/// Words are built from the glyphs of a line: a run of glyphs that touches its
/// neighbour becomes one word, and a gap wider than a fifth of the line height
/// separates two words.
pub fn PageText::words(self : PageText) -> Array[Word] {
  let words = []
  for line in self.lines() {
    let glyphs = self.glyphs_in(line.x, line.y, line.width, line.height)
    let ordered = glyphs.copy()
    ordered.sort_by(fn(a, b) { a.x.compare(b.x) })
    let mut current = []
    let mut previous : Glyph? = None
    for glyph in ordered {
      // A drawn space ends the word it stands in.
      if glyph.text.trim().is_empty() {
        flush_word(words, current, line)
        current = []
        previous = None
        continue
      }
      match previous {
        Some(p) => {
          let gap = glyph.x - p.right()
          if gap > p.height * 0.12 {
            flush_word(words, current, line)
            current = []
          }
        }
        None => ()
      }
      current.push(glyph)
      previous = Some(glyph)
    }
    flush_word(words, current, line)
  }
  words
}

///|
/// Turn a run of glyphs into a word and add it to the list.
fn flush_word(words : Array[Word], glyphs : Array[Glyph], line : Line) -> Unit {
  if glyphs.is_empty() {
    return
  }
  let text = StringBuilder()
  let mut min_x = glyphs[0].x
  let mut max_x = glyphs[0].right()
  for glyph in glyphs {
    text.write_string(glyph.text)
    if glyph.x < min_x {
      min_x = glyph.x
    }
    if glyph.right() > max_x {
      max_x = glyph.right()
    }
  }
  words.push(Word::{
    text: text.to_string(),
    x: min_x,
    y: line.y,
    width: max_x - min_x,
    height: line.height,
  })
}

///|
/// The texts of a list of words.
pub fn words_text(words : Array[Word]) -> String {
  let parts = []
  for w in words {
    parts.push(w.text)
  }
  parts.join(" ")
}

///|
/// A slice of a list of words.
pub fn words_slice(
  words : Array[Word],
  start : Int32,
  length : Int32,
) -> Array[Word] {
  let out = []
  let from = if start < 0 { 0 } else { start }
  let to = if start + length > words.length() {
    words.length()
  } else {
    start + length
  }
  let mut i = from
  while i < to {
    out.push(words[i])
    i = i + 1
  }
  out
}
