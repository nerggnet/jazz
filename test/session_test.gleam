import gleam/list
import gleam/string
import jazz/instrument
import jazz/lick
import jazz/pitch
import jazz/scale
import jazz/session

fn showing(view: session.View) -> session.Session {
  session.update(session.new(), session.ChooseView(view))
}

fn text_of(subject: session.Session) -> String {
  case session.panel(subject) {
    session.Panel(text, _) -> text
    session.Problem(message) -> "PROBLEM: " <> message
  }
}

fn abc_of(subject: session.Session) -> String {
  case session.panel(subject) {
    session.Panel(_, abc) -> abc
    session.Problem(message) -> "PROBLEM: " <> message
  }
}

/// Everything after the heading line.
fn body(text: String) -> String {
  case string.split(text, "\n") {
    [_, ..rest] -> string.join(rest, "\n")
    [] -> text
  }
}

pub fn every_view_shows_something_test() {
  list.each(session.all_views(), fn(view) {
    let assert session.Panel(text, abc) = session.panel(showing(view))
    assert text != ""
    assert string.contains(abc, "X:1")
    assert string.contains(abc, "K:")
  })
}

pub fn choosing_an_instrument_test() {
  let subject = session.update(session.new(), session.ChooseInstrument("tenor"))
  assert subject.player.id == "tenor"
  // An instrument nobody has leaves the session alone rather than breaking it.
  let same = session.update(subject, session.ChooseInstrument("banjo"))
  assert same.player.id == "tenor"
}

pub fn the_key_is_always_concert_test() {
  // Concert C read on alto is A, and the session keeps the concert name.
  let subject = session.new()
  assert subject.player.id == "alto"
  assert pitch.class_to_string(subject.key) == "C"
  assert pitch.class_to_string(session.written_key(subject)) == "A"
}

pub fn stepping_round_the_cycle_test() {
  let walked =
    list.fold(list.repeat(Nil, 12), [session.new()], fn(trail, _) {
      let assert [latest, ..] = trail
      [session.update(latest, session.StepKey(1)), ..trail]
    })
  let names =
    walked
    |> list.reverse
    |> list.map(fn(one) { pitch.class_to_string(one.key) })
  // Twelve steps round the cycle of fourths comes home again.
  assert names
    == ["C", "F", "Bb", "Eb", "Ab", "Db", "Gb", "B", "E", "A", "D", "G", "C"]
}

pub fn stepping_back_undoes_stepping_forward_test() {
  let subject = session.new()
  let there_and_back =
    session.update(
      session.update(subject, session.StepKey(1)),
      session.StepKey(-1),
    )
  assert there_and_back.key == subject.key
}

pub fn a_new_line_is_a_different_line_test() {
  let first = showing(session.LineView)
  let second = session.update(first, session.NewLine)
  assert first.seed != second.seed
  assert text_of(first) != text_of(second)
  // And the old one is still reachable from the seed it was made with.
  assert text_of(session.Session(..second, seed: first.seed)) == text_of(first)
}

pub fn bad_chord_text_reports_instead_of_crashing_test() {
  let subject =
    session.update(showing(session.ChordView), session.TypeChord("Hm7"))
  let assert session.Problem(message) = session.panel(subject)
  assert string.contains(message, "not a note name")
  // And typing the rest of it recovers.
  let fixed = session.update(subject, session.TypeChord("Bbm7"))
  assert string.contains(text_of(fixed), "Gm7")
}

pub fn changes_can_be_typed_off_a_chart_test() {
  let subject =
    session.update(
      showing(session.AnalysisView),
      session.TypeChanges("Dm7 | G7 | Cmaj7"),
    )
  assert string.contains(text_of(subject), "ii-V-I in A")
  // Bar lines and stray spaces are not the player's problem. The heading
  // still shows what was typed, so only the analysis underneath is compared.
  let without_bars =
    session.update(subject, session.TypeChanges("Dm7 G7 Cmaj7"))
  assert body(text_of(subject)) == body(text_of(without_bars))
}

pub fn the_level_changes_the_vocabulary_test() {
  let simple = showing(session.LineView)
  let harder = session.update(simple, session.ChooseLevel(lick.Advanced))
  assert text_of(simple) != text_of(harder)
}

