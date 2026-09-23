//// Generating single note lines over changes.
////
//// There is no library of transcribed licks here, on purpose. Stored licks
//// belong to whoever played them, and learning them one at a time teaches the
//// phrases rather than the language. What is encoded instead is the grammar
//// that produces them:
////
////   - break the form into phrases, and leave silence at the end of each,
////   - break the form into phrases, and leave silence at the end of each,
////   - land on a chord tone on the strong beat, usually the third or seventh,
////   - arrive at it by step, by chromatic approach, or by enclosure,
////   - fill the space between with scale motion, an arpeggio, or a pattern.
////
//// The phrases come first because everything else hangs off them. Without
//// them a chorus is thirty two bars of unbroken eighth notes, which nobody
//// plays, nobody can read, and nobody can breathe through.
////
//// The phrases come first because everything else depends on them. Without
//// them a chorus is thirty two bars of unbroken eighth notes, which nobody
//// plays, nobody can read, and nobody can breathe through.
////
//// Everything is generated from a seed, so a line can be recovered later, and
//// stays at concert pitch until something renders it.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import jazz/chord.{type Chord}
import jazz/internal/num
import jazz/internal/random.{type Random}
import jazz/interval
import jazz/pitch.{type Pitch, type PitchClass, Pitch}
import jazz/progression.{type Progression}
import jazz/scale

/// Durations are counted in eighth notes, so a bar of four four is eight.
pub const bar = 8

pub type Event {
  /// A tied note is held into the one after it rather than played again.
  Tone(pitch: Pitch, duration: Int, tied: Bool)
  Rest(duration: Int)
  /// The three tones after this one are a triplet: each written as an
  /// eighth, the three of them played in the time of two.
  Triplet
}

/// How much room a run of events takes up, which for a triplet is less than
/// the notes in it are written as.
pub fn room(events: List(Event)) -> Int {
  case events {
    [] -> 0
    [Triplet, ..rest] -> 2 + room(list.drop(rest, 3))
    [Tone(_, length, _), ..rest] -> length + room(rest)
    [Rest(length), ..rest] -> length + room(rest)
  }
}

/// The stretch of line played over one chord, with a note on how it was made.
pub type Segment {
  Segment(chord: Chord, events: List(Event), target: String, device: String)
}

pub type Line {
  Line(segments: List(Segment), seed: Int, arc: Arc)
}

/// The shape the line's register makes across the whole form.
///
/// Without one, targets are chosen purely for smooth voice leading, which
/// minimises motion by definition: the line sits in one octave and stays
/// there all chorus. An arc gives it somewhere to be going.
pub type Arc {
  /// Up to a peak around two thirds through, then away. The usual shape of
  /// a chorus, and the one that sounds like it was heading somewhere.
  Arch
  /// Climbing throughout.
  Rise
  /// Two arches, for a longer form that would sag in the middle of one.
  Wave
}

pub fn arc_name(arc: Arc) -> String {
  case arc {
    Arch -> "an arch"
    Rise -> "a climb"
    Wave -> "two arches"
  }
}

/// How much vocabulary to draw on.
pub type Level {
  Beginner
  Intermediate
  Advanced
}

/// How the line arrives at the next target note.
pub type Approach {
  Direct
  ChromaticBelow
  ChromaticAbove
  DiatonicAbove
  DoubleChromaticBelow
  EnclosureAboveBelow
  EnclosureBelowAbove
  /// Arrive on the next chord before it does, and hold the note over the bar
  /// line. The most characteristic rhythm in the idiom.
  Anticipate
}

/// What fills the space between one target and the next.
pub type Connector {
  ScaleRun
  Arpeggio
  DigitalPattern
  ChordTonesDown
}

pub type Options {
  Options(level: Level, seed: Int, low: Pitch, high: Pitch)
}

/// Sensible defaults at concert pitch: two octaves in the middle of the horn.
pub fn options(level: Level, seed: Int) -> Options {
  Options(level, seed, pitch.note(pitch.A, 0, 3), pitch.note(pitch.A, 0, 5))
}

pub fn level_from_string(text: String) -> Result(Level, String) {
  case string.lowercase(string.trim(text)) {
    "beginner" | "beginners" | "easy" | "1" -> Ok(Beginner)
    "intermediate" | "medium" | "2" -> Ok(Intermediate)
    "advanced" | "hard" | "3" -> Ok(Advanced)
    _ ->
      Error(
        "unknown level `" <> text <> "`, try beginner, intermediate or advanced",
      )
  }
}

pub fn all_levels() -> List(Level) {
  [Beginner, Intermediate, Advanced]
}

pub fn level_name(level: Level) -> String {
  case level {
    Beginner -> "beginner"
    Intermediate -> "intermediate"
    Advanced -> "advanced"
  }
}

// --- Generating --------------------------------------------------------------

/// A line over a named progression.
pub fn over_progression(subject: Progression, settings: Options) -> Line {
  over_chords(spread(subject), settings)
}

