//// Tonal pitch representation.
////
//// A pitch is a letter name plus a chromatic alteration, never a bare
//// semitone number. Keeping the spelling is what lets `E#` and `F` remain
//// different notes, and that is what makes transposition for E-flat and
//// B-flat instruments produce a readable part instead of enharmonic sludge.

import gleam/int
import gleam/string
import jazz/internal/num

/// The seven natural note names.
pub type Letter {
  C
  D
  E
  F
  G
  A
  B
}

/// A letter with an alteration in semitones: positive is sharp, negative is
/// flat, zero is natural.
pub type PitchClass {
  PitchClass(letter: Letter, alteration: Int)
}

/// A pitch class in a specific octave, using scientific pitch notation where
/// middle C is `C4`.
pub type Pitch {
  Pitch(class: PitchClass, octave: Int)
}

/// Which spelling to reach for when a note could be written either way.
pub type Spelling {
  PreferFlats
  PreferSharps
}

// --- Construction ------------------------------------------------------------

/// A natural pitch class.
pub fn natural(letter: Letter) -> PitchClass {
  PitchClass(letter, 0)
}

/// A pitch class with an alteration.
pub fn class(letter: Letter, alteration: Int) -> PitchClass {
  PitchClass(letter, alteration)
}

/// A pitch, in one call: `note(B, -1, 3)` is the B-flat below middle C.
pub fn note(letter: Letter, alteration: Int, octave: Int) -> Pitch {
  Pitch(PitchClass(letter, alteration), octave)
}

// --- Letters -----------------------------------------------------------------

/// The position of a letter in the diatonic scale, counting `C` as 0.
pub fn diatonic_index(letter: Letter) -> Int {
  case letter {
    C -> 0
    D -> 1
    E -> 2
    F -> 3
    G -> 4
    A -> 5
    B -> 6
  }
}

/// The letter at a diatonic index, wrapping in both directions.
pub fn letter_at(index: Int) -> Letter {
  case num.modulo(index, 7) {
    0 -> C
    1 -> D
    2 -> E
    3 -> F
    4 -> G
    5 -> A
    _ -> B
  }
}

/// How many semitones a natural letter sits above `C`.
pub fn letter_semitones(letter: Letter) -> Int {
  case letter {
    C -> 0
    D -> 2
    E -> 4
    F -> 5
    G -> 7
    A -> 9
    B -> 11
  }
}

/// Where a letter sits on the line of fifths, counting `C` as 0.
fn letter_fifths(letter: Letter) -> Int {
  case letter {
    F -> -1
    C -> 0
    G -> 1
    D -> 2
    A -> 3
    E -> 4
    B -> 5
  }
}

// --- Measurement -------------------------------------------------------------

/// The pitch class as a number from 0 (C) to 11 (B), discarding the spelling.
pub fn class_semitones(pitch_class: PitchClass) -> Int {
  num.modulo(letter_semitones(pitch_class.letter) + pitch_class.alteration, 12)
}

/// The MIDI note number of a pitch, where middle C (`C4`) is 60.
pub fn to_midi(pitch: Pitch) -> Int {
  { pitch.octave + 1 }
  * 12
  + letter_semitones(pitch.class.letter)
  + pitch.class.alteration
}

/// The absolute diatonic position of a pitch, counting `C0` as 0. Used by
/// transposition to decide which letter a note is spelled with.
pub fn diatonic_position(pitch: Pitch) -> Int {
  pitch.octave * 7 + diatonic_index(pitch.class.letter)
}

/// Rebuild a pitch from an absolute diatonic position and a MIDI number. The
/// alteration is whatever it takes to bridge the two, which is exactly how
/// spelling-correct transposition works.
pub fn from_position(position: Int, midi: Int) -> Pitch {
  let octave = num.floor_div(position, 7)
  let letter = letter_at(position)
  let natural_midi = { octave + 1 } * 12 + letter_semitones(letter)
  Pitch(PitchClass(letter, midi - natural_midi), octave)
}

/// Where a pitch class sits on the line of fifths. This doubles as the key
/// signature of its major key: `D` is 2 (two sharps), `Eb` is -3 (three flats).
pub fn fifths(pitch_class: PitchClass) -> Int {
  letter_fifths(pitch_class.letter) + 7 * pitch_class.alteration
}

/// The pitch class at a position on the line of fifths.
pub fn from_fifths(position: Int) -> PitchClass {
  let alteration = num.floor_div(position + 1, 7)
  PitchClass(letter_of_fifths(position - 7 * alteration), alteration)
}

fn letter_of_fifths(position: Int) -> Letter {
  case position {
    -1 -> F
    0 -> C
    1 -> G
    2 -> D
    3 -> A
    4 -> E
    _ -> B
  }
}

// --- Comparison --------------------------------------------------------------

/// Whether two pitch classes sound the same, however they are spelled.
pub fn enharmonic(a: PitchClass, b: PitchClass) -> Bool {
  class_semitones(a) == class_semitones(b)
}

/// Whether two pitch classes are spelled identically.
pub fn same(a: PitchClass, b: PitchClass) -> Bool {
  a.letter == b.letter && a.alteration == b.alteration
}

// --- Respelling --------------------------------------------------------------

/// Respell a pitch class with as few accidentals as possible.
///
/// This throws away the original spelling, so use it on a key centre the
/// player has to read in, not on notes inside a scale where the spelling is
/// carrying information.
pub fn simplify(pitch_class: PitchClass, prefer: Spelling) -> PitchClass {
  let semitones = class_semitones(pitch_class)
  let candidate = case prefer {
    PreferFlats -> flat_spelling(semitones)
    PreferSharps -> sharp_spelling(semitones)
  }
  candidate
}

