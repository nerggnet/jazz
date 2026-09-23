import gleam/int
import gleam/list
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
