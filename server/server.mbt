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
  /// The text of the accepted version and of the proposal of the last
  /// publish, by task name: what the viewer renders.
  renders : Map[String, (@pdftext.PdfText, @pdftext.PdfText)]
}

///|
pub fn App::new(
  repo : String,
  worktrees : String,
  journal : @journal.Journal,
) -> App {
  let store = Store::new(repo + "/.git/papilot")
  {
    repo,
    worktrees,
    journal,
    store,
    tasks: Map([]),
    rounds: Map([]),
    renders: Map([]),
  }
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
/// Send the index page of the engine.
///
/// The engine is a JSON interface, not a viewer; the page lists what there
/// is, so that opening the address in a browser shows where to go instead of
/// an error.
async fn send_index(conn : @http.ServerConnection, app : App) -> Unit {
  let mut tasks = ""
  for (_, task) in app.tasks {
    tasks += "<li><a href=\"/tasks/\{task.id}/view\">\{task.id}</a> " +
      "(<a href=\"/tasks/\{task.id}/changes\">changes</a>)</li>\n"
  }
  if tasks == "" {
    tasks = "<li>no tasks yet — POST /tasks " +
      "with <code>{\"id\": \"my-task\", \"main\": \"main.tex\"}</code></li>\n"
  }
  let body = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">" +
    "<title>papilot</title>" +
    "<style>body{font-family:sans-serif;max-width:42em;margin:2em auto;" +
    "padding:0 1em;line-height:1.5}code{background:#f0f0f0;padding:0 .3em}" +
    "td{padding:.2em .8em .2em 0}h1{font-size:1.4em}</style>" +
    "</head><body>\n" +
    "<h1>papilot — work on the PDF, not the .tex</h1>\n" +
    "<p>Serving <code>\{app.repo}</code></p>\n" +
    "<h2>Endpoints</h2>\n<table>\n" +
    "<tr><td><code>GET <a href=\"/health\">/health</a></code></td>" +
    "<td>is the engine alive?</td></tr>\n" +
    "<tr><td><code>GET <a href=\"/tasks\">/tasks</a></code></td>" +
    "<td>the tasks that exist</td></tr>\n" +
    "<tr><td><code>POST /tasks</code></td>" +
    "<td>create a task</td></tr>\n" +
    "<tr><td><code>GET /tasks/:id</code></td>" +
    "<td>the task and its last round</td></tr>\n" +
    "<tr><td><code>POST /tasks/:id/publish</code></td>" +
    "<td>compile both versions, report the changes</td></tr>\n" +
    "<tr><td><code>GET /tasks/:id/changes</code></td>" +
    "<td>the changes of the last round</td></tr>\n" +
    "<tr><td><code>POST /tasks/:id/decisions</code></td>" +
    "<td>accept, reject or comment on a change</td></tr>\n" +
    "<tr><td><code>POST /tasks/:id/undo</code></td>" +
    "<td>take a decision back</td></tr>\n" +
    "</table>\n" +
    "<h2>Tasks</h2>\n<ul>\n\{tasks}</ul>\n" +
    "<p>Everything else answers with JSON.</p>\n" +
    "</body></html>\n"
  conn
  ..send_response(200, "OK", extra_headers={
    "Content-Type": "text/html; charset=utf-8",
  })
  ..write_string(body)
  .end_response()
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
    "Content-Length": byte_length(body).to_string(),
  })
  ..write_string(body)
  .end_response()
}

///|
/// The review page of a task.
///
/// Two vector renderings of the page, before and after, with the changes
/// listed beside them. A change is highlighted on both sides; the buttons
/// decide it. This is a small stand-in for the editor a user would build on
/// the JSON interface.
fn viewer_page(app : App, id : String) -> String? {
  if !app.tasks.contains(id) {
    return None
  }
  let fallback = (612.0, 792.0)
  let (width, height) = match app.renders.get(id) {
    Some((before, after)) =>
      match after.page(1) {
        Some(page) => (page.width, page.height)
        None =>
          match before.page(1) {
            Some(page) => (page.width, page.height)
            None => fallback
          }
      }
    None => fallback
  }
  Some(viewer_shell(id, width, height))
}

