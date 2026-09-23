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
import gleam/string
import jazz/chord.{type Chord}
import jazz/comp
import jazz/instrument.{type Instrument}
import jazz/internal/num
import jazz/interval.{type Interval}
import jazz/lick.{type Line}
import jazz/pattern.{type Pattern}
import jazz/pitch.{type Pitch, type PitchClass, Pitch}
import jazz/progression.{type Progression}
import jazz/scale.{type Scale, type ScaleKind}

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
  /// Notes sounding together, as a piano plays a chord. Accidentals are
  /// decided per note, in the same order.
  Stack(
    pitches: List(Pitch),
    duration: Int,
    accidentals: List(Option(Int)),
    chord: Option(String),
    annotation: Option(String),
  )
  Rest(duration: Int, chord: Option(String), annotation: Option(String))
  /// Time that passes without a printed note, for chord charts.
  Spacer(duration: Int, chord: Option(String), annotation: Option(String))
  /// The next `count` events are played in the time of `into` of them, so
  /// three in the time of two is a triplet.
  ///
  /// A marker in the list rather than a box around the notes, because that
  /// is what both notations are: ABC puts `(3` in front of the group and
  /// MusicXML hangs a time modification on each note in it. A flat list is
  /// also what every pass in this module already walks, and a tree would
  /// have meant teaching all of them to recurse for the sake of one figure.
  Tuplet(
    count: Int,
    into: Int,
    chord: Option(String),
    annotation: Option(String),
  )
}

pub type Measure {
  Measure(
    events: List(Event),
    /// A key signature starting here, as a position on the line of fifths.
    /// Only the bar that changes key carries one; everything after it reads
    /// in that key until something says otherwise.
    key: Option(Int),
  )
}

pub type Clef {
  Treble
  Bass
}

/// One staff of a score.
pub type Part {
  Part(
    name: String,
    clef: Clef,
    /// The General MIDI voice this staff is played with.
    sound: Int,
    /// The key signature, as a position on the line of fifths. Every staff
    /// has its own, because a horn does not read in the same key as the
    /// piano standing next to it.
    signature: Int,
    /// How far what is written is from what is heard, written to sounding.
    /// `None` for a part that reads at concert pitch.
    transpose: Option(Interval),
    measures: List(Measure),
  )
}

/// A part written for a horn, which sounds somewhere other than where it is
/// written. `shift` is what moved the music onto the page; the part carries
/// the way back.
fn reading(part: Part, shift: Interval) -> Part {
  Part(..part, transpose: Some(interval.negate(shift)))
}

pub type Score {
  Score(
    title: String,
    subtitle: String,
    /// Beats per bar and the note value that gets the beat.
    time: #(Int, Int),
    /// The note value durations are counted in: 8 means eighth notes.
    unit: Int,
    tempo: Option(Int),
    /// How the eighths are meant to be read -- "Swing" or nothing. Printed
    /// beside the tempo, because a chart that swings without saying so leaves
    /// every reader to decide for themselves.
    feel: Option(String),
    parts: List(Part),
  )
}

/// How many units fit in one bar.
/// The tempo to write at when nobody has said otherwise, in quarter notes a
/// minute.
///
/// A tempo belongs in the music rather than in whatever is playing it. A score
/// without one leaves every reader to invent it, and two readers inventing
/// different ones is how a playhead ends up running ahead of the sound, so it
/// is a parameter rather than something a caller can forget to set.
pub const default_tempo = 120

pub fn measure_capacity(score: Score) -> Int {
  score.time.0 * score.unit / score.time.1
}

pub fn events(score: Score) -> List(Event) {
  list.flat_map(score.parts, fn(part) {
    list.flat_map(part.measures, fn(one) { one.events })
  })
}

