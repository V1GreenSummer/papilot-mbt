///|
/// The state the server keeps while it runs.
pub struct App {
  /// The repository the server works on.
  repo : String
  /// The folder the worktrees of the tasks live in.
  worktrees : String
  /// The journal the decisions are written to.
  journal : @journal.Journal
  /// The state that survives a restart.
  store : Store
  /// The tasks that exist, by name.
  tasks : Map[String, @task.Task]
  /// The last round of every task, by name.
  rounds : Map[String, @task.Round]
}

///|
pub fn App::new(
  repo : String,
  worktrees : String,
  journal : @journal.Journal,
) -> App {
  let store = Store::new(repo + "/.git/papilot")
  { repo, worktrees, journal, store, tasks: Map([]), rounds: Map([]), }
}

///|
/// The tasks that exist, read from the state of the repository.
pub async fn App::load(app : App) -> App {
  let tasks = Map([])
  for task in app.store.tasks() {
    tasks.set(task.id, task)
  }
  let rounds = app.store.rounds()
  { ..app, tasks, rounds, }
}

///|
/// Send a JSON answer.
async fn send_json(
  conn : @http.ServerConnection,
  code : Int32,
  json : Json,
) -> Unit {
  let body = json.stringify()
  conn
  ..send_response(code, "OK", extra_headers={
    "Content-Type": "application/json",
    "Content-Length": body.length().to_string(),
  })
  ..write_string(body)
  .end_response()
}

///|
/// Send an answer that reports a problem.
async fn send_error(
  conn : @http.ServerConnection,
  code : Int32,
  message : String,
) -> Unit {
  send_json(conn, code, Json::object({ "error": Json::string(message) }))
}

///|
/// Read the body of a request.
async fn read_body(body : &@io.Reader) -> String {
  let data = body.read_all()
  @utf8.decode_lossy(data.binary())
}

///|
/// The parts of a path.
fn path_parts(path : String) -> Array[String] {
  let parts = []
  for part in path.split("/") {
    let text = part.trim().to_owned()
    if !text.is_empty() {
      parts.push(text)
    }
  }
  parts
}

