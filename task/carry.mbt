///|
/// Whether a change of a round continues a change of the round before.
///
/// A change continues another one when it stands in the same place of the
/// page and replaces the same text. The agent may have revised the change, so
/// the new text is not compared.
pub fn continues(previous : @compare.Change, change : @compare.Change) -> Bool {
  if previous.page != change.page {
    return false
  }
  if previous.old_text != change.old_text {
    return false
  }
  // A change that adds text has nothing to continue: the text before it is
  // the same everywhere.
  previous.old_text != ""
}

///|
/// The decisions of a round, carried over from the round before.
///
/// A change that the author has not decided yet stays in the list, so that the
/// author does not have to look at it again. A change that was decided keeps
/// its decision, and a revised change shows the comment it answers.
pub async fn carry_decisions(
  journal : @journal.Journal,
  task : String,
  round : Round,
  previous : Round?,
) -> Round {
  let changes = []
  for change in round.changes {
    let decision = match previous {
      Some(before) => {
        let mut found : Int32? = None
        let mut index = 0
        while index < before.changes.length() {
          if continues(before.changes[index].change, change.change) {
            found = Some(index)
            break
          }
          index = index + 1
        }
        match found {
          Some(i) =>
            journal.decision_of(task, before.number, i) catch {
              _ => None
            }
          None => None
        }
      }
      None => None
    }
    changes.push(TaskChange::{
      change: change.change,
      edit: change.edit,
      source: change.source,
      decision,
    })
  }
  Round::new(round.number, changes, round.edits)
}