/// A line over a list of chords, each with a length in eighth notes.
pub fn over_chords(items: List(#(Chord, Int)), settings: Options) -> Line {
  let generator = random.new(settings.seed)
  let total = list.fold(items, 0, fn(sum, one) { sum + one.1 })
  let #(windows, generator) =
    phrase_plan(total, settings.level, generator, 0, [])
  let #(shape, generator) = random.pick(generator, arcs(), Arch)
  let #(targets, generator) =
    choose_targets(items, settings, shape, total, generator, None, 0, [])
  let segments =
    fill_all(items, targets, windows, settings, generator, 0, Echo(None, 0), [])
  Line(segments, settings.seed, shape)
}

/// Arches mostly, because that is what a chorus does.
fn arcs() -> List(Arc) {
  [Arch, Arch, Rise, Wave]
}

/// Where the line ought to be sitting at a given point in the form.
fn aiming_at(shape: Arc, at: Int, total: Int, settings: Options) -> Int {
  let low = pitch.to_midi(settings.low)
  let high = pitch.to_midi(settings.high)
  let position = case total <= 0 {
    True -> 0
    False -> at * 100 / total
  }
  low + { high - low } * height_at(turns(shape), position) / 100
}

/// The arc as a few turning points, in hundredths of the form and of the
/// range, with straight lines between them.
fn turns(shape: Arc) -> List(#(Int, Int)) {
  case shape {
    Arch -> [#(0, 25), #(58, 90), #(100, 28)]
    Rise -> [#(0, 15), #(100, 90)]
    Wave -> [#(0, 28), #(30, 78), #(55, 38), #(82, 90), #(100, 45)]
  }
}

fn height_at(points: List(#(Int, Int)), position: Int) -> Int {
  case points {
    [] -> 50
    [#(_, only)] -> only
    [#(from, low), #(to, high), ..rest] ->
      case position <= to {
        False -> height_at([#(to, high), ..rest], position)
        True ->
          case to == from {
            True -> high
            False -> low + { high - low } * { position - from } / { to - from }
          }
      }
  }
}

// --- Phrasing ----------------------------------------------------------------

/// A stretch of the form where the line plays, in eighth notes from the top.
/// Everything between one window and the next is silence.
type Window {
  Window(from: Int, until: Int)
}

/// Break the form into phrases, each coming in near its start and stopping
/// before its end.
fn phrase_plan(
  total: Int,
  level: Level,
  generator: Random,
  at: Int,
  acc: List(Window),
) -> #(List(Window), Random) {
  case at >= total {
    True -> #(list.reverse(acc), generator)
    False -> {
      let #(wanted, generator) =
        random.pick(generator, phrase_lengths(level), 2 * bar)
      let span = int.min(wanted, total - at)
      let #(late, generator) = entry(level, generator)
      let #(wanted_rest, generator) = breath(level, generator)

      // However the dice fall, a phrase plays at least one note.
      let late = int.max(0, int.min(late, span - 1))
      let rest = int.max(0, int.min(wanted_rest, span - late - 1))

      phrase_plan(total, level, generator, at + span, [
        Window(at + late, at + span - rest),
        ..acc
      ])
    }
  }
}

fn phrase_lengths(level: Level) -> List(Int) {
  case level {
    Beginner -> [2 * bar]
    Intermediate -> [2 * bar, 2 * bar, 4 * bar]
    Advanced -> [2 * bar, 4 * bar, 4 * bar]
  }
}

/// How late into a phrase the line comes in.
fn entry(level: Level, generator: Random) -> #(Int, Random) {
  case level {
    Beginner -> #(0, generator)
    Intermediate -> random.below(generator, 3)
    Advanced -> random.below(generator, 5)
  }
}

/// How much silence to leave at the end of a phrase. Beginners get more of
/// it, because space is the part that takes longest to learn to trust.
fn breath(level: Level, generator: Random) -> #(Int, Random) {
  let #(least, spread) = case level {
    Beginner -> #(4, 5)
    Intermediate -> #(2, 4)
    Advanced -> #(1, 4)
  }
  let #(extra, generator) = random.below(generator, spread)
  #(least + extra, generator)
}

/// The part of a segment that gets played, as offsets inside it.
fn clip(windows: List(Window), at: Int, length: Int) -> Window {
  case
    list.find(windows, fn(one) { one.from < at + length && one.until > at })
  {
    Ok(one) ->
      Window(int.max(0, one.from - at), int.min(length, one.until - at))
    Error(_) -> Window(0, 0)
  }
}

/// Whether the line is sounding at a given point in the form.
fn sounding(windows: List(Window), at: Int) -> Bool {
  list.any(windows, fn(one) { one.from <= at && one.until > at })
}

/// Split each bar's time evenly between the chords in it.
fn spread(subject: Progression) -> List(#(Chord, Int)) {
  list.flat_map(subject.bars, fn(each) {
    list.zip(each.chords, progression.shares(list.length(each.chords), bar))
  })
}

/// First pass: decide where the line has to be on each downbeat. Doing this
/// before filling anything is what lets a segment approach the note the next
/// segment is going to start on.
fn choose_targets(
  items: List(#(Chord, Int)),
  settings: Options,
  shape: Arc,
  total: Int,
  generator: Random,
  previous: Option(Pitch),
  at: Int,
  acc: List(#(Pitch, String)),
) -> #(List(#(Pitch, String)), Random) {
  case items {
    [] -> #(list.reverse(acc), generator)
    [#(current, length), ..rest] -> {
      let tones = chord_pitches(current, settings)
      let #(wanted, label, generator) =
        target_class(current, settings.level, generator)
      let candidates = case
        list.filter(tones, fn(one) { pitch.same(one.class, wanted) })
      {
        [] -> tones
        found -> found
      }
      let aim = aiming_at(shape, at, total, settings)
      let target = case previous {
        Some(note) ->
          settling(candidates, pitch.to_midi(note), aim, settings.low)
        None -> nearest_to(candidates, aim, settings.low)
      }
      choose_targets(
        rest,
        settings,
        shape,
        total,
        generator,
        Some(target),
        at + length,
        [#(target, label), ..acc],
      )
    }
  }
}

fn fill_all(
  items: List(#(Chord, Int)),
  targets: List(#(Pitch, String)),
  windows: List(Window),
  settings: Options,
  generator: Random,
  at: Int,
  carry: Echo,
  acc: List(Segment),
) -> List(Segment) {
  case items, targets {
    [#(current, length), ..rest], [#(target, label), ..later] -> {
      let played = clip(windows, at, length)
      // An approach note only means anything when it runs into the note it is
      // approaching. Across a rest, the next phrase starts fresh instead.
      let next = case later {
        [#(upcoming, _), ..] ->
          case played.until == length && sounding(windows, at + length) {
            True -> Some(upcoming)
            False -> None
          }
        [] -> None
      }
      let #(segment, generator, carry) =
        fill(
          current,
          length,
          played,
          target,
          label,
          next,
          settings,
          carry,
          at + played.from,
          generator,
        )
      fill_all(rest, later, windows, settings, generator, at + length, carry, [
        segment,
        ..acc
      ])
    }
    _, _ -> list.reverse(acc)
  }
}

fn fill(
  current: Chord,
  length: Int,
  played: Window,
  target: Pitch,
  label: String,
  next: Option(Pitch),
  settings: Options,
  carry: Echo,
  start: Int,
  generator: Random,
) -> #(Segment, Random, Echo) {
  case int.max(0, played.until - played.from) {
    // A silent bar hands the figure on untouched, so a phrase can still
    // answer the one before it across the gap.
    0 -> #(Segment(current, [Rest(length)], "-", "resting"), generator, carry)
    slots ->
      sound(
        current,
        length,
        played,
        slots,
        target,
        label,
        next,
        settings,
        carry,
        start,
        generator,
      )
  }
}

fn sound(
  current: Chord,
  length: Int,
  played: Window,
  slots: Int,
  target: Pitch,
  label: String,
  next: Option(Pitch),
  settings: Options,
  carry: Echo,
  start: Int,
  generator: Random,
) -> #(Segment, Random, Echo) {
  let tones = scale_pitches(current, settings)
  let arpeggio = chord_pitches(current, settings)

  // Which way the line is heading, decided before the figure so that a
  // figure carried over keeps the direction it was thought of in. The same
  // offsets read backwards would be an inversion, not a sequence.
  let direction = case next {
    Some(upcoming) ->
      case pitch.to_midi(upcoming) >= pitch.to_midi(target) {
        True -> 1
        False -> -1
      }
    None -> 1
  }

  let #(figure, generator) =
    choose_figure(slots, next, direction, settings, carry, generator)

  let landing = arrival(figure.shape, next)
  let approach = build_approach(landing, next, tones)

  // The approach notes are always eighths; what is left is the room the
  // figure itself has to fill, and the rhythm says how many notes that is.
  let #(beats, generator) =
    rhythm(
      start,
      slots - approach_length(landing),
      settings.level,
      generator,
      [],
    )
  let body =
    replay(
      figure.shape,
      int.max(0, notes_wanted(beats) - 1),
      tones,
      arpeggio,
      target,
    )
    |> mend(approach, rungs_of(figure.shape, tones, arpeggio), direction)

  let melody = lay(beats, [target, ..body], [])
  let arriving =
    list.map(approach, fn(one) { Tone(one, 1, landing == Anticipate) })

  let notes = list.append(melody, arriving)

  let after = length - played.until
  let events = list.flatten([silence(played.from), notes, silence(after)])

  #(
    Segment(
      chord: current,
      events: events,
      target: label,
      device: describe(figure, landing)
        <> case list.contains(beats, Three) {
        True -> ", in triplets"
        False -> ""
      }
        <> case after > 0 {
        True -> ", then a breath"
        False -> ""
      },
    ),
    generator,
    Echo(Some(figure.shape), case figure.repeated {
      True -> carry.run + 1
      False -> 0
    }),
  )
}

fn silence(length: Int) -> List(Event) {
  case length > 0 {
    True -> [Rest(length)]
    False -> []
  }
}

// --- Vocabulary --------------------------------------------------------------

fn approaches(level: Level) -> List(Approach) {
  case level {
    Beginner -> [Direct, Direct, ChromaticBelow, Anticipate]
    Intermediate -> [
      Direct,
      ChromaticBelow,
      ChromaticAbove,
      DiatonicAbove,
      EnclosureAboveBelow,
      Anticipate,
      Anticipate,
    ]
    Advanced -> [
      ChromaticBelow,
      DiatonicAbove,
      DoubleChromaticBelow,
      EnclosureAboveBelow,
      EnclosureBelowAbove,
      Anticipate,
      Anticipate,
    ]
  }
}

fn connectors(level: Level) -> List(Connector) {
  case level {
    Beginner -> [ScaleRun, ScaleRun, Arpeggio]
    Intermediate -> [ScaleRun, Arpeggio, DigitalPattern]
    Advanced -> [ScaleRun, Arpeggio, DigitalPattern, ChordTonesDown]
  }
}

/// Which chord tone to aim at. Beginners get the plain outline of the chord;
/// everyone else aims at the guide tones, because those are the notes that
/// say which chord it is.
fn target_class(
  current: Chord,
  level: Level,
  generator: Random,
) -> #(PitchClass, String, Random) {
  let available = chord.intervals(current)
  let wanted = case level {
    Beginner -> [1, 3, 5]
    Intermediate -> [3, 7, 3, 1, 5]
    Advanced -> [3, 7, 9, 13, 5]
  }
  let usable =
    list.filter(wanted, fn(number) {
      list.any(available, fn(step) { interval.number(step) == number })
    })
  let #(number, generator) = case usable {
    [] -> #(1, generator)
    some -> random.pick(generator, some, 1)
  }
  let step = case
    list.find(available, fn(one) { interval.number(one) == number })
  {
    Ok(found) -> found
    Error(_) -> interval.degree(1, 0)
  }
  #(
    interval.transpose_class(current.root, step),
    interval.to_degree_string(step),
    generator,
  )
}

fn approach_length(approach: Approach) -> Int {
  case approach {
    Direct -> 0
    ChromaticBelow | ChromaticAbove | DiatonicAbove | Anticipate -> 1
    DoubleChromaticBelow | EnclosureAboveBelow | EnclosureBelowAbove -> 2
  }
}

fn build_approach(
  approach: Approach,
  next: Option(Pitch),
  tones: List(Pitch),
) -> List(Pitch) {
  case next {
    None -> []
    Some(target) ->
      case approach {
        Direct -> []
        // The note itself, early: the tie is what makes it an anticipation
        // rather than the same note played twice.
        Anticipate -> [target]
        ChromaticBelow -> [semitone_below(target)]
        ChromaticAbove -> [semitone_above(target)]
        DiatonicAbove -> [step_from(tones, target, 1)]
        DoubleChromaticBelow -> [tone_below(target), semitone_below(target)]
        EnclosureAboveBelow -> [
          step_from(tones, target, 1),
          semitone_below(target),
        ]
        EnclosureBelowAbove -> [
          semitone_below(target),
          step_from(tones, target, 1),
        ]
      }
  }
}

/// A figure with the notes taken out of it: how far each step sits from the
/// one it started on, and how it arrived at whatever came next.
///
/// This is what makes a sequence possible. Offsets are counted in steps of a
/// ladder rather than in semitones, so replaying them from a new target over
/// a new chord gives the same shape spelled in the new harmony, which is what
/// a player does when they answer a bar with itself a step lower.
type Shape {
  Shape(connector: Connector, offsets: List(Int), approach: Approach)
}

/// What one segment hands to the next: the figure it played, and how many
/// times that figure has been running.
type Echo {
  Echo(shape: Option(Shape), run: Int)
}

/// A figure decided on, sized to the room available.
type Figure {
  Figure(shape: Shape, body: Int, repeated: Bool)
}

/// One move of a rhythm: a note of some length, or three in the time of two.
type Beat {
  Straight(length: Int)
  Three
}

/// How the room available is divided up, in eighths.
///
/// Mostly eighths, which is what the idiom is made of, with the occasional
/// quarter for the line to lean on and, for a player who can hold them
/// together, a triplet. A note longer than an eighth has to start on a beat
/// or it cannot be written down without tying it to something, and a triplet
/// has to fill a whole beat for the same reason.
fn rhythm(
  from: Int,
  room: Int,
  level: Level,
  generator: Random,
  acc: List(Beat),
) -> #(List(Beat), Random) {
  case room <= 0 {
    True -> #(list.reverse(acc), generator)
    False ->
      case room >= 2 && { from % 2 } == 0 {
        False ->
          rhythm(from + 1, room - 1, level, generator, [Straight(1), ..acc])
        True -> {
          // A level that never plays triplets does not draw for them either,
          // so its lines are the same lines they always were.
          let #(three, generator) = case tripling(level) {
            0 -> #(False, generator)
            odds -> random.chance(generator, odds)
          }
          case three {
            True -> rhythm(from + 2, room - 2, level, generator, [Three, ..acc])
            False -> {
              let #(hold, generator) = random.chance(generator, leaning(level))
              case hold {
                True ->
                  rhythm(from + 2, room - 2, level, generator, [
                    Straight(2),
                    ..acc
                  ])
                False ->
                  rhythm(from + 1, room - 1, level, generator, [
                    Straight(1),
                    ..acc
                  ])
              }
            }
          }
        }
      }
  }
}

/// How many notes a rhythm asks for.
fn notes_wanted(beats: List(Beat)) -> Int {
  list.fold(beats, 0, fn(total, one) {
    case one {
      Three -> total + 3
      Straight(_) -> total + 1
    }
  })
}

/// Pitches laid out on the rhythm, with a marker in front of every triplet.
fn lay(
  beats: List(Beat),
  pitches: List(Pitch),
  acc: List(Event),
) -> List(Event) {
  case beats, pitches {
    [], _ -> list.reverse(acc)
    _, [] -> list.reverse(acc)
    [Straight(length), ..rest], [one, ..more] ->
      lay(rest, more, [Tone(one, length, False), ..acc])
    [Three, ..rest], [first, second, third, ..more] ->
      lay(rest, more, [
        Tone(third, 1, False),
        Tone(second, 1, False),
        Tone(first, 1, False),
        Triplet,
        ..acc
      ])
    // Not enough left to make three of: write what there is straight rather
    // than leaving a triplet mark standing over the wrong number of notes.
    [Three, ..rest], [one, ..more] ->
      lay(rest, more, [Tone(one, 1, False), ..acc])
  }
}

/// How readily a level reaches for a triplet.
///
/// Not at all to begin with: an even stream of eighths is hard enough, and
/// three against two is the thing that makes a beginner's line fall apart.
fn tripling(level: Level) -> Int {
  case level {
    Beginner -> 0
    Intermediate -> 10
    Advanced -> 18
  }
}

/// How readily a level leans on a note instead of running eighths.
fn leaning(level: Level) -> Int {
  case level {
    Beginner -> 30
    Intermediate -> 18
    Advanced -> 10
  }
}

/// How often a level answers a figure with itself.
fn repeat_chance(level: Level) -> Int {
  case level {
    Beginner -> 40
    Intermediate -> 50
    Advanced -> 55
  }
}

/// Carry the last figure over, or think of a new one.
///
/// A figure is allowed to come back twice and no more. Stating an idea,
/// sequencing it, and then going somewhere else is the shape of the thing;
/// a fourth time is a stuck record.
fn choose_figure(
  slots: Int,
  next: Option(Pitch),
  direction: Int,
  settings: Options,
  carry: Echo,
  generator: Random,
) -> #(Figure, Random) {
  case carried(slots, next, carry) {
    Error(_) -> invent(slots, next, direction, settings, generator)
    Ok(#(shape, room)) -> {
      let #(again, generator) =
        random.chance(generator, repeat_chance(settings.level))
      case again {
        True -> #(Figure(shape, room, True), generator)
        False -> invent(slots, next, direction, settings, generator)
      }
    }
  }
}

/// The last figure, if there is one and it still fits.
fn carried(
  slots: Int,
  next: Option(Pitch),
  carry: Echo,
) -> Result(#(Shape, Int), Nil) {
  case carry.shape, carry.run < 2 {
    Some(shape), True -> {
      let room = slots - 1 - approach_length(arrival(shape, next))
      // A shorter room cuts the figure off, which still reads as the same
      // idea. A longer one would have to invent the end of it, so it does
      // not count as the same figure at all.
      case room > 0 && room <= list.length(shape.offsets) {
        True -> Ok(#(shape, room))
        False -> Error(Nil)
      }
    }
    _, _ -> Error(Nil)
  }
}

/// A figure has no approach when there is nothing after it to approach.
fn arrival(shape: Shape, next: Option(Pitch)) -> Approach {
  case next {
    Some(_) -> shape.approach
    None -> Direct
  }
}

fn invent(
  slots: Int,
  next: Option(Pitch),
  direction: Int,
  settings: Options,
  generator: Random,
) -> #(Figure, Random) {
  let #(wanted, generator) = case next {
    None -> #(Direct, generator)
    Some(_) -> random.pick(generator, approaches(settings.level), Direct)
  }
  let #(connector, generator) =
    random.pick(generator, connectors(settings.level), ScaleRun)

  // The approach has to fit in what is left of the phrase; if it does not,
  // walk in directly.
  let #(chosen, body) = case slots - 1 - approach_length(wanted) {
    room if room >= 0 -> #(wanted, room)
    _ -> #(Direct, slots - 1)
  }

  let offsets =
    steps(connector, body) |> list.map(fn(step) { direction * step })

  #(Figure(Shape(connector, offsets, chosen), body, False), generator)
}

