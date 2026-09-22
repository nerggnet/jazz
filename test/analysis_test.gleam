import gleam/list
import gleam/option.{Some}
import gleam/string
import jazz/analysis
import jazz/chord.{type Chord}
import jazz/internal/num
import jazz/pitch.{C, PitchClass}
import jazz/progression

fn changes(symbols: String) -> List(Chord) {
  let assert Ok(parsed) =
    symbols |> string.split(" ") |> list.try_map(chord.parse)
  parsed
}

fn labels(symbols: String) -> List(String) {
  changes(symbols) |> analysis.analyse |> list.map(fn(one) { one.label })
}

fn spans(symbols: String) -> List(#(Int, Int)) {
  changes(symbols)
  |> analysis.analyse
  |> list.map(fn(one) { #(one.start, one.length) })
}

pub fn finds_the_two_five_one_test() {
  assert labels("Dm7 G7 Cmaj7") == ["ii-V-I in C"]
  assert labels("Fm7 Bb7 Ebmaj7") == ["ii-V-I in Eb"]
  assert labels("Dm7 G7 C6") == ["ii-V-I in C"]
  assert spans("Dm7 G7 Cmaj7") == [#(0, 3)]
}

pub fn finds_the_minor_two_five_one_test() {
  assert labels("Dm7b5 G7alt Cm7") == ["minor ii-V-i in C"]
  assert labels("Dm7b5 G7b9 Cm(maj7)") == ["minor ii-V-i in C"]
  // A major ii into a minor tonic is not the minor cadence.
  assert labels("Dm7 G7 Cm7") == ["ii-V into C"]
}

pub fn finds_substitutes_test() {
  assert labels("Dm7 Db7 Cmaj7") == ["ii bII7 I in C"]
  assert labels("Fm7 Cmaj7") == ["minor iv into C"]
  assert labels("Fmaj7 Fm7 Bb7 Cmaj7")
    == ["ii-V into Eb", "backdoor cadence into C"]
}

pub fn finds_diminished_chords_test() {
  assert labels("Bb7 Bdim7 F7") == ["rising Bdim7"]
  assert labels("Cmaj7 C#dim7 Dm7") == ["rising C#dim7"]
}

pub fn finds_turnarounds_test() {
  assert labels("Cmaj7 A7b9 Dm7 G7") == ["I VI ii V turnaround in C"]
  // A blues turnaround starts on a dominant.
  assert labels("F7 D7 Gm7 C7") == ["I VI ii V turnaround in F"]
}

pub fn finds_coltrane_changes_test() {
  assert labels("Bmaj7 D7 Gmaj7 Bb7 Ebmaj7") == ["major third cycle: B G Eb"]
}

pub fn nested_cells_are_left_out_test() {
  // The turnaround contains a two-five; only the turnaround is reported.
  assert spans("Cmaj7 A7 Dm7 G7") == [#(0, 4)]
}

pub fn spelling_does_not_change_the_answer_test() {
  // Charts are written by people, and people disagree about enharmonics.
  // What is found stays the same; only the names in the label follow the page.
  assert labels("Dm7 Db7 Cmaj7") == labels("Dm7 C#7 Cmaj7")
  assert spans("Fm7 Bb7 Ebmaj7") == spans("Fm7 A#7 D#maj7")
  assert labels("Fm7 A#7 D#maj7") == ["ii-V-I in D#"]
}

pub fn quiet_when_there_is_nothing_to_say_test() {
  assert labels("Cmaj7 Ebmaj7 Amaj7") == []
  assert labels("C7") == []
}

pub fn the_guide_tone_line_voice_leads_test() {
  // In every key, the seventh of each chord falls a semitone onto the third
  // of the next. That is the whole reason a two-five sounds like one idea.
  list.each(progression.cycle_of_fourths(PitchClass(C, 0)), fn(key) {
    let assert Ok(built) = progression.build("ii-V-I", key)
    // Only the three chords that move; the tonic bar repeats itself.
    let steps =
      analysis.guide_tone_line(list.take(progression.chords(built), 3))
    list.each(pairs(steps), fn(pair) {
      let #(before, after) = pair
      let assert analysis.GuideStep(_, _, Some(seventh)) = before
      let assert analysis.GuideStep(_, Some(third), _) = after
      assert num.modulo(
          pitch.class_semitones(seventh) - pitch.class_semitones(third),
          12,
        )
        == 1
    })
  })
}

pub fn guide_tones_of_a_substitute_match_the_chord_it_replaces_test() {
  let assert [g7, db7] = analysis.guide_tone_line(changes("G7 Db7"))
  let assert analysis.GuideStep(_, Some(g_third), Some(g_seventh)) = g7
  let assert analysis.GuideStep(_, Some(d_third), Some(d_seventh)) = db7
  assert pitch.class_semitones(g_third) == pitch.class_semitones(d_seventh)
  assert pitch.class_semitones(g_seventh) == pitch.class_semitones(d_third)
}

fn pairs(items: List(a)) -> List(#(a, a)) {
  case items {
    [first, second, ..rest] -> [#(first, second), ..pairs([second, ..rest])]
    _ -> []
  }
}
