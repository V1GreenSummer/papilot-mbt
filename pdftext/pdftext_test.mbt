///|
/// Build a one page PDF with a line of text at the given place.
///
/// The document is written by hand so that the test needs nothing but the
/// package itself.
fn make_pdf(text : String, x : Double, y : Double) -> Bytes {
  let content = "BT /F1 12 Tf " +
    x.to_string() +
    " " +
    y.to_string() +
    " Td (" +
    text +
    ") Tj ET"
  let objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Length " +
    content.length().to_string() +
    " >>\nstream\n" +
    content +
    "\nendstream",
  ]
  let out = StringBuilder()
  out.write_string("%PDF-1.4\n")
  let offsets = []
  for i in 0..<objects.length() {
    offsets.push(out.to_string().length())
    out.write_string(
      (i + 1).to_string() + " 0 obj\n" + objects[i] + "\nendobj\n",
    )
  }
  let start = out.to_string().length()
  out.write_string("xref\n0 " + (objects.length() + 1).to_string() + "\n")
  out.write_string("0000000000 65535 f \n")
  for offset in offsets {
    let digits = offset.to_string()
    let padding = "0000000000"
      .clamped_view(start=0, end=10 - digits.length())
      .to_owned()
    out.write_string(padding + digits + " 00000 n \n")
  }
  out.write_string(
    "trailer\n<< /Size " +
    (objects.length() + 1).to_string() +
    " /Root 1 0 R >>\nstartxref\n" +
    start.to_string() +
    "\n%%EOF\n",
  )
  @utf8.encode(out.to_string())
}

///|
test "the text of a page is read" {
  let bytes = make_pdf("Hello world", 72.0, 720.0)
  let text = @pdftext.extract(bytes) catch {
    _ => fail("the PDF could not be read")
  }
  assert_eq(text.page_count(), 1)
  let page = text.page(1).unwrap()
  assert_eq(page.width, 612.0)
  assert_eq(page.height, 792.0)
  assert_eq(page.text(), "Hello world")
}

///|
test "the place of a word on the page is known" {
  let bytes = make_pdf("Hello world", 72.0, 720.0)
  let text = @pdftext.extract(bytes) catch {
    _ => fail("the PDF could not be read")
  }
  let page = text.page(1).unwrap()
  let words = page.words()
  assert_eq(words.length(), 2)
  assert_eq(words[0].text, "Hello")
  assert_eq(words[1].text, "world")
  // The first word starts at the place the text was put.
  assert_true(words[0].x > 71.0 && words[0].x < 73.0)
  // The second word follows the first one.
  assert_true(words[1].x > words[0].x)
}

///|
test "the words of a page keep their order" {
  let bytes = make_pdf("one two three", 72.0, 720.0)
  let text = @pdftext.extract(bytes) catch {
    _ => fail("the PDF could not be read")
  }
  let page = text.page(1).unwrap()
  let words = page.words()
  assert_eq(words.length(), 3)
  assert_eq(words[0].text, "one")
  assert_eq(words[1].text, "two")
  assert_eq(words[2].text, "three")
}

///|
test "the lines of a page are found" {
  let bytes = make_pdf("a line of text", 72.0, 720.0)
  let text = @pdftext.extract(bytes) catch {
    _ => fail("the PDF could not be read")
  }
  let page = text.page(1).unwrap()
  let lines = page.lines()
  assert_eq(lines.length(), 1)
  assert_eq(lines[0].text, "a line of text")
}
