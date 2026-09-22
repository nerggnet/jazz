import gleam/list
import gleam/string
import jazz/instrument
import jazz/interval
import jazz/pitch.{A, B, C, D, F, G, PitchClass}
import jazz/scale

fn written(name: String, note: String) -> String {
  let assert Ok(player) = instrument.find(name)
  let assert Ok(concert) = pitch.parse_class(note)
  instrument.write_class(player, concert)
  |> pitch.class_to_string
}

pub fn transposition_directions_test() {
  // Concert C is A on alto, D on tenor, D on trumpet.
  assert written("alto", "C") == "A"
  assert written("tenor", "C") == "D"
  assert written("soprano", "C") == "D"
  assert written("bari", "C") == "A"
  assert written("trumpet", "C") == "D"
  assert written("concert", "C") == "C"
  // And the horn's own key sounds as the concert key it is named for.
  assert written("alto", "Eb") == "C"
  assert written("tenor", "Bb") == "C"
}

pub fn octaves_are_kept_test() {
  let assert Ok(tenor) = instrument.find("tenor")
  let assert Ok(alto) = instrument.find("alto")
  // Tenor sounds a major ninth below, not a major second.
  assert instrument.write(tenor, pitch.note(C, 0, 3)) == pitch.note(D, 0, 4)
  assert instrument.sounds(tenor, pitch.note(D, 0, 4)) == pitch.note(C, 0, 3)
  // Alto sounds a major sixth below.
  assert instrument.write(alto, pitch.note(C, 0, 4)) == pitch.note(A, 0, 4)
}

pub fn writing_then_sounding_round_trips_test() {
  let note = pitch.note(F, 1, 4)
  list.each(instrument.all(), fn(player) {
    assert instrument.sounds(player, instrument.write(player, note)) == note
  })
}

pub fn range_test() {
  let assert Ok(alto) = instrument.find("alto")
  assert instrument.in_range(alto, pitch.note(B, -1, 3))
  assert instrument.in_range(alto, pitch.note(F, 0, 6))
  assert !instrument.in_range(alto, pitch.note(A, 0, 3))
  assert !instrument.in_range(alto, pitch.note(G, 0, 6))
  // Out of range notes are folded into it by whole octaves, keeping spelling.
  assert instrument.fit_to_range(alto, pitch.note(D, -1, 2))
    == pitch.note(D, -1, 4)
  assert instrument.fit_to_range(alto, pitch.note(C, 1, 7))
    == pitch.note(C, 1, 6)
}

pub fn unreadable_keys_are_nudged_test() {
  let assert Ok(alto) = instrument.find("alto")
  let assert Ok(concert) = instrument.find("concert")
  let f_sharp = PitchClass(F, 1)
  // Concert F# for alto is literally D# major, nine sharps. Write Eb instead.
  let shift = instrument.write_interval_for_key(alto, f_sharp)
  assert pitch.class_to_string(interval.transpose_class(f_sharp, shift)) == "Eb"
  // A key that transposes to something readable is left alone.
  let shift = instrument.write_interval_for_key(alto, PitchClass(B, -1))
  assert pitch.class_to_string(interval.transpose_class(
      PitchClass(B, -1),
      shift,
    ))
    == "G"
  // Concert pitch never needs nudging.
  let shift = instrument.write_interval_for_key(concert, f_sharp)
  assert pitch.class_to_string(interval.transpose_class(f_sharp, shift)) == "F#"
}

pub fn the_nudge_is_applied_to_every_note_test() {
  let assert Ok(alto) = instrument.find("alto")
  let f_sharp = PitchClass(F, 1)
  let shift = instrument.write_interval_for_key(alto, f_sharp)
  // Every note moves by the same interval, so no part mixes flats with sharps.
  assert scale.Scale(f_sharp, scale.Ionian)
    |> scale.notes
    |> list.map(interval.transpose_class(_, shift))
    |> list.map(pitch.class_to_string)
    |> string.join(" ")
    == "Eb F G Ab Bb C D"
}
