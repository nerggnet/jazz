//// A score, in the shape notation formats agree on.
////
//// This is the layer between the theory modules and any format that puts
//// notes on paper. It holds bars, durations, beams, key signature and chord
//// symbols, and it knows nothing about ABC or MusicXML; a backend turns one
//// of these into text.
////
//// Two jobs live here because both formats need them and neither should own
//// them. The first is choosing a key signature: rather than asking, the one
//// that prints the fewest accidentals wins, which handles a plain major scale
//// and an altered dominant equally well. The second is deciding which
//// accidentals actually appear, following the real rule that one lasts to the
//// end of its bar at its own octave, so a part reads like a part instead of
//// like a list of pitches.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import jazz/chord.{type Chord}
import jazz/instrument.{type Instrument}
import jazz/internal/num
import jazz/interval.{type Interval}
import jazz/lick.{type Line}
import jazz/pitch.{type Pitch, type PitchClass, Pitch}
import jazz/progression.{type Progression}
import jazz/scale.{type Scale}

/// How a note joins the ones beside it under a beam.
pub type Beam {
  Alone
  StartBeam
  ContinueBeam
  EndBeam
}

pub type Event {
  /// `accidental` is what should be printed, not what the note is: `None`
  /// means the key signature and the rest of the bar have already said it.
  Note(
    pitch: Pitch,
    duration: Int,
    accidental: Option(Int),
    chord: Option(String),
    annotation: Option(String),
    beam: Beam,
    /// Held into the note after it rather than played again.
    tied: Bool,
  )
  Rest(duration: Int, chord: Option(String), annotation: Option(String))
  /// Time that passes without a printed note, for chord charts.
  Spacer(duration: Int, chord: Option(String), annotation: Option(String))
}

pub type Measure {
  Measure(events: List(Event))
}

pub type Score {
  Score(
    title: String,
    subtitle: String,
    /// Beats per bar and the note value that gets the beat.
    time: #(Int, Int),
    /// The note value durations are counted in: 8 means eighth notes.
    unit: Int,
    /// The key signature, as a position on the line of fifths.
    signature: Int,
    tempo: Option(Int),
    measures: List(Measure),
  )
}

/// How many units fit in one bar.
pub fn measure_capacity(score: Score) -> Int {
  score.time.0 * score.unit / score.time.1
}

pub fn events(score: Score) -> List(Event) {
  list.flat_map(score.measures, fn(one) { one.events })
}

pub fn pitches(score: Score) -> List(Pitch) {
  events(score)
  |> list.filter_map(fn(event) {
    case event {
      Note(note, ..) -> Ok(note)
      _ -> Error(Nil)
    }
  })
}

// --- Building scores ---------------------------------------------------------

/// A scale, up one octave and back down.
pub fn from_scale(subject: Scale, player: Instrument) -> Score {
  let shift = instrument.write_interval_for_key(player, subject.root)
  let root = Pitch(subject.root, 4)
  let up =
    scale.intervals(subject.kind)
    |> list.append([interval.degree(8, 0)])
    |> list.map(fn(step) { interval.transpose(root, step) })
  let notes = list.append(up, back_down(up))

  build(
    title: pitch.class_to_string(interval.transpose_class(subject.root, shift))
      <> " "
      <> scale.name(subject.kind),
    subtitle: instrument.label(player),
    events: plain(hold_last(eighths(written(notes, shift, player))), []),
    hint: interval.transpose_class(subject.root, shift),
  )
}

/// A chord, spelled out as an arpeggio up and back down.
pub fn from_chord(subject: Chord, player: Instrument) -> Score {
  let shift = instrument.write_interval_for_key(player, subject.root)
  let root = Pitch(subject.root, 4)
  let up =
    chord.intervals(subject)
    |> list.map(fn(step) { interval.transpose(root, step) })
  let notes = list.append(up, back_down(up))
  let written_chord = chord.transpose(subject, shift)
  let symbol = chord.to_string(written_chord)

  build(
    title: symbol,
    subtitle: instrument.label(player),
    events: plain(hold_last(eighths(written(notes, shift, player))), [
      #(0, symbol),
    ]),
    hint: written_chord.root,
  )
}

/// A generated line, with the changes above it.
pub fn from_line(
  line: Line,
  heading: String,
  key: PitchClass,
  player: Instrument,
) -> Score {
  let shift = instrument.write_interval_for_key(player, key)
  let moved = lick.transpose(line, shift) |> lick.simplify_spelling

  let events =
    list.flat_map(moved.segments, fn(segment) {
      let symbol = chord.to_string(segment.chord)
      list.index_map(segment.events, fn(event, at) {
        // The chord symbol belongs to the bar it starts, not to every note.
        let label = case at {
          0 -> Some(symbol)
          _ -> None
        }
        case event {
          lick.Tone(note, length, held) ->
            Note(note, length, None, label, None, Alone, held)
          lick.Rest(length) -> Rest(length, label, None)
        }
      })
    })

  build(
    title: heading,
    subtitle: instrument.label(player),
    events: events,
    hint: interval.transpose_class(key, shift),
  )
}