/// The staff a single part score is all about.
pub fn only_part(score: Score) -> Part {
  case score.parts {
    [one, ..] -> one
    [] -> Part("", Treble, instrument.piano, 0, None, [])
  }
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
pub fn from_scale(subject: Scale, player: Instrument, tempo: Int) -> Score {
  from_pattern(subject, pattern.Straight, [subject.root], player, tempo)
}

/// A pattern run through one key or through all of them.
///
/// Each key is written out in its own signature rather than in the first
/// one's, because a sheet of twelve keys all spelled in C is a sheet of
/// accidentals. That means bars that change key part way through the score,
/// which is what `Measure.key` is for.
pub fn from_pattern(
  subject: Scale,
  shape: Pattern,
  keys: List(PitchClass),
  player: Instrument,
  tempo: Int,
) -> Score {
  let sections =
    list.map(keys, fn(key) { section(subject.kind, shape, key, player, keys) })

  Score(
    title: pitch.class_to_string(heading_key(subject, sections))
      <> " "
      <> scale.name(subject.kind)
      <> case shape {
      pattern.Straight -> ""
      _ -> ", " <> string.lowercase(pattern.name(shape))
    }
      <> case keys {
      [_] -> ""
      _ -> ", round the keys"
    },
    subtitle: instrument.label(player),
    time: #(4, 4),
    unit: 8,
    tempo: Some(tempo),
    feel: None,
    parts: [
      reading(
        keyed(
          sections,
          Treble,
          instrument.label(player),
          instrument.sound(player),
        ),
        instrument.write_interval_for_key(player, subject.root),
      ),
    ],
  )
}

/// One key's worth of the exercise, written and shaped into bars.
///
/// Spelled whichever of the enharmonic ways needs the smaller signature. The
/// instrument's own rule looks at the key it is handed, which is enough for a
/// major scale, but a mode reaches further round the line of fifths than its
/// root does: concert E read by an alto is D-flat, and D-flat Dorian wants
/// seven flats where C-sharp Dorian wants five sharps.
fn section(
  kind: ScaleKind,
  shape: Pattern,
  key: PitchClass,
  player: Instrument,
  keys: List(PitchClass),
) -> #(PitchClass, Int, List(Measure)) {
  let here = scale.Scale(key, kind)
  let plain_shift = instrument.write_interval_for_key(player, key)
  let respell = interval.degree(2, -2)
  let last = case keys {
    [_] -> True
    _ -> False
  }

  [
    plain_shift,
    interval.add(plain_shift, respell),
    interval.add(plain_shift, interval.negate(respell)),
  ]
  |> list.map(fn(shift) {
    let written_key = interval.transpose_class(key, shift)
    let events =
      plain(
        hold_last(eighths(written(pattern.notes(shape, here), shift, player))),
        [],
      )
    let measures = case last {
      True -> shaped(events)
      False -> shaped(bar_out(events))
    }
    #(written_key, choose_signature(measures, written_key), measures)
  })
  |> list.fold(from: #(key, 99, []), with: fn(best, one) {
    case int.absolute_value(one.1) < int.absolute_value(best.1) {
      True -> one
      False -> best
    }
  })
}