pub fn controls_can_hand_back_strings_test() {
  // A form control gives back whatever was in its value attribute, so the
  // session takes names as well as types, and shrugs at anything it cannot
  // make sense of.
  let subject = session.new()
  assert session.update(subject, session.ChooseKeyNamed("Eb")).key
    == pitch.class(pitch.E, -1)
  assert session.update(subject, session.ChooseScaleNamed("altered")).kind
    == scale.Altered
  assert session.update(subject, session.ChooseLevelNamed("advanced")).level
    == lick.Advanced
  assert session.update(subject, session.ChooseKeyNamed("H")) == subject
  assert session.update(subject, session.ChooseScaleNamed("wonky")) == subject
  assert session.update(subject, session.ChooseLevelNamed("expert")) == subject
}

fn making_up(view: session.View) -> session.Session {
  showing(view)
  |> session.update(session.ChooseProgression(session.generated))
}

pub fn changes_can_be_made_up_test() {
  let subject = making_up(session.ProgressionView)
  let assert Ok(built) = session.changes(subject)
  assert list.length(built.bars) == 16
  // And a line can be played over whatever came out.
  let assert session.Panel(_, abc) =
    session.panel(session.update(subject, session.ChooseView(session.LineView)))
  assert string.contains(abc, "K:")
}

pub fn a_made_up_tune_can_be_any_length_test() {
  let subject =
    session.update(
      making_up(session.ProgressionView),
      session.ChooseBarsNamed("32"),
    )
  let assert Ok(built) = session.changes(subject)
  assert list.length(built.bars) == 32
  // Nonsense leaves it alone rather than producing a tune of no bars.
  assert session.update(subject, session.ChooseBarsNamed("nope")) == subject
  assert session.update(subject, session.ChooseBarsNamed("0")) == subject
}

pub fn the_tune_and_the_line_reroll_separately_test() {
  // Keeping a tune you like while trying another line over it, and the other
  // way round, is the whole reason they have seeds of their own.
  let subject = making_up(session.LineView)
  let another_line = session.update(subject, session.NewLine)
  let another_tune = session.update(subject, session.NewTune)

  let assert Ok(before) = session.changes(subject)
  let assert Ok(after_line) = session.changes(another_line)
  let assert Ok(after_tune) = session.changes(another_tune)

  assert before.bars == after_line.bars
  assert before.bars != after_tune.bars
  assert text_of(subject) != text_of(another_line)
}

pub fn a_made_up_tune_follows_the_key_test() {
  let subject =
    session.update(
      making_up(session.ProgressionView),
      session.ChooseKeyNamed("Eb"),
    )
  let assert Ok(built) = session.changes(subject)
  assert pitch.class_to_string(built.key) == "Eb"
  assert session.uses_key(subject)
}

pub fn the_tempo_can_be_changed_test() {
  let subject = session.update(session.new(), session.ChooseTempoNamed("80"))
  assert subject.tempo == 80
  // The score carries it, which is what the playhead and the synth both read.
  let assert session.Panel(_, abc) = session.panel(subject)
  assert string.contains(abc, "Q:1/4=80")
  // And nonsense leaves it alone rather than producing a score nobody can play.
  assert session.update(subject, session.ChooseTempoNamed("0")) == subject
  assert session.update(subject, session.ChooseTempoNamed("9000")) == subject
  assert session.update(subject, session.ChooseTempoNamed("presto")) == subject
}

pub fn the_horn_can_be_silenced_test() {
  // Turning the horn off leaves the written backing to play against, which
  // is the whole reason for writing one out.
  let subject = session.new()
  assert subject.horn_sounds
  let quiet = session.update(subject, session.PlayTheHorn(False))
  assert !quiet.horn_sounds
  // It changes nothing about what is on the page, only what is heard.
  assert text_of(quiet) == text_of(subject)
  assert session.update(quiet, session.PlayTheHorn(True)) == subject
}