/// The shape of a figure, before it knows what notes it will be made of.
fn steps(connector: Connector, count: Int) -> List(Int) {
  case connector {
    ScaleRun | Arpeggio ->
      num.counting(count) |> list.map(fn(step) { step + 1 })
    ChordTonesDown ->
      num.counting(count) |> list.map(fn(step) { -1 * { step + 1 } })
    // The one-two-three-five pattern every player runs through the cycle,
    // each group starting a step higher than the last.
    DigitalPattern ->
      num.counting(count)
      |> list.map(fn(step) {
        let position = step + 1
        let offset = case position % 4 {
          0 -> 0
          1 -> 1
          2 -> 2
          _ -> 4
        }
        position / 4 + offset
      })
  }
}

/// Turn a shape back into notes, from a given starting note, turning round at
/// the edges of the range rather than repeating the top note.
fn replay(
  shape: Shape,
  body: Int,
  tones: List(Pitch),
  arpeggio: List(Pitch),
  from: Pitch,
) -> List(Pitch) {
  let rungs = rungs_of(shape, tones, arpeggio)
  let start = index_of(rungs, from)
  // A figure is sized in eighths, and a triplet asks for three notes where
  // two were expected, so a shape can be asked for more than it has. Running
  // it round again is a sequence, which is a thing a player does; stopping
  // short would leave the bar with a hole in it.
  over_and_over(shape.offsets, body, [])
  |> list.map(fn(offset) { at(rungs, along(rungs, start, offset)) })
}

