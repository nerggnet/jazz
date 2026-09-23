//// Writing the backing out rather than leaving it to be imagined.
////
//// Shell voicings: the root underneath, and above it the notes that say
//// which chord it is. Those are the third and the seventh, which the
//// analyser already knows how to find, and moving them as little as possible
//// from one chord to the next is what a pianist does without thinking about
//// it. The alternative, stacking every chord from its root, leaps about and
//// sounds like an exercise.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import jazz/chord.{type Chord}
import jazz/internal/num
import jazz/pitch.{type Pitch, type PitchClass, Pitch}
import jazz/progression.{type Progression}

/// A chord as somebody would actually put their hands on it.
pub type Voicing {
  Voicing(chord: Chord, duration: Int, notes: List(Pitch))
}

/// Where the root sits, low enough to be a bass note.
const bass_low = 36

const bass_high = 48

/// And where the guide tones sit: clear of the root, and no higher than
/// middle C, so a bass staff does not fill up with ledger lines.
const upper_low = 48

const upper_high = 60

/// A comp under a set of changes, one voicing for each chord.
pub fn under(subject: Progression) -> List(Voicing) {
  subject.bars
  |> list.flat_map(fn(bar) {
    list.zip(bar.chords, progression.shares(list.length(bar.chords), 8))
  })
  |> walk(None, [])
}

fn walk(
  segments: List(#(Chord, Int)),
  previous: Option(Voicing),
  acc: List(Voicing),
) -> List(Voicing) {
  case segments {
    [] -> list.reverse(acc)
    [#(one, length), ..rest] -> {
      let voiced = voice(one, length, previous)
      walk(rest, Some(voiced), [voiced, ..acc])
    }
  }
}

fn voice(one: Chord, length: Int, previous: Option(Voicing)) -> Voicing {
  let root = place(one.root, bass_aim(previous), bass_low, bass_high)
  let guides = chord.guide_tones(one)
  let upper = assign(guides, upper_aims(previous, list.length(guides)))
  Voicing(one, length, [root, ..upper])
}

/// Which voice takes which note.
///
/// Pairing the third to the last third and the seventh to the last seventh
/// looks tidy and sounds wrong: from Dm7 to G7 the F is common to both, and a
/// player holds it rather than moving it to the B while another voice crosses
/// underneath. Trying it both ways and keeping whichever moves less finds the
/// held note by itself.
fn assign(guides: List(PitchClass), aims: List(Int)) -> List(Pitch) {
  case guides, aims {
    [first, second], [here, there] -> {
      let straight = [
        place(first, here, upper_low, upper_high),
        place(second, there, upper_low, upper_high),
      ]
      let crossed = [
        place(second, here, upper_low, upper_high),
        place(first, there, upper_low, upper_high),
      ]
      case effort(crossed, aims) < effort(straight, aims) {
        True -> crossed
        False -> straight
      }
    }
    _, _ ->
      list.zip(guides, aims)
      |> list.map(fn(entry) { place(entry.0, entry.1, upper_low, upper_high) })
  }
}

fn effort(notes: List(Pitch), aims: List(Int)) -> Int {
  list.zip(notes, aims)
  |> list.fold(0, fn(total, entry) {
    total + int.absolute_value(pitch.to_midi(entry.0) - entry.1)
  })
}

/// Aim each note at wherever the last chord left that voice, so the hand
/// moves as little as it can.
fn bass_aim(previous: Option(Voicing)) -> Int {
  case previous {
    Some(Voicing(notes: [root, ..], ..)) -> pitch.to_midi(root)
    _ -> { bass_low + bass_high } / 2
  }
}

fn upper_aims(previous: Option(Voicing), count: Int) -> List(Int) {
  let held = case previous {
    Some(one) -> list.drop(one.notes, 1) |> list.map(pitch.to_midi)
    None -> []
  }
  num.counting(count)
  |> list.map(fn(at) {
    case list.drop(held, at) {
      [was, ..] -> was
      [] -> { upper_low + upper_high } / 2
    }
  })
}

/// The octave of a note closest to where the hand already was, within the
/// stretch it is allowed.
fn place(class: PitchClass, aim: Int, low: Int, high: Int) -> Pitch {
  case reachable(class, low, high) {
    [] -> Pitch(class, 3)
    [first, ..rest] ->
      list.fold(rest, first, fn(best, one) {
        case
          int.absolute_value(pitch.to_midi(one) - aim)
          < int.absolute_value(pitch.to_midi(best) - aim)
        {
          True -> one
          False -> best
        }
      })
  }
}

fn reachable(class: PitchClass, low: Int, high: Int) -> List(Pitch) {
  num.counting(9)
  |> list.map(fn(octave) { Pitch(class, octave) })
  |> list.filter(fn(one) {
    pitch.to_midi(one) >= low && pitch.to_midi(one) <= high
  })
}
