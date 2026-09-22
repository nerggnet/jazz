import gleam/list
import gleam/string
import jazz/chord
import jazz/pitch

fn symbol(text: String) -> String {
  let assert Ok(parsed) = chord.parse(text)
  chord.to_string(parsed)
}

fn note_names(text: String) -> String {
  let assert Ok(parsed) = chord.parse(text)
  chord.notes(parsed)
  |> list.map(pitch.class_to_string)
  |> string.join(" ")
}

pub fn dialects_agree_test() {
  // The same chord, written the six ways players actually write it.
  assert symbol("Cm7") == "Cm7"
  assert symbol("Cmi7") == "Cm7"
  assert symbol("Cmin7") == "Cm7"
  assert symbol("C-7") == "Cm7"
  assert symbol("CMaj7") == "Cmaj7"
  assert symbol("C^7") == "Cmaj7"
  assert symbol("C\u{0394}7") == "Cmaj7"
  assert symbol("CM7") == "Cmaj7"
  assert symbol("C^") == "Cmaj7"
}

pub fn half_and_fully_diminished_test() {
  assert symbol("Cm7b5") == "Cm7b5"
  assert symbol("C\u{00F8}") == "Cm7b5"
  assert symbol("C-7b5") == "Cm7b5"
  assert symbol("Cdim7") == "Cdim7"
  assert symbol("C\u{00B0}7") == "Cdim7"
  assert note_names("Cm7b5") == "C Eb Gb Bb"
  assert note_names("Cdim7") == "C Eb Gb Bbb"
}

pub fn extensions_collapse_test() {
  // A thirteenth implies the ninth, so the symbol does not spell it out.
  assert symbol("C13") == "C13"
  assert symbol("Cm11") == "Cm11"
  assert symbol("Cmaj9") == "Cmaj9"
  assert symbol("C6") == "C6"
  assert symbol("C6/9") == "C6/9"
  assert note_names("C13") == "C E G Bb D A"
  assert note_names("C6/9") == "C E G A D"
}

pub fn alterations_test() {
  assert symbol("Bb7#9") == "Bb7#9"
  assert symbol("C7b9") == "C7b9"
  assert symbol("Cmaj7#11") == "Cmaj7#11"
  assert symbol("C7#5") == "C7#5"
  assert symbol("C7b5") == "C7b5"
  assert note_names("Bb7#9") == "Bb D F Ab C#"
  assert note_names("C7#5") == "C E G# Bb"
}

pub fn altered_dominant_test() {
  // `alt` expands to every bent extension, and comes back as `alt`.
  assert symbol("C7alt") == "C7alt"
  assert symbol("Calt") == "C7alt"
  assert note_names("C7alt") == "C E Bb Db D# F# Ab"
}

pub fn sus_and_slash_test() {
  assert symbol("C7sus4") == "C7sus4"
  assert symbol("Csus4") == "Csus4"
  assert symbol("Am7/D") == "Am7/D"
  assert symbol("Cm(maj7)") == "Cm(maj7)"
  assert note_names("C7sus4") == "C F G Bb"
}

pub fn flat_roots_survive_test() {
  // The `b` right after the letter is a flat, even with a digit behind it.
  assert symbol("Bb7") == "Bb7"
  assert symbol("Ebmaj7") == "Ebmaj7"
  assert symbol("Dbm7") == "Dbm7"
  assert symbol("F#7b9") == "F#7b9"
  assert note_names("Ebmaj7") == "Eb G Bb D"
}

pub fn guide_tones_test() {
  let assert Ok(g7) = chord.parse("G7")
  assert list.map(chord.guide_tones(g7), pitch.class_to_string) == ["B", "F"]
  let assert Ok(cmaj7) = chord.parse("Cmaj7")
  assert list.map(chord.guide_tones(cmaj7), pitch.class_to_string) == ["E", "B"]
}

pub fn rejects_nonsense_test() {
  let assert Error(_) = chord.parse("Hm7")
  let assert Error(_) = chord.parse("Cm7zz")
  let assert Error(_) = chord.parse("")
}
