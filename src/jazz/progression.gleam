//// Chord progressions, built from a key rather than written out per key.
////
//// Each progression is defined in scale degrees, so asking for it in all
//// twelve keys is the same work as asking for it in one. That is the whole
//// point: the reason to own a tool like this is to practise something round
//// the cycle without copying it out by hand twelve times.

import gleam/list
import gleam/option.{None}
import gleam/string
import jazz/chord.{
  type Chord, Chord, DiminishedSeventh, DiminishedTriad, MajorSeventh,
  MajorTriad, MinorSeventh, MinorTriad, NoSeventh, Tension,
}
import jazz/internal/num
import jazz/interval
import jazz/pitch.{type PitchClass, Pitch}

/// One bar of four beats, holding one or two chords.
pub type Bar {
  Bar(chords: List(Chord))
}

pub type Progression {
  Progression(
    id: String,
    name: String,
    note: String,
    key: PitchClass,
    bars: List(Bar),
  )
}

// --- Chord shorthands --------------------------------------------------------

fn root(key: PitchClass, number: Int, alteration: Int) -> PitchClass {
  interval.transpose_class(key, interval.degree(number, alteration))
}

fn maj7(note: PitchClass) -> Chord {
  Chord(note, MajorTriad, MajorSeventh, False, [], [], None)
}

fn six(note: PitchClass) -> Chord {
  Chord(note, MajorTriad, NoSeventh, True, [], [], None)
}

fn dom7(note: PitchClass) -> Chord {
  Chord(note, MajorTriad, MinorSeventh, False, [], [], None)
}

fn m7(note: PitchClass) -> Chord {
  Chord(note, MinorTriad, MinorSeventh, False, [], [], None)
}

fn m7b5(note: PitchClass) -> Chord {
  Chord(note, DiminishedTriad, MinorSeventh, False, [], [], None)
}

fn dim7(note: PitchClass) -> Chord {
  Chord(note, DiminishedTriad, DiminishedSeventh, False, [], [], None)
}

fn alt7(note: PitchClass) -> Chord {
  Chord(
    note,
    MajorTriad,
    MinorSeventh,
    False,
    [
      Tension(9, -1),
      Tension(9, 1),
      Tension(11, 1),
      Tension(13, -1),
    ],
    [5],
    None,
  )
}

fn dom7b9(note: PitchClass) -> Chord {
  Chord(note, MajorTriad, MinorSeventh, False, [Tension(9, -1)], [], None)
}

// --- The catalogue -----------------------------------------------------------

/// Everything `jazz progression` knows how to build, with a note on what it is
/// for.
pub fn catalogue() -> List(#(String, String)) {
  [
    #("ii-V-I", "The major two-five-one. Learn this one in all twelve keys."),
    #("minor-ii-V-i", "The minor two-five-one, with an altered dominant."),
    #("turnaround", "I VI ii V. Four bars that send you back to the top."),
    #("blues", "The twelve bar jazz blues, with the bar eight detour."),
    #("rhythm-changes-a", "The A section of rhythm changes."),
    #("coltrane", "Giant Steps bars one to four. Three keys, four bars."),
    #("backdoor", "The backdoor cadence: IV to bVII7 to I."),
    #("tritone-sub", "ii V I with the dominant swapped for its tritone."),
  ]
}

/// Build a named progression in a key.
pub fn build(id: String, key: PitchClass) -> Result(Progression, String) {
  case string.lowercase(string.trim(id)) {
    "ii-v-i" | "251" | "ii-v-i-major" -> Ok(two_five_one(key))
    "minor-ii-v-i" | "minor-251" | "ii-v-i-minor" -> Ok(minor_two_five_one(key))
    "turnaround" | "1-6-2-5" -> Ok(turnaround(key))
    "blues" -> Ok(blues(key))
    "rhythm-changes-a" | "rhythm" | "rhythm-changes" ->
      Ok(rhythm_changes_a(key))
    "coltrane" | "giant-steps" -> Ok(coltrane(key))
    "backdoor" -> Ok(backdoor(key))
    "tritone-sub" | "tritone" | "sub" -> Ok(tritone_sub(key))
    _ ->
      Error("unknown progression `" <> id <> "`, try `jazz list progressions`")
  }
}