fn over_and_over(pattern: List(Int), wanted: Int, acc: List(Int)) -> List(Int) {
  case pattern, wanted <= list.length(acc) {
    [], _ -> list.reverse(acc)
    _, True -> list.reverse(acc)
    _, False ->
      over_and_over(
        pattern,
        wanted,
        list.fold(pattern, acc, fn(kept, one) { [one, ..kept] }),
      )
  }
  |> list.take(wanted)
}

fn rungs_of(
  shape: Shape,
  tones: List(Pitch),
  arpeggio: List(Pitch),
) -> List(Pitch) {
  case shape.connector {
    ScaleRun | DigitalPattern -> tones
    Arpeggio | ChordTonesDown -> arpeggio
  }
}

fn along(rungs: List(Pitch), from: Int, offset: Int) -> Int {
  let octave = list.length(list.unique(list.map(rungs, fn(one) { one.class })))
  wrap(from + offset, list.length(rungs), octave, 0)
}

/// A body note landing on the note the approach was about to play sounds it
/// twice, which reads as a stutter rather than as anything. Moving the last
/// one a rung further keeps the count and loses the repeat.
fn mend(
  body: List(Pitch),
  approach: List(Pitch),
  rungs: List(Pitch),
  direction: Int,
) -> List(Pitch) {
  case list.last(body), list.first(approach) {
    Ok(tail), Ok(head) ->
      case pitch.to_midi(tail) == pitch.to_midi(head) {
        False -> body
        True -> {
          let before = case list.reverse(body) {
            [_, earlier, ..] -> pitch.to_midi(earlier)
            _ -> -1
          }
          let at_index = index_of(rungs, tail)
          // On in the direction of travel first, and back the other way if
          // that only moves the stutter somewhere else.
          let candidates =
            [direction, -direction]
            |> list.map(fn(step) { at(rungs, along(rungs, at_index, step)) })
            |> list.filter(fn(one) {
              pitch.to_midi(one) != pitch.to_midi(head)
              && pitch.to_midi(one) != before
            })
          case candidates {
            [moved, ..] -> swap_last(body, moved)
            [] -> body
          }
        }
      }
    _, _ -> body
  }
}

