import gleam/int
import gleam/list
import gleam/string
import jazz/pitch.{type PitchClass, A, B, C, D, F, G, PitchClass}
import jazz/scale

fn notes(root: PitchClass, kind: scale.ScaleKind) -> String {
  scale.Scale(root, kind)
  |> scale.notes
  |> list.map(pitch.class_to_string)
  |> string.join(" ")
}

pub fn major_modes_test() {
  assert notes(PitchClass(C, 0), scale.Ionian) == "C D E F G A B"
  assert notes(PitchClass(D, 0), scale.Dorian) == "D E F G A B C"
  assert notes(PitchClass(F, 0), scale.Lydian) == "F G A B C D E"
  assert notes(PitchClass(G, 0), scale.Mixolydian) == "G A B C D E F"
  assert notes(PitchClass(B, 0), scale.Locrian) == "B C D E F G A"
}

pub fn every_scale_uses_seven_letters_or_repeats_deliberately_test() {
  // A seven note scale must use each letter once. This is the property that
  // stops Ab major coming out as G# A# C C# D# F G.
  let seven_note =
    list.filter(scale.all_kinds(), fn(kind) { scale.size(kind) == 7 })
  list.each(seven_note, fn(kind) {
    let letters =
      scale.Scale(PitchClass(A, -1), kind)
      |> scale.notes
      |> list.map(fn(note) { pitch.letter_to_string(note.letter) })
    assert list.length(list.unique(letters)) == 7
  })
}

pub fn awkward_keys_are_spelled_properly_test() {
  assert notes(PitchClass(A, -1), scale.Ionian) == "Ab Bb C Db Eb F G"
  assert notes(PitchClass(C, 1), scale.Ionian) == "C# D# E# F# G# A# B#"
  assert notes(PitchClass(G, -1), scale.Lydian) == "Gb Ab Bb C Db Eb F"
}

pub fn jazz_scales_test() {
  assert notes(PitchClass(C, 0), scale.Altered) == "C Db Eb Fb Gb Ab Bb"
  assert notes(PitchClass(C, 0), scale.MelodicMinor) == "C D Eb F G A B"
  assert notes(PitchClass(C, 0), scale.LydianDominant) == "C D E F# G A Bb"
  assert notes(PitchClass(C, 0), scale.WholeTone) == "C D E F# G# A#"
  assert notes(PitchClass(C, 0), scale.DiminishedHalfWhole)
    == "C Db D# E F# G A Bb"
  assert notes(PitchClass(C, 0), scale.Blues) == "C Eb F F# G Bb"
  assert notes(PitchClass(C, 0), scale.BebopDominant) == "C D E F G A Bb B"
}

pub fn bebop_scales_have_eight_notes_test() {
  // The extra note is the whole point: chord tones land on the beat.
  assert scale.size(scale.BebopDominant) == 8
  assert scale.size(scale.BebopMajor) == 8
  assert scale.size(scale.BebopDorian) == 8
  assert scale.size(scale.DiminishedHalfWhole) == 8
}

pub fn altered_scale_is_melodic_minor_a_semitone_up_test() {
  // G altered and Ab melodic minor are the same notes, which is the trick
  // every player learns for altered dominants.
  let altered =
    scale.Scale(PitchClass(G, 0), scale.Altered)
    |> scale.notes
    |> list.map(pitch.class_semitones)
    |> list.sort(compare)
  let melodic =
    scale.Scale(PitchClass(A, -1), scale.MelodicMinor)
    |> scale.notes
    |> list.map(pitch.class_semitones)
    |> list.sort(compare)
  assert altered == melodic
}

fn compare(a: Int, b: Int) {
  int.compare(a, b)
}

pub fn lookup_accepts_nicknames_test() {
  assert scale.kind_from_string("major") == Ok(scale.Ionian)
  assert scale.kind_from_string("Melodic Minor") == Ok(scale.MelodicMinor)
  assert scale.kind_from_string("alt") == Ok(scale.Altered)
  assert scale.kind_from_string("half-whole") == Ok(scale.DiminishedHalfWhole)
  let assert Error(_) = scale.kind_from_string("phrygian-lydian")
}
