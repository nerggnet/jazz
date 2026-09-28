//// The web interface.
////
//// A view over `jazz/session` and very little else: the model, the update and
//// every decision about what to show live in the session, which is why they
//// can be tested without a browser. What is here is elements, and the bridge
//// to abcjs that turns a tune into notation and into sound.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import jazz/harmony
import jazz/instrument
import jazz/lick
import jazz/pattern
import jazz/pitch
import jazz/progression
import jazz/scale
import jazz/session.{type Session}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/event

pub type Model {
  Model(session: Session, playing: Bool)
}

pub type Msg {
  /// Anything the session already knows how to do.
  Did(session.Action)
  Play
  Hush
  Ended
  Keep
}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let _ = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_arguments) -> #(Model, Effect(Msg)) {
  let model = Model(session.new(), False)
  #(model, ready(model))
}

/// The sounds for whatever is on screen, fetched ahead of being asked for,
/// and then every other sound this horn could need.
fn ready(model: Model) -> Effect(Msg) {
  let everything =
    effect.from(fn(_) { fetch_every_sound(session.sounds(model.session)) })
  case session.panel(model.session) {
    session.Panel(_, abc) -> effect.batch([warm(abc), everything])
    session.Problem(_) -> everything
  }
}

fn update(model: Model, message: Msg) -> #(Model, Effect(Msg)) {
  case message {
    // Changing what is on screen while it is playing would leave the sound
    // and the notation describing different things.
    Did(action) -> {
      let moved = Model(session.update(model.session, action), False)
      // Whatever is on screen is what Play will play, so its sounds can be
      // fetched now rather than after somebody has asked to hear them.
      case model.playing {
        True -> #(moved, effect.batch([silence(), ready(moved)]))
        False -> #(moved, ready(moved))
      }
    }
    Play ->
      case session.panel(model.session) {
        session.Panel(_, abc) -> #(
          Model(..model, playing: True),
          sound(
            abc,
            !model.session.horn_sounds,
            model.session.swing,
            model.session.count_in,
            model.session.round_and_round,
          ),
        )
        session.Problem(_) -> #(model, effect.none())
      }
    // Nothing about the page changes: the file is handed to the browser and
    // the browser takes it from there.
    Keep ->
      case session.sheet(model.session) {
        Ok(#(name, body)) -> #(model, keep(name, body))
        Error(_) -> #(model, effect.none())
      }
    Hush -> #(Model(..model, playing: False), silence())
    Ended -> #(Model(..model, playing: False), effect.none())
  }
}

fn sound(
  abc: String,
  quiet_horn: Bool,
  swing: Bool,
  count_in: Bool,
  again: Bool,
) -> Effect(Msg) {
  effect.from(fn(dispatch) {
    play(abc, quiet_horn, swing, count_in, again, fn() { dispatch(Ended) })
  })
}

/// MusicXML is text, and its media type is the one notation programs look for.
fn keep(name: String, body: String) -> Effect(Msg) {
  effect.from(fn(_) {
    download(name, body, "application/vnd.recordare.musicxml+xml")
  })
}

/// Fetching the sounds is worth doing early and never worth waiting for.
fn warm(abc: String) -> Effect(Msg) {
  effect.from(fn(_) { fetch_sounds(abc) })
}

fn silence() -> Effect(Msg) {
  effect.from(fn(_dispatch) { stop() })
}

// --- View --------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([attribute.class("app")], [
    banner(model),
    tabs(model),
    controls(model),
    stage(model),
  ])
}

fn banner(model: Model) -> Element(Msg) {
  let written = pitch.class_to_string(session.written_key(model.session))
  let concert = pitch.class_to_string(model.session.key)
  html.header([attribute.class("banner")], [
    html.h1([], [html.text("jazz")]),
    html.p([attribute.class("blurb")], [
      html.text(instrument.label(model.session.player)),
      html.text(case instrument.is_concert(model.session.player) {
        True -> ""
        False -> " reads " <> written <> " for concert " <> concert
      }),
    ]),
  ])
}

