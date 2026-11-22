///|
/// Escape a text for SVG.
fn escape(text : String) -> String {
  let out = StringBuilder()
  for c in text.to_array() {
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// The CSS font family for a PDF font name.
fn family(font : String) -> String {
  if font.contains("Times") {
    "Times New Roman, Times, serif"
  } else if font.contains("Courier") {
    "Courier New, Courier, monospace"
  } else if font.contains("Helvetica") || font.contains("Arial") {
    "Helvetica, Arial, sans-serif"
  } else {
    // Computer Modern and everything else are serif faces.
    "Georgia, Times New Roman, serif"
  }
}

///|
/// A run of glyphs set together: one `<text>` element in the SVG.
priv struct Run {
  font : String
  size : Double
  y : Double
  left : Double
  mut right : Double
  mut text : String
}

///|
/// Render a page as a standalone vector SVG.
///
/// Every placed glyph becomes text in the SVG, so the page looks like the
/// printed one and stays selectable. The PDF grows upwards; the SVG grows
/// downwards, so the page is flipped once and every run is flipped back.
pub fn page_svg(page : @pdftext.PageText) -> String {
  let width = page.width
  let height = page.height
  let runs = []
  let mut current : Run? = None
  for glyph in page.glyphs {
    if glyph.text.is_empty() {
      continue
    }
    let size = if glyph.size > 0.0 { glyph.size } else { glyph.height * 0.85 }
    match current {
      Some(run) =>
        if run.font == glyph.font &&
          (run.size - size).abs() < 0.1 &&
          (run.y - glyph.y).abs() < 2.0 &&
          glyph.x - run.right < size * 0.6 {
          run.text += glyph.text
          run.right = glyph.x + glyph.width
          continue
        }
      None => ()
    }
    let run = Run::{
      font: glyph.font,
      size,
      y: glyph.y,
      left: glyph.x,
      right: glyph.x + glyph.width,
      text: glyph.text,
    }
    runs.push(run)
    current = Some(run)
  }
  let out = StringBuilder()
  out.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" +
    fmt(width) +
    "\" height=\"" +
    fmt(height) +
    "\" viewBox=\"0 0 " +
    fmt(width) +
    " " +
    fmt(height) +
    "\">",
  )
  out.write_string("<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
  out.write_string(
    "<g transform=\"scale(1,-1) translate(0,-" + fmt(height) + ")\">",
  )
  for run in runs {
    // The glyph box hangs below the baseline by about a fifth of the size.
    let baseline = run.y + run.size * 1.2 * 0.22
    out.write_string(
      "<text transform=\"translate(" +
      fmt(run.left) +
      " " +
      fmt(baseline) +
      ") scale(1 -1)\" font-family=\"" +
      family(run.font) +
      "\" font-size=\"" +
      fmt(run.size) +
      "\">" +
      escape(run.text) +
      "</text>",
    )
  }
  out.write_string("</g></svg>")
  out.to_string()
}

///|
/// Format a number for SVG.
fn fmt(value : Double) -> String {
  let text = value.to_string()
  match text.rev_find(".") {
    Some(_) => text
    None => text + ".0"
  }
}
