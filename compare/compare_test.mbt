///|
/// Build a page with one word per entry.
fn page_with(number : Int32, words : Array[String]) -> @pdftext.PageText {
  let glyphs = []
  let mut x = 72.0
  for word in words {
    for c in word.to_array() {
      glyphs.push(@pdftext.Glyph::new(c.to_string(), x, 700.0, 6.0, 10.0))
      x = x + 6.0
    }
    glyphs.push(@pdftext.Glyph::new(" ", x, 700.0, 6.0, 10.0))
    x = x + 6.0
  }
  @pdftext.PageText::new(number, 612.0, 792.0, glyphs)
}

///|
test "identical documents have no changes" {
  let old = @pdftext.PdfText::new([page_with(1, ["the", "same", "words"])])
  let new = @pdftext.PdfText::new([page_with(1, ["the", "same", "words"])])
  assert_eq(@compare.compare(old, new).length(), 0)
}

///|
test "a changed word is reported as a change" {
  let old = @pdftext.PdfText::new([page_with(1, ["the", "quick", "fox"])])
  let new = @pdftext.PdfText::new([page_with(1, ["the", "slow", "fox"])])
  let changes = @compare.compare(old, new)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].old_text, "quick")
  assert_eq(changes[0].new_text, "slow")
  assert_eq(changes[0].page, 1)
}

///|
test "an inserted word is reported as a change" {
  let old = @pdftext.PdfText::new([page_with(1, ["a", "fox"])])
  let new = @pdftext.PdfText::new([page_with(1, ["a", "red", "fox"])])
  let changes = @compare.compare(old, new)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].old_text, "")
  assert_eq(changes[0].new_text, "red")
}

///|
test "a deleted word is reported as a change" {
  let old = @pdftext.PdfText::new([page_with(1, ["a", "red", "fox"])])
  let new = @pdftext.PdfText::new([page_with(1, ["a", "fox"])])
  let changes = @compare.compare(old, new)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].old_text, "red")
  assert_eq(changes[0].new_text, "")
}

///|
test "the change covers the area of the new text" {
  let old = @pdftext.PdfText::new([page_with(1, ["the", "quick", "fox"])])
  let new = @pdftext.PdfText::new([page_with(1, ["the", "slow", "fox"])])
  let changes = @compare.compare(old, new)
  let rect = changes[0].rect
  assert_true(rect.width > 0.0)
  assert_true(rect.height > 0.0)
}

///|
test "changes are reported on every page" {
  let old = @pdftext.PdfText::new([page_with(1, ["one"]), page_with(2, ["two"])])
  let new = @pdftext.PdfText::new([page_with(1, ["one"]), page_with(2, ["TWO"])])
  let changes = @compare.compare(old, new)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].page, 2)
}

///|
test "a change is turned into JSON for the client" {
  let old = @pdftext.PdfText::new([page_with(1, ["the", "quick", "fox"])])
  let new = @pdftext.PdfText::new([page_with(1, ["the", "slow", "fox"])])
  let changes = @compare.compare(old, new)
  let json = changes[0].to_json()
  assert_eq(@jsonx.text(json, "old_text"), "quick")
  assert_eq(@jsonx.text(json, "new_text"), "slow")
  assert_eq(@jsonx.number(json, "page"), 1)
}

///|
test "the change covers the words that replaced the old ones" {
  // A page whose first line is not prose: the words of the diff and the words
  // of the page have to be the same sequence, or the area of the change is
  // lost.
  let old = @pdftext.PdfText::new([
    page_with(1, ["\\section{Hello}", "The", "quick", "brown", "fox."]),
  ])
  let new = @pdftext.PdfText::new([
    page_with(1, ["\\section{Hello}", "The", "quick", "red", "fox."]),
  ])
  let changes = @compare.compare(old, new)
  assert_eq(changes.length(), 1)
  assert_eq(changes[0].old_text, "brown")
  assert_eq(changes[0].new_text, "red")
  assert_true(changes[0].rect.x > 100.0)
  assert_true(changes[0].rect.width > 5.0)
  assert_true(changes[0].rect.height > 5.0)
}
