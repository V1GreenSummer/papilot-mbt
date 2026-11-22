///|
pub extend TokenKind with Eq::{not_equal, equal}

///|
pub extend TokenKind with @debug.Debug::{to_repr}

///|
pub extend ControlWord with Eq::{not_equal, equal}

///|
pub extend ControlWord with @debug.Debug::{to_repr}

///|
/// The lexical class of a token in a LaTeX source file.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum TokenKind {
  /// Ordinary characters that carry meaning.
  Text
  /// A control sequence: `\alpha`, `\begin`, `\\`, `\%`.
  ControlSequence
  /// A comment, from `%` up to (but not including) the end of the line.
  Comment
  /// An opening brace `{`.
  BeginGroup
  /// A closing brace `}`.
  EndGroup
  /// A math shift `$`.
  MathShift
}

///|
pub fn TokenKind::to_string(self : TokenKind) -> String {
  match self {
    Text => "Text"
    ControlSequence => "ControlSequence"
    Comment => "Comment"
    BeginGroup => "BeginGroup"
    EndGroup => "EndGroup"
    MathShift => "MathShift"
  }
}

///|
pub struct Token {
  kind : TokenKind
  span : Span
}

///|
pub fn Token::to_string(self : Token) -> String {
  "\{self.kind.to_string()}\{self.span.to_string()}"
}

///|
/// The name of a control sequence, split into the two forms TeX distinguishes.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum ControlWord {
  /// `\alpha`, `\begin` — a control word made of letters, possibly prefixed
  /// with `@` as in `\@foo`.
  Word(String)
  /// `\\`, `\%`, `\{` — a control symbol, a single non-letter character.
  Symbol(Char)
}

///|
pub fn ControlWord::name(self : ControlWord) -> String {
  match self {
    Word(w) => w
    Symbol(c) => c.to_string()
  }
}

///|
pub fn ControlWord::to_string(self : ControlWord) -> String {
  match self {
    Word(w) => "\\" + w
    Symbol(c) => "\\" + c.to_string()
  }
}

///|
/// A tokenized LaTeX source file.
///
/// The lexer keeps the brace structure so that the parser can recover the
/// argument of any command without re-scanning the text.
pub struct Lexer {
  source : Source
  tokens : Array[Token]
  /// Maps the index of a `BeginGroup` token to the index of its `EndGroup`.
  group_end : Map[Int32, Int32]
  /// Maps the index of an `EndGroup` token to the index of its `BeginGroup`.
  group_start : Map[Int32, Int32]
}

///|
pub fn Lexer::new(source : Source, tokens : Array[Token]) -> Lexer {
  let group_end = Map([])
  let group_start = Map([])
  let stack = []
  for i in 0..<tokens.length() {
    match tokens[i].kind {
      BeginGroup => stack.push(i)
      EndGroup =>
        if stack.length() > 0 {
          let open = stack.pop().unwrap()
          group_end.set(open, i)
          group_start.set(i, open)
        }
      _ => ()
    }
  }
  { source, tokens, group_end, group_start, }
}

///|
/// The number of tokens in the stream.
pub fn Lexer::length(self : Lexer) -> Int32 {
  self.tokens.length()
}

///|
pub fn Lexer::get(self : Lexer, index : Int32) -> Token? {
  if index >= 0 && index < self.tokens.length() {
    Some(self.tokens[index])
  } else {
    None
  }
}

///|
/// The span of the content between the braces of the group opened at `index`.
///
/// Returns `None` when the token is not a group opener or the group is not
/// closed.
pub fn Lexer::group_content(self : Lexer, index : Int32) -> Span? {
  match self.group_end.get(index) {
    Some(end) => {
      let open = self.tokens[index]
      let close = self.tokens[end]
      Some(Span::new(open.span.end, close.span.start))
    }
    None => None
  }
}

///|
/// The span of the whole group, braces included.
pub fn Lexer::group_span(self : Lexer, index : Int32) -> Span? {
  match self.group_end.get(index) {
    Some(end) => {
      let open = self.tokens[index]
      let close = self.tokens[end]
      Some(Span::new(open.span.start, close.span.end))
    }
    None => None
  }
}

///|
/// The raw text of a token.
pub fn Lexer::token_text(self : Lexer, index : Int32) -> String {
  match self.get(index) {
    Some(t) => self.source.text(t.span)
    None => ""
  }
}

