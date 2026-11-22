///|
/// How a document is compiled.
pub struct BuildSettings {
  /// The root document, relative to the source folder.
  main : String
  /// The program that builds the document.
  compiler : String
  /// The engine to run: `pdflatex`, `xelatex` or `lualatex`.
  engine : String
  /// The folder that is copied for every build.
  source_dir : String
  /// The folder the document is built in.
  work_dir : String
}

///|
pub fn BuildSettings::new(
  main : String,
  engine : String,
  source_dir : String,
  work_dir : String,
  compiler~ : String = "latexmk",
) -> BuildSettings {
  { main, compiler, engine, source_dir, work_dir, }
}

///|
/// The result of a build.
pub struct BuildResult {
  /// The exit code of the compiler.
  code : Int32
  /// Where the PDF was expected.
  expected_pdf : String
  /// The path of the PDF that was produced.
  pdf : String?
  /// The path of the SyncTeX file that was produced.
  synctex : String?
  /// The log of the compiler.
  log : String
}

///|
pub fn BuildResult::ok(self : BuildResult) -> Bool {
  self.code == 0
}

///|
/// The moment the build happened, as seconds since the epoch.
///
/// Every build of the same day prints the same date, so that a document does
/// not change just because it was compiled again. The moment is taken at noon
/// UTC of the current day, which keeps the value inside the day in every time
/// zone.
pub fn source_date_epoch() -> Int64 {
  let now = @env.now()
  let seconds = (now.to_double() / 1000.0).to_int64()
  // Round down to the day, then move to noon.
  let day = seconds / 86400L
  day * 86400L + 12L * 3600L
}

///|
/// The key a build is cached under.
///
/// The key holds everything that can change the output: the settings, the
/// state of the sources and the day of the build.
pub fn cache_key(settings : BuildSettings, content_key : String) -> String {
  let day = source_date_epoch() / 86400L
  let engine = settings.engine
  let main = settings.main
  main + "|" + engine + "|" + content_key + "|" + day.to_string()
}

///|
/// The arguments latexmk is run with.
fn latexmk_args(settings : BuildSettings) -> Array[String] {
  let args = [
    "-interaction=nonstopmode", "-file-line-error", "-halt-on-error", "-synctex=1",
  ]
  match settings.engine {
    "xelatex" => args.push("-xelatex")
    "lualatex" => args.push("-lualatex")
    _ => args.push("-pdf")
  }
  args.push(settings.main)
  args
}

///|
/// Compile a document.
///
/// The build is reproducible: `SOURCE_DATE_EPOCH` is set to the moment of the
/// day, unless the author set it themselves, and the run stops at the first
/// error so that a broken document fails loudly.
pub async fn compile(settings : BuildSettings) -> BuildResult {
  let env = Map([])
  env.set("SOURCE_DATE_EPOCH", source_date_epoch().to_string())
  env.set("FORCE_SOURCE_DATE", "1")
  let (code, stdout, stderr) = @process.collect_output(
    settings.compiler,
    latexmk_args(settings),
    extra_env=env,
    cwd=settings.work_dir,
  )
  let log = @utf8.decode_lossy(stdout.binary()) +
    @utf8.decode_lossy(stderr.binary())
  let stem = strip_extension(settings.main)
  let pdf_path = settings.work_dir + "/" + stem + ".pdf"
  let synctex_path = settings.work_dir + "/" + stem + ".synctex.gz"
  BuildResult::{
    code,
    expected_pdf: pdf_path,
    pdf: if file_exists(pdf_path) {
      Some(pdf_path)
    } else {
      None
    },
    synctex: if file_exists(synctex_path) {
      Some(synctex_path)
    } else {
      None
    },
    log,
  }
}

///|
/// The name of a file without its extension.
fn strip_extension(name : String) -> String {
  let mut last = name.length()
  while last > 0 {
    let c = name.get_char(last - 1).unwrap_or(' ')
    if c == '.' {
      // The dot is at `last - 1`, so the name ends before it.
      return name.clamped_view(start=0, end=last - 1).to_owned()
    }
    last = last - 1
  }
  name
}

///|
/// Whether a file exists.
async fn file_exists(path : String) -> Bool {
  @fs.exists(path) catch {
    _ => false
  }
}

///|
/// The engine to use for a document.
///
/// A document that loads `fontspec` needs XeLaTeX or LuaLaTeX; everything else
/// is fine with pdfLaTeX.
pub fn engine_for(source : String) -> String {
  if source.contains("fontspec") || source.contains("unicode-math") {
    "xelatex"
  } else {
    "pdflatex"
  }
}
