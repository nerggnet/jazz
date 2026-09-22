//// Chords, and the chord symbols players actually write.
////
//// Jazz chord notation is a family of dialects rather than a notation, so the
//// parser accepts `C-7`, `Cmi7` and `Cm7` alike, along with `^` and `Δ` for
//// major and `ø` for half-diminished. Case matters in exactly one place, and
//// it is the place everybody already knows: `CM7` is major, `Cm7` is minor.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import jazz/interval.{type Interval}
import jazz/pitch.{type PitchClass}
import jazz/scale.{type ScaleKind}

pub type Triad {
  MajorTriad
  MinorTriad
  DiminishedTriad
  AugmentedTriad
  Sus2
  Sus4
}

pub type Seventh {
  NoSeventh
  MajorSeventh
  MinorSeventh
  DiminishedSeventh
}

/// An extension or an altered chord tone, as a degree and how far it is bent.
pub type Tension {
  Tension(degree: Int, alteration: Int)
}

pub type Chord {
  Chord(
    root: PitchClass,
    triad: Triad,
    seventh: Seventh,
    sixth: Bool,
    tensions: List(Tension),
    /// Degrees deliberately left out. An altered dominant drops its fifth,
    /// because the b13 is already doing that job.
    omit: List(Int),
    bass: Option(PitchClass),
  )
}

/// A plain triad, as a starting point for building chords by hand.
pub fn new(root: PitchClass, triad: Triad) -> Chord {
  Chord(root, triad, NoSeventh, False, [], [], None)
}

// --- The chords everything else is built out of ------------------------------

pub fn major_seventh(root: PitchClass) -> Chord {
  Chord(root, MajorTriad, MajorSeventh, False, [], [], None)
}

pub fn sixth(root: PitchClass) -> Chord {
  Chord(root, MajorTriad, NoSeventh, True, [], [], None)
}

pub fn dominant(root: PitchClass) -> Chord {
  Chord(root, MajorTriad, MinorSeventh, False, [], [], None)
}

pub fn dominant_flat_nine(root: PitchClass) -> Chord {
  Chord(root, MajorTriad, MinorSeventh, False, [Tension(9, -1)], [], None)
}

/// Every extension bent at once, and no natural fifth to argue with them.
pub fn altered(root: PitchClass) -> Chord {
  Chord(
    root,
    MajorTriad,
    MinorSeventh,
    False,
    [Tension(9, -1), Tension(9, 1), Tension(11, 1), Tension(13, -1)],
    [5],
    None,
  )
}

pub fn minor_seventh(root: PitchClass) -> Chord {
  Chord(root, MinorTriad, MinorSeventh, False, [], [], None)
}

pub fn minor_sixth(root: PitchClass) -> Chord {
  Chord(root, MinorTriad, NoSeventh, True, [], [], None)
}

pub fn half_diminished(root: PitchClass) -> Chord {
  Chord(root, DiminishedTriad, MinorSeventh, False, [], [], None)
}

pub fn diminished_seventh(root: PitchClass) -> Chord {
  Chord(root, DiminishedTriad, DiminishedSeventh, False, [], [], None)
}

pub fn suspended(root: PitchClass) -> Chord {
  Chord(root, Sus4, MinorSeventh, False, [], [], None)
}

// --- Notes -------------------------------------------------------------------

