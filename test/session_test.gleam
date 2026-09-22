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

pub fn views_declare_what_they_need_test() {
  assert session.uses_key(session.ScaleView)
  assert !session.uses_key(session.ChordView)
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