fn swap_last(body: List(Pitch), with: Pitch) -> List(Pitch) {
  list.append(list.take(body, list.length(body) - 1), [with])
}

/// Fold a figure that runs off the end of the range back by whole octaves.
///
/// Bouncing off the edge instead would bend the shape, and the shape is the
/// point: a sequence that turns round halfway through is not a sequence. An
/// octave down keeps every pitch class and the contour with it, which is what
/// a player does when they run out of horn.
fn wrap(index: Int, size: Int, octave: Int, tries: Int) -> Int {
  case octave <= 0 || tries > 8 {
    True -> int.max(0, int.min(index, size - 1))
    False ->
      case index < 0, index >= size {
        True, _ -> wrap(index + octave, size, octave, tries + 1)
        _, True -> wrap(index - octave, size, octave, tries + 1)
        _, _ -> index
      }
  }
}

fn describe(figure: Figure, landing: Approach) -> String {
  let filling = case figure.repeated {
    True -> "the same shape again"
    False ->
      case figure.shape.connector {
        ScaleRun -> "scale run"
        Arpeggio -> "arpeggio"
        DigitalPattern -> "1235 pattern"
        ChordTonesDown -> "chord tones down"
      }
  }
  let arrived = case landing {
    Direct -> ""
    ChromaticBelow -> ", chromatic from below"
    ChromaticAbove -> ", chromatic from above"
    DiatonicAbove -> ", step from above"
    DoubleChromaticBelow -> ", double chromatic"
    EnclosureAboveBelow -> ", enclosure above then below"
    EnclosureBelowAbove -> ", enclosure below then above"
    Anticipate -> ", arriving early and holding over"
  }
  filling <> arrived
}

