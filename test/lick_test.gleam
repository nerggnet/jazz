import gleam/int
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

fn first_tone(segment: lick.Segment) -> Result(pitch.Pitch, Nil) {
  segment.events
  |> list.filter_map(fn(event) {
    case event {
      lick.Tone(note, _, _) -> Ok(note)
      lick.Rest(_) -> Error(Nil)
    }
  })
  |> list.first
}

fn silence(subject: lick.Line) -> Int {
  subject.segments
  |> list.flat_map(fn(one) { one.events })
  |> list.fold(0, fn(total, event) {
    case event {
      lick.Rest(beats) -> total + beats
      lick.Tone(_, _, _) -> total
    }
  })
}

pub fn every_target_is_a_chord_tone_test() {
  // The first note over a chord is the whole point, and it has to belong to
  // the chord. Since a phrase can start anywhere, this is also what says no
  // approach note is left dangling on the far side of a rest: whatever comes
  // out of a silence is a target, not the tail of the figure before it.
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 5, 12, 64], fn(seed) {
      list.each(line(level, seed).segments, fn(segment) {
        case first_tone(segment) {
          Error(_) -> Nil
          Ok(first) -> {
            let tones = chord.notes(segment.chord)
            assert list.any(tones, fn(one) { pitch.same(one, first.class) })
          }
        }
      })
    })
  })
}

pub fn lines_breathe_test() {
  // Every line leaves somewhere to breathe, and none of them is all silence.
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 2, 3, 4, 5, 9, 21], fn(seed) {
      let subject = line(level, seed)
      let quiet = silence(subject)
      assert quiet > 0
      assert quiet < lick.duration(subject)
      assert lick.pitches(subject) != []
    })
  })
}

pub fn beginners_are_given_more_space_test() {
  // Space is the part that takes longest to learn to trust, so a beginner
  // gets more of it handed to them. Measured over a chorus rather than a
  // single cell: four bars is too small a sample to tell the levels apart.
  let assert Ok(changes) =
    progression.parse("|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|")
  let quiet = fn(level) {
    [1, 2, 3, 4, 5, 6, 7, 8]
    |> list.map(fn(seed) {
      silence(lick.over_progression(changes, lick.options(level, seed)))
    })
    |> list.fold(0, fn(total, one) { total + one })
  }
  assert quiet(lick.Beginner) > quiet(lick.Intermediate)
  assert quiet(lick.Intermediate) > quiet(lick.Advanced)
}

pub fn rests_are_never_empty_test() {
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 2, 3, 7, 13], fn(seed) {
      list.each(line(level, seed).segments, fn(segment) {
        list.each(segment.events, fn(event) {
          let beats = case event {
            lick.Rest(length) -> length
            lick.Tone(_, length, _) -> length
          }
          assert beats > 0
        })
      })
    })
  })
}