fn heading_key(
  subject: Scale,
  sections: List(#(PitchClass, Int, List(Measure))),
) -> PitchClass {
  case sections {
    [#(key, _, _), ..] -> key
    [] -> subject.root
  }
}

/// Sections one after another, each starting a bar of its own and announcing
/// the key it is in.
fn keyed(
  sections: List(#(PitchClass, Int, List(Measure))),
  clef: Clef,
  name: String,
  sound: Int,
) -> Part {
  let leading = case sections {
    [#(_, signature, _), ..] -> signature
    [] -> 0
  }
  let measures =
    sections
    |> list.index_map(fn(section, at) {
      let #(_, signature, measures) = section
      // The header has already announced the first one.
      case at, measures {
        0, _ -> measures
        _, [first, ..rest] -> [Measure(..first, key: Some(signature)), ..rest]
        _, [] -> []
      }
    })
    |> list.flatten

  settle(measures, leading, clef, name, sound)
}

/// Round an exercise up to whole bars.
fn bar_out(events: List(Event)) -> List(Event) {
  let used = sounding(events)
  case int.modulo(used, 8) {
    Ok(0) | Error(_) -> events
    Ok(over) -> list.append(events, [Rest(8 - over, None, None)])
  }
}

/// A chord, spelled out as an arpeggio up and back down.
pub fn from_chord(subject: Chord, player: Instrument, tempo: Int) -> Score {
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
    tempo: tempo,
    sound: instrument.sound(player),
    shift: shift,
  )
}

/// A generated line, with the changes above it.
pub fn from_line(
  line: Line,
  heading: String,
  key: PitchClass,
  player: Instrument,
  tempo: Int,
) -> Score {
  let shift = instrument.write_interval_for_key(player, key)
  build(
    title: heading,
    subtitle: instrument.label(player),
    events: line_events(lick.transpose(line, shift) |> lick.simplify_spelling),
    hint: interval.transpose_class(key, shift),
    tempo: tempo,
    sound: instrument.sound(player),
    shift: shift,
  )
}

/// A line with a written out comp beneath it: the piano on the upper staff at
/// concert pitch, the part to play on the lower one.
pub fn from_line_with_backing(
  line: Line,
  changes: Progression,
  heading: String,
  player: Instrument,
  tempo: Int,
) -> Score {
  let shift = instrument.write_interval_for_key(player, changes.key)
  let moved = lick.transpose(line, shift) |> lick.simplify_spelling

  let comping =
    comp.comping(changes)
    |> list.map(fn(stroke) {
      case stroke {
        comp.Strike(notes, length) ->
          Stack(notes, length, list.map(notes, fn(_) { None }), None, None)
        comp.Wait(length) -> Rest(length, None, None)
      }
    })

  // A walking bass is quarter notes and nothing else, which in eighths is a
  // two apiece.
  let walking =
    comp.walking(changes)
    |> list.map(fn(one) { Note(one, 2, None, None, None, Alone, False) })

  Score(
    title: heading,
    subtitle: instrument.label(player),
    time: #(4, 4),
    unit: 8,
    tempo: Some(tempo),
    feel: None,
    parts: [
      assemble_in(comping, changes.key, Treble, "Piano", instrument.piano),
      assemble_in(walking, changes.key, Bass, "Bass", instrument.bass),
      reading(
        assemble(
          line_events(moved),
          interval.transpose_class(changes.key, shift),
          Treble,
          instrument.label(player),
          instrument.sound(player),
        ),
        shift,
      ),
    ],
  )
}

fn line_events(moved: Line) -> List(Event) {
  list.flat_map(moved.segments, fn(segment) {
    // The chord symbol belongs to the bar the segment starts, not to every
    // note in it.
    carrying(segment.events, Some(chord.to_string(segment.chord)), [])
  })
}

fn carrying(
  events: List(lick.Event),
  label: Option(String),
  acc: List(Event),
) -> List(Event) {
  case events {
    [] -> list.reverse(acc)
    [one, ..rest] -> {
      let written = case one {
        lick.Tone(note, length, held) ->
          Note(note, length, None, label, None, Alone, held)
        lick.Rest(length) -> Rest(length, label, None)
        lick.Triplet -> Tuplet(3, 2, label, None)
      }
      carrying(rest, None, [written, ..acc])
    }
  }
}

/// A chord chart: bars carrying symbols and no printed notes.
pub fn from_progression(
  subject: Progression,
  player: Instrument,
  tempo: Int,
) -> Score {
  let shift = instrument.write_interval_for_key(player, subject.key)
  let moved = progression.transpose(subject, shift)
  let capacity = 8

  let measures =
    list.map(moved.bars, fn(one) {
      Measure(
        None,
        events: list.zip(
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
    tempo: Some(tempo),
    feel: None,
    parts: [
      Part(
        name: instrument.label(player),
        clef: Treble,
        sound: instrument.piano,
        signature: signature_near(moved.key),
        transpose: Some(interval.negate(shift)),
        measures: measures,
      ),
    ],
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
///
/// Only where the bar has room for it. A quarter note that will not fit is
/// pushed into a bar of its own, and the exercise ends with a bar seven
/// eighths long -- which is not a bar. An exercise that comes out to whole
/// bars on its own is better left alone.
fn hold_last(notes: List(#(Pitch, Int))) -> List(#(Pitch, Int)) {
  let room = case int.modulo(list.length(notes) - 1, 8) {
    Ok(position) -> position <= 6
    Error(_) -> False
  }
  case list.reverse(notes), room {
    [#(note, _), ..rest], True -> list.reverse([#(note, 2), ..rest])
    _, _ -> notes
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
  tempo tempo: Int,
  sound sound: Int,
  shift shift: Interval,
) -> Score {
  Score(
    title: title,
    subtitle: subtitle,
    time: #(4, 4),
    unit: 8,
    tempo: Some(tempo),
    feel: None,
    parts: [reading(assemble(events, hint, Treble, subtitle, sound), shift)],
  )
}

/// Lay events into bars, pick a key signature, work out the accidentals.
fn assemble(
  events: List(Event),
  hint: PitchClass,
  clef: Clef,
  name: String,
  sound: Int,
) -> Part {
  let measures = shaped(events)
  settle(measures, choose_signature(measures, hint), clef, name, sound)
}

/// A staff that reads in a key somebody has already decided on.
///
/// The rhythm section gets this rather than the fewest-accidentals rule. A
/// walking bass is half chromatic approach notes, and turning that rule loose
/// on them lands the bass in a different key signature from the piano standing
/// next to it, which is nobody's idea of a score.
fn assemble_in(
  events: List(Event),
  key: PitchClass,
  clef: Clef,
  name: String,
  sound: Int,
) -> Part {
  let measures = shaped(events)
  settle(measures, signature_near(key), clef, name, sound)
}

fn shaped(events: List(Event)) -> List(Measure) {
  let capacity = 8
  events
  |> into_measures(capacity, #([], 0), [])
  |> list.map(spell_silences)
  |> list.map(beam_measure(_, capacity))
}

fn settle(
  measures: List(Measure),
  signature: Int,
  clef: Clef,
  name: String,
  sound: Int,
) -> Part {
  Part(
    name,
    clef,
    sound,
    signature,
    None,
    apply_accidentals(measures, signature),
  )
}

/// Fill bars by duration rather than by count, so a held note takes the room
/// it deserves. Nothing is split across a bar line: an event that will not fit
/// starts the next bar instead, and a tuplet moves with its notes.
fn into_measures(
  events: List(Event),
  capacity: Int,
  current: #(List(Event), Int),
  done: List(Measure),
) -> List(Measure) {
  let #(held, used) = current
  case step(events) {
    #([], _, _) ->
      case held {
        [] -> list.reverse(done)
        _ -> list.reverse([Measure(list.reverse(held), None), ..done])
      }
    #(taken, length, rest) ->
      case held != [] && used + length > capacity {
        True ->
          into_measures(events, capacity, #([], 0), [
            Measure(list.reverse(held), None),
            ..done
          ])
        False ->
          into_measures(
            rest,
            capacity,
            #(
              list.fold(taken, held, fn(kept, one) { [one, ..kept] }),
              used + length,
            ),
            done,
          )
      }
  }
}

/// How long an event is written as, which inside a tuplet is not how long it
/// lasts. Use `sounding` for anything that has to add up to a bar.
pub fn duration_of(one: Event) -> Int {
  case one {
    Note(duration: length, ..) -> length
    Stack(duration: length, ..) -> length
    Rest(duration: length, ..) -> length
    Spacer(duration: length, ..) -> length
    Tuplet(..) -> 0
  }
}

/// How much room a run of events takes up.
pub fn sounding(events: List(Event)) -> Int {
  case step(events) {
    #([], _, _) -> 0
    #(_, length, rest) -> length + sounding(rest)
  }
}

/// Events taken one move at a time: usually a single event, but a tuplet and
/// the notes it governs move together. Nothing may come between them and a
/// bar line may not fall inside them, so nothing here may take them apart.
fn step(events: List(Event)) -> #(List(Event), Int, List(Event)) {
  case events {
    [] -> #([], 0, [])
    [Tuplet(count, into, _, _) as marker, ..rest] -> #(
      [marker, ..list.take(rest, count)],
      into,
      list.drop(rest, count),
    )
    [one, ..rest] -> #([one], duration_of(one), rest)
  }
}

/// Each event paired with the unit it starts on inside its bar.
///
/// Everything in a tuplet is given the position of the group, which keeps the
/// arithmetic in whole units -- a triplet eighth starts two thirds of the way
/// through one and there is no room for that here -- and has the side effect
/// of beaming the group together, which is what it wants anyway.
fn with_positions(events: List(Event)) -> List(#(Int, Event)) {
  positions(events, 0, [])
}

fn positions(
  events: List(Event),
  at: Int,
  acc: List(#(Int, Event)),
) -> List(#(Int, Event)) {
  case step(events) {
    #([], _, _) -> list.reverse(acc)
    #(taken, length, rest) ->
      positions(
        rest,
        at + length,
        list.fold(taken, acc, fn(kept, one) { [#(at, one), ..kept] }),
      )
  }
}

/// Rewrite silences as durations that can actually be written down.
///
/// Five eighths is not a rest, it is a rest and a rest: notation has symbols
/// for an eighth, a quarter, a dotted quarter and so on, and nothing in
/// between. Off the beat only the short ones read properly, so a silence
/// starting mid beat begins by filling out the beat it is in.
fn spell_silences(subject: Measure) -> Measure {
  Measure(
    ..subject,
    events: with_positions(subject.events)
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
  let groups = grouping(subject.events, capacity / 2, 0, 0, [])
  Measure(
    ..subject,
    events: list.index_map(groups, fn(entry, at) {
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

/// Which beam each event belongs under: half a bar at a time, except that
/// the notes of a tuplet beam with each other and nothing else, so the
/// bracket over them reads as the one figure it is.
fn grouping(
  events: List(Event),
  group_size: Int,
  at: Int,
  tag: Int,
  acc: List(#(Int, Event)),
) -> List(#(Int, Event)) {
  case events {
    [] -> list.reverse(acc)
    [Tuplet(count, into, _, _) as marker, ..rest] -> {
      // Negative, so a tuplet's beam can never be the same as a bar's.
      let own = -1 - tag
      grouping(
        list.drop(rest, count),
        group_size,
        at + into,
        tag + 1,
        list.fold([marker, ..list.take(rest, count)], acc, fn(kept, one) {
          [#(own, one), ..kept]
        }),
      )
    }
    [one, ..rest] ->
      grouping(rest, group_size, at + duration_of(one), tag, [
        #(at / group_size, one),
        ..acc
      ])
  }
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

/// Whether a note needs an accidental written, given what the key signature
/// and the rest of the bar have already said.
fn needed(
  note: Pitch,
  seen: dict.Dict(#(Int, Int), Int),
  signature: Int,
) -> #(Option(Int), dict.Dict(#(Int, Int), Int)) {
  let letter = note.class.letter
  let wanted = note.class.alteration
  let key = #(pitch.diatonic_index(letter), note.octave)
  let standing = case dict.get(seen, key) {
    Ok(found) -> found
    Error(_) -> pitch.key_alteration(letter, signature)
  }
  case wanted == standing {
    True -> #(None, seen)
    False -> #(Some(wanted), dict.insert(seen, key, wanted))
  }
}

/// Decide which accidentals get printed.
///
/// An accidental lasts to the end of its bar at its own octave, so each bar
/// starts again from whatever the key signature says and only notes that
/// disagree with the state so far need any ink.
fn apply_accidentals(measures: List(Measure), signature: Int) -> List(Measure) {
  let #(done, _) =
    list.fold(measures, #([], signature), fn(state, one) {
      let #(kept, active) = state
      let signature = option.unwrap(one.key, active)
      #([spell(one, signature), ..kept], signature)
    })
  list.reverse(done)
}

fn spell(one: Measure, signature: Int) -> Measure {
  {
    let #(events, _) =
      list.fold(one.events, #([], dict.new()), fn(state, event) {
        let #(done, seen) = state
        case event {
          Note(..) as note -> {
            let #(mark, seen) = needed(note.pitch, seen, signature)
            #([Note(..note, accidental: mark), ..done], seen)
          }
          Stack(..) as stack -> {
            let #(marks, seen) =
              list.fold(stack.pitches, #([], seen), fn(state, one) {
                let #(marks, seen) = state
                let #(mark, seen) = needed(one, seen, signature)
                #([mark, ..marks], seen)
              })
            #([Stack(..stack, accidentals: list.reverse(marks)), ..done], seen)
          }
          other -> #([other, ..done], seen)
        }
      })
    Measure(..one, events: list.reverse(events))
  }
}
