///|
pub extend ReferenceKind with Eq::{not_equal, equal}

///|
pub extend ReferenceKind with @debug.Debug::{to_repr}

///|
/// What a `\...` command refers to.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum ReferenceKind {
  /// `\label{name}`
  Label
  /// `\ref{name}`, `\eqref`, `\autoref`, `\cref`, `\Cref`, `\pageref`
  Ref
  /// `\cite{name}`, `\citep`, `\citet`, `\parencite`, `\textcite`
  Cite
  /// `\include{name}`
  Include
  /// `\input{name}`
  Input
  /// `\subfile{name}`
  Subfile
  /// `\bibliography{name}`, `\addbibresource{name}`
  Bibliography
}

///|
pub fn ReferenceKind::to_string(self : ReferenceKind) -> String {
  match self {
    Label => "Label"
    Ref => "Ref"
    Cite => "Cite"
    Include => "Include"
    Input => "Input"
    Subfile => "Subfile"
    Bibliography => "Bibliography"
  }
}

///|
pub struct Reference {
  kind : ReferenceKind
  name : String
  /// The span of the argument, braces excluded.
  span : Span
}

///|
/// A sectioning unit of a document.
pub struct Section {
  /// `0` for `\part` up to `5` for `\paragraph`.
  level : Int32
  /// The heading text as written in the source.
  title : String
  /// The span of the heading text.
  title_span : Span
  /// The span of the heading command through the end of the section body.
  span : Span
  /// The span of the section body, excluding the heading.
  body_span : Span
}

///|
pub fn Section::to_string(self : Section) -> String {
  "Section(level=\{self.level}, title=\{self.title})"
}

///|
/// A LaTeX environment instance.
pub struct Environment {
  name : String
  /// The span of `\begin{name}`.
  begin_span : Span
  /// The span of `\end{name}`.
  end_span : Span
  /// The span of the environment body.
  content_span : Span
}

///|
/// The structure of a parsed LaTeX document.
pub struct Document {
  /// All sections in document order.
  sections : Array[Section]
  /// All labelled or referenced names.
  references : Array[Reference]
  /// All environment instances.
  environments : Array[Environment]
  /// Everything before `\begin{document}`.
  preamble_span : Span
  /// Everything from `\begin{document}` to the end of the file.
  body_span : Span
}

///|
/// Environments whose content is not LaTeX and must not be scanned.
fn is_verbatim_environment(name : String) -> Bool {
  name == "verbatim" ||
  name == "Verbatim" ||
  name == "lstlisting" ||
  name == "minted" ||
  name == "alltt" ||
  name == "comment" ||
  name.has_prefix("filecontents")
}

///|
/// The level of a sectioning command, or `None` when it is not one.
fn section_level(name : String) -> Int32? {
  match name {
    "part" => Some(0)
    "chapter" => Some(1)
    "section" => Some(2)
    "subsection" => Some(3)
    "subsubsection" => Some(4)
    "paragraph" => Some(5)
    _ => None
  }
}

///|
/// The kind of reference a command introduces, or `None` when it is not one.
fn reference_kind(name : String) -> ReferenceKind? {
  match name {
    "label" => Some(ReferenceKind::Label)
    "ref"
    | "eqref"
    | "autoref"
    | "cref"
    | "Cref"
    | "pageref"
    | "nameref"
    | "vref"
    | "Vref" => Some(ReferenceKind::Ref)
    "cite"
    | "citep"
    | "citet"
    | "parencite"
    | "textcite"
    | "footcite"
    | "autocite"
    | "citeauthor"
    | "citeyear"
    | "citenum" => Some(ReferenceKind::Cite)
    "include" => Some(ReferenceKind::Include)
    "input" => Some(ReferenceKind::Input)
    "subfile" => Some(ReferenceKind::Subfile)
    "bibliography" | "addbibresource" => Some(ReferenceKind::Bibliography)
    _ => None
  }
}

///|
/// The word of the control sequence at `index`, if there is one.
fn command_at(lexer : Lexer, index : Int32) -> String? {
  match lexer.get(index) {
    Some(t) =>
      if t.kind == ControlSequence {
        match parse_control(lexer.source.text(t.span)) {
          Some(ControlWord::Word(w)) => Some(w)
          Some(ControlWord::Symbol(_)) => None
          None => None
        }
      } else {
        None
      }
    None => None
  }
}

///|
/// The index of the group that holds the argument of the command at `index`.
///
/// Handles the starred form (`\section*{...}`) and commands whose argument is
/// not a braced group (which have no argument).
fn argument_group(lexer : Lexer, index : Int32) -> Int32? {
  let mut next = index + 1
  match lexer.get(next) {
    Some(t) =>
      // `\section*` puts a `*` between the command and its argument.
      if t.kind == Text && lexer.source.text(t.span) == "*" {
        next = next + 1
      }
    None => return None
  }
  match lexer.get(next) {
    Some(t) => if t.kind == BeginGroup { Some(next) } else { None }
    None => None
  }
}

///|
/// The raw text of a group argument.
fn argument_text(lexer : Lexer, group_index : Int32) -> String {
  match lexer.group_content(group_index) {
    Some(span) => lexer.source.text(span).trim().to_owned()
    None => ""
  }
}

///|
/// Parse a LaTeX source string into its structure.
///
/// The parser is tolerant of unbalanced braces and unknown commands: it records
/// what it recognises and ignores the rest.
pub fn parse_text(text : String) -> Document {
  parse(Source::new(text))
}

