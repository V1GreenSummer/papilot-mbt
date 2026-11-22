///|
/// A change of a round, with the edit of the source it belongs to.
///
/// A change on the page is what the author sees; the edit is what has to be
/// applied when the author accepts it. The two are connected through the
/// SyncTeX file of the proposal.
#derive(Eq)
#derive(@debug.Debug)
pub struct TaskChange {
  /// The change as it appears on the page.
  change : @compare.Change
  /// The index of the source edit the change belongs to.
  edit : Int32?
  /// The source the change comes from.
  source : @synctex.SourceLocation?
  /// The decision the author already made about this change.
  decision : @journal.Decision?
}

///|
pub extend TaskChange with Eq::{not_equal, equal}

///|
pub extend TaskChange with @debug.Debug::{to_repr}

///|
pub fn TaskChange::to_string(self : TaskChange) -> String {
  "TaskChange(\{self.change.to_string()})"
}

///|
/// The change of a JSON object.
pub fn TaskChange::from_json(json : Json) -> TaskChange? {
  let change = match @compare.Change::from_json(json) {
    Some(c) => c
    None => return None
  }
  let source = match @jsonx.field(json, "source") {
    Some(s) =>
      Some(
        @synctex.SourceLocation::new(
          @jsonx.text(s, "file"),
          @jsonx.number(s, "line"),
        ),
      )
    None => None
  }
  let edit = match @jsonx.field(json, "edit") {
    Some(_) => Some(@jsonx.number(json, "edit"))
    None => None
  }
  Some(TaskChange::{ change, edit, source, decision: None, })
}

///|
/// The change as the client sees it.
pub fn TaskChange::to_json(self : TaskChange) -> Json {
  let json = match self.change.to_json() {
    Json::Object(fields) => fields
    _ => Map([])
  }
  match self.edit {
    Some(index) => json.set("edit", Json::number(index.to_double()))
    None => ()
  }
  match self.source {
    Some(source) =>
      json.set(
        "source",
        Json::object({
          "file": Json::string(source.file),
          "line": Json::number(source.line.to_double()),
        }),
      )
    None => ()
  }
  Json::object(json)
}

///|
/// Why a round could not be published.
///
/// A failure is always reported. A round that cannot be built is never shown
/// as a round without changes, because that would hide the problem from the
/// author.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum PublishError {
  /// The accepted text could not be compiled.
  AcceptedBuildFailed(String)
  /// The proposal of the agent could not be compiled.
  ProposalBuildFailed(String)
  /// The PDF of the accepted text is missing.
  NoAcceptedPdf
  /// The PDF of the proposal is missing.
  NoProposalPdf
  /// The PDF of the accepted text could not be read.
  CannotReadAccepted
  /// The PDF of the proposal could not be read.
  CannotReadProposal
  /// The SyncTeX file of the proposal could not be read.
  CannotReadSynctex
}

///|
pub extend PublishError with Eq::{not_equal, equal}

///|
pub extend PublishError with @debug.Debug::{to_repr}

///|
pub fn PublishError::to_string(self : PublishError) -> String {
  match self {
    AcceptedBuildFailed(log) =>
      "the accepted text could not be compiled: " + log
    ProposalBuildFailed(log) => "the proposal could not be compiled: " + log
    NoAcceptedPdf => "the accepted text has no PDF"
    NoProposalPdf => "the proposal has no PDF"
    CannotReadAccepted => "the PDF of the accepted text could not be read"
    CannotReadProposal => "the PDF of the proposal could not be read"
    CannotReadSynctex => "the SyncTeX file of the proposal could not be read"
  }
}

///|
/// The result of publishing a round.
pub struct PublishResult {
  /// The round that was published.
  round : Round
  /// The log of the compilation of the proposal.
  log : String
}

