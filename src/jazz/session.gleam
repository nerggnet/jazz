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

import gleam/int
import jazz/chord
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
import jazz/tune

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
    /// How long a generated tune should be.
    bars: Int,
    /// Quarter notes a minute, for whatever is played or printed.
    tempo: Int,
    /// Whether the horn part is heard as well as seen. Turning it off leaves
    /// the backing to play against, which is the point of writing one out.
    horn_sounds: Bool,
    seed: Int,
    /// Kept apart from the line's seed so a tune can be kept while the line
    /// over it is rerolled, and the other way round.
    tune_seed: Int,
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
  ChooseBarsNamed(String)
  ChooseTempoNamed(String)
  PlayTheHorn(Bool)
  NewLine
  NewTune
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
    bars: 16,
    tempo: notation.default_tempo,
    horn_sounds: True,
    seed: 1,
    tune_seed: 1,
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
    NewTune -> {
      let #(next, _) = random.step(random.new(session.tune_seed))
      Session(..session, tune_seed: next)
    }
    ChooseBarsNamed(name) ->
      case int.parse(name) {
        Ok(bars) if bars > 0 -> Session(..session, bars: bars)
        _ -> session
      }
    PlayTheHorn(sounding) -> Session(..session, horn_sounds: sounding)
    ChooseTempoNamed(name) ->
      case int.parse(name) {
        Ok(beats) if beats >= 20 && beats <= 400 ->
          Session(..session, tempo: beats)
        _ -> session
      }
  }
}

// --- Showing -----------------------------------------------------------------

/// The changes the session is pointed at: one from the catalogue, or whatever
/// has been typed in.
pub fn changes(session: Session) -> Result(Progression, String) {
  case typing_changes(session), generating_tune(session) {
    True, _ -> progression.parse(session.changes_text)
    _, True ->
      Ok(tune.generate(
        session.bars,
        session.key,
        session.level,
        session.tune_seed,
      ))
    _, _ -> progression.build(session.progression_id, session.key)
  }
}

/// Whether the changes are being typed rather than picked.
pub fn typing_changes(session: Session) -> Bool {
  session.progression_id == typed
}

/// Whether the changes are being made up on the spot.
pub fn generating_tune(session: Session) -> Bool {
  session.progression_id == generated
}

/// The name of the entry that means "the ones I typed".
pub const typed = "typed"

/// And the one that means "make some up".
pub const generated = "generated"

/// Lengths worth offering. Thirty two comes out as AABA.
pub fn bar_choices() -> List(Int) {
  [8, 12, 16, 24, 32]
}

/// Slow enough to learn something on, fast enough to sound like the music.
pub fn tempo_choices() -> List(Int) {
  [60, 80, 100, 120, 140, 160, 180, 200, 240]
}

/// Named the way the chart names it: the key on the page, with the concert
/// key alongside when those differ.
fn heading(session: Session, built: Progression) -> String {
  let written =
    interval.transpose_class(
      built.key,
      instrument.write_interval_for_key(session.player, built.key),
    )
  built.name
  <> " in "
  <> pitch.class_to_string(written)
  <> case instrument.is_concert(session.player) {
    True -> ""
    False -> "  (concert " <> pitch.class_to_string(built.key) <> ")"
  }
}

pub fn panel(session: Session) -> Panel {
  case session.view {
    ScaleView -> {
      let subject = scale.Scale(session.key, session.kind)
      Panel(
        text.scale_view(subject, session.player),
        abc.render(notation.from_scale(subject, session.player, session.tempo)),
      )
    }

    ChordView ->
      case chord.parse(session.chord_text) {
        Error(message) -> Problem(message)
        Ok(subject) ->
          Panel(
            text.chord_view(subject, session.player),
            abc.render(notation.from_chord(
              subject,
              session.player,
              session.tempo,
            )),
          )
      }

    ProgressionView ->
      case changes(session) {
        Error(message) -> Problem(message)
        Ok(built) ->
          Panel(
            text.progression_view(built, session.player),
            abc.render(notation.from_progression(
              built,
              session.player,
              session.tempo,
            )),
          )
      }

    LineView ->
      case changes(session) {
        Error(message) -> Problem(message)
        Ok(built) -> {
          let line = lick.over_progression(built, options(session))
          Panel(
            text.lick_view(
              line,
              heading(session, built),
              session.player,
              built.key,
            ),
            abc.render(notation.from_line_with_backing(
              line,
              built,
              heading(session, built),
              session.player,
              session.tempo,
            )),
          )
        }
      }

    AnalysisView ->
      case changes(session) {
        Error(message) -> Problem(message)
        Ok(built) ->
          Panel(
            text.analysis_view(
              progression.chords(built),
              heading(session, built),
              session.player,
              built.key,
            ),
            abc.render(notation.from_progression(
              built,
              session.player,
              session.tempo,
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

/// Whether the key control does anything from here. Typed changes carry their
/// own key, so the picker has nothing to say about them.
pub fn uses_key(session: Session) -> Bool {
  case session.view {
    ScaleView -> True
    ProgressionView | LineView | AnalysisView -> !typing_changes(session)
    ChordView -> False
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
