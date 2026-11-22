///|
test "wb token kind values" {
  let lexer = tokenize_text("Hi")
  match lexer.tokens[0].kind {
    Text => ()
    _ => fail("expected text")
  }
  let k = TokenKind::Text
  match k {
    Text => ()
    _ => fail("expected text")
  }
}

///|
test "wb group content is empty for an unclosed group" {
  let lexer = tokenize_text("\\alpha{unclosed")
  assert_eq(lexer.group_content(1), None)
}

///|
test "wb tokenizer reports the span of a comment" {
  let src = "a% hello\nb"
  let lexer = tokenize_text(src)
  let comment = lexer.tokens[1]
  assert_eq(comment.kind, Comment)
  assert_eq(lexer.text(comment.span), "% hello")
}
