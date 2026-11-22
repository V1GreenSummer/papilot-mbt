///|
/// Copy a folder and everything in it.
///
/// The build of the accepted text runs in a copy of the sources, so that the
/// working tree of the author keeps no trace of the compilation.
pub async fn copy_tree(source : String, target : String) -> Unit {
  @fs.mkdir(target, recursive=true) catch {
    _ => ()
  }
  let dir = @fs.opendir(source) catch { _ => return }
  defer dir.close()
  while dir.next() is Some(entry) {
    let from = source + "/" + entry.name
    let to = target + "/" + entry.name
    if entry.is_dir {
      copy_tree(from, to)
    } else {
      let content = @fs.read_file(from) catch { _ => continue }
      @fs.write_file(to, content) catch {
        _ => ()
      }
    }
  }
}

///|
/// Remove a folder and everything in it.
pub async fn remove_tree(path : String) -> Unit {
  let dir = @fs.opendir(path) catch {
    _ => {
      @fs.remove(path) catch {
        _ => ()
      }
      return
    }
  }
  let names = []
  while dir.next() is Some(entry) {
    names.push(entry.name)
  }
  dir.close()
  for name in names {
    let child = path + "/" + name
    let kind = @fs.kind(child) catch { _ => continue }
    if kind == @fs.FileKind::Directory {
      remove_tree(child)
    } else {
      @fs.remove(child) catch {
        _ => ()
      }
    }
  }
  @fs.remove(path) catch {
    _ => ()
  }
}