pub fn phrasing_does_not_change_the_length_test() {
  // Silence takes up exactly the room the notes it replaced would have.
  let assert Ok(changes) =
    progression.parse("|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|")
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 4, 17], fn(seed) {
      let subject = lick.over_progression(changes, lick.options(level, seed))
      assert lick.duration(subject) == 16 * lick.bar
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

fn chorus(level: lick.Level, seed: Int) -> lick.Line {
  let assert Ok(changes) =
    progression.parse("|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|")
  lick.over_progression(changes, lick.options(level, seed))
}

fn tones(segment: lick.Segment) -> List(pitch.Pitch) {
  list.filter_map(segment.events, fn(event) {
    case event {
      lick.Tone(note, _, _) -> Ok(note)
      lick.Rest(_) -> Error(Nil)
    }
  })
}

/// The steps of a figure, in semitones and with their direction.
fn deltas(notes: List(pitch.Pitch)) -> List(Int) {
  case notes {
    [first, second, ..rest] -> [
      pitch.to_midi(second) - pitch.to_midi(first),
      ..deltas([second, ..rest])
    ]
    _ -> []
  }
}

fn heading(step: Int) -> Int {
  case step > 0, step < 0 {
    True, _ -> 1
    _, True -> -1
    _, _ -> 0
  }
}

fn repeated(segment: lick.Segment) -> Bool {
  string.contains(segment.device, "the same shape again")
}

fn pairs(items: List(a)) -> List(#(a, a)) {
  case items {
    [first, second, ..rest] -> [#(first, second), ..pairs([second, ..rest])]
    _ -> []
  }
}

pub fn figures_come_back_test() {
  // A chorus that never repeats itself is a random walk through correct
  // notes. Something has to come back.
  let sequences =
    [lick.Beginner, lick.Intermediate, lick.Advanced]
    |> list.flat_map(fn(level) {
      [1, 2, 3, 4, 5] |> list.map(fn(seed) { chorus(level, seed) })
    })
    |> list.flat_map(fn(one) { one.segments })
    |> list.count(repeated)
  assert sequences > 10
}

pub fn a_sequence_keeps_the_shape_test() {
  // Repeating a figure means the same contour aimed at a new target over a
  // new chord, not the same notes: that is what makes it a sequence.
  let checked =
    [lick.Beginner, lick.Intermediate, lick.Advanced]
    |> list.flat_map(fn(level) {
      [1, 2, 3, 4, 5, 6, 7, 8] |> list.map(fn(seed) { chorus(level, seed) })
    })
    |> list.flat_map(fn(one) { pairs(one.segments) })
    |> list.filter(fn(pair) {
      let #(before, after) = pair
      // Enough notes either side that the comparison is of the figure and
      // not of whatever approach note happened to follow it.
      repeated(after)
      && list.length(tones(before)) >= 6
      && list.length(tones(after)) >= 6
    })
  list.each(checked, fn(pair) {
    let #(before, after) = pair
    list.zip(deltas(tones(after)), deltas(tones(before)))
    |> list.take(4)
    |> list.each(fn(steps) {
      let #(here, there) = steps
      // An octave jump is a figure being folded back into the range rather
      // than part of the shape, so those positions are not compared.
      assert int.absolute_value(here) >= 7
        || int.absolute_value(there) >= 7
        || heading(here) == heading(there)
    })
  })
  assert list.length(checked) > 5
}

pub fn a_figure_is_not_run_into_the_ground_test() {
  // State it, sequence it, then go somewhere else. A fourth time in a row is
  // a stuck record.
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 2, 3, 4, 5, 6, 7, 8], fn(seed) {
      let #(longest, _) =
        list.fold(chorus(level, seed).segments, #(0, 0), fn(state, segment) {
          let #(worst, run) = state
          let run = case repeated(segment) {
            True -> run + 1
            False -> 0
          }
          #(int.max(worst, run), run)
        })
      assert longest <= 2
    })
  })
}

fn sounded(subject: lick.Line) -> List(lick.Event) {
  subject.segments
  |> list.flat_map(fn(one) { one.events })
  |> list.filter(fn(event) {
    case event {
      lick.Tone(_, _, _) -> True
      lick.Rest(_) -> False
    }
  })
}

fn choruses() -> List(lick.Line) {
  [lick.Beginner, lick.Intermediate, lick.Advanced]
  |> list.flat_map(fn(level) {
    [1, 2, 3, 4, 5, 6, 7, 8] |> list.map(fn(seed) { chorus(level, seed) })
  })
}

pub fn the_line_does_not_stutter_test() {
  // Two of the same note in a row reads as a mistake rather than as anything.
  // A tie is the exception, and the whole point: that pair is one note held,
  // not the same note twice.
  let #(stutters, total) =
    choruses()
    |> list.fold(#(0, 0), fn(state, one) {
      let #(bad, seen) = state
      let notes = sounded(one)
      let repeats =
        pairs(notes)
        |> list.count(fn(pair) {
          case pair {
            #(lick.Tone(before, _, False), lick.Tone(after, _, _)) ->
              pitch.to_midi(before) == pitch.to_midi(after)
            _ -> False
          }
        })
      #(bad + repeats, seen + list.length(notes))
    })
  assert total > 1000
  assert stutters * 100 < total
}

