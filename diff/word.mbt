///|
pub extend Word with Eq::{not_equal, equal}

///|
pub extend Word with @debug.Debug::{to_repr}

///|
/// A word of running text, with the punctuation that belongs to it.
///
/// `word` is the bare word, `prefix` the opening punctuation and `suffix` the
/// closing punctuation. Keeping them apart lets the diff compare words while
/// still reproducing the exact original text.
#derive(Eq)
#derive(@debug.Debug)
pub struct Word {
  word : String
  prefix : String
  suffix : String
}

///|
pub fn Word::new(
  word : String,
  prefix~ : String = "",
  suffix~ : String = "",
) -> Word {
  { word, prefix, suffix, }
}

///|
/// The word without its punctuation.
pub fn Word::text(self : Word) -> String {
  self.word
}

///|
/// The word with its punctuation, exactly as it appears in the text.
pub fn Word::full(self : Word) -> String {
  self.prefix + self.word + self.suffix
}

///|
/// Whether the word carries letters or digits.
pub fn Word::is_word(self : Word) -> Bool {
  for c in self.word {
    if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      return true
    }
  }
  false
}

///|
/// Characters that open a word when they follow a space.
fn is_opening_punctuation(c : Char) -> Bool {
  c == '(' || c == '[' || c == '{' || c == '<' || c == '"' || c == '\u{201C}'
}

///|
/// Characters that close a word when they follow a letter.
fn is_closing_punctuation(c : Char) -> Bool {
  c == ')' ||
  c == ']' ||
  c == '}' ||
  c == '>' ||
  c == '"' ||
  c == ',' ||
  c == '.' ||
  c == ';' ||
  c == ':' ||
  c == '!' ||
  c == '?' ||
  c == '\u{201D}'
}

///|
/// Split running text into words.
///
/// The split follows the rules of typeset prose: a word is a run of letters
/// and digits, and punctuation attaches to the word it belongs to. A hyphen at
/// the end of a line keeps the two halves together only when the text also
/// contains the joined form, which the caller decides; here a trailing hyphen
/// is kept as part of the word so that the diff can still show it.
pub fn tokenize_words(text : String) -> Array[Word] {
  let chars = text.to_array()
  let n = chars.length()
  let words = []
  let i = Ref(0)
  while i.val < n {
    let c = chars[i.val]
    if c.is_whitespace() {
      i.val = i.val + 1
      continue
    }
    let begin = i.val
    let prefix = StringBuilder()
    // Leading punctuation.
    while i.val < n && is_opening_punctuation(chars[i.val]) {
      prefix.write_char(chars[i.val])
      i.val = i.val + 1
    }
    let word_start = i.val
    while i.val < n {
      let ch = chars[i.val]
      if ch.is_ascii_alphabetic() ||
        ch.is_ascii_digit() ||
        ch == '-' ||
        ch == '\u{2019}' ||
        ch == '\'' {
        i.val = i.val + 1
      } else {
        break
      }
    }
    let word_end = i.val
    let suffix = StringBuilder()
    while i.val < n && is_closing_punctuation(chars[i.val]) {
      suffix.write_char(chars[i.val])
      i.val = i.val + 1
    }
    if word_end > word_start {
      let word = String::from_array(
        chars.clamped_view(start=word_start, end=word_end),
      )
      words.push(
        Word::new(word, prefix=prefix.to_string(), suffix=suffix.to_string()),
      )
    } else if prefix.to_string().length() > 0 || suffix.to_string().length() > 0 {
      // A run of punctuation that belongs to no word.
      let word = String::from_array(chars.clamped_view(start=begin, end=i.val))
      words.push(Word::new(word))
    } else {
      // A character that is neither a letter nor punctuation, such as the
      // dollar sign of a formula. It stands on its own.
      words.push(Word::new(c.to_string()))
      i.val = i.val + 1
    }
    // The loop always moves, whatever the text holds.
    if i.val == begin {
      i.val = i.val + 1
    }
  }
  words
}

///|
/// The bare words of a text, used for comparison.
pub fn word_keys(words : Array[Word]) -> Array[String] {
  let keys = []
  for w in words {
    keys.push(w.word)
  }
  keys
}
