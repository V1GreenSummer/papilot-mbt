/// The packages of the review engine, gathered in one place.
///
/// The root package names every package of the module, so that a reader can
/// see the whole engine at a glance and so that the module builds as a whole.

///|
fn _keep_latex() -> Int32 {
  @latex.parse_text("\\section{Intro}").sections.length()
}

///|
fn _keep_diff() -> Int32 {
  @diff.diff_text("a b", "a c").length()
}

///|
fn _keep_synctex() -> Int32 {
  @synctex.parse("SyncTeX Version:1\nContent:\n").page_count()
}

///|
fn _keep_pdftext() -> Int32 {
  @pdftext.PdfText::new([]).page_count()
}

///|
fn _keep_git() -> String {
  @git.branch_of("task")
}

///|
fn _keep_build() -> String {
  @build.cache_key(
    @build.BuildSettings::new("main.tex", "pdflatex", ".", "."),
    "key",
  )
}

///|
fn _keep_compare() -> Int32 {
  @compare.compare(@pdftext.PdfText::new([]), @pdftext.PdfText::new([])).length()
}

///|
fn _keep_journal() -> String {
  @journal.Entry::TaskCreated("task", "/tmp").to_string()
}

///|
fn _keep_task() -> String {
  @task.branch_of("task")
}

///|
fn _keep_server() -> String {
  @server.App::new("/repo", "/worktrees", @journal.Journal::new("/journal")).repo
}

///|
fn _keep_jsonx() -> String {
  @jsonx.text(
    @jsonx.field(@json.Json::string("x"), "x").unwrap_or(@json.Json::null()),
    "x",
  )
}

///|
fn _keep_render() -> String {
  let page = @pdftext.PageText::new(1, 612.0, 792.0, [])
  @render.page_svg(page)
}
