//// Scales, defined as interval formulas rather than note tables.
////
//// Every scale is a list of degrees measured from the root, which is how
//// players learn them ("one, two, flat three, four...") and which means the
//// spelling of every note falls out of the interval arithmetic for free. No
//// scale needs a hand-written table of note names, in any key.

import gleam/list
import gleam/string
import jazz/interval.{type Interval}
import jazz/pitch.{type PitchClass}

pub type ScaleKind {
  // The major scale and its modes.
  Ionian
  Dorian
  Phrygian
  Lydian
  Mixolydian
  Aeolian
  Locrian
  // Melodic minor and the modes that earn their keep over altered chords.
  MelodicMinor
  DorianFlat2
  LydianAugmented
  LydianDominant
  MixolydianFlat6
  LocrianNatural2
  Altered
  // Harmonic minor.
  HarmonicMinor
  PhrygianDominant
  // Symmetric scales.
  WholeTone
  DiminishedWholeHalf
  DiminishedHalfWhole
  // Bebop scales: eight notes, so chord tones land on the beat.
  BebopDominant
  BebopMajor
  BebopDorian
  // Pentatonics and the blues scale.
  MajorPentatonic
  MinorPentatonic
  Blues
}

pub type Scale {
  Scale(root: PitchClass, kind: ScaleKind)
}

