///|
test "a page is rendered as an svg" {
  let page = @pdftext.PageText::new(1, 612.0, 792.0, [
    @pdftext.Glyph::new(
      "H",
      72.0,
      700.0,
      8.0,
      10.0,
      font="Helvetica",
      size=12.0,
    ),
    @pdftext.Glyph::new(
      "i",
      80.0,
      700.0,
      4.0,
      10.0,
      font="Helvetica",
      size=12.0,
    ),
  ])
  let svg = @render.page_svg(page)
  assert_true(svg.has_prefix("<svg"))
  assert_true(svg.contains("</svg>"))
  assert_true(svg.contains(">Hi</text>"))
  // The two glyphs set together become one text run at the first one's place.
  assert_true(svg.contains("translate(72"))
  assert_true(svg.contains("Helvetica, Arial, sans-serif"))
  assert_true(svg.contains("font-size=\"12"))
}

///|
test "special characters are escaped in the svg" {
  let page = @pdftext.PageText::new(1, 100.0, 100.0, [
    @pdftext.Glyph::new("a<b&c", 10.0, 10.0, 30.0, 10.0),
  ])
  let svg = @render.page_svg(page)
  assert_true(svg.contains("a&lt;b&amp;c"))
  assert_false(svg.contains("a<b"))
}

///|
test "the page is flipped so pdf coordinates work" {
  let page = @pdftext.PageText::new(1, 612.0, 792.0, [
    @pdftext.Glyph::new("g", 100.0, 700.0, 5.0, 10.0),
  ])
  let svg = @render.page_svg(page)
  assert_true(svg.contains("scale(1,-1) translate(0,-792"))
  // And the run is flipped back upright.
  assert_true(svg.contains("scale(1 -1)"))
}
