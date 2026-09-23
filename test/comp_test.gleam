import gleam/int
import gleam/list
import gleam/string
import jazz/chord
import jazz/comp
import jazz/pitch.{type Pitch, C, PitchClass}
import jazz/progression

fn under(text: String) -> List(comp.Voicing) {
  let assert Ok(changes) = progression.parse(text)
  comp.under(changes)
}

fn midi(notes: List(Pitch)) -> List(Int) {
  list.map(notes, pitch.to_midi)
}

fn catalogue() -> List(comp.Voicing) {
  progression.catalogue()
  |> list.flat_map(fn(entry) {
    progression.cycle_of_fourths(PitchClass(C, 0))
    |> list.flat_map(fn(key) {
      let assert Ok(built) = progression.build(entry.0, key)
      comp.under(built)
    })
  })
}

pub fn a_voicing_says_which_chord_it_is_test() {
  // The root underneath, and above it the notes that tell a major seventh
  // from a minor one.
  list.each(catalogue(), fn(voiced) {
    let assert [root, ..upper] = voiced.notes
    assert pitch.same(root.class, voiced.chord.root)
    let wanted = chord.guide_tones(voiced.chord)
    list.each(wanted, fn(tone) {
      assert list.any(upper, fn(one) { pitch.same(one.class, tone) })
    })
  })
}

pub fn a_comp_stays_where_hands_reach_test() {
  list.each(catalogue(), fn(voiced) {
    let assert [root, ..upper] = voiced.notes
    // Low enough to be a bass note, high enough to be written down.
    assert pitch.to_midi(root) >= 36 && pitch.to_midi(root) <= 48
    list.each(upper, fn(one) {
      assert pitch.to_midi(one) >= 48 && pitch.to_midi(one) <= 60
    })
  })
}

pub fn the_voices_barely_move_test() {
  // The whole point of shell voicings: from one chord to the next the hand
  // shifts by a step or two, not by a leap. Stacking every chord from its
  // root instead would average far more than this.
  let steps =
    under("| Dm7 | G7 | Cmaj7 | Am7 | Dm7 | G7 | Cmaj7 | Cmaj7 |")
    |> list.map(fn(one) { list.drop(midi(one.notes), 1) })
    |> pairs
    |> list.flat_map(fn(pair) {
      list.zip(pair.0, pair.1)
      |> list.map(fn(move) { int.absolute_value(move.1 - move.0) })
    })
  let total = list.fold(steps, 0, fn(sum, one) { sum + one })
  assert list.length(steps) > 10
  assert total <= list.length(steps) * 2
}

pub fn a_common_tone_is_held_test() {
  // Dm7 and G7 share an F. A player keeps it rather than moving it, and the
  // seventh above falls a semitone onto the third.
  let assert [two, five, ..] = under("| Dm7 | G7 | Cmaj7 |")
  let held =
    list.filter(list.drop(midi(two.notes), 1), fn(one) {
      list.contains(list.drop(midi(five.notes), 1), one)
    })
  assert list.length(held) == 1
}

pub fn a_comp_fills_the_bars_test() {
  let voiced = under("| Dm7 G7 | Cmaj7 | Am7 D7 | Gmaj7 |")
  let total = list.fold(voiced, 0, fn(sum, one) { sum + one.duration })
  assert total == 4 * 8
  assert list.length(voiced) == 6
}