///|
/// The page itself, with the task name and the size of its pages in it.
fn viewer_shell(id : String, width : Double, height : Double) -> String {
  let w = width.to_string()
  let h = height.to_string()
  let page = "<div class=\"pane\"><div class=\"frame\">" +
    "<img id=\"img-SIDE\" src=\"/tasks/\{id}/page/1/SIDE.svg\" " +
    "onload=\"reshow()\">" +
    "<div class=\"hl\" id=\"hl-SIDE\"></div></div>" +
    "<div class=\"label\">SIDE</div></div>"
  let before = page.replace(old="SIDE", new="before")
  let after = page.replace(old="SIDE", new="after")
  "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\">" +
  "<title>papilot — \{id}</title>\n" +
  "<style>\n" +
  "body{font-family:sans-serif;margin:0;display:flex;height:100vh}\n" +
  "#side{width:20em;min-width:16em;padding:1em;overflow-y:auto;" +
  "border-right:1px solid #ccc}\n" +
  "#side h1{font-size:1.1em}\n" +
  "#changes li{padding:.4em .2em;border-bottom:1px solid #eee;cursor:pointer}\n" +
  "#changes .dec{color:#0a0;font-size:.85em}\n" +
  "#changes .src{color:#888;font-size:.85em}\n" +
  "#meta{margin:1em 0;font-size:.9em;min-height:3em}\n" +
  "button{margin-right:.4em}\n" +
  "#pages{flex:1;display:flex;gap:1em;padding:1em;overflow:auto}\n" +
  ".pane{flex:1;min-width:0}\n" +
  ".frame{position:relative;border:1px solid #999}\n" +
  ".frame img{width:100%;display:block}\n" +
  ".hl{display:none;position:absolute;border:2px solid #d33;" +
  "background:rgba(255,60,60,.12);pointer-events:none}\n" +
  ".label{text-align:center;color:#666;padding:.3em}\n" +
  "</style></head><body>\n" +
  "<div id=\"side\"><h1>task \{id}</h1>\n" +
  "<button onclick=\"publish()\">Publish a round</button>\n" +
  "<div id=\"meta\">publish a round to see the changes</div>\n" +
  "<ol id=\"changes\"></ol></div>\n" +
  "<div id=\"pages\">" +
  before +
  after +
  "</div>\n" +
  "<script>\n" +
  "const TASK = '\{id}';\n" +
  "const PAGE = { w: \{w}, h: \{h} };\n" +
  "let changes = [];\n" +
  "let round = 0;\n" +
  "let current = -1;\n" +
  "let page = 1;\n" +
  "fetch('/tasks/\{id}/changes').then(r => r.json()).then(j => {\n" +
  "  round = j.round;\n" +
  "  changes = j.changes;\n" +
  "  const list = document.getElementById('changes');\n" +
  "  j.changes.forEach((c, i) => {\n" +
  "    const li = document.createElement('li');\n" +
  "    let html = '<b>#' + i + '</b> ' +\n" +
  "      '<code>-' + c.old_text + ' +' + c.new_text + '</code><br>';\n" +
  "    if (c.source) html += '<span class=\"src\">' +\n" +
  "      c.source.file.split('/').pop() + ':' + c.source.line + '</span> ';\n" +
  "    if (c.decision) html += '<span class=\"dec\">' + c.decision.kind + '</span>';\n" +
  "    html += '<div><button onclick=\"event.stopPropagation();decide(' + i +\n" +
  "      ',\\'accept\\')\">Accept</button>' +\n" +
  "      '<button onclick=\"event.stopPropagation();decide(' + i +\n" +
  "      ',\\'reject\\')\">Reject</button>' +\n" +
  "      '<button onclick=\"event.stopPropagation();decide(' + i +\n" +
  "      ',\\'comment\\')\">Comment</button></div>';\n" +
  "    li.innerHTML = html;\n" +
  "    li.onclick = () => show(i);\n" +
  "    list.appendChild(li);\n" +
  "  });\n" +
  "  document.getElementById('meta').textContent =\n" +
  "    'round ' + round + ', ' + j.changes.length + ' changes';\n" +
  "  if (j.changes.length) show(0);\n" +
  "});\n" +
  "function show(i) {\n" +
  "  current = i;\n" +
  "  const c = changes[i];\n" +
  "  if (!c) return;\n" +
  "  if (c.page !== page) {\n" +
  "    page = c.page;\n" +
  "    document.getElementById('img-before').src =\n" +
  "      '/tasks/\{id}/page/' + page + '/before.svg';\n" +
  "    document.getElementById('img-after').src =\n" +
  "      '/tasks/\{id}/page/' + page + '/after.svg';\n" +
  "  }\n" +
  "  ['before', 'after'].forEach(side => {\n" +
  "    const img = document.getElementById('img-' + side);\n" +
  "    const s = img.clientWidth / PAGE.w;\n" +
  "    const hl = document.getElementById('hl-' + side);\n" +
  "    hl.style.left = (c.rect.x * s) + 'px';\n" +
  "    hl.style.top = ((PAGE.h - c.rect.y - c.rect.height) * s) + 'px';\n" +
  "    hl.style.width = (c.rect.width * s) + 'px';\n" +
  "    hl.style.height = (c.rect.height * s) + 'px';\n" +
  "    hl.style.display = 'block';\n" +
  "  });\n" +
  "}\n" +
  "function reshow() { if (current >= 0) show(current); }\n" +
  "function decide(i, kind) {\n" +
  "  const body = { round, change: i, decision: kind };\n" +
  "  if (kind === 'comment') body.comment = prompt('comment') || '';\n" +
  "  fetch('/tasks/\{id}/decisions', {\n" +
  "    method: 'POST',\n" +
  "    headers: { 'Content-Type': 'application/json' },\n" +
  "    body: JSON.stringify(body)\n" +
  "  }).then(() => location.reload());\n" +
  "}\n" +
  "function publish() {\n" +
  "  fetch('/tasks/\{id}/publish', { method: 'POST' })\n" +
  "    .then(() => location.reload());\n" +
  "}\n" +
  "</script>\n</body></html>\n"
}