pub fn two_five_one(key: PitchClass) -> Progression {
  Progression(
    id: "ii-V-I",
    name: "Major ii-V-I",
    note: "Aim for the third of each chord and let the sevenths fall a step.",
    key: key,
    bars: [
      Bar([m7(root(key, 2, 0))]),
      Bar([dom7(root(key, 5, 0))]),
      Bar([maj7(key)]),
      Bar([maj7(key)]),
    ],
  )
}

pub fn minor_two_five_one(key: PitchClass) -> Progression {
  Progression(
    id: "minor-ii-V-i",
    name: "Minor ii-V-i",
    note: "The altered dominant is melodic minor a semitone above its root.",
    key: key,
    bars: [
      Bar([m7b5(root(key, 2, 0))]),
      Bar([alt7(root(key, 5, 0))]),
      Bar([m7(key)]),
      Bar([m7(key)]),
    ],
  )
}

pub fn turnaround(key: PitchClass) -> Progression {
  Progression(
    id: "turnaround",
    name: "I VI ii V turnaround",
    note: "The last two bars of almost every standard.",
    key: key,
    bars: [
      Bar([maj7(key)]),
      Bar([dom7b9(root(key, 6, 0))]),
      Bar([m7(root(key, 2, 0))]),
      Bar([dom7(root(key, 5, 0))]),
    ],
  )
}

pub fn blues(key: PitchClass) -> Progression {
  Progression(
    id: "blues",
    name: "Twelve bar jazz blues",
    note: "Bars eight to ten are a two-five; the rest is the blues scale.",
    key: key,
    bars: [
      Bar([dom7(key)]),
      Bar([dom7(root(key, 4, 0))]),
      Bar([dom7(key)]),
      Bar([m7(root(key, 5, 0)), dom7(key)]),
      Bar([dom7(root(key, 4, 0))]),
      Bar([dim7(root(key, 4, 1))]),
      Bar([dom7(key)]),
      Bar([m7(root(key, 3, 0)), dom7(root(key, 6, 0))]),
      Bar([m7(root(key, 2, 0))]),
      Bar([dom7(root(key, 5, 0))]),
      Bar([dom7(key), dom7(root(key, 6, 0))]),
      Bar([m7(root(key, 2, 0)), dom7(root(key, 5, 0))]),
    ],
  )
}

pub fn rhythm_changes_a(key: PitchClass) -> Progression {
  Progression(
    id: "rhythm-changes-a",
    name: "Rhythm changes, A section",
    note: "Two chords a bar. Guide tones matter more than scales here.",
    key: key,
    bars: [
      Bar([six(key), dom7b9(root(key, 6, 0))]),
      Bar([m7(root(key, 2, 0)), dom7(root(key, 5, 0))]),
      Bar([m7(root(key, 3, 0)), dom7b9(root(key, 6, 0))]),
      Bar([m7(root(key, 2, 0)), dom7(root(key, 5, 0))]),
      Bar([dom7(key)]),
      Bar([dom7(root(key, 4, 0)), dim7(root(key, 4, 1))]),
      Bar([six(key), dom7b9(root(key, 6, 0))]),
      Bar([m7(root(key, 2, 0)), dom7(root(key, 5, 0))]),
    ],
  )
}

pub fn coltrane(key: PitchClass) -> Progression {
  Progression(
    id: "coltrane",
    name: "Coltrane changes",
    note: "Three tonics a major third apart. Play the arpeggios before the scales.",
    key: key,
    bars: {
      // Each tonic is a major third below the last, and each dominant is the
      // five of wherever the tune is about to land.
      let second = root(key, 6, -1)
      let third = root(second, 6, -1)
      [
        Bar([maj7(key), dom7(root(second, 5, 0))]),
        Bar([maj7(second), dom7(root(third, 5, 0))]),
        Bar([maj7(third)]),
        Bar([m7(root(second, 2, 0)), dom7(root(second, 5, 0))]),
      ]
    },
  )
}

