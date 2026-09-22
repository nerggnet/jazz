//// Generating single note lines over changes.
////
//// There is no library of transcribed licks here, on purpose. Stored licks
//// belong to whoever played them, and learning them one at a time teaches the
//// phrases rather than the language. What is encoded instead is the grammar
//// that produces them:
////
////   - land on a chord tone on the strong beat, usually the third or seventh,
////   - arrive at it by step, by chromatic approach, or by enclosure,
////   - fill the space between with scale motion, an arpeggio, or a pattern.
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
  Tone(pitch: Pitch, duration: Int)
  Rest(duration: Int)
}

/// The stretch of line played over one chord, with a note on how it was made.
pub type Segment {
  Segment(chord: Chord, events: List(Event), target: String, device: String)
}

pub type Line {
  Line(segments: List(Segment), seed: Int)
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
  let #(targets, generator) =
    choose_targets(items, settings, generator, None, [])
  let segments = fill_all(items, targets, settings, generator, [])
  Line(segments, settings.seed)
}

/// Split each bar's time evenly between the chords in it.
fn spread(subject: Progression) -> List(#(Chord, Int)) {
  list.flat_map(subject.bars, fn(each) {
    let share = case list.length(each.chords) {
      0 -> bar
      count -> bar / count
    }
    list.map(each.chords, fn(one) { #(one, share) })
  })
}

/// First pass: decide where the line has to be on each downbeat. Doing this
/// before filling anything is what lets a segment approach the note the next
/// segment is going to start on.
fn choose_targets(
  items: List(#(Chord, Int)),
  settings: Options,
  generator: Random,
  previous: Option(Pitch),
  acc: List(#(Pitch, String)),
) -> #(List(#(Pitch, String)), Random) {
  case items {
    [] -> #(list.reverse(acc), generator)
    [#(current, _), ..rest] -> {
      let tones = chord_pitches(current, settings)
      let #(wanted, label, generator) =
        target_class(current, settings.level, generator)
      let candidates = case
        list.filter(tones, fn(one) { pitch.same(one.class, wanted) })
      {
        [] -> tones
        found -> found
      }
      let target = case previous {
        Some(note) -> nearest(candidates, note)
        None -> middle(candidates, settings)
      }
      choose_targets(rest, settings, generator, Some(target), [
        #(target, label),
        ..acc
      ])
    }
  }
}

fn fill_all(
  items: List(#(Chord, Int)),
  targets: List(#(Pitch, String)),
  settings: Options,
  generator: Random,
  acc: List(Segment),
) -> List(Segment) {
  case items, targets {
    [#(current, length), ..rest], [#(target, label), ..later] -> {
      let next = case later {
        [#(upcoming, _), ..] -> Some(upcoming)
        [] -> None
      }
      let #(segment, generator) =
        fill(current, length, target, label, next, settings, generator)
      fill_all(rest, later, settings, generator, [segment, ..acc])
    }
    _, _ -> list.reverse(acc)
  }
}

fn fill(
  current: Chord,
  length: Int,
  target: Pitch,
  label: String,
  next: Option(Pitch),
  settings: Options,
  generator: Random,
) -> #(Segment, Random) {
  let tones = scale_pitches(current, settings)
  let arpeggio = chord_pitches(current, settings)

  let #(wanted, generator) = case next {
    None -> #(Direct, generator)
    Some(_) -> random.pick(generator, approaches(settings.level), Direct)
  }
  let #(connector, generator) =
    random.pick(generator, connectors(settings.level), ScaleRun)

  // The approach has to fit in the bar; if it does not, walk in directly.
  let #(chosen, body_length) = case length - 1 - approach_length(wanted) {
    room if room >= 0 -> #(wanted, room)
    _ -> #(Direct, length - 1)
  }

  let direction = case next {
    Some(upcoming) ->
      case pitch.to_midi(upcoming) >= pitch.to_midi(target) {
        True -> 1
        False -> -1
      }
    None -> 1
  }

  let body =
    build_body(connector, tones, arpeggio, target, body_length, direction)
  let approach = build_approach(chosen, next, tones)

  let events =
    [target, ..body]
    |> list.append(approach)
    |> list.map(fn(one) { Tone(one, 1) })

  #(
    Segment(
      chord: current,
      events: events,
      target: label,
      device: describe(connector, chosen),
    ),
    generator,
  )
}

// --- Vocabulary --------------------------------------------------------------

fn approaches(level: Level) -> List(Approach) {
  case level {
    Beginner -> [Direct, Direct, ChromaticBelow]
    Intermediate -> [
      Direct,
      ChromaticBelow,
      ChromaticAbove,
      DiatonicAbove,
      EnclosureAboveBelow,
    ]
    Advanced -> [
      ChromaticBelow,
      DiatonicAbove,
      DoubleChromaticBelow,
      EnclosureAboveBelow,
      EnclosureBelowAbove,
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
    ChromaticBelow | ChromaticAbove | DiatonicAbove -> 1
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

fn build_body(
  connector: Connector,
  tones: List(Pitch),
  arpeggio: List(Pitch),
  from: Pitch,
  count: Int,
  direction: Int,
) -> List(Pitch) {
  case connector {
    ScaleRun -> walk(tones, from, count, direction)
    Arpeggio -> walk(arpeggio, from, count, direction)
    ChordTonesDown -> walk(arpeggio, from, count, -1)
    DigitalPattern -> digital(tones, from, count, direction)
  }
}

/// Step through a list of pitches, turning round at the edges of the range
/// rather than repeating the top note.
fn walk(
  tones: List(Pitch),
  from: Pitch,
  count: Int,
  direction: Int,
) -> List(Pitch) {
  let start = index_of(tones, from)
  let size = list.length(tones)
  num.counting(count)
  |> list.map(fn(step) {
    at(tones, reflect(start + direction * { step + 1 }, size))
  })
}

/// The one-two-three-five pattern every player runs through the cycle, each
/// group starting a step higher than the last.
fn digital(
  tones: List(Pitch),
  from: Pitch,
  count: Int,
  direction: Int,
) -> List(Pitch) {
  let start = index_of(tones, from)
  let size = list.length(tones)
  num.counting(count)
  |> list.map(fn(step) {
    let position = step + 1
    let offset = case position % 4 {
      0 -> 0
      1 -> 1
      2 -> 2
      _ -> 4
    }
    at(tones, reflect(start + direction * { position / 4 + offset }, size))
  })
}

fn describe(connector: Connector, approach: Approach) -> String {
  let filling = case connector {
    ScaleRun -> "scale run"
    Arpeggio -> "arpeggio"
    DigitalPattern -> "1235 pattern"
    ChordTonesDown -> "chord tones down"
  }
  let arrival = case approach {
    Direct -> ""
    ChromaticBelow -> ", chromatic from below"
    ChromaticAbove -> ", chromatic from above"
    DiatonicAbove -> ", step from above"
    DoubleChromaticBelow -> ", double chromatic"
    EnclosureAboveBelow -> ", enclosure above then below"
    EnclosureBelowAbove -> ", enclosure below then above"
  }
  filling <> arrival
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

fn middle(tones: List(Pitch), settings: Options) -> Pitch {
  let wanted =
    { pitch.to_midi(settings.low) + pitch.to_midi(settings.high) } / 2
  nearest_to(tones, wanted, settings.low)
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
      Tone(note, _) -> Ok(note)
      Rest(_) -> Error(Nil)
    }
  })
}

/// How long the line is, in eighth notes.
pub fn duration(line: Line) -> Int {
  line.segments
  |> list.flat_map(fn(one) { one.events })
  |> list.fold(0, fn(total, event) {
    case event {
      Tone(_, length) -> total + length
      Rest(length) -> total + length
    }
  })
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
            Tone(note, length) ->
              case int.absolute_value(note.class.alteration) > 1 {
                True ->
                  Tone(
                    pitch.respell(note, case note.class.alteration > 0 {
                      True -> pitch.PreferSharps
                      False -> pitch.PreferFlats
                    }),
                    length,
                  )
                False -> Tone(note, length)
              }
            Rest(length) -> Rest(length)
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
            Tone(note, length) -> Tone(interval.transpose(note, by), length)
            Rest(length) -> Rest(length)
          }
        }),
      )
    }),
  )
}
