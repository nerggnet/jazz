import gleam/list
import gleam/option
import gleam/set
import gleam/string
import jazz/instrument
import jazz/notation
import jazz/pattern
import jazz/pitch.{type Pitch, C, D, PitchClass}
import jazz/progression
import jazz/render/abc
import jazz/scale

fn major(root: pitch.PitchClass) -> scale.Scale {
  scale.Scale(root, scale.Ionian)
}

fn spelled(notes: List(Pitch)) -> List(String) {
  list.map(notes, pitch.to_string)
}

pub fn every_pattern_is_reachable_by_name_test() {
  list.each(pattern.all(), fn(one) {
    assert pattern.from_string(pattern.id(one)) == Ok(one)
    assert pattern.name(one) != ""
    assert pattern.usage(one) != ""
  })
  assert pattern.from_string("nope") != Ok(pattern.Straight)
}

pub fn the_straight_pattern_is_the_scale_test() {
  // What the scale view has always shown: up an octave and back down,
  // touching the top note once.
  assert spelled(pattern.notes(pattern.Straight, major(PitchClass(C, 0))))
    == [
      "C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5", "B4", "A4", "G4", "F4",
      "E4", "D4", "C4",
    ]
}

pub fn thirds_climb_in_pairs_test() {
  let notes = spelled(pattern.notes(pattern.Thirds, major(PitchClass(C, 0))))
  // Up: each degree with the one two above it. Down: the same shape falling.
  assert list.take(notes, 6) == ["C4", "E4", "D4", "F4", "E4", "G4"]
  assert list.drop(notes, 16) |> list.take(4) == ["C5", "A4", "B4", "G4"]
  assert list.length(notes) == 32
}

pub fn a_digital_pattern_is_one_two_three_five_test() {
  let notes = spelled(pattern.notes(pattern.Digital, major(PitchClass(C, 0))))
  assert list.take(notes, 8) == ["C4", "D4", "E4", "G4", "D4", "E4", "F4", "A4"]
}

pub fn a_pattern_reaches_below_the_root_coming_down_test() {
  // Descending thirds from the root need the degree under it, or the shape
  // breaks at the bottom.
  let notes = pattern.notes(pattern.Thirds, major(PitchClass(C, 0)))
  let assert Ok(last) = list.last(notes)
  assert pitch.to_string(last) == "A3"
}

pub fn every_pattern_in_every_scale_stays_in_the_scale_test() {
  // A pattern rearranges a scale; it never invents a note.
  list.each(scale.all_kinds(), fn(kind) {
    let subject = scale.Scale(PitchClass(D, 0), kind)
    let inside =
      set.from_list(list.map(scale.notes(subject), pitch.class_to_string))
    list.each(pattern.all(), fn(shape) {
      list.each(pattern.notes(shape, subject), fn(one) {
        assert set.contains(inside, pitch.class_to_string(one.class))
      })
    })
  })
}

pub fn every_pattern_comes_out_in_whole_bars_test() {
  // Exercises are laid end to end when they run round the keys, so one that
  // does not fill its bars pushes the next key off the downbeat.
  let assert Ok(alto) = instrument.find("alto")
  list.each(pattern.all(), fn(shape) {
    let score =
      notation.from_pattern(
        major(PitchClass(C, 0)),
        shape,
        [PitchClass(C, 0)],
        alto,
        notation.default_tempo,
      )
    let part = notation.only_part(score)
    list.each(part.measures, fn(one) {
      let filled =
        list.fold(one.events, 0, fn(sum, event) {
          sum + notation.duration_of(event)
        })
      assert filled == 8
    })
  })
}

pub fn round_the_keys_announces_each_one_test() {
  let assert Ok(alto) = instrument.find("alto")
  let score =
    notation.from_pattern(
      major(PitchClass(C, 0)),
      pattern.Thirds,
      progression.cycle_of_fourths(PitchClass(C, 0)),
      alto,
      notation.default_tempo,
    )
  let written = abc.render(score)

  // Twelve keys, and eleven of them have to say so part way through: the
  // first is already in the header.
  let changes =
    notation.only_part(score).measures
    |> list.filter(fn(one) { one.key != option.None })
  assert list.length(changes) == 11
  assert string.contains(written, "[K:")
  assert string.contains(written, "round the keys")

  // Each key gets the same amount of room, and nobody starts mid bar.
  assert list.length(notation.only_part(score).measures) == 12 * 4
}

pub fn no_key_asks_for_more_than_six_accidentals_test() {
  // A mode reaches further round the line of fifths than its root does, so
  // the instrument's own respelling rule is not enough on its own: concert E
  // read by an alto is Db, and Db Dorian wants seven flats where C# Dorian
  // wants five sharps.
  list.each(instrument.all(), fn(player) {
    list.each([scale.Ionian, scale.Dorian, scale.Altered], fn(kind) {
      let score =
        notation.from_pattern(
          scale.Scale(PitchClass(C, 0), kind),
          pattern.Thirds,
          progression.cycle_of_fourths(PitchClass(C, 0)),
          player,
          notation.default_tempo,
        )
      let part = notation.only_part(score)
      let signatures = [
        part.signature,
        ..list.filter_map(part.measures, fn(one) {
          option.to_result(one.key, Nil)
        })
      ]
      list.each(signatures, fn(one) {
        assert one >= -6 && one <= 6
      })
    })
  })
}
