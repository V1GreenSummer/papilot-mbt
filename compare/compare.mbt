///|
pub extend Change with Eq::{not_equal, equal}

///|
pub extend Change with @debug.Debug::{to_repr}

///|
/// A change between two versions of a document.
///
/// A change is what the author sees: an area of the page that reads
/// differently before and after.
#derive(Eq)
#derive(@debug.Debug)
pub struct Change {
  /// The number of the page the change is on.
  page : Int32
  /// The area of the page the change covers.
  rect : @synctex.Rect
  /// The text before the change.
  old_text : String
  /// The text after the change.
  new_text : String
  /// The words that were there before.
  old_words : Array[String]
  /// The words that are there now.
  new_words : Array[String]
}

///|
pub fn Change::to_string(self : Change) -> String {
  "Change(page=\{self.page}, -\{self.old_text} +\{self.new_text})"
}

///|
pub fn Change::new(
  page : Int32,
  rect : @synctex.Rect,
  old_text : String,
  new_text : String,
) -> Change {
  { page, rect, old_text, new_text, old_words: [], new_words: [], }
}

///|
/// A change as the client sees it.
pub fn Change::to_json(self : Change) -> Json {
  Json::object({
    "page": Json::number(self.page.to_double()),
    "rect": Json::object({
      "x": Json::number(self.rect.x),
      "y": Json::number(self.rect.y),
      "width": Json::number(self.rect.width),
      "height": Json::number(self.rect.height),
    }),
    "old_text": Json::string(self.old_text),
    "new_text": Json::string(self.new_text),
  })
}

///|
/// The change of a JSON object.
pub fn Change::from_json(json : Json) -> Change? {
  let page = @jsonx.number(json, "page")
  let rect = match @jsonx.field(json, "rect") {
    Some(r) =>
      @synctex.Rect::new(
        @jsonx.real(r, "x"),
        @jsonx.real(r, "y"),
        @jsonx.real(r, "width"),
        @jsonx.real(r, "height"),
      )
    None => return None
  }
  let old_text = @jsonx.text(json, "old_text")
  let new_text = @jsonx.text(json, "new_text")
  Some(Change::{ page, rect, old_text, new_text, old_words: [], new_words: [], })
}

///|
/// The area covered by a set of words.
fn rect_of(words : Array[@pdftext.Word]) -> @synctex.Rect {
  if words.is_empty() {
    return @synctex.Rect::new(0.0, 0.0, 0.0, 0.0)
  }
  let mut min_x = words[0].x
  let mut min_y = words[0].y
  let mut max_x = words[0].x + words[0].width
  let mut max_y = words[0].y + words[0].height
  for w in words {
    if w.x < min_x {
      min_x = w.x
    }
    if w.y < min_y {
      min_y = w.y
    }
    if w.x + w.width > max_x {
      max_x = w.x + w.width
    }
    if w.y + w.height > max_y {
      max_y = w.y + w.height
    }
  }
  @synctex.Rect::new(min_x, min_y, max_x - min_x, max_y - min_y)
}

///|
/// The texts of a list of words.
fn texts_of(words : Array[@pdftext.Word]) -> Array[String] {
  let texts = []
  for w in words {
    texts.push(w.text)
  }
  texts
}

///|
/// Compare two versions of a document and report what changed.
///
/// The comparison works on the words of the page, so that a change is
/// reported where it is seen and not where it was written.
pub fn compare(old : @pdftext.PdfText, new : @pdftext.PdfText) -> Array[Change] {
  let changes = []
  let page_count = if new.page_count() > old.page_count() {
    new.page_count()
  } else {
    old.page_count()
  }
  let mut number = 1
  while number <= page_count {
    let old_page = old.page(number)
    let new_page = new.page(number)
    match (old_page, new_page) {
      (Some(o), Some(n)) => {
        let page_changes = compare_page(o, n)
        for change in page_changes {
          changes.push(change)
        }
      }
      _ => ()
    }
    number = number + 1
  }
  changes
}

///|
/// Compare one page.
fn compare_page(
  old : @pdftext.PageText,
  new : @pdftext.PageText,
) -> Array[Change] {
  let changes = []
  let old_words = old.words()
  let new_words = new.words()
  // The words of the page are compared directly, so that the indices of the
  // difference line up with the words that carry the geometry of the page.
  let old_diff_words = old_words.map(fn(w) { @diff.Word::new(w.text) })
  let new_diff_words = new_words.map(fn(w) { @diff.Word::new(w.text) })
  let differences = @diff.diff_words(old_diff_words, new_diff_words)
  for difference in differences {
    let removed = @pdftext.words_slice(
      old_words,
      difference.old_start(),
      difference.removed().length(),
    )
    let added = @pdftext.words_slice(
      new_words,
      difference.new_start(),
      difference.added().length(),
    )
    // The area of the change is where the new text is; when the text was
    // deleted there is no new area, so the old one is used.
    let rect = if added.is_empty() { rect_of(removed) } else { rect_of(added) }
    changes.push(Change::{
      page: new.number,
      rect,
      old_text: difference.old_text(),
      new_text: difference.new_text(),
      old_words: texts_of(removed),
      new_words: texts_of(added),
    })
  }
  changes
}

///|
/// The source lines that a change touches.
///
/// The SyncTeX file of the new document says which lines produced the area of
/// the change.
pub fn source_of(
  change : Change,
  synctex : @synctex.SynctexFile,
) -> Array[@synctex.SourceLocation] {
  synctex.lines_at(change.page, change.rect)
}
