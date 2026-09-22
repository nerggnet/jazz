//// Reading changes back.
////
//// Given a set of changes, find the cells a player already knows how to
//// handle: two-fives, turnarounds, tritone substitutes, the backdoor cadence,
//// passing diminished chords. Recognising them is most of what separates
//// reading a tune from playing one, because a two-five is one idea to prepare
//// rather than two unrelated chords to react to.
////
//// Comparison is by sound rather than by spelling. Charts are written by
//// people, and one of them will write `C#7` where the last one wrote `Db7`.

import gleam/list
import gleam/option.{type Option, None, Some}
import jazz/chord.{
  type Chord, AugmentedTriad, DiminishedSeventh, DiminishedTriad, MajorSeventh,
  MajorTriad, MinorSeventh, MinorTriad, NoSeventh, Sus2, Sus4,
}
import jazz/internal/num
import jazz/interval
import jazz/pitch.{type PitchClass}

/// Something recognised, covering `length` chords from `start`.
pub type Finding {
  Finding(start: Int, length: Int, label: String, detail: String)
}

// --- Chord shapes ------------------------------------------------------------

fn is_minor_seventh(one: Chord) -> Bool {
  one.triad == MinorTriad && one.seventh == MinorSeventh
}

fn is_half_diminished(one: Chord) -> Bool {
  one.triad == DiminishedTriad && one.seventh == MinorSeventh
}

fn is_fully_diminished(one: Chord) -> Bool {
  one.triad == DiminishedTriad && one.seventh == DiminishedSeventh
}

/// Anything with dominant function: a seventh chord, however it is dressed,
/// including the sus and augmented versions.
fn is_dominant(one: Chord) -> Bool {
  one.seventh == MinorSeventh
  && case one.triad {
    MajorTriad | AugmentedTriad | Sus4 | Sus2 -> True
    _ -> False
  }
}

fn is_major_tonic(one: Chord) -> Bool {
  one.triad == MajorTriad
  && {
    one.seventh == MajorSeventh || { one.seventh == NoSeventh && one.sixth }
  }
}

fn is_minor_tonic(one: Chord) -> Bool {
  one.triad == MinorTriad && { one.seventh != NoSeventh || one.sixth }
}

/// Whether the second root sits a given number of semitones above the first.
fn apart(from: Chord, to: Chord, semitones: Int) -> Bool {
  num.modulo(
    pitch.class_semitones(to.root) - pitch.class_semitones(from.root),
    12,
  )
  == semitones
}

fn name(root: PitchClass) -> String {
  pitch.class_to_string(root)
}

// --- Detectors ---------------------------------------------------------------

/// Everything recognised in a set of changes, in order.
///
/// A cell contained entirely inside a longer one is left out, so a turnaround
/// is reported as a turnaround rather than also as the two-five inside it.
pub fn analyse(chords: List(Chord)) -> List(Finding) {
  num.counting(list.length(chords))
  |> list.filter_map(fn(at) {
    case detect_at(chords, at) {
      Some(found) -> Ok(found)
      None -> Error(Nil)
    }
  })
  |> strip_contained
}

fn detect_at(chords: List(Chord), at: Int) -> Option(Finding) {
  first_match(chords, at, [
    major_third_cycle,
    turnaround,
    rising_diminished,
    major_two_five_one,
    minor_two_five_one,
    tritone_two_five_one,
    backdoor,
    borrowed_fourth,
    passing_diminished,
    two_five,
    tritone_resolution,
  ])
}

fn first_match(
  chords: List(Chord),
  at: Int,
  detectors: List(fn(List(Chord), Int) -> Option(Finding)),
) -> Option(Finding) {
  case detectors {
    [] -> None
    [detector, ..rest] ->
      case detector(chords, at) {
        Some(found) -> Some(found)
        None -> first_match(chords, at, rest)
      }
  }
}

/// The chords from `at` onwards, as far as any detector needs to see.
fn window(chords: List(Chord), at: Int) -> List(Chord) {
  list.take(list.drop(chords, at), 5)
}

