///|
pub extend NodeKind with Eq::{not_equal, equal}

///|
pub extend NodeKind with @debug.Debug::{to_repr}

///|
pub extend Node with Eq::{not_equal, equal}

///|
pub extend Node with @debug.Debug::{to_repr}

///|
pub extend Rect with Eq::{not_equal, equal}

///|
pub extend Rect with @debug.Debug::{to_repr}

///|
pub extend SourceLocation with Eq::{not_equal, equal}

///|
pub extend SourceLocation with @debug.Debug::{to_repr}

///|
pub extend PageLine with Eq::{not_equal, equal}

///|
pub extend PageLine with @debug.Debug::{to_repr}

///|
/// The kind of a SyncTeX record.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum NodeKind {
  /// `[` — a horizontal box.
  HBox
  /// `(` — a vertical box.
  VBox
  /// `h` — horizontal material.
  Horizontal
  /// `v` — vertical material.
  Vertical
  /// `r` — a rule.
  Rule
  /// `k` — a kern.
  Kern
  /// `g` — glue.
  Glue
  /// `x` — the current position.
  Current
  /// `$` — a math position.
  Math
}

///|
pub fn NodeKind::to_string(self : NodeKind) -> String {
  match self {
    HBox => "HBox"
    VBox => "VBox"
    Horizontal => "Horizontal"
    Vertical => "Vertical"
    Rule => "Rule"
    Kern => "Kern"
    Glue => "Glue"
    Current => "Current"
    Math => "Math"
  }
}

///|
/// One record of a SyncTeX file.
///
/// The positions are in the coordinate system of the PDF: the origin is the
/// bottom left corner of the page and `y` grows upwards.
#derive(Eq)
#derive(@debug.Debug)
pub struct Node {
  kind : NodeKind
  /// The tag of the input file the record came from.
  tag : Int32
  /// The source line the record came from.
  line : Int32
  /// The horizontal position, in PDF points.
  x : Double
  /// The vertical position, in PDF points.
  y : Double
  /// The width of the box, in PDF points.
  width : Double
  /// The height of the box, in PDF points.
  height : Double
}

///|
pub fn Node::to_string(self : Node) -> String {
  "\{self.kind.to_string()}(\{self.tag},\{self.line})"
}

