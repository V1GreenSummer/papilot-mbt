///|
test "a request without an Origin header is from the same origin" {
  let request = @http.Request::{
    meth: @http.RequestMethod::Get,
    path: "/health",
    headers: Map([]),
  }
  assert_true(@server.same_origin(request))
}

///|
test "a request from the engine's own address is allowed" {
  let request = @http.Request::{
    meth: @http.RequestMethod::Get,
    path: "/health",
    headers: Map([("Origin", "http://127.0.0.1:8765")]),
  }
  assert_true(@server.same_origin(request))
}

///|
test "a request from another origin is refused" {
  let request = @http.Request::{
    meth: @http.RequestMethod::Get,
    path: "/health",
    headers: Map([("Origin", "https://evil.example")]),
  }
  assert_false(@server.same_origin(request))
}

///|
test "a null origin is allowed" {
  let request = @http.Request::{
    meth: @http.RequestMethod::Get,
    path: "/health",
    headers: Map([("Origin", "null")]),
  }
  assert_true(@server.same_origin(request))
}

///|
async test "the state of a repository survives a write" {
  let dir = @fs.tmpdir(prefix="papilot-store")
  let store = @server.Store::new(dir + "/.git/papilot")
  let task = @task.Task::new(
    "t1", "/repo", "/worktrees/t1", "papilot/t1", "abc123", "main.tex", "pdflatex",
  )
  store.save_task(task)
  let tasks = store.tasks()
  assert_eq(tasks.length(), 1)
  assert_eq(tasks[0].id, "t1")
  assert_eq(tasks[0].main, "main.tex")
}

///|
async test "the last round of a task is kept" {
  let dir = @fs.tmpdir(prefix="papilot-store")
  let store = @server.Store::new(dir + "/.git/papilot")
  let task = @task.Task::new(
    "t1", "/repo", "/worktrees/t1", "papilot/t1", "abc123", "main.tex", "pdflatex",
  )
  let round = @task.Round::new(1, [], [])
  store.save_round(task.id, round)
  let round = @task.Round::new(2, [], [])
  store.save_round(task.id, round)
  let rounds = store.rounds()
  assert_eq(rounds.length(), 1)
  assert_eq(rounds.get("t1").unwrap().number, 2)
}