/// The chord before `at`, if there is one.
fn before(chords: List(Chord), at: Int) -> Option(Chord) {
  case at {
    0 -> None
    _ ->
      case list.drop(chords, at - 1) {
        [one, ..] -> Some(one)
        [] -> None
      }
  }
}

fn found(
  at: Int,
  length: Int,
  label: String,
  detail: String,
) -> Option(Finding) {
  Some(Finding(at, length, label, detail))
}

fn major_two_five_one(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [two, five, one, ..] ->
      case
        is_minor_seventh(two)
        && is_dominant(five)
        && is_major_tonic(one)
        && apart(two, five, 5)
        && apart(five, one, 5)
      {
        True ->
          found(
            at,
            3,
            "ii-V-I in " <> name(one.root),
            "The seventh of each chord falls a semitone onto the third of the next. Play that and the changes play themselves.",
          )
        False -> None
      }
    _ -> None
  }
}

fn minor_two_five_one(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [two, five, one, ..] ->
      case
        is_half_diminished(two)
        && is_dominant(five)
        && is_minor_tonic(one)
        && apart(two, five, 5)
        && apart(five, one, 5)
      {
        True ->
          found(
            at,
            3,
            "minor ii-V-i in " <> name(one.root),
            "Altered dominant: melodic minor a semitone above "
              <> name(five.root)
              <> " gives every extension at once.",
          )
        False -> None
      }
    _ -> None
  }
}

fn tritone_two_five_one(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [two, five, one, ..] ->
      case
        { is_minor_seventh(two) || is_half_diminished(two) }
        && is_dominant(five)
        && apart(two, five, 11)
        && apart(five, one, 11)
      {
        True ->
          found(
            at,
            3,
            "ii bII7 I in " <> name(one.root),
            name(five.root)
              <> "7 is standing in for the dominant a tritone away. Same third and seventh, swapped over, so the bass walks down by semitones.",
          )
        False -> None
      }
    _ -> None
  }
}

fn two_five(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [two, five, ..] ->
      case
        { is_minor_seventh(two) || is_half_diminished(two) }
        && is_dominant(five)
        && apart(two, five, 5)
      {
        True ->
          found(
            at,
            2,
            "ii-V into "
              <> name(interval.transpose_class(five.root, interval.degree(4, 0))),
            "A two-five that does not land here. Something else follows, or it moves on to the next one.",
          )
        False -> None
      }
    _ -> None
  }
}

fn tritone_resolution(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [five, one, ..] ->
      case
        is_dominant(five) && apart(five, one, 11) && !is_fully_diminished(one)
      {
        True ->
          found(
            at,
            2,
            "bII7 to " <> name(one.root),
            "The tritone substitute resolving down a semitone. Lydian dominant fits it.",
          )
        False -> None
      }
    _ -> None
  }
}

fn backdoor(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [seven, one, ..] ->
      case is_dominant(seven) && is_major_tonic(one) && apart(seven, one, 2) {
        True ->
          found(
            at,
            2,
            "backdoor cadence into " <> name(one.root),
            "bVII7 borrowed from the parallel minor. Lydian dominant, and the b7 falls to the fifth.",
          )
        False -> None
      }
    _ -> None
  }
}

fn borrowed_fourth(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [four, one, ..] ->
      case
        { is_minor_seventh(four) || is_minor_tonic(four) }
        && is_major_tonic(one)
        && apart(four, one, 7)
      {
        True ->
          found(
            at,
            2,
            "minor iv into " <> name(one.root),
            "The fourth borrowed from the parallel minor. Its flat sixth is the note doing the work, pulling down onto the fifth.",
          )
        False -> None
      }
    _ -> None
  }
}