/// The degrees of a scale, as `#(degree, alteration)` pairs.
fn formula(kind: ScaleKind) -> List(#(Int, Int)) {
  case kind {
    Ionian -> [#(1, 0), #(2, 0), #(3, 0), #(4, 0), #(5, 0), #(6, 0), #(7, 0)]
    Dorian -> [#(1, 0), #(2, 0), #(3, -1), #(4, 0), #(5, 0), #(6, 0), #(7, -1)]
    Phrygian -> [
      #(1, 0),
      #(2, -1),
      #(3, -1),
      #(4, 0),
      #(5, 0),
      #(6, -1),
      #(7, -1),
    ]
    Lydian -> [#(1, 0), #(2, 0), #(3, 0), #(4, 1), #(5, 0), #(6, 0), #(7, 0)]
    Mixolydian -> [
      #(1, 0),
      #(2, 0),
      #(3, 0),
      #(4, 0),
      #(5, 0),
      #(6, 0),
      #(7, -1),
    ]
    Aeolian -> [
      #(1, 0),
      #(2, 0),
      #(3, -1),
      #(4, 0),
      #(5, 0),
      #(6, -1),
      #(7, -1),
    ]
    Locrian -> [
      #(1, 0),
      #(2, -1),
      #(3, -1),
      #(4, 0),
      #(5, -1),
      #(6, -1),
      #(7, -1),
    ]
    MelodicMinor -> [
      #(1, 0),
      #(2, 0),
      #(3, -1),
      #(4, 0),
      #(5, 0),
      #(6, 0),
      #(7, 0),
    ]
    DorianFlat2 -> [
      #(1, 0),
      #(2, -1),
      #(3, -1),
      #(4, 0),
      #(5, 0),
      #(6, 0),
      #(7, -1),
    ]
    LydianAugmented -> [
      #(1, 0),
      #(2, 0),
      #(3, 0),
      #(4, 1),
      #(5, 1),
      #(6, 0),
      #(7, 0),
    ]
    LydianDominant -> [
      #(1, 0),
      #(2, 0),
      #(3, 0),
      #(4, 1),
      #(5, 0),
      #(6, 0),
      #(7, -1),
    ]
    MixolydianFlat6 -> [
      #(1, 0),
      #(2, 0),
      #(3, 0),
      #(4, 0),
      #(5, 0),
      #(6, -1),
      #(7, -1),
    ]
    LocrianNatural2 -> [
      #(1, 0),
      #(2, 0),
      #(3, -1),
      #(4, 0),
      #(5, -1),
      #(6, -1),
      #(7, -1),
    ]
    Altered -> [
      #(1, 0),
      #(2, -1),
      #(3, -1),
      #(4, -1),
      #(5, -1),
      #(6, -1),
      #(7, -1),
    ]
    HarmonicMinor -> [
      #(1, 0),
      #(2, 0),
      #(3, -1),
      #(4, 0),
      #(5, 0),
      #(6, -1),
      #(7, 0),
    ]
    PhrygianDominant -> [
      #(1, 0),
      #(2, -1),
      #(3, 0),
      #(4, 0),
      #(5, 0),
      #(6, -1),
      #(7, -1),
    ]
    WholeTone -> [#(1, 0), #(2, 0), #(3, 0), #(4, 1), #(5, 1), #(6, 1)]
    DiminishedWholeHalf -> [
      #(1, 0),
      #(2, 0),
      #(3, -1),
      #(4, 0),
      #(5, -1),
      #(6, -1),
      #(6, 0),
      #(7, 0),
    ]
    DiminishedHalfWhole -> [
      #(1, 0),
      #(2, -1),
      #(2, 1),
      #(3, 0),
      #(4, 1),
      #(5, 0),
      #(6, 0),
      #(7, -1),
    ]
    BebopDominant -> [
      #(1, 0),
      #(2, 0),
      #(3, 0),
      #(4, 0),
      #(5, 0),
      #(6, 0),
      #(7, -1),
      #(7, 0),
    ]
    BebopMajor -> [
      #(1, 0),
      #(2, 0),
      #(3, 0),
      #(4, 0),
      #(5, 0),
      #(5, 1),
      #(6, 0),
      #(7, 0),
    ]
    BebopDorian -> [
      #(1, 0),
      #(2, 0),
      #(3, -1),
      #(3, 0),
      #(4, 0),
      #(5, 0),
      #(6, 0),
      #(7, -1),
    ]
    MajorPentatonic -> [#(1, 0), #(2, 0), #(3, 0), #(5, 0), #(6, 0)]
    MinorPentatonic -> [#(1, 0), #(3, -1), #(4, 0), #(5, 0), #(7, -1)]
    Blues -> [#(1, 0), #(3, -1), #(4, 0), #(4, 1), #(5, 0), #(7, -1)]
  }
}

/// The intervals of a scale, measured from its root.
pub fn intervals(kind: ScaleKind) -> List(Interval) {
  list.map(formula(kind), fn(step) { interval.degree(step.0, step.1) })
}

/// The notes of a scale, spelled correctly for its root.
pub fn notes(scale: Scale) -> List(PitchClass) {
  list.map(intervals(scale.kind), fn(step) {
    interval.transpose_class(scale.root, step)
  })
}

/// The scale's degrees written as a jazz formula: `1 2 b3 4 5 6 b7`.
pub fn degrees(kind: ScaleKind) -> List(String) {
  list.map(intervals(kind), interval.to_degree_string)
}

/// How many notes the scale has.
pub fn size(kind: ScaleKind) -> Int {
  list.length(formula(kind))
}

// --- Naming ------------------------------------------------------------------

pub fn name(kind: ScaleKind) -> String {
  case kind {
    Ionian -> "Ionian (major)"
    Dorian -> "Dorian"
    Phrygian -> "Phrygian"
    Lydian -> "Lydian"
    Mixolydian -> "Mixolydian"
    Aeolian -> "Aeolian (natural minor)"
    Locrian -> "Locrian"
    MelodicMinor -> "Melodic minor"
    DorianFlat2 -> "Dorian b2"
    LydianAugmented -> "Lydian augmented"
    LydianDominant -> "Lydian dominant"
    MixolydianFlat6 -> "Mixolydian b6"
    LocrianNatural2 -> "Locrian natural 2"
    Altered -> "Altered (super Locrian)"
    HarmonicMinor -> "Harmonic minor"
    PhrygianDominant -> "Phrygian dominant"
    WholeTone -> "Whole tone"
    DiminishedWholeHalf -> "Diminished (whole-half)"
    DiminishedHalfWhole -> "Diminished (half-whole)"
    BebopDominant -> "Bebop dominant"
    BebopMajor -> "Bebop major"
    BebopDorian -> "Bebop Dorian"
    MajorPentatonic -> "Major pentatonic"
    MinorPentatonic -> "Minor pentatonic"
    Blues -> "Blues"
  }
}

/// A one-line note on where the scale is actually used.
pub fn usage(kind: ScaleKind) -> String {
  case kind {
    Ionian -> "Over Imaj7. Careful with the 4th, it clashes with the 3rd."
    Dorian -> "The default minor sound. Over im7 and iim7."
    Phrygian -> "Over iiim7, and for a Spanish colour."
    Lydian -> "Over Imaj7 and maj7#11. The 4th is now safe to sit on."
    Mixolydian -> "Over an unaltered V7 that is not resolving."
    Aeolian -> "Over im7 when the 6th should stay dark."
    Locrian -> "Over m7b5, though Locrian natural 2 usually sounds better."
    MelodicMinor -> "Over m(maj7) and minor tonics."
    DorianFlat2 -> "Over sus b9 chords."
    LydianAugmented -> "Over maj7#5."
    LydianDominant -> "Over 7#11, and over the tritone substitute."
    MixolydianFlat6 -> "Over V7 resolving to a minor chord."
    LocrianNatural2 -> "Over m7b5. The natural 9th makes it singable."
    Altered -> "Over V7alt. Every extension is bent: b9 #9 #11 b13."
    HarmonicMinor -> "Over im(maj7), and the source of V7b9 in minor."
    PhrygianDominant -> "Over V7b9 resolving to minor."
    WholeTone -> "Over 7#5. Six notes, no resolution, use sparingly."
    DiminishedWholeHalf -> "Over dim7."
    DiminishedHalfWhole -> "Over 7b9 and 13b9. The workhorse dominant scale."
    BebopDominant -> "Over V7. The extra note keeps chord tones on the beat."
    BebopMajor -> "Over Imaj7 and I6."
    BebopDorian -> "Over im7 in a two-five."
    MajorPentatonic ->
      "Over maj7 and 7. Safe, and never sounds like an exercise."
    MinorPentatonic -> "Over m7. Also the blues, from the fourth degree."
    Blues -> "Over anything in a blues, including the wrong chord."
  }
}

pub fn all_kinds() -> List(ScaleKind) {
  [
    Ionian,
    Dorian,
    Phrygian,
    Lydian,
    Mixolydian,
    Aeolian,
    Locrian,
    MelodicMinor,
    DorianFlat2,
    LydianAugmented,
    LydianDominant,
    MixolydianFlat6,
    LocrianNatural2,
    Altered,
    HarmonicMinor,
    PhrygianDominant,
    WholeTone,
    DiminishedWholeHalf,
    DiminishedHalfWhole,
    BebopDominant,
    BebopMajor,
    BebopDorian,
    MajorPentatonic,
    MinorPentatonic,
    Blues,
  ]
}

/// The name you would type to ask for this scale.
pub fn id(kind: ScaleKind) -> String {
  case kind {
    Ionian -> "ionian"
    Dorian -> "dorian"
    Phrygian -> "phrygian"
    Lydian -> "lydian"
    Mixolydian -> "mixolydian"
    Aeolian -> "aeolian"
    Locrian -> "locrian"
    MelodicMinor -> "melodic-minor"
    DorianFlat2 -> "dorian-b2"
    LydianAugmented -> "lydian-augmented"
    LydianDominant -> "lydian-dominant"
    MixolydianFlat6 -> "mixolydian-b6"
    LocrianNatural2 -> "locrian-natural-2"
    Altered -> "altered"
    HarmonicMinor -> "harmonic-minor"
    PhrygianDominant -> "phrygian-dominant"
    WholeTone -> "whole-tone"
    DiminishedWholeHalf -> "diminished-whole-half"
    DiminishedHalfWhole -> "diminished-half-whole"
    BebopDominant -> "bebop-dominant"
    BebopMajor -> "bebop-major"
    BebopDorian -> "bebop-dorian"
    MajorPentatonic -> "major-pentatonic"
    MinorPentatonic -> "minor-pentatonic"
    Blues -> "blues"
  }
}

fn aliases(kind: ScaleKind) -> List(String) {
  case kind {
    Ionian -> ["major", "maj"]
    Aeolian -> ["minor", "natural-minor", "min"]
    MelodicMinor -> ["jazz-minor", "melodic"]
    Altered -> ["super-locrian", "alt", "diminished-whole-tone"]
    LydianDominant -> ["lydian-b7", "acoustic", "overtone"]
    LocrianNatural2 -> ["locrian-2", "half-diminished"]
    DiminishedWholeHalf -> ["diminished", "whole-half", "dim"]
    DiminishedHalfWhole -> ["half-whole", "dominant-diminished"]
    HarmonicMinor -> ["harmonic"]
    PhrygianDominant -> ["spanish", "phrygian-major"]
    MajorPentatonic -> ["pentatonic", "major-pent"]
    MinorPentatonic -> ["minor-pent"]
    BebopDominant -> ["bebop"]
    _ -> []
  }
}

/// Look a scale up by name, accepting the common nicknames.
pub fn kind_from_string(text: String) -> Result(ScaleKind, String) {
  let wanted =
    text
    |> string.trim
    |> string.lowercase
    |> string.replace(" ", "-")
    |> string.replace("_", "-")
  let found =
    list.find(all_kinds(), fn(kind) {
      id(kind) == wanted || list.contains(aliases(kind), wanted)
    })
  case found {
    Ok(kind) -> Ok(kind)
    Error(_) -> Error("unknown scale `" <> text <> "`, try `jazz list scales`")
  }
}
