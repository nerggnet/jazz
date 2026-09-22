import gleam/list
import gleam/string
import jazz/analysis
import jazz/chord
import jazz/instrument
import jazz/lick
import jazz/notation
import jazz/pitch.{C, F, PitchClass}
import jazz/progression
import jazz/render/abc
import jazz/tune

fn made(bars: Int, level: lick.Level, seed: Int) -> progression.Progression {
  tune.generate(bars, PitchClass(C, 0), level, seed)
}

fn levels() -> List(lick.Level) {
  [lick.Beginner, lick.Intermediate, lick.Advanced]
}

fn seeds() -> List(Int) {
  [1, 2, 3, 4, 5, 6, 7, 8, 11, 19]
}

fn symbols(built: progression.Progression) -> String {
  built
  |> progression.chords
  |> list.map(chord.to_string)
  |> string.join(" ")
}

pub fn a_tune_is_the_length_it_was_asked_for_test() {
  list.each([4, 8, 12, 16, 24, 32, 64], fn(bars) {
    list.each(levels(), fn(level) {
      list.each(seeds(), fn(seed) {
        assert list.length(made(bars, level, seed).bars) == bars
      })
    })
  })
}

pub fn a_tune_comes_home_test() {
  // However far the changes wander, they end where they started.
  list.each([8, 16, 32], fn(bars) {
    list.each(levels(), fn(level) {
      list.each(seeds(), fn(seed) {
        let built = made(bars, level, seed)
        let assert Ok(final) = list.last(progression.chords(built))
        assert pitch.same(final.root, built.key)
        let assert Ok(first) = list.first(progression.chords(built))
        // And they open somewhere that belongs to the key rather than
        // wherever the dice landed.
        assert first.root != final.root || pitch.same(first.root, built.key)
      })
    })
  })
}

pub fn the_same_seed_gives_the_same_tune_test() {
  assert symbols(made(16, lick.Advanced, 42))
    == symbols(made(16, lick.Advanced, 42))
  assert symbols(made(16, lick.Advanced, 42))
    != symbols(made(16, lick.Advanced, 43))
}

pub fn the_analyser_finds_what_the_generator_put_in_test() {
  // The generator is the analyser's grammar run backwards, so everything it
  // makes should be something the analyser can name. This is the test that
  // says the changes are idiomatic rather than merely well formed.
  list.each([16, 32], fn(bars) {
    list.each(levels(), fn(level) {
      list.each(seeds(), fn(seed) {
        let built = made(bars, level, seed)
        let found = analysis.analyse(progression.chords(built))
        let covered = list.fold(found, 0, fn(total, one) { total + one.length })
        // Most of the tune should be inside something with a name.
        assert covered * 2 > list.length(progression.chords(built))
      })
    })
  })
}

pub fn a_long_tune_has_a_form_test() {
  // Thirty two bars come out as AABA, because a form needs something to come
  // back to for the same reason a line needs a figure that returns.
  list.each(levels(), fn(level) {
    list.each(seeds(), fn(seed) {
      let bars = made(32, level, seed).bars
      let first = list.take(bars, 8)
      let second = list.take(list.drop(bars, 8), 8)
      let bridge = list.take(list.drop(bars, 16), 8)
      let last = list.drop(bars, 24)
      assert first == second
      assert first == last
      assert first != bridge
    })
  })
}

pub fn every_level_sounds_like_itself_test() {
  // A beginner tune stays in one key; the harder ones go somewhere.
  let keys_touched = fn(level) {
    seeds()
    |> list.map(fn(seed) {
      made(16, level, seed)
      |> progression.chords
      |> list.map(fn(one) { pitch.class_semitones(one.root) })
      |> list.unique
      |> list.length
    })
    |> list.fold(0, fn(total, one) { total + one })
  }
  assert keys_touched(lick.Beginner) < keys_touched(lick.Intermediate)
  assert keys_touched(lick.Intermediate) <= keys_touched(lick.Advanced)
}

pub fn a_tune_can_be_played_and_printed_test() {
  // The whole point: changes to blow over, on the horn in front of you.
  let assert Ok(alto) = instrument.find("alto")
  list.each(levels(), fn(level) {
    list.each([1, 5, 9], fn(seed) {
      let built = made(16, level, seed)

      let chart = abc.render(notation.from_progression(built, alto))
      assert string.contains(chart, "K:")

      let #(low, high) = instrument.comfortable_range(alto)
      let line =
        lick.over_progression(built, lick.Options(level, seed, low, high))
      assert lick.duration(line) == 16 * lick.bar
      // The line is made at concert pitch; the range belongs to the part.
      let written =
        lick.transpose(line, instrument.write_interval_for_key(alto, built.key))
      list.each(lick.pitches(written), fn(one) {
        assert instrument.in_range(alto, one)
      })
    })
  })
}

pub fn tunes_can_be_asked_for_in_any_key_test() {
  list.each(progression.cycle_of_fourths(PitchClass(F, 0)), fn(key) {
    let built = tune.generate(16, key, lick.Advanced, 3)
    assert list.length(built.bars) == 16
    let assert Ok(final) = list.last(progression.chords(built))
    assert pitch.same(final.root, key)
  })
}

pub fn silly_requests_are_survived_test() {
  assert list.length(tune.generate(0, PitchClass(C, 0), lick.Beginner, 1).bars)
    >= 2
  assert list.length(tune.generate(1, PitchClass(C, 0), lick.Beginner, 0).bars)
    >= 2
  assert list.length(tune.generate(3, PitchClass(C, 0), lick.Advanced, -5).bars)
    == 3
}
