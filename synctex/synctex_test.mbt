///|
/// A small SyncTeX file with two boxes on one page.
fn sample() -> String {
  let lines = [
    "SyncTeX Version:1", "Input:1:main.tex", "Input:2:chapter1.tex", "Magnification:1000",
    "Unit:1", "X Offset:0", "Y Offset:0", "Content:", "!100", "{1", "[1,10:655360,655360:3248640,800100,0",
    "(1,10:655360,655360:3248640,800100,0", "[2,20:655360,1310720:3248640,800100,0",
    "]", "}", "",
  ]
  lines.join("\n")
}

///|
test "parse reads the header" {
  let file = @synctex.parse(sample())
  assert_eq(file.version, 1)
  assert_eq(file.page_count(), 1)
  assert_eq(file.file_for_tag(1), Some("main.tex"))
  assert_eq(file.file_for_tag(2), Some("chapter1.tex"))
  assert_eq(file.file_for_tag(3), None)
}

///|
test "parse reads the boxes of a page" {
  let file = @synctex.parse(sample())
  let nodes = file.page_nodes(1)
  assert_eq(nodes.length(), 3)
  assert_eq(nodes[0].kind, @synctex.NodeKind::HBox)
  assert_eq(nodes[0].tag, 1)
  assert_eq(nodes[0].line, 10)
}

///|
test "coordinates are converted to PDF points" {
  let file = @synctex.parse(sample())
  let node = file.page_nodes(1)[0]
  assert_true(node.x > 9.9 && node.x < 10.1)
  assert_true(node.y > 9.9 && node.y < 10.1)
  assert_true(node.width > 49.5 && node.width < 49.6)
}

///|
test "a point on the page resolves to its source line" {
  let file = @synctex.parse(sample())
  let location = file
    .source_at(1, @synctex.Rect::new(11.0, 11.0, 4.0, 4.0))
    .unwrap()
  assert_eq(location.file, "main.tex")
  assert_eq(location.line, 10)
}

///|
test "a point lower on the page resolves to the other file" {
  let file = @synctex.parse(sample())
  let location = file
    .source_at(1, @synctex.Rect::new(11.0, 21.0, 4.0, 4.0))
    .unwrap()
  assert_eq(location.file, "chapter1.tex")
  assert_eq(location.line, 20)
}

///|
test "a point outside every box has no source" {
  let file = @synctex.parse(sample())
  assert_eq(file.source_at(1, @synctex.Rect::new(300.0, 500.0, 4.0, 4.0)), None)
}

///|
test "sources_at reports every line inside the selection" {
  let file = @synctex.parse(sample())
  let locations = file.sources_at(1, @synctex.Rect::new(9.0, 9.0, 60.0, 20.0))
  assert_eq(locations.length(), 2)
}

///|
test "lines_at reports each line once" {
  let file = @synctex.parse(sample())
  let lines = file.lines_at(1, @synctex.Rect::new(9.0, 9.0, 60.0, 20.0))
  assert_eq(lines.length(), 2)
}

///|
test "input records may appear inside the content" {
  let lines = [
    "SyncTeX Version:1", "Input:1:main.tex", "Magnification:1000", "Unit:1", "Content:",
    "{1", "Input:2:late.tex", "[2,3:655360,655360:3248640,800100,0", "}", "",
  ]
  let text = lines.join("\n")
  let file = @synctex.parse(text)
  assert_eq(file.file_for_tag(2), Some("late.tex"))
  let location = file
    .source_at(1, @synctex.Rect::new(11.0, 11.0, 4.0, 4.0))
    .unwrap()
  assert_eq(location.file, "late.tex")
}

///|
test "rectangle helpers" {
  let rect = @synctex.Rect::new(10.0, 20.0, 30.0, 40.0)
  assert_eq(rect.right(), 40.0)
  assert_eq(rect.top(), 60.0)
  assert_eq(rect.center_x(), 25.0)
  assert_true(rect.contains_point(10.0, 20.0))
  assert_false(rect.contains_point(50.0, 20.0))
  assert_eq(rect.area(), 1200.0)
}
