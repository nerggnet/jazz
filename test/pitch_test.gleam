import jazz/interval
import jazz/pitch.{A, B, C, D, E, F, G, Pitch, PitchClass}

fn transpose_class(name: String, number: Int, alteration: Int) -> String {
  let assert Ok(root) = pitch.parse_class(name)
  interval.transpose_class(root, interval.degree(number, alteration))
  |> pitch.class_to_string
}

pub fn letter_round_trip_test() {
  assert pitch.letter_at(pitch.diatonic_index(F)) == F
  assert pitch.letter_at(-1) == B
  assert pitch.letter_at(7) == C
}

pub fn midi_numbers_test() {
  assert pitch.to_midi(pitch.note(C, 0, 4)) == 60
  assert pitch.to_midi(pitch.note(A, 0, 4)) == 69
  // The octave follows the letter, so Cb4 is spelled up here but sounds below.
  assert pitch.to_midi(pitch.note(C, -1, 4)) == 59
  assert pitch.to_midi(pitch.note(B, 1, 3)) == 60
}

pub fn spelling_survives_transposition_test() {
  // The whole point of the representation: same sound, different letter.
  assert transpose_class("F#", 6, 0) == "D#"
  assert transpose_class("Gb", 6, 0) == "Eb"
  assert transpose_class("C", 3, -1) == "Eb"
  assert transpose_class("C", 2, 1) == "D#"
  assert transpose_class("B", 3, 0) == "D#"
  assert transpose_class("Eb", 5, 0) == "Bb"
}

pub fn transposition_is_reversible_test() {
  let up = interval.degree(6, 0)
  let start = pitch.note(F, 1, 4)
  assert start
    |> interval.transpose(up)
    |> interval.transpose(interval.negate(up))
    == start
}

pub fn interval_between_test() {
  let from = pitch.note(C, 0, 4)
  let to = pitch.note(A, 0, 4)
  assert interval.to_string(interval.between(from, to)) == "M6"
  assert interval.to_string(interval.between(
      pitch.note(F, 0, 4),
      pitch.note(B, 0, 4),
    ))
    == "A4"
  assert interval.to_string(interval.between(
      pitch.note(F, 0, 4),
      pitch.note(C, -1, 5),
    ))
    == "d5"
}

pub fn interval_naming_test() {
  assert interval.to_string(interval.degree(1, 0)) == "P1"
  assert interval.to_string(interval.degree(7, -1)) == "m7"
  assert interval.to_string(interval.degree(7, -2)) == "d7"
  assert interval.to_string(interval.degree(9, 0)) == "M9"
  assert interval.to_string(interval.degree(13, -1)) == "m13"
  assert interval.to_degree_string(interval.degree(11, 1)) == "#11"
}

pub fn line_of_fifths_test() {
  assert pitch.fifths(PitchClass(C, 0)) == 0
  assert pitch.fifths(PitchClass(D, 0)) == 2
  assert pitch.fifths(PitchClass(E, -1)) == -3
  assert pitch.fifths(PitchClass(D, 1)) == 9
  assert pitch.from_fifths(-3) == PitchClass(E, -1)
  assert pitch.from_fifths(6) == PitchClass(F, 1)
}

pub fn unreadable_keys_get_respelled_test() {
  // D# major has nine sharps; Eb major is the same notes and far less ink.
  assert pitch.simplify_key(PitchClass(D, 1)) == PitchClass(E, -1)
  // Six accidentals is still readable, so leave it alone.
  assert pitch.simplify_key(PitchClass(F, 1)) == PitchClass(F, 1)
  assert pitch.simplify_key(PitchClass(G, -1)) == PitchClass(G, -1)
  assert pitch.simplify_key(PitchClass(G, 0)) == PitchClass(G, 0)
}

pub fn parsing_test() {
  assert pitch.parse_class("Bb") == Ok(PitchClass(B, -1))
  assert pitch.parse_class("f#") == Ok(PitchClass(F, 1))
  assert pitch.parse_class("Ebb") == Ok(PitchClass(E, -2))
  assert pitch.parse("Bb3") == Ok(Pitch(PitchClass(B, -1), 3))
  assert pitch.parse("C12") == Ok(Pitch(PitchClass(C, 0), 12))
  let assert Error(_) = pitch.parse_class("H")
  let assert Error(_) = pitch.parse("C")
  assert pitch.class_to_string(PitchClass(G, -1)) == "Gb"
}
