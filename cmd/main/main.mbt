///|
async fn main {
  @cli.run_cli() catch {
    err => println("papilot stopped: \{err}")
  }
}