///|
/// A rectangle on a page, in PDF points.
#derive(Eq)
#derive(@debug.Debug)
pub struct Rect {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
pub fn Rect::new(
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> Rect {
  { x, y, width, height, }
}

///|
/// The horizontal centre of the rectangle.
pub fn Rect::center_x(self : Rect) -> Double {
  self.x + self.width / 2.0
}

///|
/// The vertical centre of the rectangle.
pub fn Rect::center_y(self : Rect) -> Double {
  self.y + self.height / 2.0
}

///|
/// The right edge of the rectangle.
pub fn Rect::right(self : Rect) -> Double {
  self.x + self.width
}

///|
/// The top edge of the rectangle.
pub fn Rect::top(self : Rect) -> Double {
  self.y + self.height
}

///|
/// Whether the rectangle contains a point.
pub fn Rect::contains_point(self : Rect, px : Double, py : Double) -> Bool {
  px >= self.x && px <= self.right() && py >= self.y && py <= self.top()
}

///|
/// Whether the rectangle overlaps another one.
pub fn Rect::overlaps(self : Rect, other : Rect) -> Bool {
  self.x < other.right() &&
  other.x < self.right() &&
  self.y < other.top() &&
  other.y < self.top()
}

///|
/// The area of the rectangle.
pub fn Rect::area(self : Rect) -> Double {
  if self.width <= 0.0 || self.height <= 0.0 {
    0.0
  } else {
    self.width * self.height
  }
}

///|
/// A place in the source of the document.
#derive(Eq)
#derive(@debug.Debug)
pub struct SourceLocation {
  /// The path of the file, as the SyncTeX file spells it.
  file : String
  /// The line in that file.
  line : Int32
}

///|
pub fn SourceLocation::new(file : String, line : Int32) -> SourceLocation {
  { file, line, }
}

///|
pub fn SourceLocation::to_string(self : SourceLocation) -> String {
  "\{self.file}:\{self.line}"
}

///|
/// The pages of a SyncTeX file.
pub struct Page {
  number : Int32
  nodes : Array[Node]
}

///|
/// A parsed SyncTeX file.
///
/// SyncTeX is what makes it possible to point at a page and have the source
/// found: every typeset box remembers the file and the line it came from.
pub struct SynctexFile {
  version : Int32
  inputs : Map[Int32, String]
  magnification : Double
  unit : Double
  x_offset : Double
  y_offset : Double
  pages : Array[Page]
}

///|
/// The number of pages in the file.
pub fn SynctexFile::page_count(self : SynctexFile) -> Int32 {
  self.pages.length()
}

///|
/// The path of the input file with the given tag.
pub fn SynctexFile::file_for_tag(self : SynctexFile, tag : Int32) -> String? {
  self.inputs.get(tag)
}

///|
/// The tags of the input files, in the order they were declared.
pub fn SynctexFile::input_tags(self : SynctexFile) -> Array[Int32] {
  let tags = []
  for (tag, _) in self.inputs {
    tags.push(tag)
  }
  tags.sort_by(fn(a, b) { a.compare(b) })
  tags
}

///|
/// The nodes of a page.
pub fn SynctexFile::page_nodes(self : SynctexFile, page : Int32) -> Array[Node] {
  for p in self.pages {
    if p.number == page {
      return p.nodes
    }
  }
  []
}

///|
/// Read a number from `chars` starting at `i`, advancing `i` past it.
fn read_number(chars : Array[Char], i : Ref[Int32]) -> Double {
  let n = chars.length()
  let begin = i.val
  while i.val < n && (chars[i.val] == '-' || chars[i.val] == '+') {
    i.val = i.val + 1
  }
  while i.val < n && chars[i.val].is_ascii_digit() {
    i.val = i.val + 1
  }
  if i.val < n && chars[i.val] == '.' {
    i.val = i.val + 1
    while i.val < n && chars[i.val].is_ascii_digit() {
      i.val = i.val + 1
    }
  }
  let text = String::from_array(chars.clamped_view(start=begin, end=i.val))
  to_double(text)
}

///|
/// Parse an integer, falling back to zero.
fn to_int(text : String) -> Int32 {
  @strconv.parse_int(text) catch {
    _ => 0
  }
}

///|
/// Parse a floating point number, falling back to zero.
fn to_double(text : String) -> Double {
  @strconv.parse_double(text) catch {
    _ => 0.0
  }
}

///|
/// Parse one content record.
///
/// The grammar is `<kind><tag>,<line>:<x>,<y>[:<width>,<height>[,<depth>]]`,
/// where the trailing parts depend on the kind of the record.
fn parse_node(line : String) -> Node? {
  if line.is_empty() {
    return None
  }
  let chars = line.to_array()
  let kind = match chars[0] {
    '[' => NodeKind::HBox
    '(' => NodeKind::VBox
    'h' => NodeKind::Horizontal
    'v' => NodeKind::Vertical
    'r' => NodeKind::Rule
    'k' => NodeKind::Kern
    'g' => NodeKind::Glue
    'x' => NodeKind::Current
    '$' => NodeKind::Math
    _ => return None
  }
  let i = Ref(1)
  let tag = read_number(chars, i).to_int()
  if i.val < chars.length() && chars[i.val] == ',' {
    i.val = i.val + 1
  }
  let line_no = read_number(chars, i).to_int()
  if i.val < chars.length() && chars[i.val] == ':' {
    i.val = i.val + 1
  }
  let x = read_number(chars, i)
  if i.val < chars.length() && chars[i.val] == ',' {
    i.val = i.val + 1
  }
  let y = read_number(chars, i)
  let mut width = 0.0
  let mut height = 0.0
  if i.val < chars.length() && chars[i.val] == ':' {
    i.val = i.val + 1
    width = read_number(chars, i)
    if i.val < chars.length() && chars[i.val] == ',' {
      i.val = i.val + 1
      height = read_number(chars, i)
    }
  }
  Some(Node::{ kind, tag, line: line_no, x, y, width, height, })
}

///|
/// Parse a SyncTeX file.
///
/// The parser accepts the text form of the format. The coordinates are
/// converted to PDF points, so that they can be compared with the geometry of
/// the PDF directly.
pub fn parse(text : String) -> SynctexFile {
  let inputs = Map([])
  let pages = []
  let version = Ref(0)
  let magnification = Ref(1000.0)
  let unit = Ref(65536.0)
  let x_offset = Ref(0.0)
  let y_offset = Ref(0.0)
  let current_page = Ref(None)
  let in_content = Ref(false)
  for raw_line in text.split("\n") {
    let line = raw_line.trim().to_owned()
    if line.is_empty() {
      continue
    }
    if line.has_prefix("SyncTeX Version:") {
      version.val = to_int(
        line.clamped_view(start=16, end=line.length()).to_owned(),
      )
      continue
    }
    if line.has_prefix("Input:") {
      let rest = line.clamped_view(start=6, end=line.length())
      let sep = rest.find(":")
      match sep {
        Some(index) => {
          let tag_text = rest.clamped_view(start=0, end=index)
          let path = rest.clamped_view(start=index + 1, end=rest.length())
          let tag = to_int(tag_text.to_owned())
          if tag > 0 {
            inputs.set(tag, path.to_owned())
          }
        }
        None => ()
      }
      continue
    }
    if line.has_prefix("Magnification:") {
      magnification.val = to_double(
        line.clamped_view(start=14, end=line.length()).to_owned(),
      )
      continue
    }
    if line.has_prefix("Unit:") {
      unit.val = to_double(
        line.clamped_view(start=5, end=line.length()).to_owned(),
      )
      continue
    }
    if line.has_prefix("X Offset:") {
      x_offset.val = to_double(
        line.clamped_view(start=9, end=line.length()).to_owned(),
      )
      continue
    }
    if line.has_prefix("Y Offset:") {
      y_offset.val = to_double(
        line.clamped_view(start=9, end=line.length()).to_owned(),
      )
      continue
    }
    if line.has_prefix("Content:") {
      in_content.val = true
      continue
    }
    if line.has_prefix("Count:") || line.has_prefix("Postamble:") {
      continue
    }
    if !in_content.val {
      continue
    }
    let first = line.get_char(0).unwrap_or(' ')
    if first == '{' {
      let page = to_int(
        line.clamped_view(start=1, end=line.length()).to_owned(),
      )
      let page = if page > 0 { page } else { pages.length() + 1 }
      current_page.val = Some(page)
      pages.push(Page::{ number: page, nodes: [], })
      continue
    }
    if first == '}' {
      current_page.val = None
      continue
    }
    if first == '!' || first == ']' || first == ')' {
      continue
    }
    match parse_node(line) {
      Some(node) =>
        if current_page.val is Some(_) && pages.length() > 0 {
          let last = pages[pages.length() - 1]
          last.nodes.push(node)
        }
      None => ()
    }
  }
  let scale = unit.val / 65536.0
  let pages = pages.map(fn(p) {
    let nodes = p.nodes.map(fn(n) {
      Node::{
        ..n,
        x: n.x * scale + x_offset.val,
        y: n.y * scale + y_offset.val,
        width: n.width * scale,
        height: n.height * scale,
      }
    })
    Page::{ ..p, nodes, }
  })
  SynctexFile::{
    version: version.val,
    inputs,
    magnification: magnification.val,
    unit: unit.val,
    x_offset: x_offset.val,
    y_offset: y_offset.val,
    pages,
  }
}

///|
/// Parse a SyncTeX file from its uncompressed text.
pub fn parse_text(text : String) -> SynctexFile {
  parse(text)
}

///|
/// The source locations whose typeset output lies inside `rect`.
///
/// Only records that carry a size are considered, because a position without an
/// extent cannot tell whether it lies inside a selection.
pub fn SynctexFile::sources_at(
  self : SynctexFile,
  page : Int32,
  rect : Rect,
) -> Array[SourceLocation] {
  let found = []
  let seen = []
  for node in self.page_nodes(page) {
    if node.width <= 0.0 || node.height <= 0.0 {
      continue
    }
    let box = Rect::new(node.x, node.y, node.width, node.height)
    if box.overlaps(rect) {
      match self.file_for_tag(node.tag) {
        Some(file) => {
          let key = file + ":" + node.line.to_string()
          if !seen.contains(key) {
            seen.push(key)
            found.push(SourceLocation::{ file, line: node.line, })
          }
        }
        None => ()
      }
    }
  }
  found
}

///|
/// The source location that best explains `rect`.
///
/// The best explanation is the smallest typeset box that covers the middle of
/// the rectangle: big boxes cover whole pages and would answer every query
/// with the same line.
pub fn SynctexFile::source_at(
  self : SynctexFile,
  page : Int32,
  rect : Rect,
) -> SourceLocation? {
  let px = rect.center_x()
  let py = rect.center_y()
  let mut best : Node? = None
  let mut best_area = 0.0
  for node in self.page_nodes(page) {
    if node.width <= 0.0 || node.height <= 0.0 {
      continue
    }
    let box = Rect::new(node.x, node.y, node.width, node.height)
    if !box.contains_point(px, py) {
      continue
    }
    let area = box.area()
    match best {
      Some(_) =>
        if area < best_area {
          best = Some(node)
          best_area = area
        }
      None => {
        best = Some(node)
        best_area = area
      }
    }
  }
  match best {
    Some(node) =>
      match self.file_for_tag(node.tag) {
        Some(file) => Some(SourceLocation::{ file, line: node.line, })
        None => None
      }
    None => self.nearest_word(page, px, py)
  }
}

///|
/// The source of the word that was set closest to a point.
///
/// The records of a word know the line they were set from, so they answer a
/// question that the boxes cannot: where a single word of the page comes from.
fn SynctexFile::nearest_word(
  self : SynctexFile,
  page : Int32,
  px : Double,
  py : Double,
) -> SourceLocation? {
  let mut best : Node? = None
  let mut best_distance = 0.0
  for node in self.page_nodes(page) {
    if node.kind != NodeKind::Current {
      continue
    }
    let dx = node.x - px
    let dy = node.y - py
    let distance = dx * dx + dy * dy
    match best {
      Some(_) =>
        if distance < best_distance {
          best = Some(node)
          best_distance = distance
        }
      None => {
        best = Some(node)
        best_distance = distance
      }
    }
  }
  match best {
    Some(node) =>
      match self.file_for_tag(node.tag) {
        Some(file) => Some(SourceLocation::{ file, line: node.line, })
        None => None
      }
    None => None
  }
}

///|
/// The lines of the source that produced `rect`.
///
/// Unlike `sources_at` this reports every distinct line, which is what an
/// agent needs to know before it edits anything.
pub fn SynctexFile::lines_at(
  self : SynctexFile,
  page : Int32,
  rect : Rect,
) -> Array[SourceLocation] {
  let seen = []
  let result = []
  for location in self.sources_at(page, rect) {
    let key = location.file + ":" + location.line.to_string()
    if !seen.contains(key) {
      seen.push(key)
      result.push(location)
    }
  }
  result
}

///|
/// A line of typeset output, with the source line it came from.
///
/// SyncTeX records where every word of the page was set, in the order the
/// words appear on the page. The records of one line share their vertical
/// position, which is how the lines of a page are told apart.
#derive(Eq)
#derive(@debug.Debug)
pub struct PageLine {
  /// The tag of the input file.
  tag : Int32
  /// The source line.
  line : Int32
  /// The vertical position of the line.
  v : Double
  /// How many words the file saw on this line.
  words : Int32
}

///|
/// The lines of a page, in reading order.
///
/// The records are grouped by their vertical position; a line that is set in
/// more than one place appears more than once, once for each place.
pub fn SynctexFile::page_lines(
  self : SynctexFile,
  page : Int32,
) -> Array[PageLine] {
  let lines : Array[PageLine] = []
  for node in self.page_nodes(page) {
    if node.kind != NodeKind::Current {
      continue
    }
    // A new group starts whenever the source line changes. The records of one
    // line are written one after the other, so this recovers the lines of the
    // page in the order they were set.
    match lines.last() {
      Some(last) =>
        if last.tag == node.tag && last.line == node.line {
          lines[lines.length() - 1] = PageLine::{
            ..last,
            words: last.words + 1,
          }
          continue
        }
      None => ()
    }
    lines.push(PageLine::{
      tag: node.tag,
      line: node.line,
      v: node.y,
      words: 1,
    })
  }
  lines
}

///|
/// The source line of the page that holds the given word count.
///
/// The lines of the page are matched to the lines of the typeset output by
/// their order and by the number of words they hold. The order is the
/// backbone: a document that grew a sentence still has its lines in the same
/// sequence.
pub fn SynctexFile::match_lines(
  self : SynctexFile,
  page : Int32,
  counts : Array[Int32],
) -> Array[Int32] {
  let lines = self.page_lines(page)
  let result : Array[Int32] = []
  let m = lines.length()
  let n = counts.length()
  let mut used = 0
  for i in 0..<n {
    // Where the line is expected, by proportion. The order of the lines is the
    // backbone; the number of words tells whether the guess is right.
    let expected = if m > 0 && n > 0 { i * m / n } else { 0 }
    let from = if expected > used { expected } else { used }
    let to = if expected + 4 < m { expected + 4 } else { m }
    let mut best = -1
    let mut best_distance = 1000000
    let mut j = from
    while j < to {
      let difference = lines[j].words - counts[i]
      let distance = if difference < 0 { -difference } else { difference }
      if distance < best_distance {
        best_distance = distance
        best = j
      }
      j = j + 1
    }
    if best >= 0 {
      result.push(best)
      used = best
    } else {
      result.push(-1)
    }
  }
  result
}

///|
/// The source location of the line of the page at the given index.
pub fn SynctexFile::source_of_line(
  self : SynctexFile,
  page : Int32,
  index : Int32,
) -> SourceLocation? {
  let lines = self.page_lines(page)
  if index < 0 || index >= lines.length() {
    return None
  }
  let line = lines[index]
  match self.file_for_tag(line.tag) {
    Some(file) => Some(SourceLocation::{ file, line: line.line, })
    None => None
  }
}
