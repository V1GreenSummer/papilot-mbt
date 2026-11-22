///|
pub extend Located with Eq::{not_equal, equal}

///|
pub extend Located with @debug.Debug::{to_repr}

///|
/// A place on the page, with the source it came from.
#derive(Eq)
#derive(@debug.Debug)
pub struct Located {
  /// The source location.
  source : @synctex.SourceLocation
  /// The area of the page the location covers.
  rect : @synctex.Rect
}

///|
/// Find the source of an area of a page.
///
/// This is the heart of the idea: the author marks a place on the page and the
/// source is found. The typeset output and the SyncTeX file are matched by
/// their reading order and by the number of words they hold, so a document that
/// changed still lines up.
pub fn locate(
  page : @pdftext.PageText,
  synctex : @synctex.SynctexFile,
  number : Int32,
  rect : @synctex.Rect,
) -> Located? {
  let lines = page.lines()
  if lines.is_empty() {
    return None
  }
  // The line of the page that holds the middle of the area.
  let center_x = rect.center_x()
  let center_y = rect.center_y()
  let mut best = -1
  let mut best_distance = 1000000.0
  for i in 0..<lines.length() {
    let line = lines[i]
    let line_rect = @synctex.Rect::new(line.x, line.y, line.width, line.height)
    let distance = if line_rect.contains_point(center_x, center_y) {
      0.0
    } else {
      let dx = if center_x < line_rect.x {
        line_rect.x - center_x
      } else if center_x > line_rect.right() {
        center_x - line_rect.right()
      } else {
        0.0
      }
      let dy = if center_y < line_rect.y {
        line_rect.y - center_y
      } else if center_y > line_rect.top() {
        center_y - line_rect.top()
      } else {
        0.0
      }
      dx * dx + dy * dy
    }
    if distance < best_distance {
      best_distance = distance
      best = i
    }
  }
  if best < 0 {
    return None
  }
  // Match the lines of the page with the lines of the typeset output.
  let counts = []
  for line in lines {
    counts.push(word_count(line))
  }
  let matches = synctex.match_lines(number, counts)
  if best >= matches.length() {
    return None
  }
  let index = matches[best]
  if index < 0 {
    return None
  }
  match synctex.source_of_line(number, index) {
    Some(source) => {
      let line = lines[best]
      Some(Located::{
        source,
        rect: @synctex.Rect::new(line.x, line.y, line.width, line.height),
      })
    }
    None => None
  }
}

///|
/// The number of words of a line of the page.
fn word_count(line : @pdftext.Line) -> Int32 {
  let text = line.text
  if text.is_empty() {
    return 0
  }
  let count = Ref(1)
  for c in text.to_array() {
    if c == ' ' {
      count.val = count.val + 1
    }
  }
  count.val
}

///|
/// Find the source of every change of a document.
pub fn locate_all(
  pages : @pdftext.PdfText,
  synctex : @synctex.SynctexFile,
  changes : Array[Change],
) -> Array[Located?] {
  let found = []
  for change in changes {
    let located = match pages.page(change.page) {
      Some(page) => locate(page, synctex, change.page, change.rect)
      None => None
    }
    found.push(located)
  }
  found
}