///|
/// Handle one request.
pub async fn handle(
  app : Ref[App],
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let parts = path_parts(request.path)
  match (request.meth, parts) {
    (@http.RequestMethod::Get, ["health"]) =>
      send_json(conn, 200, Json::object({ "status": Json::string("ok") }))
    (@http.RequestMethod::Get, ["tasks"]) => {
      let tasks = []
      for (_, task) in app.val.tasks {
        tasks.push(task.to_json())
      }
      send_json(conn, 200, Json::object({ "tasks": Json::array(tasks) }))
    }
    (@http.RequestMethod::Post, ["tasks"]) => {
      let text = read_body(body)
      let json = @json.parse(text) catch {
        _ => {
          send_error(conn, 400, "the request body is not valid JSON")
          return
        }
      }
      let id = @jsonx.text(json, "id")
      let main = @jsonx.text(json, "main")
      let engine = @jsonx.text(json, "engine")
      let id = if id.is_empty() { "task" } else { id }
      let main = if main.is_empty() { "main.tex" } else { main }
      let engine = if engine.is_empty() { "pdflatex" } else { engine }
      let task = @task.create(
        app.val.repo,
        id,
        main,
        engine,
        app.val.worktrees,
        ".",
      ) catch {
        _ => None
      }
      match task {
        Some(t) => {
          let _ = app.val.journal.append(
            @journal.Entry::TaskCreated(t.id, t.worktree),
          )
          app.val.tasks.set(t.id, t)
          app.val.store.save_task(t)
          send_json(conn, 201, t.to_json())
        }
        None => send_error(conn, 500, "the task could not be created")
      }
    }
    (@http.RequestMethod::Get, ["tasks", id]) =>
      match app.val.tasks.get(id) {
        Some(task) => {
          let json = match task.to_json() {
            Json::Object(obj) => obj
            _ => Map([])
          }
          match app.val.rounds.get(id) {
            Some(round) => json.set("round", round.to_json())
            None => ()
          }
          send_json(conn, 200, Json::object(json))
        }
        None => send_error(conn, 404, "there is no task with that name")
      }
    (@http.RequestMethod::Get, ["tasks", id, "changes"]) =>
      match app.val.rounds.get(id) {
        Some(round) => send_json(conn, 200, round.to_json())
        None => send_error(conn, 404, "the task has no round yet")
      }
    (@http.RequestMethod::Post, ["tasks", id, "publish"]) =>
      match app.val.tasks.get(id) {
        Some(task) => {
          let round = round_number(app.val.rounds, id) + 1
          let build_root = task.worktree + "-build"
          let published = @task.publish(task, round, build_root) catch {
            _ =>
              Err(@task.PublishError::ProposalBuildFailed("the engine stopped"))
          }
          match published {
            Ok(result) => {
              // The changes that the author has not decided yet stay in the
              // list, and the ones that were decided keep their decision.
              let previous = app.val.rounds.get(id)
              let carried = @task.carry_decisions(
                app.val.journal,
                id,
                result.round,
                previous,
              ) catch {
                _ => result.round
              }
              app.val.rounds.set(id, carried)
              app.val.store.save_round(id, carried)
              let _ = app.val.journal.append(
                @journal.Entry::RoundPublished(
                  id,
                  round,
                  carried.changes.length(),
                ),
              )
              send_json(conn, 200, carried.to_json())
            }
            Err(reason) => send_error(conn, 500, reason.to_string())
          }
        }
        None => send_error(conn, 404, "there is no task with that name")
      }
    (@http.RequestMethod::Post, ["tasks", id, "decisions"]) => {
      let text = read_body(body)
      let json = @json.parse(text) catch {
        _ => {
          send_error(conn, 400, "the request body is not valid JSON")
          return
        }
      }
      let round = @jsonx.number(json, "round")
      let change = @jsonx.number(json, "change")
      let kind = @jsonx.text(json, "decision")
      let comment = @jsonx.text(json, "comment")
      let decision = match kind {
        "accept" => @journal.Decision::Accepted
        "reject" => @journal.Decision::Rejected
        "comment" => @journal.Decision::Commented(comment)
        _ => {
          send_error(conn, 400, "the decision is not known")
          return
        }
      }
      // The decision is written down before it is applied, so that an engine
      // that stops in the middle knows what to finish.
      let _ = app.val.journal.append(
        @journal.Entry::Deciding(id, round, change, decision),
      )
      let reason = apply_decision(app.val, id, round, change, decision) catch {
        err => "the decision failed: " + err.to_string()
      }
      let _ = app.val.journal.append(
        @journal.Entry::Decided(id, round, change, decision),
      )
      if reason.is_empty() {
        send_json(
          conn,
          200,
          Json::object({ "status": Json::string("applied") }),
        )
      } else {
        send_json(
          conn,
          200,
          Json::object({
            "status": Json::string("recorded"),
            "reason": Json::string(reason),
          }),
        )
      }
    }
    (@http.RequestMethod::Post, ["tasks", id, "undo"]) => {
      let text = read_body(body)
      let json = @json.parse(text) catch {
        _ => {
          send_error(conn, 400, "the request body is not valid JSON")
          return
        }
      }
      let round = @jsonx.number(json, "round")
      let change = @jsonx.number(json, "change")
      let undone = undo_decision(app.val, id, round, change) catch {
        _ => false
      }
      let _ = app.val.journal.append(@journal.Entry::Undone(id, round, change))
      if undone {
        send_json(conn, 200, Json::object({ "status": Json::string("undone") }))
      } else {
        send_json(
          conn,
          200,
          Json::object({ "status": Json::string("recorded") }),
        )
      }
    }
    _ => send_error(conn, 404, "there is no such endpoint")
  }
}

///|
/// The number of the last round of a task.
fn round_number(rounds : Map[String, @task.Round], id : String) -> Int32 {
  match rounds.get(id) {
    Some(round) => round.number
    None => 0
  }
}

///|
/// The change of a round that a decision is about.
fn change_of(
  rounds : Map[String, @task.Round],
  id : String,
  round : Int32,
  change : Int32,
) -> @task.TaskChange? {
  match rounds.get(id) {
    Some(r) =>
      if r.number != round {
        None
      } else if change >= 0 && change < r.changes.length() {
        Some(r.changes[change])
      } else {
        None
      }
    None => None
  }
}

