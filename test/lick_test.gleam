import gleam/list
import gleam/string
import jazz/chord
import jazz/instrument
import jazz/interval
import jazz/lick
import jazz/pitch.{type Pitch, C, PitchClass}
import jazz/progression

fn line(level: lick.Level, seed: Int) -> lick.Line {
  let assert Ok(changes) = progression.build("ii-V-I", PitchClass(C, 0))
  lick.over_progression(changes, lick.options(level, seed))
}

fn notes(subject: lick.Line) -> List(Pitch) {
  lick.pitches(subject)
}

fn devices(subject: lick.Line) -> String {
  subject.segments |> list.map(fn(one) { one.device }) |> string.join(" | ")
}

pub fn the_same_seed_gives_the_same_line_test() {
  assert notes(line(lick.Intermediate, 42))
    == notes(line(lick.Intermediate, 42))
  assert notes(line(lick.Intermediate, 42))
    != notes(line(lick.Intermediate, 43))
}

pub fn the_line_fills_the_changes_test() {
  // Four bars of four four is thirty two eighth notes, no more and no less.
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 2, 3, 7, 99], fn(seed) {
      assert lick.duration(line(level, seed)) == 4 * lick.bar
    })
  })
}

pub fn every_target_is_a_chord_tone_test() {
  // The note on the downbeat is the whole point; it has to belong to the chord.
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 5, 12, 64], fn(seed) {
      list.each(line(level, seed).segments, fn(segment) {
        let assert [lick.Tone(first, _), ..] = segment.events
        let tones = chord.notes(segment.chord)
        assert list.any(tones, fn(one) { pitch.same(one, first.class) })
      })
    })
  })
}

pub fn lines_stay_in_the_range_they_were_given_test() {
  // Approach notes may reach a tone below a target sitting on the floor of
  // the range, which is why the tolerance is not zero.
  let settings = lick.options(lick.Advanced, 3)
  let assert Ok(changes) = progression.build("blues", PitchClass(C, 0))
  let subject = lick.over_progression(changes, settings)
  let low = pitch.to_midi(settings.low) - 2
  let high = pitch.to_midi(settings.high)
  list.each(notes(subject), fn(one) {
    assert pitch.to_midi(one) >= low && pitch.to_midi(one) <= high
  })
}

pub fn beginners_are_not_handed_enclosures_test() {
  list.each([1, 2, 3, 4, 5, 6, 7, 8], fn(seed) {
    let simple = devices(line(lick.Beginner, seed))
    assert !string.contains(simple, "enclosure")
    assert !string.contains(simple, "double chromatic")
    assert !string.contains(simple, "1235")
  })
}

pub fn advanced_lines_use_the_whole_vocabulary_test() {
  let everything =
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    |> list.map(fn(seed) { devices(line(lick.Advanced, seed)) })
    |> string.join(" ")
  assert string.contains(everything, "enclosure")
  assert string.contains(everything, "1235")
  assert string.contains(everything, "chord tones down")
}

pub fn transposing_a_line_is_reversible_test() {
  let original = line(lick.Intermediate, 11)
  let up = interval.degree(6, 0)
  let there_and_back =
    lick.transpose(lick.transpose(original, up), interval.negate(up))
  assert notes(there_and_back) == notes(original)
}

pub fn double_accidentals_are_respelled_test() {
  // Transposing up a major sixth is what turns A# into F##.
  let written =
    line(lick.Advanced, 7)
    |> lick.transpose(interval.degree(6, 0))
    |> lick.simplify_spelling
  list.each(notes(written), fn(one) {
    assert one.class.alteration >= -1 && one.class.alteration <= 1
  })
}

pub fn generated_lines_fit_the_horn_test() {
  // The default range is taken from the instrument, so a written line lands
  // where the player can actually play it.
  list.each(instrument.all(), fn(player) {
    let #(low, high) = instrument.comfortable_range(player)
    let settings = lick.Options(lick.Intermediate, 5, low, high)
    let assert Ok(changes) = progression.build("turnaround", PitchClass(C, 0))
    let subject =
      lick.over_progression(changes, settings)
      |> lick.transpose(instrument.write_interval_for_key(
        player,
        PitchClass(C, 0),
      ))
    list.each(lick.pitches(subject), fn(one) {
      assert instrument.in_range(player, one)
    })
  })
}
