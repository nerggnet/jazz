//// Intervals as a diatonic size plus a chromatic size.
////
//// Storing both is what makes transposition spelling-correct: the diatonic
//// size decides the letter of the result, the chromatic size decides its
//// accidental. An augmented fourth and a diminished fifth are six semitones
//// each, but only one of them turns `F` into `B`.

import gleam/int
import gleam/string
import jazz/internal/num
import jazz/pitch.{type Pitch, type PitchClass, Pitch}

/// An interval. Build one with `degree`, or with `from_quality` when parsing
/// something a human typed.
pub opaque type Interval {
  Interval(steps: Int, semitones: Int)
}

/// How an interval is named. Unisons, fourths, fifths and octaves are perfect;
/// everything else is major or minor.
pub type Quality {
  Perfect
  Major
  Minor
  Augmented(Int)
  Diminished(Int)
}

// --- Construction ------------------------------------------------------------

/// An interval written the way jazz formulas are written: a scale degree and
/// how far it is bent. `degree(3, -1)` is a minor third, `degree(11, 1)` is a
/// sharp eleventh, `degree(7, -2)` is the diminished seventh of a `dim7` chord.
///
/// The degree is one-based, so `degree(1, 0)` is a unison and `degree(8, 0)` is
/// an octave. Degrees above 8 stay compound rather than folding down.
pub fn degree(number: Int, alteration: Int) -> Interval {
  let steps = number - 1
  Interval(steps, diatonic_semitones(steps) + alteration)
}

/// An interval from a degree and a quality, rejecting combinations that do not
/// name anything, such as a major fifth.
pub fn from_quality(number: Int, quality: Quality) -> Result(Interval, Nil) {
  let steps = number - 1
  case is_perfect_class(steps), quality {
    True, Perfect -> Ok(degree(number, 0))
    True, Augmented(n) -> Ok(degree(number, n))
    True, Diminished(n) -> Ok(degree(number, -n))
    False, Major -> Ok(degree(number, 0))
    False, Minor -> Ok(degree(number, -1))
    False, Augmented(n) -> Ok(degree(number, n))
    False, Diminished(n) -> Ok(degree(number, -n - 1))
    _, _ -> Error(Nil)
  }
}

/// A whole number of octaves.
pub fn octaves(count: Int) -> Interval {
  Interval(7 * count, 12 * count)
}

// --- Measurement -------------------------------------------------------------

/// The one-based diatonic number: 3 for any kind of third, 9 for any ninth.
pub fn number(interval: Interval) -> Int {
  interval.steps + 1
}

/// How far the interval is bent away from its major or perfect form.
pub fn alteration(interval: Interval) -> Int {
  interval.semitones - diatonic_semitones(interval.steps)
}

/// The size of the interval in semitones.
pub fn semitones(interval: Interval) -> Int {
  interval.semitones
}

/// The size of the interval in diatonic steps, counting a unison as 0.
pub fn steps(interval: Interval) -> Int {
  interval.steps
}

/// The name of the interval's quality.
pub fn quality(interval: Interval) -> Quality {
  let offset = alteration(interval)
  case is_perfect_class(interval.steps), offset {
    True, 0 -> Perfect
    True, n if n > 0 -> Augmented(n)
    True, n -> Diminished(-n)
    False, 0 -> Major
    False, -1 -> Minor
    False, n if n > 0 -> Augmented(n)
    False, n -> Diminished(-n - 1)
  }
}

fn is_perfect_class(steps: Int) -> Bool {
  case num.modulo(steps, 7) {
    0 | 3 | 4 -> True
    _ -> False
  }
}

fn diatonic_semitones(steps: Int) -> Int {
  let within_octave = case num.modulo(steps, 7) {
    0 -> 0
    1 -> 2
    2 -> 4
    3 -> 5
    4 -> 7
    5 -> 9
    _ -> 11
  }
  12 * num.floor_div(steps, 7) + within_octave
}

// --- Arithmetic --------------------------------------------------------------

/// Stack one interval on top of another.
pub fn add(a: Interval, b: Interval) -> Interval {
  Interval(a.steps + b.steps, a.semitones + b.semitones)
}

/// Point an interval the other way, for transposing downwards.
pub fn negate(interval: Interval) -> Interval {
  Interval(-interval.steps, -interval.semitones)
}

/// Fold a compound interval down into a single octave, so a major ninth
/// becomes a major second.
pub fn simple(interval: Interval) -> Interval {
  degree(num.modulo(interval.steps, 7) + 1, alteration(interval))
}

// --- Transposition -----------------------------------------------------------

/// Transpose a pitch, keeping the spelling that the interval implies.
///
/// The diatonic size picks the letter and the semitone size fills in whatever
/// accidental is needed to reach it, so `F#` up a major sixth is `D#` and not
/// `Eb`, however much you might prefer to read the latter.
pub fn transpose(from: Pitch, by: Interval) -> Pitch {
  pitch.from_position(
    pitch.diatonic_position(from) + by.steps,
    pitch.to_midi(from) + by.semitones,
  )
}

/// Transpose a pitch class, discarding the octave.
pub fn transpose_class(from: PitchClass, by: Interval) -> PitchClass {
  transpose(Pitch(from, 4), by).class
}

/// The interval from one pitch up to another. Descending pairs give a negative
/// interval, which `transpose` will happily undo.
pub fn between(from: Pitch, to: Pitch) -> Interval {
  Interval(
    pitch.diatonic_position(to) - pitch.diatonic_position(from),
    pitch.to_midi(to) - pitch.to_midi(from),
  )
}

// --- Printing ----------------------------------------------------------------

/// The interval in shorthand, such as `M3`, `m7`, `P5`, `A4` or `d5`.
pub fn to_string(interval: Interval) -> String {
  let prefix = case quality(interval) {
    Perfect -> "P"
    Major -> "M"
    Minor -> "m"
    Augmented(n) -> string.repeat("A", n)
    Diminished(n) -> string.repeat("d", n)
  }
  prefix <> int.to_string(number(interval))
}

/// The interval as a jazz formula degree, such as `1`, `b3`, `#11`.
pub fn to_degree_string(interval: Interval) -> String {
  pitch.accidental_to_string(alteration(interval))
  <> int.to_string(number(interval))
}