fn tabs(model: Model) -> Element(Msg) {
  html.div(
    [attribute.class("tabs")],
    list.map(session.all_views(), fn(one) {
      html.button(
        [
          attribute.class(case one == model.session.view {
            True -> "tab chosen"
            False -> "tab"
          }),
          event.on_click(Did(session.ChooseView(one))),
        ],
        [html.text(session.view_name(one))],
      )
    }),
  )
}

/// Every control is named, and stays the element it was named as.
///
/// The list changes shape from view to view and even within one -- the
/// pattern picker steps aside once the scale is being harmonised rather than
/// played -- and without a name the browser matches them up by position. A
/// `<select>` re-used that way keeps whichever option was showing, so the
/// picker ends up displaying one thing and meaning another.
fn controls(model: Model) -> Element(Msg) {
  let shared = [
    #("instrument", instruments(model)),
    #("tempo", tempos(model)),
  ]
  let particular = case model.session.view {
    session.ScaleView ->
      list.flatten([
        [#("key", keys(model)), #("scale", scales(model))],
        case session.showing_chords(model.session) {
          True -> []
          False -> [#("pattern", patterns(model))]
        },
        [#("flavour", flavours(model)), #("round", all_keys(model))],
      ])
    session.ChordView ->
      list.flatten([
        [#("chord", chord_box(model))],
        case session.showing_chords(model.session) {
          True -> []
          False -> [#("arpeggio", arpeggios(model))]
        },
        [#("flavour", flavours(model)), #("round", all_keys(model))],
      ])
    session.ProgressionView -> source(model, [])
    session.LineView ->
      case session.generating_tune(model.session) {
        True ->
          source(model, [
            #("round", all_keys(model)),
            #("seed", seed_box(model)),
            #("tune-seed", tune_seed_box(model)),
            #("again", again()),
          ])
        False ->
          source(model, [
            #("level", levels(model)),
            #("round", all_keys(model)),
            #("seed", seed_box(model)),
            #("again", again()),
          ])
      }
    session.AnalysisView -> source(model, [])
  }
  keyed.div([attribute.class("controls")], list.append(shared, particular))
}

fn instruments(model: Model) -> Element(Msg) {
  field(
    "Instrument",
    html.select(
      [event.on_change(fn(name) { Did(session.ChooseInstrument(name)) })],
      list.map(instrument.all(), fn(one) {
        html.option(
          [
            attribute.value(one.id),
            attribute.selected(one.id == model.session.player.id),
          ],
          instrument.label(one),
        )
      }),
    ),
  )
}

fn tempos(model: Model) -> Element(Msg) {
  field(
    "Tempo",
    html.select(
      [event.on_change(fn(name) { Did(session.ChooseTempoNamed(name)) })],
      list.map(session.tempo_choices(), fn(one) {
        html.option(
          [
            attribute.value(int.to_string(one)),
            attribute.selected(one == model.session.tempo),
          ],
          int.to_string(one),
        )
      }),
    ),
  )
}

fn keys(model: Model) -> Element(Msg) {
  let chosen = pitch.class_to_string(model.session.key)
  field(
    "Concert key",
    html.div([attribute.class("stepper")], [
      html.button(
        [attribute.class("step"), event.on_click(Did(session.StepKey(-1)))],
        [html.text("\u{2039}")],
      ),
      html.select(
        [event.on_change(fn(name) { Did(session.ChooseKeyNamed(name)) })],
        list.map(progression.cycle_of_fourths(pitch.natural(pitch.C)), fn(one) {
          let name = pitch.class_to_string(one)
          html.option(
            [attribute.value(name), attribute.selected(name == chosen)],
            name,
          )
        }),
      ),
      html.button(
        [attribute.class("step"), event.on_click(Did(session.StepKey(1)))],
        [html.text("\u{203A}")],
      ),
    ]),
  )
}

fn scales(model: Model) -> Element(Msg) {
  field(
    "Scale",
    html.select(
      [event.on_change(fn(name) { Did(session.ChooseScaleNamed(name)) })],
      list.map(scale.all_kinds(), fn(one) {
        html.option(
          [
            attribute.value(scale.id(one)),
            attribute.selected(one == model.session.kind),
          ],
          scale.name(one),
        )
      }),
    ),
  )
}

fn patterns(model: Model) -> Element(Msg) {
  field(
    "Pattern",
    html.select(
      [event.on_change(fn(name) { Did(session.ChoosePatternNamed(name)) })],
      list.map(pattern.all(), fn(one) {
        html.option(
          [
            attribute.value(pattern.id(one)),
            attribute.selected(one == model.session.shape),
          ],
          pattern.name(one),
        )
      }),
    ),
  )
}

/// Which chords to draw out of the scale, if any. The first entry is the
/// scale on its own, which is what the view was before there were chords in
/// it and what it goes back to.
fn flavours(model: Model) -> Element(Msg) {
  field(
    "Chords",
    html.select(
      [event.on_change(fn(name) { Did(session.ChooseFlavourNamed(name)) })],
      [
        html.option(
          [
            attribute.value(session.plain),
            attribute.selected(model.session.flavour == None),
          ],
          "None",
        ),
        ..list.map(harmony.all_flavours(), fn(one) {
          html.option(
            [
              attribute.value(harmony.id(one)),
              attribute.selected(model.session.flavour == Some(one)),
            ],
            harmony.name(one),
          )
        })
      ],
    ),
  )
}

fn arpeggios(model: Model) -> Element(Msg) {
  field(
    "Pattern",
    html.select(
      [event.on_change(fn(name) { Did(session.ChooseArpeggioNamed(name)) })],
      list.map(pattern.arpeggios(), fn(one) {
        html.option(
          [
            attribute.value(pattern.arpeggio_id(one)),
            attribute.selected(one == model.session.arpeggio),
          ],
          pattern.arpeggio_name(one),
        )
      }),
    ),
  )
}

/// The same thing round the cycle of fourths, which is how a scale pattern,
/// an arpeggio and a lick are all actually practised once they are under the
/// fingers.
fn all_keys(model: Model) -> Element(Msg) {
  field(
    "Keys",
    html.select(
      [
        event.on_change(fn(name) { Did(session.RoundTheKeys(name == "all")) }),
      ],
      [
        html.option(
          [
            attribute.value("one"),
            attribute.selected(!model.session.round_the_keys),
          ],
          "This one",
        ),
        html.option(
          [
            attribute.value("all"),
            attribute.selected(model.session.round_the_keys),
          ],
          "All twelve",
        ),
      ],
    ),
  )
}

/// Where the changes come from. Typed ones carry their own key, so the key
/// picker steps aside for the box.
fn source(
  model: Model,
  rest: List(#(String, Element(Msg))),
) -> List(#(String, Element(Msg))) {
  let picked = case
    session.typing_changes(model.session),
    session.generating_tune(model.session)
  {
    True, _ -> [#("changes", changes(model)), #("typed", changes_box(model))]
    _, True -> [
      #("key", keys(model)),
      #("changes", changes(model)),
      #("bars", bars(model)),
      #("level", levels(model)),
      #("fresh", fresh_tune()),
    ]
    _, _ -> [#("key", keys(model)), #("changes", changes(model))]
  }
  list.append(picked, rest)
}

fn bars(model: Model) -> Element(Msg) {
  field(
    "Bars",
    html.select(
      [event.on_change(fn(name) { Did(session.ChooseBarsNamed(name)) })],
      list.map(session.bar_choices(), fn(one) {
        html.option(
          [
            attribute.value(int.to_string(one)),
            attribute.selected(one == model.session.bars),
          ],
          int.to_string(one),
        )
      }),
    ),
  )
}

fn fresh_tune() -> Element(Msg) {
  field(
    "\u{00A0}",
    html.button(
      [attribute.class("primary"), event.on_click(Did(session.NewTune))],
      [html.text("New tune")],
    ),
  )
}

fn changes(model: Model) -> Element(Msg) {
  field(
    "Changes",
    html.select(
      [event.on_change(fn(id) { Did(session.ChooseProgression(id)) })],
      [
        html.option(
          [
            attribute.value(session.generated),
            attribute.selected(session.generating_tune(model.session)),
          ],
          "made up",
        ),
        html.option(
          [
            attribute.value(session.typed),
            attribute.selected(session.typing_changes(model.session)),
          ],
          "typed in",
        ),
        ..list.map(progression.catalogue(), fn(one) {
          html.option(
            [
              attribute.value(one.0),
              attribute.selected(one.0 == model.session.progression_id),
            ],
            one.0,
          )
        })
      ],
    ),
  )
}

fn levels(model: Model) -> Element(Msg) {
  field(
    "Level",
    html.select(
      [event.on_change(fn(name) { Did(session.ChooseLevelNamed(name)) })],
      list.map(lick.all_levels(), fn(one) {
        html.option(
          [
            attribute.value(lick.level_name(one)),
            attribute.selected(one == model.session.level),
          ],
          lick.level_name(one),
        )
      }),
    ),
  )
}

fn again() -> Element(Msg) {
  field(
    "\u{00A0}",
    html.button(
      [attribute.class("primary"), event.on_click(Did(session.NewLine))],
      [
        html.text("Another line"),
      ],
    ),
  )
}

/// The number that made this line.
///
/// The readout has always ended by naming it, and until now there was
/// nowhere to put it back, so a line somebody liked yesterday was gone. It
/// is typed rather than changed as you go, because every keystroke would
/// otherwise engrave a line nobody asked for.
fn seed_box(model: Model) -> Element(Msg) {
  seed_field("Seed", model.session.seed, session.TypeSeed)
}

fn tune_seed_box(model: Model) -> Element(Msg) {
  seed_field("Tune", model.session.tune_seed, session.TypeTuneSeed)
}

fn seed_field(
  name: String,
  value: Int,
  action: fn(String) -> session.Action,
) -> Element(Msg) {
  field(
    name,
    html.input([
      attribute.class("seed"),
      attribute.type_("text"),
      attribute.value(int.to_string(value)),
      event.on_change(fn(text) { Did(action(text)) }),
    ]),
  )
}

fn chord_box(model: Model) -> Element(Msg) {
  field(
    "Chord",
    html.input([
      attribute.class("wide"),
      attribute.type_("text"),
      attribute.value(model.session.chord_text),
      attribute.placeholder("Bb7#9"),
      event.on_input(fn(text) { Did(session.TypeChord(text)) }),
    ]),
  )
}

fn changes_box(model: Model) -> Element(Msg) {
  named_field(
    "field grow",
    "Bars, separated by |  (Enter to apply)",
    html.input([
      attribute.class("wide changes"),
      attribute.type_("text"),
      attribute.value(model.session.changes_text),
      attribute.placeholder("| Dm7 | G7 | Cmaj7 | Cmaj7 |"),
      // On change rather than on input: a whole tune is a lot of keystrokes,
      // and regenerating the line and engraving the score after every one of
      // them makes typing feel like wading.
      event.on_change(fn(text) { Did(session.TypeChanges(text)) }),
    ]),
  )
}

fn field(name: String, control: Element(Msg)) -> Element(Msg) {
  named_field("field", name, control)
}

fn named_field(
  class: String,
  name: String,
  control: Element(Msg),
) -> Element(Msg) {
  html.label([attribute.class(class)], [
    html.span([attribute.class("name")], [html.text(name)]),
    control,
  ])
}

fn stage(model: Model) -> Element(Msg) {
  case session.panel(model.session) {
    session.Problem(message) ->
      html.div([attribute.class("stage")], [
        html.div([attribute.class("problem")], [html.text(message)]),
      ])
    session.Panel(readout, abc) ->
      html.div([attribute.class("stage")], [
        html.div([attribute.class("paper")], [
          element.unsafe_raw_html(
            "",
            "div",
            [attribute.class("notation")],
            render_notation(abc),
          ),
          html.div([attribute.class("playback")], [
            swing_switch(model),
            count_switch(model),
            loop_switch(model),
            horn_switch(model),
            play_button(model),
            keep_button(),
          ]),
        ]),
        html.pre([attribute.class("readout")], [html.text(readout)]),
      ])
  }
}

/// Swing is the default because this is a jazz tool, but a scale practised
/// long-short is a different exercise from one practised straight, so it is
/// a switch rather than a decision.
fn swing_switch(model: Model) -> Element(Msg) {
  switch(model.session.swing, session.SwingIt, "Swing", "Straight")
}

fn count_switch(model: Model) -> Element(Msg) {
  switch(model.session.count_in, session.CountIn, "Count in", "No count")
}

fn loop_switch(model: Model) -> Element(Msg) {
  switch(model.session.round_and_round, session.RoundAndRound, "Loop", "Once")
}

fn switch(
  on: Bool,
  action: fn(Bool) -> session.Action,
  when_on: String,
  when_off: String,
) -> Element(Msg) {
  html.button(
    [
      attribute.class(case on {
        True -> "toggle on"
        False -> "toggle"
      }),
      event.on_click(Did(action(!on))),
    ],
    [
      html.text(case on {
        True -> when_on
        False -> when_off
      }),
    ],
  )
}

/// Only worth offering where there is a backing to play against.
fn horn_switch(model: Model) -> Element(Msg) {
  case model.session.view {
    session.LineView ->
      html.button(
        [
          attribute.class(case model.session.horn_sounds {
            True -> "toggle on"
            False -> "toggle"
          }),
          event.on_click(Did(session.PlayTheHorn(!model.session.horn_sounds))),
        ],
        [
          html.text(case model.session.horn_sounds {
            True -> "Horn on"
            False -> "Horn off"
          }),
        ],
      )
    _ -> element.none()
  }
}

/// The score as a file, for a music stand rather than a screen.
fn keep_button() -> Element(Msg) {
  html.button(
    [
      attribute.class("keep"),
      attribute.title("Download as MusicXML"),
      event.on_click(Keep),
    ],
    [html.text("Download")],
  )
}

fn play_button(model: Model) -> Element(Msg) {
  case model.playing {
    True ->
      html.button([attribute.class("play playing"), event.on_click(Hush)], [
        html.text("Stop"),
      ])
    False ->
      html.button([attribute.class("play"), event.on_click(Play)], [
        html.text("Play"),
      ])
  }
}

// --- abcjs -------------------------------------------------------------------
//
// Each of these has a Gleam body so the module still compiles for Erlang,
// where there is no browser and none of it can run.

@external(javascript, "./jazz_web_ffi.mjs", "renderNotation")
fn render_notation(abc: String) -> String {
  case abc {
    _ -> ""
  }
}

@external(javascript, "./jazz_web_ffi.mjs", "play")
fn play(
  abc: String,
  quiet_horn: Bool,
  swing: Bool,
  count_in: Bool,
  again: Bool,
  on_ended: fn() -> Nil,
) -> Nil {
  case abc, quiet_horn, swing, count_in, again {
    _, _, _, _, _ -> on_ended()
  }
}

@external(javascript, "./jazz_web_ffi.mjs", "warm")
fn fetch_sounds(abc: String) -> Nil {
  case abc {
    _ -> Nil
  }
}

@external(javascript, "./jazz_web_ffi.mjs", "prefetch")
fn fetch_every_sound(spec: String) -> Nil {
  case spec {
    _ -> Nil
  }
}

@external(javascript, "./jazz_web_ffi.mjs", "download")
fn download(name: String, body: String, kind: String) -> Nil {
  case name, body, kind {
    _, _, _ -> Nil
  }
}

@external(javascript, "./jazz_web_ffi.mjs", "stop")
fn stop() -> Nil {
  Nil
}