/// A chord chart: bars carrying symbols and no printed notes.
pub fn from_progression(subject: Progression, player: Instrument) -> Score {
  let shift = instrument.write_interval_for_key(player, subject.key)
  let moved = progression.transpose(subject, shift)
  let capacity = 8

  let measures =
    list.map(moved.bars, fn(one) {
      Measure(
        list.zip(
          one.chords,
          progression.shares(list.length(one.chords), capacity),
        )
        |> list.map(fn(entry) {
          Spacer(entry.1, Some(chord.to_string(entry.0)), None)
        }),
      )
    })

  Score(
    title: moved.name <> " in " <> pitch.class_to_string(moved.key),
    subtitle: instrument.label(player),
    time: #(4, 4),
    unit: 8,
    signature: signature_near(moved.key),
    tempo: None,
    measures: measures,
  )
}

// --- Putting the pieces together --------------------------------------------

/// Everything above the bottom note again, on the way back down.
fn back_down(up: List(Pitch)) -> List(Pitch) {
  case list.reverse(up) {
    [_, ..rest] -> rest
    [] -> []
  }
}

fn eighths(notes: List(Pitch)) -> List(#(Pitch, Int)) {
  list.map(notes, fn(one) { #(one, 1) })
}

/// Give the last note of an exercise a beat of its own, so it reads as an
/// ending rather than as a line that ran out.
fn hold_last(notes: List(#(Pitch, Int))) -> List(#(Pitch, Int)) {
  case list.reverse(notes) {
    [#(note, _), ..rest] -> list.reverse([#(note, 2), ..rest])
    [] -> []
  }
}

/// Notes with chord symbols attached at the given positions.
fn plain(
  notes: List(#(Pitch, Int)),
  chords: List(#(Int, String)),
) -> List(Event) {
  list.index_map(notes, fn(entry, at) {
    Note(
      entry.0,
      entry.1,
      None,
      list.key_find(chords, at) |> option.from_result,
      None,
      Alone,
      False,
    )
  })
}

/// Transpose for the player, then shift the whole thing by octaves until it
/// sits on the instrument rather than above or below it.
fn written(
  notes: List(Pitch),
  shift: Interval,
  player: Instrument,
) -> List(Pitch) {
  let moved = list.map(notes, interval.transpose(_, shift))
  let best =
    [0, -1, 1, -2, 2]
    |> list.fold(#(-1, 0), fn(found, octaves) {
      let #(best_count, _) = found
      let inside =
        moved
        |> list.map(interval.transpose(_, interval.octaves(octaves)))
        |> list.count(instrument.in_range(player, _))
      case inside > best_count {
        True -> #(inside, octaves)
        False -> found
      }
    })
  list.map(moved, interval.transpose(_, interval.octaves(best.1)))
}

/// Lay events into bars, pick a key signature, work out the accidentals.
fn build(
  title title: String,
  subtitle subtitle: String,
  events events: List(Event),
  hint hint: PitchClass,
) -> Score {
  let capacity = 8
  let measures =
    events
    |> into_measures(capacity, #([], 0), [])
    |> list.map(spell_silences)
    |> list.map(beam_measure(_, capacity))
  let signature = choose_signature(measures, hint)

  Score(
    title: title,
    subtitle: subtitle,
    time: #(4, 4),
    unit: 8,
    signature: signature,
    tempo: None,
    measures: apply_accidentals(measures, signature),
  )
}

/// Fill bars by duration rather than by count, so a held note takes the room
/// it deserves. Nothing is split across a bar line: an event that will not fit
/// starts the next bar instead.
fn into_measures(
  events: List(Event),
  capacity: Int,
  current: #(List(Event), Int),
  done: List(Measure),
) -> List(Measure) {
  let #(held, used) = current
  case events {
    [] ->
      case held {
        [] -> list.reverse(done)
        _ -> list.reverse([Measure(list.reverse(held)), ..done])
      }
    [one, ..rest] -> {
      let length = duration_of(one)
      case held != [] && used + length > capacity {
        True ->
          into_measures(events, capacity, #([], 0), [
            Measure(list.reverse(held)),
            ..done
          ])
        False ->
          into_measures(rest, capacity, #([one, ..held], used + length), done)
      }
    }
  }
}

pub fn duration_of(one: Event) -> Int {
  case one {
    Note(duration: length, ..) -> length
    Rest(duration: length, ..) -> length
    Spacer(duration: length, ..) -> length
  }
}

/// Each event paired with the unit it starts on inside its bar.
fn with_positions(events: List(Event)) -> List(#(Int, Event)) {
  let #(found, _) =
    list.fold(events, #([], 0), fn(state, one) {
      let #(done, at) = state
      #([#(at, one), ..done], at + duration_of(one))
    })
  list.reverse(found)
}

/// Rewrite silences as durations that can actually be written down.
///
/// Five eighths is not a rest, it is a rest and a rest: notation has symbols
/// for an eighth, a quarter, a dotted quarter and so on, and nothing in
/// between. Off the beat only the short ones read properly, so a silence
/// starting mid beat begins by filling out the beat it is in.
fn spell_silences(subject: Measure) -> Measure {
  Measure(
    with_positions(subject.events)
    |> list.flat_map(fn(entry) {
      let #(at, event) = entry
      case event {
        Rest(length, symbol, annotation) ->
          writable(at, length)
          |> list.index_map(fn(piece, index) {
            case index {
              // Whatever was attached belongs to the first piece only.
              0 -> Rest(piece, symbol, annotation)
              _ -> Rest(piece, None, None)
            }
          })
        Spacer(length, symbol, annotation) ->
          writable(at, length)
          |> list.index_map(fn(piece, index) {
            case index {
              0 -> Spacer(piece, symbol, annotation)
              _ -> Spacer(piece, None, None)
            }
          })
        other -> [other]
      }
    }),
  )
}

fn writable(at: Int, length: Int) -> List(Int) {
  case length <= 0 {
    True -> []
    False -> {
      let piece = longest_fitting(choices(at), length)
      [piece, ..writable(at + piece, length - piece)]
    }
  }
}

fn choices(at: Int) -> List(Int) {
  case at % 2 == 0 {
    True -> [8, 6, 4, 3, 2, 1]
    False -> [1]
  }
}

fn longest_fitting(sizes: List(Int), length: Int) -> Int {
  case sizes {
    [] -> 1
    [size, ..rest] ->
      case size <= length {
        True -> size
        False -> longest_fitting(rest, length)
      }
  }
}

// --- Beaming -----------------------------------------------------------------

/// Beam eighth notes in half bar groups, which is how a bebop line is written.
fn beam_measure(subject: Measure, capacity: Int) -> Measure {
  let group_size = capacity / 2
  let groups =
    subject.events
    |> with_positions
    |> list.map(fn(entry) { #(entry.0 / group_size, entry.1) })
  Measure(
    list.index_map(groups, fn(entry, at) {
      let #(group, event) = entry
      case event {
        // Only eighth notes beam; anything longer stands on its own.
        Note(duration: 1, ..) as note -> {
          let joins_before = joins(groups, at - 1, group)
          let joins_after = joins(groups, at + 1, group)
          Note(..note, beam: case joins_before, joins_after {
            False, True -> StartBeam
            True, True -> ContinueBeam
            True, False -> EndBeam
            False, False -> Alone
          })
        }
        other -> other
      }
    }),
  )
}

fn joins(groups: List(#(Int, Event)), at: Int, group: Int) -> Bool {
  case at < 0 {
    True -> False
    False ->
      case list.drop(groups, at) {
        [#(other, Note(duration: 1, ..)), ..] -> other == group
        _ -> False
      }
  }
}

// --- Key signature -----------------------------------------------------------

/// A key signature that can actually be printed, for a tonic that may not be.
fn signature_near(key: PitchClass) -> Int {
  let wanted = pitch.fifths(key)
  case wanted > 7, wanted < -7 {
    True, _ -> 7
    _, True -> -7
    _, _ -> wanted
  }
}

/// The signature that leaves the fewest accidentals on the page, breaking
/// ties towards the key the music came from.
fn choose_signature(measures: List(Measure), hint: PitchClass) -> Int {
  let wanted = signature_near(hint)
  num.counting(15)
  |> list.map(fn(step) { step - 7 })
  |> list.fold(#(wanted, 1_000_000), fn(best, candidate) {
    let cost =
      10
      * accidental_count(measures, candidate)
      + int.absolute_value(candidate - wanted)
    case cost < best.1 {
      True -> #(candidate, cost)
      False -> best
    }
  })
  |> fn(found) { found.0 }
}

fn accidental_count(measures: List(Measure), signature: Int) -> Int {
  apply_accidentals(measures, signature)
  |> list.flat_map(fn(one) { one.events })
  |> list.count(fn(event) {
    case event {
      Note(accidental: Some(_), ..) -> True
      _ -> False
    }
  })
}

// --- Accidentals -------------------------------------------------------------

/// Decide which accidentals get printed.
///
/// An accidental lasts to the end of its bar at its own octave, so each bar
/// starts again from whatever the key signature says and only notes that
/// disagree with the state so far need any ink.
fn apply_accidentals(measures: List(Measure), signature: Int) -> List(Measure) {
  list.map(measures, fn(one) {
    let #(events, _) =
      list.fold(one.events, #([], dict.new()), fn(state, event) {
        let #(done, seen) = state
        case event {
          Note(..) as note -> {
            let letter = note.pitch.class.letter
            let wanted = note.pitch.class.alteration
            let key = #(pitch.diatonic_index(letter), note.pitch.octave)
            let standing = case dict.get(seen, key) {
              Ok(found) -> found
              Error(_) -> pitch.key_alteration(letter, signature)
            }
            case wanted == standing {
              True -> #([Note(..note, accidental: None), ..done], seen)
              False -> #(
                [Note(..note, accidental: Some(wanted)), ..done],
                dict.insert(seen, key, wanted),
              )
            }
          }
          other -> #([other, ..done], seen)
        }
      })
    Measure(list.reverse(events))
  })
}