///|
/// Apply a decision to the sources.
async fn apply_decision(
  app : App,
  id : String,
  round : Int32,
  change : Int32,
  decision : @journal.Decision,
) -> String {
  let task = match app.tasks.get(id) {
    Some(t) => t
    None => return "there is no task with that name"
  }
  let task_change = match change_of(app.rounds, id, round, change) {
    Some(c) => c
    None => return "the task has no such change in that round"
  }
  let index = match task_change.edit {
    Some(i) => i
    None => return "the change does not belong to an edit of the source"
  }
  let round_state = match app.rounds.get(id) {
    Some(r) => r
    None => return "the task has no round"
  }
  if index >= round_state.edits.length() {
    return "the round has no such edit"
  }
  let edit = round_state.edits[index]
  let done = match decision {
    @journal.Decision::Accepted => @task.accept(task, edit)
    @journal.Decision::Rejected => @task.reject(task, edit)
    @journal.Decision::Commented(_) => false
  }
  if done {
    ""
  } else {
    "the change could not be applied"
  }
}

///|
/// Undo a decision.
async fn undo_decision(
  app : App,
  id : String,
  round : Int32,
  change : Int32,
) -> Bool {
  let task = match app.tasks.get(id) {
    Some(t) => t
    None => return false
  }
  let task_change = match change_of(app.rounds, id, round, change) {
    Some(c) => c
    None => return false
  }
  let index = match task_change.edit {
    Some(i) => i
    None => return false
  }
  let round_state = match app.rounds.get(id) {
    Some(r) => r
    None => return false
  }
  if index >= round_state.edits.length() {
    return false
  }
  let edit = round_state.edits[index]
  let decision = app.journal.decision_of(id, round, change) catch { _ => None }
  match decision {
    Some(@journal.Decision::Accepted) => @task.undo_accept(task, edit)
    Some(@journal.Decision::Rejected) => @task.undo_reject(task, edit)
    _ => false
  }
}

///|
/// Run the server until it is stopped.
/// The hours the engine waits before it stops when nobody uses it.
pub const IDLE_HOURS : Int32 = 12

///|
/// Whether a request comes from the machine the engine runs on.
///
/// The engine listens on the loopback address only, but a page of another
/// origin could still ask it to do something. The answer is no.
pub fn same_origin(request : @http.Request) -> Bool {
  match request.headers.get("Origin") {
    Some(origin) =>
      origin == "null" ||
      origin.contains("127.0.0.1") ||
      origin.contains("localhost") ||
      origin.contains("[::1]")
    None => true
  }
}

///|
/// Run the server until it is stopped.
pub async fn serve(app : App, port : Int32) -> Unit {
  let address = @socket.Addr::parse("127.0.0.1:" + port.to_string())
  let server = @http.Server(address)
  // The tasks of the repository are taken up again.
  let loaded = App::load(app) catch { _ => app }
  let state = Ref(loaded)
  // The decisions that were started but never finished are made again.
  finish_unfinished(state) catch {
    _ => ()
  }
  let last_seen = Ref(@env.now())
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      let limit = (IDLE_HOURS * 3600 * 1000).to_uint64()
      let mut running = true
      while running {
        @async.sleep(60 * 1000)
        let idle = @env.now() - last_seen.val
        if idle > limit {
          server.close()
          running = false
        }
      }
    })
    server.run_forever((request, body, conn) => {
      last_seen.val = @env.now()
      if !same_origin(request) {
        send_error(conn, 403, "the request comes from another origin") catch {
          _ => ()
        }
        return
      }
      handle(state, request, body, conn) catch {
        err => {
          println("the request " + request.path + " failed: " + err.to_string())
          send_error(conn, 500, "the request failed") catch {
            _ => ()
          }
        }
      }
    })
  })
}

///|
/// Make the decisions that were started but never finished.
///
/// The engine writes a decision down before it applies it, so a decision that
/// was interrupted is in the journal without its end. Applying it again is
/// safe: the merge of a change that is already there changes nothing.
pub async fn finish_unfinished(app : Ref[App]) -> Unit {
  let unfinished = app.val.journal.unfinished() catch { _ => return }
  for (task, round, change, decision) in unfinished {
    let reason = apply_decision(app.val, task, round, change, decision) catch {
      _ => "the decision failed"
    }
    if reason.is_empty() {
      let _ = app.val.journal.append(
        @journal.Entry::Decided(task, round, change, decision),
      )
    }
  }
}