///|
pub fn parse(source : Source) -> Document {
  let lexer = tokenize(source)
  let n = lexer.tokens.length()
  let sections = []
  let references = []
  let environments = []
  let verbatim_depth = @ref.Ref(0)
  let document_start = @ref.Ref(None)
  // Open environments, as (name, index of the `\begin` token, index of the
  // group holding the environment name).
  let env_stack = []
  let mut i = 0
  while i < n {
    let name = command_at(lexer, i)
    match name {
      Some("begin") =>
        match argument_group(lexer, i) {
          Some(group) => {
            let env_name = argument_text(lexer, group)
            if env_name == "document" && document_start.val is None {
              document_start.val = Some(lexer.tokens[i].span.end)
            }
            if is_verbatim_environment(env_name) {
              verbatim_depth.val = verbatim_depth.val + 1
            }
            env_stack.push((env_name, i, group))
          }
          None => ()
        }
      Some("end") =>
        match argument_group(lexer, i) {
          Some(group) => {
            let env_name = argument_text(lexer, group)
            // Pop to the matching `\begin`.
            let mut matched = None
            let mut j = env_stack.length() - 1
            while j >= 0 {
              let entry = env_stack[j]
              if entry.0 == env_name {
                matched = Some(entry)
                env_stack.truncate(j)
                break
              }
              j = j - 1
            }
            match matched {
              Some(entry) => {
                let (env_name, begin_index, begin_group) = entry
                if is_verbatim_environment(env_name) {
                  verbatim_depth.val = verbatim_depth.val - 1
                }
                let content = match lexer.group_content(begin_group) {
                  Some(s) => Span::new(s.start, lexer.tokens[i].span.start)
                  None =>
                    Span::new(
                      lexer.tokens[begin_index].span.end,
                      lexer.tokens[i].span.start,
                    )
                }
                environments.push(Environment::{
                  name: env_name,
                  begin_span: lexer.tokens[begin_index].span,
                  end_span: lexer.tokens[i].span,
                  content_span: content,
                })
              }
              None => ()
            }
          }
          None => ()
        }
      Some(cmd) =>
        if verbatim_depth.val == 0 {
          match section_level(cmd) {
            Some(level) =>
              match argument_group(lexer, i) {
                Some(group) => {
                  let title_span = match lexer.group_content(group) {
                    Some(s) => s
                    None => lexer.tokens[i].span
                  }
                  sections.push(Section::{
                    level,
                    title: argument_text(lexer, group),
                    title_span,
                    span: lexer.tokens[i].span,
                    body_span: lexer.tokens[i].span,
                  })
                }
                None => ()
              }
            None =>
              match reference_kind(cmd) {
                Some(kind) =>
                  match argument_group(lexer, i) {
                    Some(group) =>
                      match lexer.group_content(group) {
                        Some(span) =>
                          references.push(Reference::{
                            kind,
                            name: argument_text(lexer, group),
                            span,
                          })
                        None => ()
                      }
                    None => ()
                  }
                None => ()
              }
          }
        }
      None => ()
    }
    i = i + 1
  }
  // The body starts at `\begin{document}`; everything before it is preamble.
  let body_start = match document_start.val {
    Some(s) => s
    None => 0
  }
  let final_preamble = Span::new(0, body_start)
  let final_body = Span::new(body_start, source.length())
  let final_sections = close_sections(sections, final_body)
  Document::{
    sections: final_sections,
    references,
    environments,
    preamble_span: final_preamble,
    body_span: final_body,
  }
}

///|
/// Give every section a body span that reaches up to the next heading of the
/// same or a higher level.
fn close_sections(sections : Array[Section], body : Span) -> Array[Section] {
  let n = sections.length()
  let result = []
  for i in 0..<n {
    let section = sections[i]
    let mut body_end = body.end
    let mut j = i + 1
    while j < n {
      if sections[j].level <= section.level {
        body_end = sections[j].span.start
        break
      }
      j = j + 1
    }
    let body_span = Span::new(section.title_span.end, body_end)
    result.push(Section::{
      ..section,
      body_span,
      span: Span::new(section.span.start, body_end),
    })
  }
  result
}

///|
/// The innermost section that contains `offset`.
pub fn Document::section_at(self : Document, offset : Int32) -> Section? {
  let mut best : Section? = None
  for s in self.sections {
    if s.body_span.contains(offset) {
      match best {
        Some(b) => if s.level > b.level { best = Some(s) }
        None => best = Some(s)
      }
    }
  }
  best
}

///|
/// Every section whose body contains `offset`, outermost first.
pub fn Document::sections_at(self : Document, offset : Int32) -> Array[Section] {
  let found = []
  for s in self.sections {
    if s.body_span.contains(offset) {
      found.push(s)
    }
  }
  found
}

///|
/// The label defined at `offset`, if the offset is inside a `\label{...}`.
pub fn Document::label_at(self : Document, offset : Int32) -> String? {
  for r in self.references {
    if r.kind == ReferenceKind::Label && r.span.contains(offset) {
      return Some(r.name)
    }
  }
  None
}

///|
/// Every reference of the given kind.
pub fn Document::references_of(
  self : Document,
  kind : ReferenceKind,
) -> Array[Reference] {
  let found = []
  for r in self.references {
    if r.kind == kind {
      found.push(r)
    }
  }
  found
}

///|
/// The names of the files the document pulls in.
pub fn Document::included_files(self : Document) -> Array[String] {
  let names = []
  for r in self.references {
    match r.kind {
      ReferenceKind::Include | ReferenceKind::Input | ReferenceKind::Subfile =>
        if !r.name.is_empty() {
          names.push(r.name)
        }
      _ => ()
    }
  }
  names
}

///|
/// The first label that appears inside the given section.
pub fn Document::section_label(self : Document, section : Section) -> String? {
  for r in self.references {
    if r.kind == ReferenceKind::Label &&
      section.body_span.contains(r.span.start) {
      return Some(r.name)
    }
  }
  None
}