pub fn a_part_plays_back_as_its_own_horn_test() {
  // A tenor part should sound like a tenor, not like a piano.
  let alto = showing(session.LineView)
  let assert session.Panel(_, on_alto) = session.panel(alto)
  assert string.contains(on_alto, "%%MIDI program 65")
  let assert session.Panel(_, on_tenor) =
    session.panel(session.update(alto, session.ChooseInstrument("tenor")))
  assert string.contains(on_tenor, "%%MIDI program 66")
  // And the staff written for the piano sounds like one.
  assert string.contains(on_alto, "%%MIDI program 0")
}

pub fn views_declare_what_they_need_test() {
  assert session.uses_key(showing(session.ScaleView))
  assert !session.uses_key(showing(session.ChordView))
  // Typed changes bring their own key, so the picker has nothing to say.
  assert session.uses_key(showing(session.LineView))
  assert !session.uses_key(session.update(
    showing(session.LineView),
    session.ChooseProgression(session.typed),
  ))
  assert session.generates(session.LineView)
  assert !session.generates(session.ScaleView)
  assert list.length(session.all_views()) == 5
  assert list.map(session.all_views(), session.view_name)
    == ["Scale", "Chord", "Changes", "Line", "Analyse"]
}

pub fn lines_are_written_for_the_chosen_horn_test() {
  // The same session on two horns gives the same music, spelled differently.
  let alto = showing(session.LineView)
  let tenor = session.update(alto, session.ChooseInstrument("tenor"))
  assert string.contains(abc_of(alto), "T:Alto sax (Eb)")
  assert string.contains(abc_of(tenor), "T:Tenor sax (Bb)")
  assert abc_of(alto) != abc_of(tenor)
}

pub fn a_scale_can_be_chosen_test() {
  let subject =
    session.update(
      showing(session.ScaleView),
      session.ChooseScale(scale.Altered),
    )
  assert string.contains(text_of(subject), "Altered")
  assert string.contains(abc_of(subject), "Altered")
}

pub fn instruments_are_all_reachable_test() {
  list.each(instrument.all(), fn(player) {
    let subject =
      session.update(session.new(), session.ChooseInstrument(player.id))
    list.each(session.all_views(), fn(view) {
      let assert session.Panel(_, _) =
        session.panel(session.update(subject, session.ChooseView(view)))
    })
  })
}

pub fn the_feel_reaches_every_chart_test() {
  // Whatever is on screen, it says how its eighths are meant to be read.
  list.each(session.all_views(), fn(view) {
    let swung = showing(view)
    assert string.contains(abc_of(swung), "\"Swing\"")

    let straight = session.update(swung, session.SwingIt(False))
    assert !string.contains(abc_of(straight), "Swing")
  })
}

pub fn a_backed_line_is_a_band_test() {
  // Piano, bass, and the part to play over them, each with its own sound.
  let music = abc_of(showing(session.LineView))
  assert string.contains(music, "V:1 clef=treble name=\"Piano\"")
  assert string.contains(music, "V:2 clef=bass name=\"Bass\"")
  assert string.contains(music, "%%MIDI program 32")
}

pub fn the_playing_switches_all_flip_test() {
  // Four things about how it is played rather than what is played, each one
  // its own switch and none of them changing the other.
  let subject = showing(session.LineView)
  assert subject.swing && !subject.count_in && !subject.round_and_round
  assert subject.horn_sounds

  let flipped =
    session.update(subject, session.CountIn(True))
    |> session.update(session.RoundAndRound(True))
    |> session.update(session.SwingIt(False))
    |> session.update(session.PlayTheHorn(False))
  assert flipped.count_in && flipped.round_and_round
  assert !flipped.swing && !flipped.horn_sounds

  // None of them touches the notes on the page; only the feel is written.
  assert abc_of(session.update(subject, session.CountIn(True)))
    == abc_of(subject)
  assert abc_of(session.update(subject, session.RoundAndRound(True)))
    == abc_of(subject)
}

pub fn a_practice_pattern_reaches_the_page_test() {
  let subject =
    showing(session.ScaleView)
    |> session.update(session.ChoosePatternNamed("sevenths"))
  assert string.contains(text_of(subject), "Sevenths")
  assert string.contains(abc_of(subject), "sevenths")

  let round = session.update(subject, session.RoundTheKeys(True))
  assert string.contains(abc_of(round), "round the keys")
  assert string.contains(abc_of(round), "[K:")
}
