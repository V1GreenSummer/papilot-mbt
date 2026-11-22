///|
test "words keep their punctuation" {
  let words = @diff.tokenize_words("Hello, world!")
  assert_eq(words.length(), 2)
  assert_eq(words[0].word, "Hello")
  assert_eq(words[0].suffix, ",")
  assert_eq(words[1].word, "world")
  assert_eq(words[1].suffix, "!")
}

///|
test "brackets attach to the word they open" {
  let words = @diff.tokenize_words("see (below) now")
  assert_eq(words.length(), 3)
  assert_eq(words[1].prefix, "(")
  assert_eq(words[1].suffix, ")")
}

///|
test "diff finds a changed word" {
  let old = @diff.tokenize_words("the quick brown fox")
  let new = @diff.tokenize_words("the slow brown fox")
  let differences = @diff.diff_words(old, new)
  assert_eq(differences.length(), 1)
  assert_eq(differences[0].kind, @diff.ChangeKind::Replaced)
  assert_eq(differences[0].old_text(), "quick")
  assert_eq(differences[0].new_text(), "slow")
}

///|
test "diff reports an insertion" {
  let old = @diff.tokenize_words("a b")
  let new = @diff.tokenize_words("a x b")
  let differences = @diff.diff_words(old, new)
  assert_eq(differences.length(), 1)
  assert_eq(differences[0].kind, @diff.ChangeKind::Added)
  assert_eq(differences[0].old_text(), "")
  assert_eq(differences[0].new_text(), "x")
}

///|
test "diff reports a deletion" {
  let old = @diff.tokenize_words("a x b")
  let new = @diff.tokenize_words("a b")
  let differences = @diff.diff_words(old, new)
  assert_eq(differences.length(), 1)
  assert_eq(differences[0].kind, @diff.ChangeKind::Removed)
  assert_eq(differences[0].old_text(), "x")
}

///|
test "identical texts have no differences" {
  let differences = @diff.diff_text("same words here", "same words here")
  assert_eq(differences.length(), 0)
}

///|
test "a moved passage is detected" {
  let moved = "the conclusion follows from the argument above in every case"
  let old = "introduction text " + moved + " more old words"
  let new = "more new words " + moved + " trailing text"
  let differences = @diff.find_moves(
    @diff.tokenize_words(old),
    @diff.tokenize_words(new),
  )
  assert_eq(differences.length(), 1)
  assert_true(differences[0].substance() >= 20)
}

///|
test "a short repeated phrase is not a move" {
  let old = "of the paper we see that of the paper"
  let new = "of the paper and then of the paper"
  let differences = @diff.find_moves(
    @diff.tokenize_words(old),
    @diff.tokenize_words(new),
  )
  assert_eq(differences.length(), 0)
}

///|
test "line diff reports changed lines" {
  let differences = @diff.diff_lines(
    "one\ntwo\nthree\n", "one\ntwo point five\nthree\n",
  )
  assert_eq(differences.length(), 1)
  assert_eq(differences[0].removed.length(), 1)
  assert_eq(differences[0].removed[0], "two")
  assert_eq(differences[0].added[0], "two point five")
}

///|
test "split lines keeps empty lines" {
  let lines = @diff.split_lines("a\n\nb\n")
  assert_eq(lines.length(), 4)
  assert_eq(lines[1], "")
}

///|
test "joining words reproduces the text" {
  let words = @diff.tokenize_words("Hello, world!")
  assert_eq(@diff.join_words(words), "Hello, world!")
}