// --- Pitch sets --------------------------------------------------------------

fn scale_pitches(current: Chord, settings: Options) -> List(Pitch) {
  let kind = case chord.chord_scales(current) {
    [first, ..] -> first
    [] -> scale.Ionian
  }
  spread_over_range(scale.notes(scale.Scale(current.root, kind)), settings)
}

fn chord_pitches(current: Chord, settings: Options) -> List(Pitch) {
  spread_over_range(chord.notes(current), settings)
}

/// Every octave of these pitch classes that fits the range, in order.
fn spread_over_range(
  classes: List(PitchClass),
  settings: Options,
) -> List(Pitch) {
  let lowest = settings.low.octave - 1
  let span = settings.high.octave - lowest + 2
  let found =
    num.counting(span)
    |> list.flat_map(fn(step) {
      list.map(classes, fn(one) { Pitch(one, lowest + step) })
    })
    |> list.filter(fn(one) {
      pitch.to_midi(one) >= pitch.to_midi(settings.low)
      && pitch.to_midi(one) <= pitch.to_midi(settings.high)
    })
    |> list.sort(fn(a, b) { int.compare(pitch.to_midi(a), pitch.to_midi(b)) })
  case found {
    [] -> [settings.low]
    some -> some
  }
}

fn semitone_below(note: Pitch) -> Pitch {
  interval.transpose(note, interval.negate(interval.degree(2, -1)))
}

