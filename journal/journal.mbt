///|
pub extend Decision with Eq::{not_equal, equal}

///|
pub extend Decision with @debug.Debug::{to_repr}

///|
pub extend Entry with Eq::{not_equal, equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
/// What the author decided about a change.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum Decision {
  /// The change is good and goes into the document.
  Accepted
  /// The change is not wanted.
  Rejected
  /// The change needs work; the note is sent back to the agent.
  Commented(String)
}

///|
pub fn Decision::to_string(self : Decision) -> String {
  match self {
    Accepted => "Accepted"
    Rejected => "Rejected"
    Commented(text) => "Commented: " + text
  }
}

///|
/// The comment of a decision, if it has one.
pub fn Decision::comment(self : Decision) -> String? {
  match self {
    Commented(text) => Some(text)
    _ => None
  }
}

///|
/// An entry of the journal.
///
/// The journal is append only: every event that happened is written down and
/// never changed. The state of a task is the result of replaying its events.
#derive(Eq)
#derive(@debug.Debug)
pub(all) enum Entry {
  /// A task was created.
  TaskCreated(String, String)
  /// A round of a task was published.
  RoundPublished(String, Int32, Int32)
  /// A decision is about to be applied.
  Deciding(String, Int32, Int32, Decision)
  /// A decision was applied.
  Decided(String, Int32, Int32, Decision)
  /// A decision was undone.
  Undone(String, Int32, Int32)
}

///|
pub fn Entry::to_string(self : Entry) -> String {
  match self {
    TaskCreated(task, _) => "TaskCreated(\{task})"
    RoundPublished(task, round, count) =>
      "RoundPublished(\{task}, round \{round}, \{count} changes)"
    Deciding(task, round, change, decision) =>
      "Deciding(\{task}, \{round}, \{change}, \{decision.to_string()})"
    Decided(task, round, change, decision) =>
      "Decided(\{task}, \{round}, \{change}, \{decision.to_string()})"
    Undone(task, round, change) => "Undone(\{task}, \{round}, \{change})"
  }
}

///|
/// The task an entry belongs to.
pub fn Entry::task(self : Entry) -> String {
  match self {
    TaskCreated(task, _) => task
    RoundPublished(task, _, _) => task
    Deciding(task, _, _, _) => task
    Decided(task, _, _, _) => task
    Undone(task, _, _) => task
  }
}

///|
/// The JSON form of a decision.
pub fn Decision::to_json(self : Decision) -> Json {
  decision_to_json(self)
}

///|
/// The JSON form of a decision.
fn decision_to_json(decision : Decision) -> Json {
  match decision {
    Accepted => Json::object({ "kind": Json::string("accepted") })
    Rejected => Json::object({ "kind": Json::string("rejected") })
    Commented(text) =>
      Json::object({
        "kind": Json::string("commented"),
        "text": Json::string(text),
      })
  }
}

///|
/// The decision of a JSON object.
fn decision_of_json(json : Json) -> Decision {
  match @jsonx.text(json, "kind") {
    "accepted" => Accepted
    "rejected" => Rejected
    "commented" => Commented(@jsonx.text(json, "text"))
    _ => Rejected
  }
}

///|
/// The JSON form of an entry.
pub fn Entry::to_json(self : Entry) -> Json {
  match self {
    TaskCreated(task, worktree) =>
      Json::object({
        "type": Json::string("task_created"),
        "task": Json::string(task),
        "worktree": Json::string(worktree),
      })
    RoundPublished(task, round, count) =>
      Json::object({
        "type": Json::string("round_published"),
        "task": Json::string(task),
        "round": Json::number(round.to_double()),
        "changes": Json::number(count.to_double()),
      })
    Deciding(task, round, change, decision) =>
      Json::object({
        "type": Json::string("deciding"),
        "task": Json::string(task),
        "round": Json::number(round.to_double()),
        "change": Json::number(change.to_double()),
        "decision": decision_to_json(decision),
      })
    Decided(task, round, change, decision) =>
      Json::object({
        "type": Json::string("decided"),
        "task": Json::string(task),
        "round": Json::number(round.to_double()),
        "change": Json::number(change.to_double()),
        "decision": decision_to_json(decision),
      })
    Undone(task, round, change) =>
      Json::object({
        "type": Json::string("undone"),
        "task": Json::string(task),
        "round": Json::number(round.to_double()),
        "change": Json::number(change.to_double()),
      })
  }
}

