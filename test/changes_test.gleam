import gleam/list
import gleam/string
import jazz/chord
import jazz/pitch
import jazz/progression

fn shape(text: String) -> String {
  let assert Ok(parsed) = progression.parse(text)
  parsed.bars
  |> list.map(fn(one) {
    one.chords |> list.map(chord.to_string) |> string.join(" ")
  })
  |> string.join(" | ")
}

fn key_of(text: String) -> String {
  let assert Ok(parsed) = progression.parse(text)
  pitch.class_to_string(parsed.key)
}

fn bars(text: String) -> Int {
  let assert Ok(parsed) = progression.parse(text)
  list.length(parsed.bars)
}

pub fn bars_come_from_bar_lines_test() {
  assert shape("| Dm7 | G7 | Cmaj7 |") == "Dm7 | G7 | Cmaj7"
  // Chords sharing a bar stay in that bar.
  assert shape("| Cm7 F7 | Bbmaj7 |") == "Cm7 F7 | Bbmaj7"
  assert bars("| Cm7 F7 | Bbmaj7 |") == 2
}

pub fn the_outer_bar_lines_are_optional_test() {
  assert shape("Dm7 | G7 | Cmaj7") == shape("| Dm7 | G7 | Cmaj7 |")
  assert shape("|Dm7|G7|Cmaj7|") == shape("| Dm7 | G7 | Cmaj7 |")
  // Heavier bar lines are still just bar lines.
  assert shape("| Dm7 | G7 || Cmaj7 |]") == "Dm7 | G7 | Cmaj7"
}

pub fn without_bar_lines_each_chord_gets_a_bar_test() {
  // So the short way of asking still means what it looks like.
  assert shape("Dm7 G7 Cmaj7") == "Dm7 | G7 | Cmaj7"
  assert bars("Dm7 G7 Cmaj7") == 3
}

pub fn a_percent_holds_the_bar_before_test() {
  assert shape("| Dm7 | % | G7 | % |") == "Dm7 | Dm7 | G7 | G7"
  assert shape("| Cm7 F7 | % |") == "Cm7 F7 | Cm7 F7"
  // Nothing between two bar lines makes no bar, because that is what a
  // trailing bar line and a double bar line look like.
  assert shape("| Dm7 | | G7 |") == "Dm7 | G7"
}

pub fn a_repeat_is_played_twice_test() {
  assert shape("|: Dm7 | G7 :|") == "Dm7 | G7 | Dm7 | G7"
  assert shape("| Cmaj7 |: Dm7 | G7 :| Cmaj7 |")
    == "Cmaj7 | Dm7 | G7 | Dm7 | G7 | Cmaj7"
  // Sixteen bars of typing, thirty two bars of tune.
  assert bars("|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|") == 16
}

pub fn newlines_are_just_spaces_test() {
  assert shape("| Dm7 | G7 |\n| Cmaj7 | Cmaj7 |") == "Dm7 | G7 | Cmaj7 | Cmaj7"
}

pub fn the_key_comes_from_the_last_chord_test() {
  assert key_of("| Dm7 | G7 | Cmaj7 |") == "C"
  assert key_of("| Cm7 | F7 | Bbmaj7 |") == "Bb"
  assert key_of("| Am7b5 | D7alt | Gm6 |") == "G"
}

pub fn a_whole_tune_test() {
  // Sixteen bars of a minor blues, with the last four written once.
  let text =
    "|: Cm7 | Fm7 | Cm7 | Cm7 |
      | Fm7 | Fm7 | Cm7 | Cm7 :|
      | Abmaj7 | G7alt | Cm7 | Am7b5 D7alt |"
  assert bars(text) == 20
  let assert Ok(parsed) = progression.parse(text)
  assert list.length(progression.chords(parsed)) == 21
  assert pitch.class_to_string(parsed.key) == "D"
}

pub fn complaints_are_specific_test() {
  let assert Error(first) = progression.parse("| Dm7 | H7 | Cmaj7 |")
  assert string.contains(first, "bar 2")
  assert string.contains(first, "not a note name")

  let assert Error(unclosed) = progression.parse("|: Dm7 | G7")
  assert string.contains(unclosed, "never closed")

  let assert Error(unopened) = progression.parse("| Dm7 | G7 :|")
  assert string.contains(unopened, "no `|:`")

  let assert Error(nested) = progression.parse("|: Dm7 |: G7 :|")
  assert string.contains(nested, "inside another")

  let assert Error(stray) = progression.parse("| Dm7 : G7 |")
  assert string.contains(stray, "beside a bar line")

  let assert Error(leading) = progression.parse("| % | G7 |")
  assert string.contains(leading, "there is none")

  let assert Error(shared) = progression.parse("| Dm7 % | G7 |")
  assert string.contains(shared, "on its own")

  let assert Error(empty) = progression.parse("   ")
  assert string.contains(empty, "no chords found")
}