fn pairs(items: List(a)) -> List(#(a, a)) {
  case items {
    [first, second, ..rest] -> [#(first, second), ..pairs([second, ..rest])]
    _ -> []
  }
}

// --- The rhythm section ------------------------------------------------------

fn strokes(text: String) -> List(comp.Stroke) {
  let assert Ok(changes) = progression.parse(text)
  comp.comping(changes)
}

fn bassline(text: String) -> List(Pitch) {
  let assert Ok(changes) = progression.parse(text)
  comp.walking(changes)
}

pub fn a_comp_still_fills_the_bars_test() {
  let played = strokes("| Dm7 G7 | Cmaj7 | Am7 D7 | Gmaj7 |")
  let total =
    list.fold(played, 0, fn(sum, one) {
      case one {
        comp.Strike(_, length) -> sum + length
        comp.Wait(length) -> sum + length
      }
    })
  assert total == 4 * 8
}

pub fn a_comp_leaves_holes_test() {
  // A chord held down for every bar is an exercise. Somewhere between a
  // third and two thirds of the time the hands should be off the keys or
  // the rhythm is not a rhythm.
  let played = strokes(string.repeat("| Dm7 | G7 | Cmaj7 | Cmaj7 |", 4))
  let silence =
    list.fold(played, 0, fn(sum, one) {
      case one {
        comp.Wait(length) -> sum + length
        comp.Strike(_, _) -> sum
      }
    })
  let total = 16 * 8
  assert silence * 4 > total
  assert silence * 2 < total
}

pub fn a_comp_does_not_repeat_itself_test() {
  // Landing on the same beat every bar is a metronome, not a comp.
  let shapes =
    list.map(progression.catalogue(), fn(entry) {
      let assert Ok(built) = progression.build(entry.0, PitchClass(C, 0))
      comp.comping(built)
      |> list.map(fn(one) {
        case one {
          comp.Strike(_, length) -> "x" <> int.to_string(length)
          comp.Wait(length) -> "-" <> int.to_string(length)
        }
      })
      |> string.join("")
    })
  list.each(shapes, fn(one) {
    assert string.length(one) > 0
  })
  assert list.length(list.unique(shapes)) > 1
}

pub fn the_piano_keeps_out_of_the_bass_test() {
  // With somebody walking underneath, the pianist drops the root and plays
  // where the bass is not.
  list.each(strokes("| Dm7 G7 | Cmaj7 | Am7 D7 | Gmaj7 |"), fn(one) {
    case one {
      comp.Wait(_) -> Nil
      comp.Strike(notes, _) -> {
        assert list.length(notes) == 2
        list.each(notes, fn(note) {
          assert pitch.to_midi(note) >= 60 && pitch.to_midi(note) <= 72
        })
      }
    }
  })
}

pub fn a_bass_walks_one_note_to_the_beat_test() {
  let assert Ok(changes) = progression.parse("| Dm7 G7 | Cmaj7 | Am7 | D7 |")
  assert list.length(comp.walking(changes)) == 4 * 4
}

pub fn a_bass_lands_on_the_root_of_every_chord_test() {
  // Beat one of a chord is its root. Everything else is negotiable.
  list.each(progression.catalogue(), fn(entry) {
    list.each(progression.cycle_of_fourths(PitchClass(C, 0)), fn(key) {
      let assert Ok(built) = progression.build(entry.0, key)
      let notes = comp.walking(built)
      let roots =
        built.bars
        |> list.flat_map(fn(bar) {
          list.zip(bar.chords, progression.shares(list.length(bar.chords), 4))
        })
      list.fold(roots, notes, fn(left, segment) {
        let #(one, beats) = segment
        let assert [first, ..] = left
        assert pitch.same(first.class, one.root)
        list.drop(left, beats)
      })
      Nil
    })
  })
}

pub fn a_bass_approaches_the_next_root_test() {
  // The note before a change is a semitone from where the band is going.
  list.each(progression.catalogue(), fn(entry) {
    let assert Ok(built) = progression.build(entry.0, PitchClass(C, 0))
    let notes = comp.walking(built)
    let segments =
      built.bars
      |> list.flat_map(fn(bar) {
        list.zip(bar.chords, progression.shares(list.length(bar.chords), 4))
      })
    list.fold(segments, #(notes, 0), fn(state, segment) {
      let #(left, at) = state
      let #(_, beats) = segment
      case beats > 1 && at + 1 < list.length(segments) {
        False -> Nil
        True -> {
          let assert Ok(leading) = list.first(list.drop(left, beats - 1))
          let assert Ok(#(next, _)) = list.first(list.drop(segments, at + 1))
          let assert Ok(arrival) = list.first(list.drop(left, beats))
          assert pitch.same(arrival.class, next.root)
          let gap =
            int.absolute_value(pitch.to_midi(arrival) - pitch.to_midi(leading))
          assert gap == 1
        }
      }
      #(list.drop(left, beats), at + 1)
    })
    Nil
  })
}

pub fn a_bass_stays_on_its_staff_test() {
  list.each(progression.catalogue(), fn(entry) {
    list.each(progression.cycle_of_fourths(PitchClass(C, 0)), fn(key) {
      let assert Ok(built) = progression.build(entry.0, key)
      list.each(comp.walking(built), fn(one) {
        assert pitch.to_midi(one) >= 36 && pitch.to_midi(one) <= 57
      })
    })
  })
}

pub fn a_bass_does_not_leap_about_test() {
  // A walking line walks. Averaging much more than a third or so between
  // notes means it is jumping octaves to find its notes instead.
  let notes = bassline(string.repeat("| Dm7 | G7 | Cmaj7 | Am7 |", 4))
  let steps =
    pairs(notes)
    |> list.map(fn(pair) {
      int.absolute_value(pitch.to_midi(pair.1) - pitch.to_midi(pair.0))
    })
  let total = list.fold(steps, 0, fn(sum, one) { sum + one })
  assert list.length(steps) > 50
  assert total <= list.length(steps) * 4
}