pub fn backdoor(key: PitchClass) -> Progression {
  Progression(
    id: "backdoor",
    name: "Backdoor cadence",
    note: "bVII7 resolves to I through its own flat seventh. Use Lydian dominant.",
    key: key,
    bars: [
      Bar([maj7(root(key, 4, 0))]),
      Bar([m7(root(key, 4, 0))]),
      Bar([dom7(root(key, 7, -1))]),
      Bar([maj7(key)]),
    ],
  )
}

pub fn tritone_sub(key: PitchClass) -> Progression {
  Progression(
    id: "tritone-sub",
    name: "ii V I with a tritone substitute",
    note: "bII7 shares its third and seventh with V7, so one line covers both halves.",
    key: key,
    bars: [
      Bar([m7(root(key, 2, 0)), dom7(root(key, 5, 0))]),
      Bar([maj7(key)]),
      Bar([m7(root(key, 2, 0)), dom7(root(key, 2, -1))]),
      Bar([maj7(key)]),
    ],
  )
}

// --- Views -------------------------------------------------------------------

/// Every chord in the progression, in order.
pub fn chords(progression: Progression) -> List(Chord) {
  list.flat_map(progression.bars, fn(bar) { bar.chords })
}

/// Move a whole progression to another key.
pub fn transpose(
  progression: Progression,
  by: interval.Interval,
) -> Progression {
  Progression(
    ..progression,
    key: interval.transpose_class(progression.key, by),
    bars: list.map(progression.bars, fn(bar) {
      Bar(list.map(bar.chords, chord.transpose(_, by)))
    }),
  )
}

/// The roman numeral for a chord in a key, such as `iim7`, `V7` or `bVII7`.
pub fn roman(key: PitchClass, of: Chord) -> String {
  let steps =
    num.modulo(
      pitch.diatonic_position(Pitch(of.root, 4))
        - pitch.diatonic_position(Pitch(key, 4)),
      7,
    )
  let semitones =
    num.modulo(
      pitch.to_midi(Pitch(of.root, 4)) - pitch.to_midi(Pitch(key, 4)),
      12,
    )
  let plain = interval.semitones(interval.degree(steps + 1, 0))
  let alteration = wrap_alteration(semitones - plain)
  let numeral = case of.triad {
    MinorTriad | DiminishedTriad -> string.lowercase(numeral_of(steps))
    _ -> numeral_of(steps)
  }
  pitch.accidental_to_string(alteration) <> numeral <> chord.quality_string(of)
}

fn wrap_alteration(alteration: Int) -> Int {
  case alteration > 6, alteration < -6 {
    True, _ -> alteration - 12
    _, True -> alteration + 12
    _, _ -> alteration
  }
}

fn numeral_of(steps: Int) -> String {
  case steps {
    0 -> "I"
    1 -> "II"
    2 -> "III"
    3 -> "IV"
    4 -> "V"
    5 -> "VI"
    _ -> "VII"
  }
}

// --- Keys --------------------------------------------------------------------

/// The twelve keys in the order jazz practises them: down a fifth each time,
/// respelled whenever the key signature would run away.
pub fn cycle_of_fourths(start: PitchClass) -> List(PitchClass) {
  let base = pitch.fifths(start)
  num.counting(12)
  |> list.map(fn(step) { pitch.simplify_key(pitch.from_fifths(base - step)) })
}

/// The same twelve keys, going the other way.
pub fn cycle_of_fifths(start: PitchClass) -> List(PitchClass) {
  let base = pitch.fifths(start)
  num.counting(12)
  |> list.map(fn(step) { pitch.simplify_key(pitch.from_fifths(base + step)) })
}

/// Twelve keys in chromatic order.
pub fn chromatic(start: PitchClass) -> List(PitchClass) {
  num.counting(12)
  |> list.map(fn(step) {
    pitch.simplify_key(interval.transpose_class(
      start,
      interval.degree(2, -1 + step),
    ))
  })
}