pub fn a_tie_is_held_rather_than_played_again_test() {
  // An anticipation is only an anticipation if the note carries over. A tie
  // into a different note would just be wrong.
  let checked =
    choruses()
    |> list.flat_map(fn(one) { pairs(sounded(one)) })
    |> list.filter(fn(pair) {
      case pair.0 {
        lick.Tone(_, _, held) -> held
        lick.Rest(_) -> False
      }
    })
  list.each(checked, fn(pair) {
    let assert #(lick.Tone(before, _, _), lick.Tone(after, _, _)) = pair
    assert pitch.to_midi(before) == pitch.to_midi(after)
  })
  // And it has to actually be happening.
  assert list.length(checked) > 20
}

pub fn a_tie_never_hangs_off_the_end_test() {
  // Nothing to hold into means nothing to tie to.
  list.each(choruses(), fn(one) {
    let assert Ok(final) = list.last(sounded(one))
    let assert lick.Tone(_, _, held) = final
    assert !held
  })
}

pub fn the_line_leans_on_notes_test() {
  // Not everything is an eighth note, and a beginner leans more often than
  // somebody who has the eighths to spare.
  let held = fn(level) {
    [1, 2, 3, 4, 5, 6, 7, 8]
    |> list.map(fn(seed) {
      sounded(chorus(level, seed))
      |> list.count(fn(event) {
        case event {
          lick.Tone(_, beats, _) -> beats > 1
          lick.Rest(_) -> False
        }
      })
    })
    |> list.fold(0, fn(total, one) { total + one })
  }
  assert held(lick.Beginner) > 0
  assert held(lick.Advanced) > 0
  assert held(lick.Beginner) > held(lick.Advanced)
}

fn heights(subject: lick.Line) -> List(Int) {
  list.filter_map(subject.segments, fn(one) {
    case first_tone(one) {
      Ok(note) -> Ok(pitch.to_midi(note))
      Error(_) -> Error(Nil)
    }
  })
}

fn average(values: List(Int)) -> Int {
  case list.length(values) {
    0 -> 0
    count -> list.fold(values, 0, fn(total, one) { total + one }) / count
  }
}

/// The average height of the targets in each third of the form.
fn thirds(subject: lick.Line) -> #(Int, Int, Int) {
  let values = heights(subject)
  let step = list.length(values) / 3
  #(
    average(list.take(values, step)),
    average(list.take(list.drop(values, step), step)),
    average(list.drop(values, 2 * step)),
  )
}

fn shaped(arc: lick.Arc) -> List(lick.Line) {
  [lick.Beginner, lick.Intermediate, lick.Advanced]
  |> list.flat_map(fn(level) {
    [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
    |> list.map(fn(seed) { chorus(level, seed) })
  })
  |> list.filter(fn(one) { one.arc == arc })
}

fn across(lines: List(lick.Line)) -> #(Int, Int, Int) {
  let totals =
    list.fold(lines, #(0, 0, 0), fn(sum, one) {
      let #(first, middle, last) = thirds(one)
      #(sum.0 + first, sum.1 + middle, sum.2 + last)
    })
  let count = int.max(1, list.length(lines))
  #(totals.0 / count, totals.1 / count, totals.2 / count)
}

pub fn the_line_goes_somewhere_test() {
  // Choosing every target for the smoothest voice leading keeps the line in
  // one octave all chorus, because staying put is always the smallest move.
  list.each(choruses(), fn(one) {
    let reached = heights(one)
    let assert Ok(lowest) = list.reduce(reached, int.min)
    let assert Ok(highest) = list.reduce(reached, int.max)
    assert highest - lowest > 7
  })
}

pub fn an_arch_peaks_in_the_middle_test() {
  let arches = shaped(lick.Arch)
  assert list.length(arches) > 10
  let #(first, middle, last) = across(arches)
  assert middle > first
  assert middle > last
}

pub fn a_climb_climbs_test() {
  let climbs = shaped(lick.Rise)
  assert list.length(climbs) > 3
  let #(first, _, last) = across(climbs)
  assert last > first
}

pub fn the_arc_does_not_tear_the_line_apart_test() {
  // Targets are the same note in different octaves, so the arc is choosing a
  // register. It must never ask for more than the octave that implies.
  list.each(choruses(), fn(one) {
    list.each(pairs(heights(one)), fn(step) {
      assert int.absolute_value(step.1 - step.0) <= 12
    })
  })
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
