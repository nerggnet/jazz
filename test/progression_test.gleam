import gleam/int
import gleam/list
import gleam/string
import jazz/chord
import jazz/interval
import jazz/pitch.{type PitchClass, B, C, F, PitchClass}
import jazz/progression

fn symbols(built: progression.Progression) -> String {
  built
  |> progression.chords
  |> list.map(chord.to_string)
  |> string.join(" ")
}

fn numerals(built: progression.Progression) -> String {
  built
  |> progression.chords
  |> list.map(progression.roman(built.key, _))
  |> string.join(" ")
}

fn in_key(id: String, key: PitchClass) -> progression.Progression {
  let assert Ok(built) = progression.build(id, key)
  built
}

pub fn two_five_one_test() {
  assert symbols(in_key("ii-V-I", PitchClass(C, 0))) == "Dm7 G7 Cmaj7 Cmaj7"
  assert symbols(in_key("ii-V-I", PitchClass(B, -1))) == "Cm7 F7 Bbmaj7 Bbmaj7"
  assert numerals(in_key("ii-V-I", PitchClass(C, 0))) == "iim7 V7 Imaj7 Imaj7"
}

pub fn minor_two_five_one_test() {
  assert symbols(in_key("minor-ii-V-i", PitchClass(C, 0)))
    == "Dm7b5 G7alt Cm7 Cm7"
  assert numerals(in_key("minor-ii-V-i", PitchClass(C, 0)))
    == "iim7b5 V7alt im7 im7"
}

pub fn blues_test() {
  assert symbols(in_key("blues", PitchClass(F, 0)))
    == "F7 Bb7 F7 Cm7 F7 Bb7 Bdim7 F7 Am7 D7 Gm7 C7 F7 D7 Gm7 C7"
  // The bar six diminished chord is built on the raised fourth.
  assert numerals(in_key("blues", PitchClass(F, 0)))
    == "I7 IV7 I7 vm7 I7 IV7 #ivdim7 I7 iiim7 VI7 iim7 V7 I7 VI7 iim7 V7"
}

pub fn tritone_sub_shares_guide_tones_test() {
  // The whole point of the substitute: G7 and Db7 share a third and a seventh,
  // swapped over, which is why a line over one works over the other.
  let assert Ok(g7) = chord.parse("G7")
  let assert Ok(db7) = chord.parse("Db7")
  let sounds = fn(notes) {
    notes |> list.map(pitch.class_semitones) |> list.sort(int.compare)
  }
  assert sounds(chord.guide_tones(g7)) == sounds(chord.guide_tones(db7))
}

pub fn coltrane_test() {
  // Giant Steps, bars one to four, as written.
  assert symbols(in_key("coltrane", PitchClass(B, 0)))
    == "Bmaj7 D7 Gmaj7 Bb7 Ebmaj7 Am7 D7"
}

pub fn every_catalogue_entry_builds_test() {
  // Nothing can be listed that cannot be built, in any of the twelve keys.
  list.each(progression.catalogue(), fn(entry) {
    list.each(progression.cycle_of_fourths(PitchClass(C, 0)), fn(key) {
      let assert Ok(built) = progression.build(entry.0, key)
      assert progression.chords(built) != []
    })
  })
}

pub fn transposing_a_progression_keeps_its_numerals_test() {
  let original = in_key("rhythm-changes-a", PitchClass(B, -1))
  let moved = progression.transpose(original, interval.degree(6, 0))
  assert numerals(original) == numerals(moved)
  assert pitch.class_to_string(moved.key) == "G"
}

pub fn cycle_of_fourths_test() {
  assert progression.cycle_of_fourths(PitchClass(C, 0))
    |> list.map(pitch.class_to_string)
    |> string.join(" ")
    == "C F Bb Eb Ab Db Gb B E A D G"
  assert progression.cycle_of_fifths(PitchClass(C, 0))
    |> list.map(pitch.class_to_string)
    |> string.join(" ")
    == "C G D A E B F# Db Ab Eb Bb F"
}
