//// The chords a scale contains.
////
//// `jazz/chord` answers the question a chart asks: here is a chord, what do I
//// play over it. This module asks it the other way round, which is the
//// question a player asks with a scale already under their fingers and
//// nothing to use it on. The answer is not a table either: a chord fits a
//// scale when every note of it is in the scale, so the list falls out of
//// trying the shapes of a flavour on every note the scale has.
////
//// Matching is by sound rather than by spelling, because a dim7 built on C is
//// spelled with a B double flat and the scale it came out of will have called
//// that note A.

import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import jazz/chord.{
  type Chord, type Seventh, type Triad, AugmentedTriad, DiminishedSeventh,
  DiminishedTriad, MajorSeventh, MajorTriad, MinorSeventh, MinorTriad, NoSeventh,
  Sus2, Sus4,
}
import jazz/pitch.{type PitchClass}
import jazz/progression.{type Progression}
import jazz/scale.{type Scale}

/// How thickly the scale is harmonised. Each one is a different sound rather
/// than a different amount of theory: a chart written in sixths is a different
/// record from one written in thirteenths.
pub type Flavour {
  Triads
  Sevenths
  Sixths
  Extended
  Suspended
}

// --- The chords --------------------------------------------------------------

/// Every chord of that flavour the scale will carry, rooted on the scale's own
/// notes and in the order the scale runs.
pub fn chords(subject: Scale, flavour: Flavour) -> List(Chord) {
  let notes = scale.notes(subject)
  let tones = list.map(notes, pitch.class_semitones)
  list.flat_map(notes, fn(root) {
    shapes(flavour)
    |> list.index_map(fn(shape, at) { #(at, shape(root)) })
    |> list.filter(fn(entry) { fits(entry.1, tones) })
  })
  |> list.index_map(fn(entry, at) { #(at, entry.0, entry.1) })
  |> once_each
  |> list.map(fn(entry) { entry.2 })
}

/// Whether the scale has every note of the chord in it.
fn fits(one: Chord, tones: List(Int)) -> Bool {
  chord.notes(one)
  |> list.all(fn(note) { list.contains(tones, pitch.class_semitones(note)) })
}

/// A symmetric chord turns up on several notes of the scale and is the same
/// chord every time -- a dim7 four times over, an augmented triad twice -- so
/// it is listed once, spelled the way that needs the fewest accidentals.
///
/// Only against its own shape: `Cmaj13` and `Am11` are the same six notes and
/// are not remotely the same chord.
fn once_each(candidates: List(#(Int, Int, Chord))) -> List(#(Int, Int, Chord)) {
  list.filter(candidates, fn(one) {
    let #(at, shape, chord) = one
    !list.any(candidates, fn(other) {
      let #(other_at, other_shape, other_chord) = other
      other_shape == shape
      && sound(other_chord) == sound(chord)
      && case accidentals(other_chord) - accidentals(chord) {
        0 -> other_at < at
        fewer -> fewer < 0
      }
    })
  })
}

/// The chord as a set of pitches, with the spelling thrown away.
fn sound(one: Chord) -> List(Int) {
  chord.notes(one)
  |> list.map(pitch.class_semitones)
  |> list.sort(int.compare)
}

/// How much ink the chord takes to write down.
fn accidentals(one: Chord) -> Int {
  chord.notes(one)
  |> list.fold(0, fn(total, note) {
    total + int.absolute_value(note.alteration)
  })
}

/// The same chords as changes, so they can be printed, charted or played like
/// any other set of changes. One chord to a bar, in scale order.
pub fn as_progression(subject: Scale, flavour: Flavour) -> Progression {
  progression.Progression(
    id: "harmony",
    name: name(flavour) <> " from " <> scale.name(subject.kind),
    note: usage(flavour),
    key: subject.root,
    // A scale that carries none of them still has to draw a bar, or there is
    // no score to put on the screen at all.
    bars: case chords(subject, flavour) {
      [] -> [progression.Bar([])]
      found -> list.map(found, fn(one) { progression.Bar([one]) })
    },
  )
}

/// The scale a chord is played on, as a scale.
///
/// `jazz/chord` names two or three that fit and puts them in order; this is
/// the first of them, which it put first for a reason. Harmonising it is how
/// a chord answers the question a scale answers: not only what to play over
/// this chord, but what else to play *instead* of it while the rhythm section
/// holds it down.
pub fn scale_of(subject: Chord) -> Scale {
  scale.Scale(subject.root, case chord.chord_scales(subject) {
    [first, ..] -> first
    // Nothing reaches this: every chord has a scale. A dominant is the one
    // to guess with if one ever does.
    [] -> scale.Mixolydian
  })
}

// --- The shapes each flavour is made of --------------------------------------

/// The chord shapes to try, most idiomatic first. Anything the scale cannot
/// spell is dropped, so the list is a superset of what comes out.
fn shapes(flavour: Flavour) -> List(fn(PitchClass) -> Chord) {
  case flavour {
    // No suspensions here: a fourth in place of a third is a sound of its
    // own rather than a thinner triad, and it has a flavour to itself.
    Triads -> [
      built(MajorTriad, NoSeventh, False, []),
      built(MinorTriad, NoSeventh, False, []),
      built(DiminishedTriad, NoSeventh, False, []),
      built(AugmentedTriad, NoSeventh, False, []),
    ]

    Sevenths -> [
      built(MajorTriad, MajorSeventh, False, []),
      built(MinorTriad, MinorSeventh, False, []),
      built(MajorTriad, MinorSeventh, False, []),
      built(DiminishedTriad, MinorSeventh, False, []),
      built(DiminishedTriad, DiminishedSeventh, False, []),
      built(MinorTriad, MajorSeventh, False, []),
      built(AugmentedTriad, MajorSeventh, False, []),
      built(AugmentedTriad, MinorSeventh, False, []),
    ]

    Sixths -> [
      built(MajorTriad, NoSeventh, True, []),
      built(MinorTriad, NoSeventh, True, []),
      built(MajorTriad, NoSeventh, True, [#(9, 0)]),
      built(MinorTriad, NoSeventh, True, [#(9, 0)]),
    ]

    // One entry per colour rather than one per height, and the ninth is
    // always there under whatever sits above it, because that is how the
    // symbols are read.
    Extended -> [
      built(MajorTriad, MajorSeventh, False, [#(9, 0)]),
      built(MajorTriad, MajorSeventh, False, [#(9, 0), #(13, 0)]),
      built(MajorTriad, MajorSeventh, False, [#(9, 0), #(11, 1)]),
      built(MinorTriad, MinorSeventh, False, [#(9, 0)]),
      built(MinorTriad, MinorSeventh, False, [#(9, 0), #(11, 0)]),
      built(MinorTriad, MinorSeventh, False, [#(9, 0), #(13, 0)]),
      built(MinorTriad, MajorSeventh, False, [#(9, 0)]),
      built(MajorTriad, MinorSeventh, False, [#(9, 0)]),
      built(MajorTriad, MinorSeventh, False, [#(9, 0), #(13, 0)]),
      built(MajorTriad, MinorSeventh, False, [#(9, 0), #(13, 0), #(11, 1)]),
      built(MajorTriad, MinorSeventh, False, [#(9, -1)]),
      built(MajorTriad, MinorSeventh, False, [#(9, 1)]),
      built(MajorTriad, MinorSeventh, False, [#(11, 1)]),
      built(MajorTriad, MinorSeventh, False, [#(13, -1)]),
      built(MajorTriad, MinorSeventh, False, [#(9, -1), #(13, 0)]),
      chord.altered,
      built(AugmentedTriad, MinorSeventh, False, [#(9, 0)]),
      built(DiminishedTriad, MinorSeventh, False, [#(9, 0)]),
      built(DiminishedTriad, MinorSeventh, False, [#(9, 0), #(11, 0)]),
    ]

    Suspended -> [
      built(Sus4, NoSeventh, False, []),
      built(Sus2, NoSeventh, False, []),
      built(Sus4, MinorSeventh, False, []),
      built(Sus4, MinorSeventh, False, [#(9, 0)]),
      built(Sus4, MinorSeventh, False, [#(9, 0), #(13, 0)]),
      built(Sus4, MinorSeventh, False, [#(9, -1)]),
      built(Sus4, MajorSeventh, False, []),
    ]
  }
}

fn built(
  triad: Triad,
  seventh: Seventh,
  sixth: Bool,
  tensions: List(#(Int, Int)),
) -> fn(PitchClass) -> Chord {
  fn(root) {
    chord.Chord(
      root: root,
      triad: triad,
      seventh: seventh,
      sixth: sixth,
      tensions: list.map(tensions, fn(one) { chord.Tension(one.0, one.1) }),
      omit: [],
      bass: None,
    )
  }
}

// --- Naming ------------------------------------------------------------------

pub fn all_flavours() -> List(Flavour) {
  [Triads, Sevenths, Sixths, Extended, Suspended]
}

pub fn name(flavour: Flavour) -> String {
  case flavour {
    Triads -> "Triads"
    Sevenths -> "Sevenths"
    Sixths -> "Sixths"
    Extended -> "Extended chords"
    Suspended -> "Suspensions"
  }
}

/// What the flavour is for, in a line.
pub fn usage(flavour: Flavour) -> String {
  case flavour {
    Triads -> "Three notes. What an upper structure is built out of."
    Sevenths -> "Four-part harmony: the chords a chart is written in."
    Sixths -> "Lighter than a seventh, and older. The sound of a big band."
    Extended ->
      "Ninths, elevenths and thirteenths, wherever the scale carries them."
    Suspended -> "The fourth left standing in place of the third."
  }
}

/// The name you would type to ask for this flavour.
pub fn id(flavour: Flavour) -> String {
  case flavour {
    Triads -> "triads"
    Sevenths -> "sevenths"
    Sixths -> "sixths"
    Extended -> "extended"
    Suspended -> "suspended"
  }
}

fn aliases(flavour: Flavour) -> List(String) {
  case flavour {
    Triads -> ["triad", "three", "plain"]
    Sevenths -> ["seventh", "7", "sevens"]
    Sixths -> ["sixth", "6", "six-nine"]
    Extended -> ["extensions", "tall", "upper", "9", "13"]
    Suspended -> ["sus", "sus4", "modal", "quartal"]
  }
}

/// Look a flavour up by name, accepting the obvious nicknames.
pub fn flavour_from_string(text: String) -> Result(Flavour, String) {
  let wanted =
    text
    |> string.trim
    |> string.lowercase
    |> string.replace(" ", "-")
    |> string.replace("_", "-")
  case
    list.find(all_flavours(), fn(one) {
      id(one) == wanted || list.contains(aliases(one), wanted)
    })
  {
    Ok(found) -> Ok(found)
    Error(_) ->
      Error("unknown flavour `" <> text <> "`, try `jazz list flavours`")
  }
}
