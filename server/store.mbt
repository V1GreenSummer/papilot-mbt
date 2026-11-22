///|
/// The state of the engine, kept in the repository.
///
/// The state lives in `.git/papilot/` of the repository, so that the engine
/// finds its tasks again when it starts and so that nothing of it ends up in
/// the working tree of the author.
pub struct Store {
  folder : String
}

///|
pub fn Store::new(folder : String) -> Store {
  { folder, }
}

///|
/// The folder of the state.
pub fn Store::folder(self : Store) -> String {
  self.folder
}

///|
/// The file the tasks are written to.
pub fn Store::tasks_file(self : Store) -> String {
  self.folder + "/tasks.ndjson"
}

///|
/// The file the rounds are written to.
pub fn Store::rounds_file(self : Store) -> String {
  self.folder + "/rounds.ndjson"
}

///|
/// Write a task.
pub async fn Store::save_task(self : Store, task : @task.Task) -> Unit {
  self.append(self.tasks_file(), task.to_json().stringify())
}

///|
/// Write a round.
pub async fn Store::save_round(
  self : Store,
  task : String,
  round : @task.Round,
) -> Unit {
  let json = match round.to_json() {
    Json::Object(fields) => fields
    _ => Map([])
  }
  json.set("task", Json::string(task))
  self.append(self.rounds_file(), Json::object(json).stringify())
}

///|
/// Read every task.
pub async fn Store::tasks(self : Store) -> Array[@task.Task] {
  let tasks = []
  for line in self.lines(self.tasks_file()) {
    let json = @json.parse(line) catch { _ => continue }
    match @task.Task::from_json(json) {
      Some(task) => tasks.push(task)
      None => ()
    }
  }
  tasks
}

///|
/// Read the last round of every task.
pub async fn Store::rounds(self : Store) -> Map[String, @task.Round] {
  let rounds = Map([])
  for line in self.lines(self.rounds_file()) {
    let json = @json.parse(line) catch { _ => continue }
    let task = @jsonx.text(json, "task")
    match @task.Round::from_json(json) {
      Some(round) => rounds.set(task, round)
      None => ()
    }
  }
  rounds
}

///|
/// Add a line to a file.
async fn Store::append(self : Store, path : String, line : String) -> Unit {
  @fs.mkdir(self.folder, recursive=true) catch {
    _ => ()
  }
  @fs.write_file(
    path,
    line + "\n",
    append=true,
    create_mode=@fs.CreateMode::OpenOrCreate,
  ) catch {
    _ => ()
  }
}

///|
/// The lines of a file.
async fn Store::lines(self : Store, path : String) -> Array[String] {
  let _ = self
  let lines = []
  let content = @fs.read_file(path) catch { _ => return lines }
  let text = @utf8.decode_lossy(content.binary())
  for line in text.split("\n") {
    let trimmed = line.trim().to_owned()
    if !trimmed.is_empty() {
      lines.push(trimmed)
    }
  }
  lines
}