///|
/// Compile the accepted text and the proposal and report what changed.
///
/// The accepted text is the working tree of the author, built in a copy of the
/// sources. The proposal is the worktree of the agent. Both are compiled with
/// the same settings, so that the difference between the two PDFs is the
/// difference between the two texts.
pub async fn publish(
  task : Task,
  round : Int32,
  build_root : String,
  compiler~ : String = "latexmk",
) -> Result[PublishResult, PublishError] {
  // The place where the accepted text is built.
  let accepted_dir = build_root + "/accepted"
  @build.remove_tree(accepted_dir)
  let source = task.repo + "/" + task.source_dir
  @build.copy_tree(source, accepted_dir)
  // The place where the proposal is built.
  let proposal_dir = task.worktree
  // The accepted text.
  let accepted_settings = @build.BuildSettings::new(
    task.main,
    task.engine,
    task.source_dir,
    accepted_dir,
    compiler~,
  )
  let accepted = @build.compile(accepted_settings)
  if !accepted.ok() {
    return Err(PublishError::AcceptedBuildFailed(accepted.log))
  }
  // The proposal of the agent.
  let proposal_settings = @build.BuildSettings::new(
    task.main,
    task.engine,
    task.source_dir,
    proposal_dir,
    compiler~,
  )
  let proposal = @build.compile(proposal_settings)
  if !proposal.ok() {
    return Err(PublishError::ProposalBuildFailed(proposal.log))
  }
  let old_pdf = match accepted.pdf {
    Some(pdf) => pdf
    None => return Err(PublishError::NoAcceptedPdf)
  }
  let new_pdf = match proposal.pdf {
    Some(pdf) => pdf
    None => return Err(PublishError::NoProposalPdf)
  }
  let old_text = match read_pdf(old_pdf) {
    Some(t) => t
    None => return Err(PublishError::CannotReadAccepted)
  }
  let new_text = match read_pdf(new_pdf) {
    Some(t) => t
    None => return Err(PublishError::CannotReadProposal)
  }
  let changes = @compare.compare(old_text, new_text)
  // The SyncTeX file of the proposal says which source produced each change.
  let synctex = match read_synctex(proposal.synctex) {
    Some(s) => s
    None => return Err(PublishError::CannotReadSynctex)
  }
  let edits = edits_of(task)
  let task_changes = []
  for change in changes {
    // The place of the change on the page is matched with the lines of the
    // typeset output, which is where the source of the change comes from.
    let located = match new_text.page(change.page) {
      Some(page) => @compare.locate(page, synctex, change.page, change.rect)
      None => None
    }
    let source = match located {
      Some(found) => Some(found.source)
      None => None
    }
    let index = match source {
      Some(from) => edit_covering(edits, from)
      None => None
    }
    task_changes.push(TaskChange::{
      change,
      edit: index,
      source,
      decision: None,
    })
  }
  Ok(PublishResult::{
    round: Round::new(round, task_changes, edits),
    log: proposal.log,
  })
}

///|
/// The edit of the source that covers a place.
fn edit_covering(
  edits : Array[SourceEdit],
  source : @synctex.SourceLocation,
) -> Int32? {
  let mut index = 0
  while index < edits.length() {
    if edits[index].covers_new(source.file, source.line) {
      return Some(index)
    }
    index = index + 1
  }
  None
}

///|
/// Read the text of a PDF.
async fn read_pdf(path : String) -> @pdftext.PdfText? {
  let content = @fs.read_file(path) catch { _ => return None }
  let result = @pdftext.extract(content.binary()) catch { _ => return None }
  Some(result)
}

///|
/// Read the SyncTeX file of a compilation.
async fn read_synctex(path : String?) -> @synctex.SynctexFile? {
  match path {
    Some(p) => {
      let content = @fs.read_file(p) catch { _ => return None }
      let bytes = content.binary()
      let text = if bytes.length() > 2 &&
        bytes[0] == 0x1FU.to_byte() &&
        bytes[1] == 0x8BU.to_byte() {
        let raw = @gzip.decompress(bytes, max_output=64 * 1024 * 1024) catch {
          _ => return None
        }
        @utf8.decode_lossy(raw)
      } else {
        @utf8.decode_lossy(bytes)
      }
      Some(@synctex.parse(text))
    }
    None => None
  }
}
