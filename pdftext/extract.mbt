///|
pub extend PageSize with Eq::{not_equal, equal}

///|
pub extend PageSize with @debug.Debug::{to_repr}

///|
/// The size of a page, in PDF points.
#derive(Eq)
#derive(@debug.Debug)
pub struct PageSize {
  width : Double
  height : Double
}

///|
pub fn PageSize::to_string(self : PageSize) -> String {
  "PageSize(\{self.width} x \{self.height})"
}

///|
/// Read the media box of a page as a size.
fn page_size(page : @page.PdfPage) -> PageSize {
  match page.mediabox {
    @syntax.PdfObject::PdfArray(items) => {
      let numbers = []
      for item in items {
        match item {
          @syntax.PdfObject::PdfInteger(v) => numbers.push(v.to_double())
          @syntax.PdfObject::PdfReal(v) => numbers.push(v)
          @syntax.PdfObject::PdfExactReal(v) => numbers.push(v)
          _ => ()
        }
      }
      if numbers.length() >= 4 {
        let x0 = numbers[0]
        let y0 = numbers[1]
        let x1 = numbers[2]
        let y1 = numbers[3]
        PageSize::{ width: (x1 - x0).abs(), height: (y1 - y0).abs(), }
      } else {
        PageSize::{ width: 612.0, height: 792.0, }
      }
    }
    _ => PageSize::{ width: 612.0, height: 792.0, }
  }
}

///|
/// The extent of a glyph's bounding box.
///
/// The box is a quad; the width is measured between the left and the right
/// edge and the height between the bottom and the top.
fn bbox_extent(
  box : @pdflite.PdfContentBoundingBox,
) -> (Double, Double, Double, Double) {
  let xs = [box.x0, box.x1, box.x2, box.x3]
  let ys = [box.y0, box.y1, box.y2, box.y3]
  let mut min_x = xs[0]
  let mut max_x = xs[0]
  let mut min_y = ys[0]
  let mut max_y = ys[0]
  for i in 1..<4 {
    if xs[i] < min_x {
      min_x = xs[i]
    }
    if xs[i] > max_x {
      max_x = xs[i]
    }
    if ys[i] < min_y {
      min_y = ys[i]
    }
    if ys[i] > max_y {
      max_y = ys[i]
    }
  }
  (min_x, min_y, max_x - min_x, max_y - min_y)
}

///|
/// Extract the text of every page of a PDF.
pub fn extract(bytes : Bytes) -> PdfText raise @pdfcore.PdfError {
  let document = @pdflite.pdf_read_document_from_bytes(bytes)
  let pages = @pdflite.pdf_pages_of_pagetree(document)
  let result = []
  let mut number = 1
  for page in pages {
    let size = page_size(page)
    let entries = @pdflite.pdf_content_entries_of_page(document, page)
    let glyphs = []
    for entry in entries {
      match entry.object {
        @pdflite.PdfContentObject::PdfContentGlyphObject(_, _, extracted) =>
          if !extracted.is_empty() {
            let (x, y, width, height) = bbox_extent(entry.bounding_box)
            glyphs.push(Glyph::{ text: extracted, x, y, width, height, })
          }
        _ => ()
      }
    }
    result.push(PageText::{
      number,
      width: size.width,
      height: size.height,
      glyphs,
    })
    number = number + 1
  }
  PdfText::{ pages: result, }
}

///|
/// Extract the text of every page of a PDF from its bytes.
pub fn extract_from_bytes(bytes : Bytes) -> PdfText raise @pdfcore.PdfError {
  extract(bytes)
}