///|
/// Send an SVG answer.
async fn send_svg(conn : @http.ServerConnection, svg : String) -> Unit {
  conn
  ..send_response(200, "OK", extra_headers={
    "Content-Type": "image/svg+xml",
    "Content-Length": byte_length(svg).to_string(),
  })
  ..write_string(svg)
  .end_response()
}

///|
/// Send an HTML answer.
async fn send_html(conn : @http.ServerConnection, html : String) -> Unit {
  conn
  ..send_response(200, "OK", extra_headers={
    "Content-Type": "text/html; charset=utf-8",
    "Content-Length": byte_length(html).to_string(),
  })
  ..write_string(html)
  .end_response()
}

///|
/// The length of a text in bytes, as HTTP counts them.
fn byte_length(text : String) -> Int32 {
  @utf8.encode(text).length()
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
    (@http.RequestMethod::Get, []) => send_index(conn, app.val)
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
              app.val.renders.set(id, (result.before, result.after))
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
    (@http.RequestMethod::Get, ["tasks", id, "page", page, side]) => {
      let number = @strconv.parse_int(page) catch { _ => 0 }
      match app.val.renders.get(id) {
        Some((before, after)) => {
          let text = if side == "after.svg" { after } else { before }
          match text.page(number) {
            Some(page_text) => send_svg(conn, @render.page_svg(page_text))
            None => send_error(conn, 404, "there is no such page")
          }
        }
        None => send_error(conn, 404, "publish a round first")
      }
    }
    (@http.RequestMethod::Get, ["tasks", id, "view"]) =>
      match viewer_page(app.val, id) {
        Some(html) => send_html(conn, html)
        None => send_error(conn, 404, "there is no task with that name")
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