fn semitone_above(note: Pitch) -> Pitch {
  interval.transpose(note, interval.degree(2, -1))
}

fn tone_below(note: Pitch) -> Pitch {
  interval.transpose(note, interval.negate(interval.degree(2, 0)))
}

fn step_from(tones: List(Pitch), note: Pitch, offset: Int) -> Pitch {
  at(tones, reflect(index_of(tones, note) + offset, list.length(tones)))
}

fn nearest(tones: List(Pitch), to: Pitch) -> Pitch {
  nearest_to(tones, pitch.to_midi(to), to)
}

/// The pitch closest to a given sounding height. The fold has to start at a
/// real candidate: seeding it with the note being searched for would leave
/// nothing able to beat a distance of zero.
fn nearest_to(tones: List(Pitch), wanted: Int, fallback: Pitch) -> Pitch {
  case tones {
    [] -> fallback
    [first, ..rest] ->
      list.fold(rest, first, fn(best, one) {
        case
          int.absolute_value(pitch.to_midi(one) - wanted)
          < int.absolute_value(pitch.to_midi(best) - wanted)
        {
          True -> one
          False -> best
        }
      })
  }
}

/// Close to where the line just was, and close to where it ought to be going.
///
/// Candidates for a target are the same note in different octaves, so this is
/// really choosing a register. Weighting the arc above the voice leading is
/// what lets the line change octave when the shape calls for it, rather than
/// staying put because staying put is always the smallest move.
fn settling(
  candidates: List(Pitch),
  from: Int,
  aim: Int,
  fallback: Pitch,
) -> Pitch {
  case candidates {
    [] -> fallback
    [first, ..rest] ->
      list.fold(rest, first, fn(chosen, one) {
        case cost(one, from, aim) < cost(chosen, from, aim) {
          True -> one
          False -> chosen
        }
      })
  }
}

fn cost(one: Pitch, from: Int, aim: Int) -> Int {
  int.absolute_value(pitch.to_midi(one) - from)
  + 2
  * int.absolute_value(pitch.to_midi(one) - aim)
}

fn index_of(tones: List(Pitch), note: Pitch) -> Int {
  let wanted = pitch.to_midi(nearest(tones, note))
  let #(found, _) =
    list.fold(tones, #(0, 0), fn(state, one) {
      let #(found, position) = state
      case pitch.to_midi(one) == wanted && found == 0 {
        True -> #(position, position + 1)
        False -> #(found, position + 1)
      }
    })
  found
}

fn at(tones: List(Pitch), index: Int) -> Pitch {
  case list.drop(tones, index) {
    [found, ..] -> found
    [] ->
      case tones {
        [first, ..] -> first
        [] -> pitch.note(pitch.C, 0, 4)
      }
  }
}

/// Fold an index back inside the range, mirroring at the ends.
fn reflect(index: Int, size: Int) -> Int {
  case size <= 1 {
    True -> 0
    False ->
      case index < 0, index >= size {
        True, _ -> reflect(-index, size)
        _, True -> reflect(2 * size - 2 - index, size)
        _, _ -> index
      }
  }
}

// --- Reading a line back -----------------------------------------------------

pub fn pitches(line: Line) -> List(Pitch) {
  line.segments
  |> list.flat_map(fn(one) { one.events })
  |> list.filter_map(fn(event) {
    case event {
      Tone(note, _, _) -> Ok(note)
      _ -> Error(Nil)
    }
  })
}

/// How long the line is, in eighth notes.
pub fn duration(line: Line) -> Int {
  line.segments
  |> list.flat_map(fn(one) { one.events })
  |> room
}

/// The lowest and highest note of the line.
pub fn span(line: Line) -> Result(#(Pitch, Pitch), Nil) {
  case pitches(line) {
    [] -> Error(Nil)
    [first, ..rest] ->
      Ok(
        list.fold(rest, #(first, first), fn(found, one) {
          let #(low, high) = found
          #(
            case pitch.to_midi(one) < pitch.to_midi(low) {
              True -> one
              False -> low
            },
            case pitch.to_midi(one) > pitch.to_midi(high) {
              True -> one
              False -> high
            },
          )
        }),
      )
  }
}

