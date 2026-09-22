//// What an interactive front end is looking at.
////
//// A model and an update function, and nothing else: no events, no elements,
//// no platform. The web interface is a view over this, and because it is pure
//// it can be tested on both compilation targets without a browser anywhere in
//// sight.
////
//// The command line does not use this. It is one shot and takes its state
//// from flags; a session is the same state held still and poked at. Both sit
//// on the same theory underneath.

import gleam/list
import gleam/string
import jazz/chord.{type Chord}
import jazz/instrument.{type Instrument}
import jazz/internal/random
import jazz/interval
import jazz/lick.{type Level}
import jazz/notation
import jazz/pitch.{type PitchClass}
import jazz/progression.{type Progression}
import jazz/render/abc
import jazz/render/text
import jazz/scale.{type ScaleKind}

pub type View {
  ScaleView
  ChordView
  ProgressionView
  LineView
  AnalysisView
}

pub type Session {
  Session(
    player: Instrument,
    /// Always the concert key, whatever instrument is selected.
    key: PitchClass,
    kind: ScaleKind,
    chord_text: String,
    changes_text: String,
    progression_id: String,
    level: Level,
    seed: Int,
    view: View,
  )
}

pub type Action {
  ChooseInstrument(String)
  ChooseKey(PitchClass)
  /// The same choices as their typed cousins, for a front end whose controls
  /// hand back strings.
  ChooseKeyNamed(String)
  ChooseScaleNamed(String)
  ChooseLevelNamed(String)
  /// Move round the cycle of fourths: forwards for one, back for minus one.
  StepKey(Int)
  ChooseScale(ScaleKind)
  TypeChord(String)
  TypeChanges(String)
  ChooseProgression(String)
  ChooseLevel(Level)
  ChooseView(View)
  NewLine
}

/// What the session is showing, ready to be put on screen.
pub type Panel {
  Panel(text: String, abc: String)
  Problem(message: String)
}

pub fn new() -> Session {
  Session(
    player: instrument.alto_sax(),
    key: pitch.natural(pitch.C),
    kind: scale.Dorian,
    chord_text: "Bb7#9",
    changes_text: "Dm7 G7 Cmaj7",
    progression_id: "ii-V-I",
    level: lick.Beginner,
    seed: 1,
    view: ScaleView,
  )
}

// --- Updating ----------------------------------------------------------------

pub fn update(session: Session, action: Action) -> Session {
  case action {
    ChooseInstrument(name) ->
      case instrument.find(name) {
        Ok(found) -> Session(..session, player: found)
        Error(_) -> session
      }
    ChooseKey(key) -> Session(..session, key: key)
    ChooseKeyNamed(name) ->
      case pitch.parse_class(name) {
        Ok(key) -> Session(..session, key: key)
        Error(_) -> session
      }
    ChooseScaleNamed(name) ->
      case scale.kind_from_string(name) {
        Ok(kind) -> Session(..session, kind: kind)
        Error(_) -> session
      }
    ChooseLevelNamed(name) ->
      case lick.level_from_string(name) {
        Ok(level) -> Session(..session, level: level)
        Error(_) -> session
      }
    StepKey(step) ->
      Session(
        ..session,
        key: pitch.simplify_key(pitch.from_fifths(
          pitch.fifths(session.key) - step,
        )),
      )
    ChooseScale(kind) -> Session(..session, kind: kind)
    TypeChord(text) -> Session(..session, chord_text: text)
    TypeChanges(text) -> Session(..session, changes_text: text)
    ChooseProgression(id) -> Session(..session, progression_id: id)
    ChooseLevel(level) -> Session(..session, level: level)
    ChooseView(view) -> Session(..session, view: view)
    // Stepping the generator keeps this pure, and keeps every line reachable
    // again from the seed it was made with.
    NewLine -> {
      let #(next, _) = random.step(random.new(session.seed))
      Session(..session, seed: next)
    }
  }
}

// --- Showing -----------------------------------------------------------------

