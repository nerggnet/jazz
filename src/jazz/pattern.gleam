//// Ways of practising a scale that are not just the scale.
////
//// Running a scale up and back down teaches the notes and very little else.
//// What a player actually needs under their fingers is the scale in thirds,
//// in fourths, as triads, as sevenths -- the shapes that turn up in the music
//// -- and each of them starting from every degree. That is what these are.
////
//// A pattern is a handful of offsets in scale degrees, applied from each
//// degree in turn going up and then again coming down. Thirds are `0 2`:
//// play the degree you are on and the one two above it, then move up a
//// degree and do it again. Everything else here is the same idea with
//// different numbers.

import gleam/int
import gleam/list
import jazz/internal/num
import jazz/interval
import jazz/pitch.{type Pitch, Pitch}
import jazz/scale.{type Scale}

pub type Pattern {
  /// The scale itself, up and back down.
  Straight
  Thirds
  Fourths
  Triads
  Sevenths
  /// The one every horn player knows as 1-2-3-5.
  Digital
}

pub fn all() -> List(Pattern) {
  [Straight, Thirds, Fourths, Triads, Sevenths, Digital]
}

pub fn id(one: Pattern) -> String {
  case one {
    Straight -> "straight"
    Thirds -> "thirds"
    Fourths -> "fourths"
    Triads -> "triads"
    Sevenths -> "sevenths"
    Digital -> "digital"
  }
}

pub fn name(one: Pattern) -> String {
  case one {
    Straight -> "Up and down"
    Thirds -> "In thirds"
    Fourths -> "In fourths"
    Triads -> "Triads"
    Sevenths -> "Sevenths"
    Digital -> "1-2-3-5"
  }
}

/// What the exercise is for, in a line.
pub fn usage(one: Pattern) -> String {
  case one {
    Straight -> "The notes themselves, in order."
    Thirds -> "The interval most lines are built out of."
    Fourths -> "Wider, and awkward on purpose."
    Triads -> "Every triad the scale contains, in turn."
    Sevenths -> "The same again with the seventh on top."
    Digital -> "A four note cell to start a phrase with."
  }
}

pub fn from_string(text: String) -> Result(Pattern, String) {
  case list.find(all(), fn(one) { id(one) == text }) {
    Ok(found) -> Ok(found)
    Error(_) -> Error("unknown pattern: " <> text)
  }
}

/// The degrees each group of the pattern reaches, counted from the one it
/// starts on.
fn offsets(one: Pattern) -> List(Int) {
  case one {
    Straight -> [0]
    Thirds -> [0, 2]
    Fourths -> [0, 3]
    Triads -> [0, 2, 4]
    Sevenths -> [0, 2, 4, 6]
    Digital -> [0, 1, 2, 4]
  }
}

/// The exercise, as notes: up from the root an octave and back down again,
/// the shape applied from every degree on the way.
pub fn notes(one: Pattern, subject: Scale) -> List(Pitch) {
  let size = scale.size(subject.kind)
  let shape = offsets(one)
  let up =
    num.counting(size + 1)
    |> list.flat_map(fn(start) {
      list.map(shape, fn(step) { at(subject, start + step) })
    })
  let down =
    num.counting(size + 1)
    |> list.reverse
    |> list.flat_map(fn(start) {
      list.map(shape, fn(step) { at(subject, start - step) })
    })
  list.append(up, turn(up, down))
}

/// Coming down from the note you just went up to would sound it twice, which
/// is a stumble rather than a turn.
fn turn(up: List(Pitch), down: List(Pitch)) -> List(Pitch) {
  case list.last(up), down {
    Ok(last), [first, ..rest] if last == first -> rest
    _, _ -> down
  }
}

/// The pitch a given number of scale degrees above the root, counting on past
/// the octave and below the root for the degrees a descending shape reaches
/// under it.
fn at(subject: Scale, index: Int) -> Pitch {
  let size = scale.size(subject.kind)
  let steps = scale.intervals(subject.kind)
  let octave = num.floor_div(index, size)
  let degree = index - octave * size
  let root = Pitch(subject.root, 4)
  case list.drop(steps, degree) {
    [step, ..] ->
      interval.transpose(
        interval.transpose(root, step),
        interval.octaves(octave),
      )
    [] -> root
  }
}

/// How many bars of eighths the exercise takes, so several of them can be
/// laid out one after another without running into each other.
pub fn bars(one: Pattern, subject: Scale) -> Int {
  let length = list.length(notes(one, subject))
  case int.modulo(length, 8) {
    Ok(0) -> length / 8
    _ -> length / 8 + 1
  }
}