///|
/// The entry of a JSON object.
pub fn Entry::from_json(json : Json) -> Entry? {
  let kind = @jsonx.text(json, "type")
  if kind.is_empty() {
    return None
  }
  let task = @jsonx.text(json, "task")
  match kind {
    "task_created" => Some(TaskCreated(task, @jsonx.text(json, "worktree")))
    "round_published" =>
      Some(
        RoundPublished(
          task,
          @jsonx.number(json, "round"),
          @jsonx.number(json, "changes"),
        ),
      )
    "deciding" => {
      let decision = match @jsonx.field(json, "decision") {
        Some(d) => decision_of_json(d)
        None => Rejected
      }
      Some(
        Deciding(
          task,
          @jsonx.number(json, "round"),
          @jsonx.number(json, "change"),
          decision,
        ),
      )
    }
    "decided" => {
      let decision = match @jsonx.field(json, "decision") {
        Some(d) => decision_of_json(d)
        None => Rejected
      }
      Some(
        Decided(
          task,
          @jsonx.number(json, "round"),
          @jsonx.number(json, "change"),
          decision,
        ),
      )
    }
    "undone" =>
      Some(
        Undone(
          task,
          @jsonx.number(json, "round"),
          @jsonx.number(json, "change"),
        ),
      )
    _ => None
  }
}

///|
/// A journal of decisions.
///
/// The journal is a file of one JSON object per line. Because it is only ever
/// appended to, an interrupted write can be cut short without losing what came
/// before it, and the server can finish an unfinished decision when it starts.
pub struct Journal {
  path : String
}

///|
pub fn Journal::new(path : String) -> Journal {
  { path, }
}

///|
/// The path of the journal file.
pub fn Journal::path(self : Journal) -> String {
  self.path
}

///|
/// Write an entry to the journal.
///
/// The journal lives in a folder of its own, which is made before the first
/// entry is written.
pub async fn Journal::append(self : Journal, entry : Entry) -> Bool {
  let line = entry.to_json().stringify() + "\n"
  @fs.mkdir(folder_of(self.path), recursive=true) catch {
    _ => ()
  }
  // The journal is append only: an existing file is never truncated.
  @fs.write_file(
    self.path,
    line,
    append=true,
    create_mode=@fs.CreateMode::OpenOrCreate,
  ) catch {
    _ => return false
  }
  true
}

///|
/// The folder a file lives in.
fn folder_of(path : String) -> String {
  match path.rev_find("/") {
    Some(index) => path.clamped_view(start=0, end=index).to_owned()
    None => "."
  }
}

///|
/// Read every entry of the journal.
///
/// A line that cannot be read is skipped: it is the tail of an interrupted
/// write, and everything before it is still good.
pub async fn Journal::read(self : Journal) -> Array[Entry] {
  let entries = []
  let content = @fs.read_file(self.path) catch { _ => return entries }
  let text = @utf8.decode_lossy(content.binary())
  for line in text.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.is_empty() {
      continue
    }
    let json = @json.parse(trimmed) catch { _ => continue }
    match Entry::from_json(json) {
      Some(entry) => entries.push(entry)
      None => ()
    }
  }
  entries
}

///|
/// The decisions of a task, in the order they were made.
pub async fn Journal::decisions_of(
  self : Journal,
  task : String,
) -> Array[(Int32, Int32, Decision)] {
  let decisions = []
  for entry in self.read() {
    match entry {
      Decided(t, round, change, decision) =>
        if t == task {
          decisions.push((round, change, decision))
        }
      _ => ()
    }
  }
  decisions
}

///|
/// The decisions that were started but never finished.
///
/// A decision is written down before it is applied, so an engine that stops in
/// the middle leaves a trace. The decisions of this list are the ones that
/// have to be made again.
pub async fn Journal::unfinished(
  self : Journal,
) -> Array[(String, Int32, Int32, Decision)] {
  let started = []
  let finished = []
  for entry in self.read() {
    match entry {
      Deciding(task, round, change, decision) =>
        started.push((task, round, change, decision))
      Decided(task, round, change, _) =>
        finished.push(task + ":" + round.to_string() + ":" + change.to_string())
      Undone(task, round, change) =>
        finished.push(task + ":" + round.to_string() + ":" + change.to_string())
      _ => ()
    }
  }
  let left = []
  for (task, round, change, decision) in started {
    let key = task + ":" + round.to_string() + ":" + change.to_string()
    if !finished.contains(key) {
      left.push((task, round, change, decision))
    }
  }
  left
}

///|
/// The last decision made about a change of a round.
pub async fn Journal::decision_of(
  self : Journal,
  task : String,
  round : Int32,
  change : Int32,
) -> Decision? {
  let mut found = None
  for entry in self.read() {
    match entry {
      Decided(t, r, c, decision) =>
        if t == task && r == round && c == change {
          found = Some(decision)
        }
      Undone(t, r, c) =>
        if t == task && r == round && c == change {
          found = None
        }
      _ => ()
    }
  }
  found
}