/// Respell any note that came out with a double accidental.
///
/// A passing chromatic carries no harmony worth preserving, and transposing a
/// line up a major sixth turns a perfectly reasonable A sharp into F double
/// sharp. This is a rendering decision, so it belongs after transposition and
/// never in the stored line.
pub fn simplify_spelling(line: Line) -> Line {
  Line(
    ..line,
    segments: list.map(line.segments, fn(one) {
      Segment(
        ..one,
        events: list.map(one.events, fn(event) {
          case event {
            Tone(note, length, held) ->
              case int.absolute_value(note.class.alteration) > 1 {
                True ->
                  Tone(
                    pitch.respell(note, case note.class.alteration > 0 {
                      True -> pitch.PreferSharps
                      False -> pitch.PreferFlats
                    }),
                    length,
                    held,
                  )
                False -> Tone(note, length, held)
              }
            other -> other
          }
        }),
      )
    }),
  )
}

/// Move a whole line, for writing it out on a transposing instrument.
pub fn transpose(line: Line, by: interval.Interval) -> Line {
  Line(
    ..line,
    segments: list.map(line.segments, fn(one) {
      Segment(
        ..one,
        chord: chord.transpose(one.chord, by),
        events: list.map(one.events, fn(event) {
          case event {
            Tone(note, length, held) ->
              Tone(interval.transpose(note, by), length, held)
            other -> other
          }
        }),
      )
    }),
  )
}

// --- Articulation ------------------------------------------------------------
//
// Which notes are tongued and which are slurred is most of what separates a
// jazz line from the same notes played straight, and on a horn it is audible
// from across a room. It is also a convention rather than a matter of taste,
// which is what makes it something that can be written down.

/// How one note is attacked.
pub type Mark {
  Mark(
    /// Played into from the note before it rather than tongued again.
    joined: Bool,
    accent: Bool,
  )
}

/// A slur runs while the line stays inside this and breaks at anything wider:
/// bebop slurs through steps and small skips, and tongues what it leaps to.
const reach = 7

/// How long a phrase has to be before its top note is worth marking. Two
/// notes have a higher one by definition and it means nothing.
const shapely = 3

/// Where a note sits, once rests and triplets have been accounted for.
type Placed {
  Placed(note: Pitch, length: Int, at: Int, phrase: Int, held: Bool)
}

/// How each note of a line is attacked, one mark per note, in order.
///
/// Two rules, both of them the ones a method book gives. Eighths run slurred
/// until the line leaps, and whatever it leaps to is tongued. The weight goes
/// on the offbeat -- an accent on a tongued upbeat is the whole character of
/// the idiom -- and on the top of a phrase, because that is where the phrase
/// was going.
pub fn phrasing(events: List(Event)) -> List(Mark) {
  let notes = placed(events, 0, 0, [])
  let tops = peaks(notes)
  attacks(notes, tops, None, [])
}

fn placed(
  events: List(Event),
  at: Int,
  phrase: Int,
  acc: List(Placed),
) -> List(Placed) {
  case events {
    [] -> list.reverse(acc)
    // Three notes sharing the room of two all sit where the group does.
    [Triplet, ..rest] ->
      placed(
        list.drop(rest, 3),
        at + 2,
        phrase,
        list.fold(list.take(rest, 3), acc, fn(kept, one) {
          case one {
            Tone(note, _, held) -> [Placed(note, 1, at, phrase, held), ..kept]
            _ -> kept
          }
        }),
      )
    [Tone(note, length, held), ..rest] ->
      placed(rest, at + length, phrase, [
        Placed(note, length, at, phrase, held),
        ..acc
      ])
    // A silence ends a phrase, and nothing slurs across one.
    [Rest(length), ..rest] -> placed(rest, at + length, phrase + 1, acc)
  }
}

/// The highest note of each phrase worth pointing at, as a phrase number and
/// the pitch that tops it.
fn peaks(notes: List(Placed)) -> List(#(Int, Int)) {
  notes
  |> list.fold([], fn(found, one) {
    let here = pitch.to_midi(one.note)
    case list.key_find(found, one.phrase) {
      Ok(highest) if highest >= here -> found
      _ -> [
        #(one.phrase, here),
        ..list.filter(found, fn(entry) { entry.0 != one.phrase })
      ]
    }
  })
  |> list.filter(fn(entry) {
    list.count(notes, fn(one) { one.phrase == entry.0 }) >= shapely
  })
}

fn attacks(
  notes: List(Placed),
  tops: List(#(Int, Int)),
  previous: Option(Placed),
  acc: List(Mark),
) -> List(Mark) {
  case notes {
    [] -> list.reverse(acc)
    [one, ..rest] -> {
      let joined = case previous {
        Some(before) ->
          before.phrase == one.phrase
          && before.length == 1
          // A note already held into this one says so with a tie, and does
          // not need a slur saying it twice.
          && !before.held
          && int.absolute_value(
            pitch.to_midi(one.note) - pitch.to_midi(before.note),
          )
          < reach
        None -> False
      }
      let peak = case list.key_find(tops, one.phrase) {
        Ok(highest) -> highest == pitch.to_midi(one.note)
        Error(_) -> False
      }
      // A tongued upbeat, or the top of the phrase.
      let accent = peak || { !joined && one.at % 2 == 1 }
      attacks(rest, tops, Some(one), [Mark(joined, accent), ..acc])
    }
  }
}