fn flat_spelling(semitones: Int) -> PitchClass {
  case semitones {
    0 -> PitchClass(C, 0)
    1 -> PitchClass(D, -1)
    2 -> PitchClass(D, 0)
    3 -> PitchClass(E, -1)
    4 -> PitchClass(E, 0)
    5 -> PitchClass(F, 0)
    6 -> PitchClass(G, -1)
    7 -> PitchClass(G, 0)
    8 -> PitchClass(A, -1)
    9 -> PitchClass(A, 0)
    10 -> PitchClass(B, -1)
    _ -> PitchClass(B, 0)
  }
}

fn sharp_spelling(semitones: Int) -> PitchClass {
  case semitones {
    0 -> PitchClass(C, 0)
    1 -> PitchClass(C, 1)
    2 -> PitchClass(D, 0)
    3 -> PitchClass(D, 1)
    4 -> PitchClass(E, 0)
    5 -> PitchClass(F, 0)
    6 -> PitchClass(F, 1)
    7 -> PitchClass(G, 0)
    8 -> PitchClass(G, 1)
    9 -> PitchClass(A, 0)
    10 -> PitchClass(A, 1)
    _ -> PitchClass(B, 0)
  }
}

/// Respell a key centre only when its key signature would be unplayable.
///
/// Transposing concert F-sharp major for alto gives D-sharp major and its
/// nine sharps; this turns that into E-flat major, which is the same three
/// fingers and a great deal less ink. Keys of six accidentals or fewer are
/// left exactly as they were spelled.
pub fn simplify_key(pitch_class: PitchClass) -> PitchClass {
  let position = fifths(pitch_class)
  case position > 6, position < -6 {
    True, _ -> from_fifths(position - 12)
    _, True -> from_fifths(position + 12)
    _, _ -> pitch_class
  }
}

// --- Printing ----------------------------------------------------------------

/// The name of a letter.
pub fn letter_to_string(letter: Letter) -> String {
  case letter {
    C -> "C"
    D -> "D"
    E -> "E"
    F -> "F"
    G -> "G"
    A -> "A"
    B -> "B"
  }
}

/// An alteration as a run of `#` or `b`.
pub fn accidental_to_string(alteration: Int) -> String {
  case alteration {
    0 -> ""
    n if n > 0 -> string.repeat("#", n)
    n -> string.repeat("b", -n)
  }
}

/// A pitch class, such as `Bb` or `F#`.
pub fn class_to_string(pitch_class: PitchClass) -> String {
  letter_to_string(pitch_class.letter)
  <> accidental_to_string(pitch_class.alteration)
}

/// A pitch with its octave, such as `Bb3`.
pub fn to_string(pitch: Pitch) -> String {
  class_to_string(pitch.class) <> int.to_string(pitch.octave)
}

// --- Parsing -----------------------------------------------------------------

/// Parse a pitch class such as `C`, `bb`, `F#` or `Ebb`.
pub fn parse_class(text: String) -> Result(PitchClass, String) {
  case string.pop_grapheme(text) {
    Error(_) -> Error("expected a note name, found nothing")
    Ok(#(head, rest)) ->
      case parse_letter(head) {
        Error(_) -> Error("`" <> head <> "` is not a note name, use A to G")
        Ok(letter) ->
          case parse_accidentals(rest, 0) {
            Error(bad) ->
              Error("`" <> bad <> "` is not an accidental, use # or b")
            Ok(alteration) -> Ok(PitchClass(letter, alteration))
          }
      }
  }
}

/// Parse a pitch with an octave, such as `Bb3` or `C4`.
pub fn parse(text: String) -> Result(Pitch, String) {
  case split_trailing_digits(text) {
    #(_, "") -> Error("`" <> text <> "` needs an octave, such as `C4`")
    #(head, digits) ->
      case parse_class(head), int.parse(digits) {
        Ok(pitch_class), Ok(octave) -> Ok(Pitch(pitch_class, octave))
        Error(message), _ -> Error(message)
        _, Error(_) -> Error("`" <> digits <> "` is not an octave number")
      }
  }
}

fn parse_letter(text: String) -> Result(Letter, Nil) {
  case string.uppercase(text) {
    "C" -> Ok(C)
    "D" -> Ok(D)
    "E" -> Ok(E)
    "F" -> Ok(F)
    "G" -> Ok(G)
    "A" -> Ok(A)
    "B" -> Ok(B)
    _ -> Error(Nil)
  }
}

fn parse_accidentals(text: String, total: Int) -> Result(Int, String) {
  case string.pop_grapheme(text) {
    Error(_) -> Ok(total)
    Ok(#("#", rest)) -> parse_accidentals(rest, total + 1)
    Ok(#("\u{266F}", rest)) -> parse_accidentals(rest, total + 1)
    Ok(#("x", rest)) -> parse_accidentals(rest, total + 2)
    Ok(#("b", rest)) -> parse_accidentals(rest, total - 1)
    Ok(#("\u{266D}", rest)) -> parse_accidentals(rest, total - 1)
    Ok(#(other, _)) -> Error(other)
  }
}

fn split_trailing_digits(text: String) -> #(String, String) {
  let digits = string.reverse(take_digits(string.reverse(text), ""))
  let head_length = string.length(text) - string.length(digits)
  #(string.slice(text, 0, head_length), digits)
}

fn take_digits(text: String, acc: String) -> String {
  case string.pop_grapheme(text) {
    Ok(#(grapheme, rest)) ->
      case is_digit(grapheme) {
        True -> take_digits(rest, acc <> grapheme)
        False -> acc
      }
    Error(_) -> acc
  }
}

fn is_digit(grapheme: String) -> Bool {
  case grapheme {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}