/// The intervals of the chord above its root, lowest first.
pub fn intervals(chord: Chord) -> List(Interval) {
  let fifth_is_altered =
    list.any(chord.tensions, fn(tension) { tension.degree == 5 })

  let base =
    case chord.triad {
      MajorTriad -> [#(1, 0), #(3, 0), #(5, 0)]
      MinorTriad -> [#(1, 0), #(3, -1), #(5, 0)]
      DiminishedTriad -> [#(1, 0), #(3, -1), #(5, -1)]
      AugmentedTriad -> [#(1, 0), #(3, 0), #(5, 1)]
      Sus2 -> [#(1, 0), #(2, 0), #(5, 0)]
      Sus4 -> [#(1, 0), #(4, 0), #(5, 0)]
    }
    |> list.filter(fn(step) { !{ fifth_is_altered && step.0 == 5 } })

  let seventh = case chord.seventh {
    NoSeventh -> []
    MajorSeventh -> [#(7, 0)]
    MinorSeventh -> [#(7, -1)]
    DiminishedSeventh -> [#(7, -2)]
  }

  let sixth = case chord.sixth {
    True -> [#(6, 0)]
    False -> []
  }

  let extensions =
    list.map(chord.tensions, fn(tension) {
      #(tension.degree, tension.alteration)
    })

  list.flatten([base, sixth, seventh, extensions])
  |> list.filter(fn(step) { !list.contains(chord.omit, step.0) })
  |> list.map(fn(step) { interval.degree(step.0, step.1) })
  |> list.sort(fn(a, b) {
    int.compare(interval.semitones(a), interval.semitones(b))
  })
}

/// The notes of the chord, spelled for its root.
pub fn notes(chord: Chord) -> List(PitchClass) {
  list.map(intervals(chord), fn(step) {
    interval.transpose_class(chord.root, step)
  })
}

/// The chord's degrees as a jazz formula: `1 b3 b5 b7`.
pub fn degrees(chord: Chord) -> List(String) {
  list.map(intervals(chord), interval.to_degree_string)
}

/// The third and the seventh: the two notes that say what the chord is, and
/// the ones to aim at when connecting one chord to the next.
pub fn guide_tones(chord: Chord) -> List(PitchClass) {
  intervals(chord)
  |> list.filter(fn(step) {
    let number = interval.number(step)
    number == 3
    || number == 4
    || number == 7
    || { number == 6 && chord.seventh == NoSeventh }
  })
  |> list.map(fn(step) { interval.transpose_class(chord.root, step) })
}

/// Move a chord by an interval, keeping its spelling.
pub fn transpose(chord: Chord, by: Interval) -> Chord {
  Chord(
    ..chord,
    root: interval.transpose_class(chord.root, by),
    bass: option.map(chord.bass, interval.transpose_class(_, by)),
  )
}

// --- Chord scales ------------------------------------------------------------

/// Scales that fit the chord, best first.
///
/// These are the usual choices rather than the only ones; the last word
/// belongs to whoever is playing.
pub fn chord_scales(chord: Chord) -> List(ScaleKind) {
  let has = fn(degree, alteration) {
    list.contains(chord.tensions, Tension(degree, alteration))
  }
  let flat_nine = has(9, -1)
  let sharp_nine = has(9, 1)
  let sharp_eleven = has(11, 1)
  let flat_thirteen = has(13, -1) || has(5, -1)
  let sharp_five = has(5, 1)

  case chord.triad, chord.seventh {
    MajorTriad, MajorSeventh ->
      case sharp_eleven, sharp_five {
        True, _ -> [scale.Lydian, scale.LydianAugmented]
        _, True -> [scale.LydianAugmented, scale.WholeTone]
        _, _ -> [
          scale.Ionian,
          scale.Lydian,
          scale.BebopMajor,
          scale.MajorPentatonic,
        ]
      }

    MajorTriad, MinorSeventh ->
      case flat_nine || sharp_nine, sharp_eleven, sharp_five || flat_thirteen {
        True, _, True -> [scale.Altered, scale.DiminishedHalfWhole]
        True, _, _ -> [
          scale.DiminishedHalfWhole,
          scale.Altered,
          scale.PhrygianDominant,
        ]
        _, True, _ -> [scale.LydianDominant, scale.WholeTone]
        _, _, True -> [scale.MixolydianFlat6, scale.WholeTone, scale.Altered]
        _, _, _ -> [
          scale.Mixolydian,
          scale.BebopDominant,
          scale.MajorPentatonic,
          scale.Blues,
        ]
      }

    MinorTriad, MinorSeventh -> [
      scale.Dorian,
      scale.BebopDorian,
      scale.Aeolian,
      scale.MinorPentatonic,
    ]
    MinorTriad, MajorSeventh -> [scale.MelodicMinor, scale.HarmonicMinor]
    MinorTriad, _ ->
      case chord.sixth {
        True -> [scale.Dorian, scale.MelodicMinor]
        False -> [scale.Dorian, scale.Aeolian, scale.MinorPentatonic]
      }

    DiminishedTriad, MinorSeventh -> [scale.LocrianNatural2, scale.Locrian]
    DiminishedTriad, _ -> [scale.DiminishedWholeHalf]

    AugmentedTriad, MinorSeventh -> [scale.WholeTone, scale.Altered]
    AugmentedTriad, _ -> [scale.LydianAugmented, scale.WholeTone]

    Sus4, _ | Sus2, _ ->
      case flat_nine {
        True -> [scale.DorianFlat2, scale.DiminishedHalfWhole]
        False -> [scale.Mixolydian, scale.MajorPentatonic]
      }

    MajorTriad, _ ->
      case chord.sixth {
        True -> [scale.Ionian, scale.BebopMajor, scale.MajorPentatonic]
        False -> [scale.Ionian, scale.Lydian, scale.MajorPentatonic]
      }
  }
}

// --- Printing ----------------------------------------------------------------

/// The chord as a symbol, spelled canonically.
pub fn to_string(chord: Chord) -> String {
  let bass = case chord.bass {
    Some(note) -> "/" <> pitch.class_to_string(note)
    None -> ""
  }
  pitch.class_to_string(chord.root) <> suffix(chord) <> bass
}

/// Just the quality part of the symbol, without the root: `m7b5`, `7alt`.
pub fn quality_string(chord: Chord) -> String {
  suffix(chord)
}

fn suffix(chord: Chord) -> String {
  let naturals =
    chord.tensions
    |> list.filter(fn(t) { t.alteration == 0 && t.degree >= 9 })
    |> list.map(fn(t) { t.degree })
  let altered =
    chord.tensions
    |> list.filter(fn(t) { t.alteration != 0 || t.degree < 9 })
    |> list.sort(fn(a, b) { int.compare(a.degree, b.degree) })

  case is_altered_dominant(chord, naturals, altered) {
    True -> "7alt"
    False -> {
      let #(top, consumed) = top_extension(chord, naturals)
      let leftovers =
        naturals
        |> list.filter(fn(degree) { !list.contains(consumed, degree) })
        |> list.sort(int.compare)
        |> list.map(fn(degree) { "add" <> int.to_string(degree) })
        |> string.concat
      core(chord, top) <> alterations(altered) <> leftovers <> omissions(chord)
    }
  }
}

fn is_altered_dominant(
  chord: Chord,
  naturals: List(Int),
  altered: List(Tension),
) -> Bool {
  chord.triad == MajorTriad
  && chord.seventh == MinorSeventh
  && naturals == []
  && list.sort(altered, fn(a, b) {
    case int.compare(a.degree, b.degree) {
      order.Eq -> int.compare(a.alteration, b.alteration)
      other -> other
    }
  })
  == [Tension(9, -1), Tension(9, 1), Tension(11, 1), Tension(13, -1)]
}

/// The number that goes into the symbol, and which extensions it swallows.
/// `C13` implies the ninth, so the ninth is not spelled out again.
fn top_extension(chord: Chord, naturals: List(Int)) -> #(String, List(Int)) {
  let has = fn(degree) { list.contains(naturals, degree) }
  case chord.seventh, chord.sixth {
    NoSeventh, True ->
      case has(9) {
        True -> #("6/9", [9])
        False -> #("6", [])
      }
    NoSeventh, False -> #("", [])
    _, _ ->
      case has(13), has(11), has(9) {
        True, True, _ -> #("13", [9, 11, 13])
        True, _, _ -> #("13", [9, 13])
        _, True, _ -> #("11", [9, 11])
        _, _, True -> #("9", [9])
        _, _, _ -> #("7", [])
      }
  }
}

fn core(chord: Chord, top: String) -> String {
  let sus = case chord.triad {
    Sus2 -> "sus2"
    Sus4 -> "sus4"
    _ -> ""
  }
  case chord.triad, chord.seventh {
    MajorTriad, MajorSeventh | Sus2, MajorSeventh | Sus4, MajorSeventh ->
      "maj" <> or_seven(top) <> sus
    MajorTriad, MinorSeventh | Sus2, MinorSeventh | Sus4, MinorSeventh ->
      or_seven(top) <> sus
    MinorTriad, MajorSeventh -> "m(maj" <> or_seven(top) <> ")"
    MinorTriad, MinorSeventh -> "m" <> or_seven(top)
    MinorTriad, _ -> "m" <> top
    DiminishedTriad, DiminishedSeventh -> "dim7"
    DiminishedTriad, MinorSeventh -> "m" <> or_seven(top) <> "b5"
    DiminishedTriad, _ -> "dim" <> top
    AugmentedTriad, MajorSeventh -> "maj" <> or_seven(top) <> "#5"
    AugmentedTriad, MinorSeventh -> or_seven(top) <> "#5"
    AugmentedTriad, _ -> "aug" <> top
    _, _ -> top <> sus
  }
}

fn or_seven(top: String) -> String {
  case top {
    "" -> "7"
    other -> other
  }
}

fn omissions(chord: Chord) -> String {
  chord.omit
  |> list.sort(int.compare)
  |> list.map(fn(degree) { "no" <> int.to_string(degree) })
  |> string.concat
}

fn alterations(altered: List(Tension)) -> String {
  altered
  |> list.map(fn(tension) {
    pitch.accidental_to_string(tension.alteration)
    <> int.to_string(tension.degree)
  })
  |> string.concat
}

// --- Parsing -----------------------------------------------------------------

type Token {
  MajorMark
  MajorSeventhMark
  MinorMark
  HalfDiminishedMark
  DiminishedMark
  DiminishedSeventhMark
  AugmentedMark
  SusMark(Int)
  AltMark
  AddMark(Int)
  NumberMark(Int)
  AlterMark(Int, Int)
  OmitMark(Int)
  Ignore
}

type Builder {
  Builder(
    triad: Triad,
    seventh: Seventh,
    sixth: Bool,
    tensions: List(Tension),
    omit: List(Int),
    major_mark: Bool,
  )
}

/// Parse a chord symbol such as `Bb7#9`, `F-7`, `C^9`, `Ebm7b5` or `Am7/D`.
pub fn parse(text: String) -> Result(Chord, String) {
  let trimmed = string.trim(text)
  case trimmed {
    "" -> Error("expected a chord symbol, found nothing")
    _ -> {
      let #(body, bass) = split_bass(trimmed)
      case pitch.parse_class(root_of(body)) {
        Error(message) -> Error(message)
        Ok(root) ->
          case
            consume(
              string.drop_start(body, string.length(root_of(body))),
              fresh(),
            )
          {
            Error(rest) ->
              Error(
                "could not read `"
                <> rest
                <> "` in the chord symbol `"
                <> trimmed
                <> "`",
              )
            Ok(builder) -> Ok(finish(root, bass, builder))
          }
      }
    }
  }
}

fn fresh() -> Builder {
  Builder(MajorTriad, NoSeventh, False, [], [], False)
}

fn finish(
  root: PitchClass,
  bass: Option(PitchClass),
  builder: Builder,
) -> Chord {
  // `C^` and `Cmaj` on their own mean the major seventh chord.
  let seventh = case builder.major_mark, builder.seventh, builder.sixth {
    True, NoSeventh, False -> MajorSeventh
    _, existing, _ -> existing
  }
  Chord(
    root: root,
    triad: builder.triad,
    seventh: seventh,
    sixth: builder.sixth,
    tensions: list.unique(builder.tensions),
    omit: list.unique(builder.omit),
    bass: bass,
  )
}

/// The leading note name, which is a letter plus any accidentals.
fn root_of(text: String) -> String {
  case string.pop_grapheme(text) {
    Error(_) -> text
    Ok(#(letter, rest)) -> letter <> take_accidentals(rest, "")
  }
}

fn take_accidentals(text: String, acc: String) -> String {
  case string.pop_grapheme(text) {
    Ok(#("#", rest)) -> take_accidentals(rest, acc <> "#")
    Ok(#("\u{266F}", rest)) -> take_accidentals(rest, acc <> "#")
    Ok(#("b", rest)) -> take_accidentals(rest, acc <> "b")
    Ok(#("\u{266D}", rest)) -> take_accidentals(rest, acc <> "b")
    _ -> acc
  }
}

/// Split a trailing slash bass off the symbol. `C6/9` is not a slash chord,
/// and is left alone because `9` is not a note name.
fn split_bass(text: String) -> #(String, Option(PitchClass)) {
  case string.split(text, "/") {
    [body, tail] ->
      case pitch.parse_class(tail) {
        Ok(note) -> #(body, Some(note))
        Error(_) -> #(text, None)
      }
    _ -> #(text, None)
  }
}

fn consume(text: String, builder: Builder) -> Result(Builder, String) {
  case text {
    "" -> Ok(builder)
    _ ->
      case match(text) {
        Error(_) -> Error(text)
        Ok(#(token, rest)) -> consume(rest, apply(builder, token))
      }
  }
}

fn match(text: String) -> Result(#(Token, String), Nil) {
  list.fold(tokens(), Error(Nil), fn(found, entry) {
    case found {
      Ok(_) -> found
      Error(_) -> {
        let #(pattern, token) = entry
        case string.starts_with(text, pattern) {
          True -> Ok(#(token, string.drop_start(text, string.length(pattern))))
          False -> Error(Nil)
        }
      }
    }
  })
}

/// Longest patterns first, so `maj7` wins over `ma` and `ma` wins over `m`.
/// Single-letter `M` and `m` are the one case-sensitive distinction.
fn tokens() -> List(#(String, Token)) {
  [
    #("maj7", MajorSeventhMark),
    #("Maj7", MajorSeventhMark),
    #("MAJ7", MajorSeventhMark),
    #("ma7", MajorSeventhMark),
    #("Ma7", MajorSeventhMark),
    #("M7", MajorSeventhMark),
    #("^7", MajorSeventhMark),
    #("\u{0394}7", MajorSeventhMark),
    #("maj", MajorMark),
    #("Maj", MajorMark),
    #("MAJ", MajorMark),
    #("ma", MajorMark),
    #("Ma", MajorMark),
    #("^", MajorMark),
    #("\u{0394}", MajorMark),
    #("dim7", DiminishedSeventhMark),
    #("\u{00B0}7", DiminishedSeventhMark),
    #("o7", DiminishedSeventhMark),
    #("dim", DiminishedMark),
    #("\u{00B0}", DiminishedMark),
    #("\u{00F8}7", HalfDiminishedMark),
    #("\u{00F8}", HalfDiminishedMark),
    #("min", MinorMark),
    #("Min", MinorMark),
    #("mi", MinorMark),
    #("Mi", MinorMark),
    #("m", MinorMark),
    #("-", MinorMark),
    #("aug", AugmentedMark),
    #("+", AugmentedMark),
    #("sus4", SusMark(4)),
    #("sus2", SusMark(2)),
    #("sus", SusMark(4)),
    #("alt", AltMark),
    #("add9", AddMark(9)),
    #("add11", AddMark(11)),
    #("add13", AddMark(13)),
    #("add2", AddMark(9)),
    #("add4", AddMark(11)),
    #("b13", AlterMark(13, -1)),
    #("#13", AlterMark(13, 1)),
    #("b11", AlterMark(11, -1)),
    #("#11", AlterMark(11, 1)),
    #("+11", AlterMark(11, 1)),
    #("b9", AlterMark(9, -1)),
    #("#9", AlterMark(9, 1)),
    #("+9", AlterMark(9, 1)),
    #("b5", AlterMark(5, -1)),
    #("#5", AlterMark(5, 1)),
    #("+5", AlterMark(5, 1)),
    #("b6", AlterMark(13, -1)),
    #("/9", AddMark(9)),
    #("13", NumberMark(13)),
    #("11", NumberMark(11)),
    #("9", NumberMark(9)),
    #("7", NumberMark(7)),
    #("6", NumberMark(6)),
    #("/", Ignore),
    #("(", Ignore),
    #(")", Ignore),
    #(",", Ignore),
    #(" ", Ignore),
    #("no3", OmitMark(3)),
    #("no5", OmitMark(5)),
  ]
}

fn apply(builder: Builder, token: Token) -> Builder {
  case token {
    Ignore -> builder
    OmitMark(degree) -> Builder(..builder, omit: [degree, ..builder.omit])
    MajorMark -> Builder(..builder, major_mark: True)
    MajorSeventhMark ->
      Builder(..builder, major_mark: True, seventh: MajorSeventh)
    MinorMark -> Builder(..builder, triad: MinorTriad)
    HalfDiminishedMark ->
      Builder(..builder, triad: DiminishedTriad, seventh: MinorSeventh)
    DiminishedMark -> Builder(..builder, triad: DiminishedTriad)
    DiminishedSeventhMark ->
      Builder(..builder, triad: DiminishedTriad, seventh: DiminishedSeventh)
    AugmentedMark -> Builder(..builder, triad: AugmentedTriad)
    SusMark(2) -> Builder(..builder, triad: Sus2)
    SusMark(_) -> Builder(..builder, triad: Sus4)
    AltMark ->
      Builder(
        ..builder,
        seventh: MinorSeventh,
        omit: [5, ..builder.omit],
        tensions: [
          Tension(9, -1),
          Tension(9, 1),
          Tension(11, 1),
          Tension(13, -1),
          ..builder.tensions
        ],
      )
    AddMark(degree) ->
      Builder(..builder, tensions: [Tension(degree, 0), ..builder.tensions])
    NumberMark(6) -> Builder(..builder, sixth: True)
    NumberMark(7) -> Builder(..builder, seventh: implied_seventh(builder))
    NumberMark(degree) ->
      Builder(
        ..builder,
        seventh: implied_seventh(builder),
        tensions: list.append(stack_to(degree), builder.tensions),
      )
    // A flat fifth turns a minor triad diminished rather than colouring it.
    AlterMark(5, -1) if builder.triad == MinorTriad ->
      Builder(..builder, triad: DiminishedTriad)
    AlterMark(5, 1)
      if builder.triad == MajorTriad && builder.seventh == NoSeventh
    -> Builder(..builder, triad: AugmentedTriad)
    AlterMark(degree, alteration) ->
      Builder(..builder, tensions: [
        Tension(degree, alteration),
        ..builder.tensions
      ])
  }
}

fn implied_seventh(builder: Builder) -> Seventh {
  case builder.seventh, builder.major_mark {
    NoSeventh, True -> MajorSeventh
    NoSeventh, False -> MinorSeventh
    existing, _ -> existing
  }
}

/// `9` means the ninth; `11` means the ninth and the eleventh; `13` means the
/// ninth and the thirteenth, because nobody voices the eleventh in a `13`.
fn stack_to(degree: Int) -> List(Tension) {
  case degree {
    11 -> [Tension(9, 0), Tension(11, 0)]
    13 -> [Tension(9, 0), Tension(13, 0)]
    _ -> [Tension(9, 0)]
  }
}