fn passing_diminished(chords: List(Chord), at: Int) -> Option(Finding) {
  // If the chord before it already climbed a semitone into this one, that
  // reading was reported there and saying it twice helps nobody.
  let explained = case before(chords, at) {
    Some(earlier) ->
      case list.drop(chords, at) {
        [step, ..] -> apart(earlier, step, 1)
        [] -> False
      }
    None -> False
  }
  case window(chords, at) {
    [step, next, ..] ->
      case
        !explained
        && is_fully_diminished(step)
        && { apart(step, next, 1) || apart(step, next, 11) }
      {
        True ->
          found(
            at,
            2,
            "passing " <> name(step.root) <> "dim7",
            "A diminished chord walking by semitone into the next root. The whole-half diminished scale covers it.",
          )
        False -> None
      }
    _ -> None
  }
}

/// A diminished chord a semitone above the chord before it: the bar six
/// chord of a blues, and the way most standards climb between two roots.
fn rising_diminished(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [before, step, ..] ->
      case is_fully_diminished(step) && apart(before, step, 1) {
        True ->
          found(
            at,
            2,
            "rising " <> name(step.root) <> "dim7",
            "A diminished chord climbing a semitone out of "
              <> name(before.root)
              <> ". It shares three notes with the dominant it is standing in for.",
          )
        False -> None
      }
    _ -> None
  }
}

fn turnaround(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [one, six, two, five, ..] ->
      case
        // A blues turnaround starts on a dominant, not a major seventh.
        { is_major_tonic(one) || is_dominant(one) }
        && { is_dominant(six) || is_minor_seventh(six) }
        && apart(one, six, 9)
        && is_minor_seventh(two)
        && apart(one, two, 2)
        && is_dominant(five)
        && apart(one, five, 7)
      {
        True ->
          found(
            at,
            4,
            "I VI ii V turnaround in " <> name(one.root),
            "The last bars of most standards. The VI is usually played as an altered dominant however it is written.",
          )
        False -> None
      }
    _ -> None
  }
}

fn major_third_cycle(chords: List(Chord), at: Int) -> Option(Finding) {
  case window(chords, at) {
    [first, second, third, fourth, fifth] ->
      case
        is_major_tonic(first)
        && is_dominant(second)
        && is_major_tonic(third)
        && is_dominant(fourth)
        && is_major_tonic(fifth)
        && apart(first, third, 8)
        && apart(third, fifth, 8)
        && apart(second, third, 5)
        && apart(fourth, fifth, 5)
      {
        True ->
          found(
            at,
            5,
            "major third cycle: "
              <> name(first.root)
              <> " "
              <> name(third.root)
              <> " "
              <> name(fifth.root),
            "Coltrane changes. Three keys a major third apart, each arrived at by its own dominant. Learn the arpeggios before the scales.",
          )
        False -> None
      }
    _ -> None
  }
}

/// Drop anything sitting entirely inside something longer.
fn strip_contained(all: List(Finding)) -> List(Finding) {
  list.filter(all, fn(one) {
    !list.any(all, fn(other) {
      other.length > one.length
      && other.start <= one.start
      && other.start + other.length >= one.start + one.length
    })
  })
}

// --- Guide tones -------------------------------------------------------------

/// The third and seventh of a chord, the two notes that say which chord it is.
pub type GuideStep {
  GuideStep(
    chord: Chord,
    third: Option(PitchClass),
    seventh: Option(PitchClass),
  )
}

/// The guide tone line through a set of changes.
///
/// Played on its own it is the whole harmony in two voices, and it is where
/// the smooth voice leading between chords becomes obvious: the seventh of
/// one chord is usually the third of the next, a semitone lower.
pub fn guide_tone_line(chords: List(Chord)) -> List(GuideStep) {
  list.map(chords, fn(one) {
    GuideStep(
      chord: one,
      third: tone_at(one, [3, 4, 2]),
      seventh: tone_at(one, [7, 6]),
    )
  })
}

fn tone_at(one: Chord, numbers: List(Int)) -> Option(PitchClass) {
  case numbers {
    [] -> None
    [number, ..rest] ->
      case
        list.find(chord.intervals(one), fn(step) {
          interval.number(step) == number
        })
      {
        Ok(step) -> Some(interval.transpose_class(one.root, step))
        Error(_) -> tone_at(one, rest)
      }
  }
}
