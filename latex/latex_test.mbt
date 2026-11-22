///|
test "tokenize splits text, control sequences and groups" {
  let lexer = @latex.tokenize_text("Hi \\alpha{x}% note\n")
  assert_eq(lexer.length(), 7)
  assert_eq(lexer.tokens[0].kind, @latex.TokenKind::Text)
  assert_eq(lexer.tokens[1].kind, @latex.TokenKind::ControlSequence)
  assert_eq(lexer.tokens[2].kind, @latex.TokenKind::BeginGroup)
  assert_eq(lexer.tokens[3].kind, @latex.TokenKind::Text)
  assert_eq(lexer.tokens[4].kind, @latex.TokenKind::EndGroup)
  assert_eq(lexer.tokens[5].kind, @latex.TokenKind::Comment)
}

///|
test "tokenize keeps escaped percent out of comments" {
  let lexer = @latex.tokenize_text("100\\% sure")
  assert_eq(lexer.length(), 3)
  assert_eq(lexer.tokens[1].kind, @latex.TokenKind::ControlSequence)
  assert_eq(lexer.tokens[2].kind, @latex.TokenKind::Text)
}

///|
test "tokenize reads the argument of a control sequence" {
  let lexer = @latex.tokenize_text("\\section{Intro}")
  assert_eq(lexer.length(), 4)
  let group = lexer.group_content(1).unwrap()
  assert_eq(group.start, 9)
  assert_eq(group.end, 14)
}

///|
test "control words split into words and symbols" {
  match @latex.parse_control("\\alpha") {
    Some(@latex.ControlWord::Word(w)) => assert_eq(w, "alpha")
    _ => fail("expected a control word")
  }
  match @latex.parse_control("\\\\") {
    Some(@latex.ControlWord::Symbol(c)) => assert_eq(c, '\\')
    _ => fail("expected a control symbol")
  }
  match @latex.parse_control("\\@foo") {
    Some(@latex.ControlWord::Word(w)) => assert_eq(w, "@foo")
    _ => fail("expected a control word")
  }
}

///|
test "parse finds sections in document order" {
  let src = "\\documentclass{article}\n\\begin{document}\n\\section{One}\ntext\n\\subsection{Two}\n\\section{Three}\n\\end{document}\n"
  let doc = @latex.parse_text(src)
  assert_eq(doc.sections.length(), 3)
  assert_eq(doc.sections[0].title, "One")
  assert_eq(doc.sections[0].level, 2)
  assert_eq(doc.sections[1].title, "Two")
  assert_eq(doc.sections[1].level, 3)
  assert_eq(doc.sections[2].title, "Three")
}

///|
test "section bodies stop at the next heading of the same level" {
  let src = "\\section{One}\nalpha\n\\section{Two}\nbeta\n"
  let doc = @latex.parse_text(src)
  let one = doc.sections[0]
  let two = doc.sections[1]
  assert_true(one.body_span.end <= two.body_span.start)
  assert_true(one.body_span.contains(one.body_span.start))
}

///|
test "parse separates the preamble from the body" {
  let src = "\\documentclass{article}\n\\begin{document}\nBody\n\\end{document}\n"
  let doc = @latex.parse_text(src)
  assert_true(doc.preamble_span.end <= doc.body_span.start)
  assert_true(doc.body_span.contains(doc.body_span.start))
}

///|
test "parse collects labels, references and citations" {
  let src = "\\label{sec:intro}\\ref{sec:intro}\\cite{knuth1984}\\label{sec:next}"
  let doc = @latex.parse_text(src)
  let labels = doc.references_of(@latex.ReferenceKind::Label)
  assert_eq(labels.length(), 2)
  assert_eq(labels[0].name, "sec:intro")
  let refs = doc.references_of(@latex.ReferenceKind::Ref)
  assert_eq(refs.length(), 1)
  assert_eq(refs[0].name, "sec:intro")
  let cites = doc.references_of(@latex.ReferenceKind::Cite)
  assert_eq(cites.length(), 1)
  assert_eq(cites[0].name, "knuth1984")
}

///|
test "parse records included files" {
  let src = "\\include{intro}\n\\include{method}\n\\input{extra}"
  let doc = @latex.parse_text(src)
  let files = doc.included_files()
  assert_eq(files.length(), 3)
  assert_eq(files[0], "intro")
  assert_eq(files[2], "extra")
}

///|
test "parse matches environments" {
  let src = "\\begin{equation}\nE=mc^2\n\\end{equation}"
  let doc = @latex.parse_text(src)
  assert_eq(doc.environments.length(), 1)
  assert_eq(doc.environments[0].name, "equation")
  assert_true(
    doc.environments[0].content_span.contains(
      doc.environments[0].content_span.start,
    ),
  )
}

///|
test "verbatim content is not scanned for references" {
  let src = "\\begin{verbatim}\n\\label{hidden}\n\\end{verbatim}\n\\label{shown}"
  let doc = @latex.parse_text(src)
  let labels = doc.references_of(@latex.ReferenceKind::Label)
  assert_eq(labels.length(), 1)
  assert_eq(labels[0].name, "shown")
}

///|
test "section_at finds the innermost section" {
  let src = "\\section{One}\nalpha\n\\subsection{Deep}\nbeta\n"
  let doc = @latex.parse_text(src)
  let offset = src.find("beta").unwrap()
  let section = doc.section_at(offset).unwrap()
  assert_eq(section.title, "Deep")
}

///|
test "unbalanced braces do not lose the document" {
  let src = "\\section{Broken\n\\section{Fine}"
  let doc = @latex.parse_text(src)
  assert_true(doc.sections.length() >= 1)
}

///|
test "span arithmetic" {
  let a = @latex.Span::new(2, 8)
  let b = @latex.Span::new(5, 12)
  assert_eq(a.len(), 6)
  assert_true(a.overlaps(b))
  assert_eq(a.union(b).end, 12)
  assert_eq(a.intersect(b).unwrap().start, 5)
  assert_eq(a.shift(3).start, 5)
  assert_false(a.contains(8))
}
