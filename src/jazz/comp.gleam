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
import jazz/interval
import jazz/pitch.{type Pitch, type PitchClass, Pitch}
import jazz/progression.{type Progression}

/// A chord as somebody would actually put their hands on it.
pub type Voicing {
  Voicing(chord: Chord, duration: Int, notes: List(Pitch))
}

/// One thing the left hand does: put the chord down, or leave a hole.
pub type Stroke {
  Strike(notes: List(Pitch), duration: Int)
  Wait(duration: Int)
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

// --- The rhythm section ------------------------------------------------------
//
// Two players rather than one. A pianist with a bassist beside them drops the
// root and keeps the guide tones, because doubling the bass an octave up is
// what makes a recording sound muddy; and the bass walks, because a held root
// under changes is an exercise and four notes to the bar is a band.

/// The pianist's hand: guide tones, put down on a rhythm rather than held for
/// the whole bar.
pub fn comping(subject: Progression) -> List(Stroke) {
  under(subject)
  |> list.index_map(fn(one, at) {
    // The root has gone to the bass, so only the tones that name the chord
    // are left here -- and they move up an octave to get out of the way of
    // it, which is what a pianist does the moment a bassist walks in.
    let upper = list.drop(one.notes, 1) |> list.map(lift)
    figure(one.duration, at)
    |> list.map(fn(step) {
      case step {
        #(True, length) -> Strike(upper, length)
        #(False, length) -> Wait(length)
      }
    })
  })
  |> list.flatten
}

/// When in the bar the chord is actually struck, in eighths.
///
/// Three figures for a whole bar and two for a half, taken in turn. A comp
/// that lands on the same beat every bar stops being a rhythm and starts
/// being a metronome, and rotating through a few is enough to keep it
/// breathing without anybody having to decide.
fn figure(length: Int, at: Int) -> List(#(Bool, Int)) {
  case length {
    // Charleston, its answer a beat later, and the two and the four.
    8 ->
      case at % 3 {
        0 -> [#(True, 3), #(True, 3), #(False, 2)]
        1 -> [#(False, 2), #(True, 3), #(True, 3)]
        _ -> [#(False, 2), #(True, 2), #(False, 2), #(True, 2)]
      }
    4 ->
      case at % 2 {
        0 -> [#(True, 3), #(False, 1)]
        _ -> [#(False, 1), #(True, 3)]
      }
    other -> [#(True, other)]
  }
}

/// Where a walking bass goes: one note to the beat, all the way through.
pub fn walking(subject: Progression) -> List(Pitch) {
  subject.bars
  |> list.flat_map(fn(bar) {
    list.zip(bar.chords, progression.shares(list.length(bar.chords), 4))
  })
  |> stride(None, [])
}

fn lift(one: Pitch) -> Pitch {
  Pitch(one.class, one.octave + 1)
}

/// Low enough to be a bass and high enough to stay on its staff: C below the
/// stave up to the note on its top line.
const walk_low = 36

const walk_high = 57

fn stride(
  segments: List(#(Chord, Int)),
  previous: Option(Pitch),
  acc: List(Pitch),
) -> List(Pitch) {
  case segments {
    [] -> list.reverse(acc)
    [#(one, beats), ..rest] -> {
      // Where the line is headed is what decides the last note of the bar,
      // so the next chord has to be known before this one can be walked.
      let next = case rest {
        [#(after, _), ..] -> after.root
        [] -> one.root
      }
      let notes = bar_of(one, beats, next, previous)
      stride(
        rest,
        option.from_result(list.last(notes)),
        list.fold(notes, acc, fn(kept, one) { [one, ..kept] }),
      )
    }
  }
}

/// The root on the change, chord tones through the middle, and a note a
/// semitone away from wherever the band is going next.
fn bar_of(
  one: Chord,
  beats: Int,
  next: PitchClass,
  previous: Option(Pitch),
) -> List(Pitch) {
  let root = place(one.root, bass_aim_of(previous), walk_low, walk_high)
  case beats {
    beats if beats <= 1 -> [root]
    _ -> {
      let middle = through(one, beats - 2, root, [])
      let here = case middle {
        [] -> root
        _ -> last_or(middle, root)
      }
      [root, ..list.append(middle, [lead_in(next, here)])]
    }
  }
}

/// Chord tones between the root and the approach, each near the last.
fn through(
  one: Chord,
  count: Int,
  from: Pitch,
  acc: List(Pitch),
) -> List(Pitch) {
  case count <= 0 {
    True -> list.reverse(acc)
    False -> {
      let tones = list.drop(chord.notes(one), 1)
      let at = list.length(acc) % int.max(list.length(tones), 1)
      case list.drop(tones, at) {
        [] -> list.reverse(acc)
        [tone, ..] -> {
          let put = place(tone, pitch.to_midi(from), walk_low, walk_high)
          through(one, count - 1, put, [put, ..acc])
        }
      }
    }
  }
}

/// A semitone off the note the next bar starts on, taken from whichever side
/// the line is already coming from, so it carries on rather than doubling
/// back on itself.
fn lead_in(next: PitchClass, here: Pitch) -> Pitch {
  let target = place(next, pitch.to_midi(here), walk_low, walk_high)
  let semitone = interval.degree(2, -1)
  let class = case pitch.to_midi(here) > pitch.to_midi(target) {
    True -> interval.transpose_class(next, semitone)
    False -> interval.transpose_class(next, interval.negate(semitone))
  }
  place(class, pitch.to_midi(here), walk_low, walk_high)
}

fn last_or(notes: List(Pitch), fallback: Pitch) -> Pitch {
  case list.last(notes) {
    Ok(one) -> one
    Error(_) -> fallback
  }
}

fn bass_aim_of(previous: Option(Pitch)) -> Int {
  case previous {
    Some(one) -> pitch.to_midi(one)
    None -> { walk_low + walk_high } / 2
  }
}
