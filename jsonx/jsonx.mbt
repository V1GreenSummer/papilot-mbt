///|
/// The value of a field of a JSON object.
///
/// The JSON package offers the same thing, but every call has to be written
/// out again; these helpers keep the reading of a record short.
pub fn field(json : Json, name : String) -> Json? {
  match json {
    Json::Object(obj) => obj.get(name)
    _ => None
  }
}

///|
/// The text of a field of a JSON object.
pub fn text(json : Json, name : String) -> String {
  match field(json, name) {
    Some(Json::String(value)) => value
    _ => ""
  }
}

///|
/// The number of a field of a JSON object.
pub fn number(json : Json, name : String) -> Int32 {
  match field(json, name) {
    Some(Json::Number(value, ..)) => value.to_int()
    _ => 0
  }
}

///|
/// The real number of a field of a JSON object.
pub fn real(json : Json, name : String) -> Double {
  match field(json, name) {
    Some(Json::Number(value, ..)) => value
    _ => 0.0
  }
}

///|
/// The elements of a field of a JSON object.
pub fn items(json : Json, name : String) -> Array[Json] {
  match field(json, name) {
    Some(Json::Array(values)) => values
    _ => []
  }
}