pub fn panel(session: Session) -> Panel {
  case session.view {
    ScaleView -> {
      let subject = scale.Scale(session.key, session.kind)
      Panel(
        text.scale_view(subject, session.player),
        abc.render(notation.from_scale(subject, session.player)),
      )
    }

    ChordView ->
      case chord.parse(session.chord_text) {
        Error(message) -> Problem(message)
        Ok(subject) ->
          Panel(
            text.chord_view(subject, session.player),
            abc.render(notation.from_chord(subject, session.player)),
          )
      }

    ProgressionView ->
      case progression.build(session.progression_id, session.key) {
        Error(message) -> Problem(message)
        Ok(built) ->
          Panel(
            text.progression_view(built, session.player),
            abc.render(notation.from_progression(built, session.player)),
          )
      }

    LineView ->
      case progression.build(session.progression_id, session.key) {
        Error(message) -> Problem(message)
        Ok(built) -> {
          let line = lick.over_progression(built, options(session))
          let heading = built.name <> " in " <> pitch.class_to_string(built.key)
          Panel(
            text.lick_view(line, heading, session.player, built.key),
            abc.render(notation.from_line(
              line,
              heading,
              built.key,
              session.player,
            )),
          )
        }
      }

    AnalysisView ->
      case read_changes(session.changes_text) {
        Error(message) -> Problem(message)
        Ok(#(chords, key)) ->
          Panel(
            text.analysis_view(
              chords,
              session.changes_text,
              session.player,
              key,
            ),
            abc.render(notation.from_progression(
              as_chart(chords, key, session.changes_text),
              session.player,
            )),
          )
      }
  }
}

/// Generate inside whatever the chosen horn can comfortably play.
fn options(session: Session) -> lick.Options {
  let #(low, high) = instrument.comfortable_range(session.player)
  lick.Options(session.level, session.seed, low, high)
}

/// Chord symbols separated by spaces, as they would be typed off a chart.
fn read_changes(text: String) -> Result(#(List(Chord), PitchClass), String) {
  let symbols =
    text
    |> string.replace("|", " ")
    |> string.split(" ")
    |> list.filter(fn(one) { one != "" })
  case symbols {
    [] -> Error("type some chord symbols, such as `Dm7 G7 Cmaj7`")
    _ ->
      case list.try_map(symbols, chord.parse) {
        Error(message) -> Error(message)
        Ok(chords) ->
          case list.last(chords) {
            // Changes usually end where they mean to.
            Ok(final) -> Ok(#(chords, final.root))
            Error(_) -> Error("type some chord symbols")
          }
      }
  }
}

fn as_chart(
  chords: List(Chord),
  key: PitchClass,
  title: String,
) -> Progression {
  progression.Progression(
    id: "changes",
    name: title,
    note: "",
    key: key,
    bars: list.map(chords, fn(one) { progression.Bar([one]) }),
  )
}

// --- Choices a front end can offer -------------------------------------------

pub fn all_views() -> List(View) {
  [ScaleView, ChordView, ProgressionView, LineView, AnalysisView]
}

pub fn view_name(view: View) -> String {
  case view {
    ScaleView -> "Scale"
    ChordView -> "Chord"
    ProgressionView -> "Changes"
    LineView -> "Line"
    AnalysisView -> "Analyse"
  }
}

/// The twelve keys, in the order they are worth practising in.
pub fn keys(session: Session) -> List(PitchClass) {
  progression.cycle_of_fourths(session.key)
}

/// Whether the current view pays any attention to the key.
pub fn uses_key(view: View) -> Bool {
  case view {
    ScaleView | ProgressionView | LineView -> True
    ChordView | AnalysisView -> False
  }
}

/// Whether the current view is generated, and so can be asked for another.
pub fn generates(view: View) -> Bool {
  view == LineView
}

/// The key the player actually reads, which is the one worth showing them.
pub fn written_key(session: Session) -> PitchClass {
  interval.transpose_class(
    session.key,
    instrument.write_interval_for_key(session.player, session.key),
  )
}