///|
/// The raw text of a span in the tokenized source.
pub fn Lexer::text(self : Lexer, span : Span) -> String {
  self.source.text(span)
}

///|
pub fn Lexer::to_string(self : Lexer) -> String {
  let out = StringBuilder()
  for t in self.tokens {
    out.write_string(t.to_string())
    out.write_string(" ")
  }
  out.to_string()
}

///|
/// Tokenize LaTeX source into a flat token list.
///
/// The tokenizer never rejects input: a paper under review is usually broken
/// somewhere, and the engine still has to find the parts that are fine. Group
/// braces are matched even when they are unbalanced, so a missing `}` does not
/// swallow the rest of the document.
pub fn tokenize(source : Source) -> Lexer {
  let chars = source.chars
  let n = chars.length()
  let tokens = []
  let i = @ref.Ref(0)
  while i.val < n {
    let start = i.val
    let c = chars[start]
    match c {
      '%' => {
        while i.val < n && chars[i.val] != '\n' {
          i.val = i.val + 1
        }
        tokens.push(Token::{ kind: Comment, span: Span::new(start, i.val), })
      }
      '{' => {
        i.val = i.val + 1
        tokens.push(Token::{ kind: BeginGroup, span: Span::new(start, i.val), })
      }
      '}' => {
        i.val = i.val + 1
        tokens.push(Token::{ kind: EndGroup, span: Span::new(start, i.val), })
      }
      '$' => {
        i.val = i.val + 1
        tokens.push(Token::{ kind: MathShift, span: Span::new(start, i.val), })
      }
      '\\' => {
        i.val = i.val + 1
        if i.val < n {
          let c2 = chars[i.val]
          if c2 == '@' {
            i.val = i.val + 1
            while i.val < n && chars[i.val].is_ascii_alphabetic() {
              i.val = i.val + 1
            }
          } else if c2.is_ascii_alphabetic() {
            while i.val < n && chars[i.val].is_ascii_alphabetic() {
              i.val = i.val + 1
            }
          } else {
            i.val = i.val + 1
          }
        }
        tokens.push(Token::{
          kind: ControlSequence,
          span: Span::new(start, i.val),
        })
      }
      _ => {
        while i.val < n {
          let ch = chars[i.val]
          if ch == '%' || ch == '\\' || ch == '{' || ch == '}' || ch == '$' {
            break
          }
          i.val = i.val + 1
        }
        tokens.push(Token::{ kind: Text, span: Span::new(start, i.val), })
      }
    }
    // `\verb<delim>...<delim>` keeps its payload verbatim; swallow it here so
    // that the body is never mistaken for LaTeX.
    if tokens.length() > 0 {
      let last = tokens[tokens.length() - 1]
      if last.kind == ControlSequence {
        let text = source.text(last.span)
        if text == "\\verb" || text == "\\verb*" {
          if i.val < n {
            let delim = chars[i.val]
            i.val = i.val + 1
            while i.val < n && chars[i.val] != delim {
              i.val = i.val + 1
            }
            if i.val < n {
              i.val = i.val + 1
            }
            tokens.push(Token::{
              kind: Text,
              span: Span::new(last.span.end, i.val),
            })
          }
        }
      }
    }
  }
  Lexer::new(source, tokens)
}

///|
/// Tokenize a LaTeX source string.
pub fn tokenize_text(text : String) -> Lexer {
  tokenize(Source::new(text))
}

///|
/// Split the raw text of a control sequence into its `ControlWord` form.
///
/// Returns `None` when `text` is not a control sequence at all.
pub fn parse_control(text : String) -> ControlWord? {
  let chars = text.to_array()
  if chars.length() < 2 || chars[0] != '\\' {
    return None
  }
  let body = chars.clamped_view(start=1, end=chars.length())
  if body.length() == 0 {
    return None
  }
  let first = body[0]
  if first == '@' {
    let rest = chars.clamped_view(start=2, end=chars.length())
    if rest.length() == 0 {
      return Some(ControlWord::Word("@"))
    }
    return Some(ControlWord::Word("@" + String::from_array(rest)))
  }
  if first.is_ascii_alphabetic() {
    return Some(ControlWord::Word(String::from_array(body)))
  }
  Some(ControlWord::Symbol(first))
}
