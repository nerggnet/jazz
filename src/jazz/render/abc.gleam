//// ABC notation output.
////
//// ABC is terse enough to read in a terminal and paste straight into abcjs
//// or abcm2ps, which is why it is the first notation backend: a wrong octave
//// or a missing bar is visible immediately rather than after a round trip
//// through a notation program.
////
//// Everything interesting has already happened by the time a score arrives
//// here. This module only spells what it is given: it decides no accidentals,
//// chooses no key, and groups no beams.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import jazz/notation.{
  type Articulation, type Clef, type Event, type Measure, type Part, type Score,
  Accent, Bass, ContinueBeam, Note, Rest, Spacer, Staccato, Stack, StartBeam,
  Treble, Tuplet,
}
import jazz/pitch.{type Pitch}

/// How many bars go on one line of the tune.
const bars_per_line = 4

pub fn render(score: Score) -> String {
  render_book([score])
}

/// Several tunes in one file, numbered as a tune book.
pub fn render_book(scores: List(Score)) -> String {
  scores
  |> list.index_map(fn(score, at) {
    string.join(list.append(header(score, at + 1), body(score)), "\n")
  })
  |> string.join("\n\n")
  <> "\n"
}

fn header(score: Score, number: Int) -> List(String) {
  // The feel rides on the tempo line, which is where a chart carries it and
  // where abcjs prints it: beside the metronome mark rather than buried in
  // the music.
  let feel = case score.feel {
    Some(text) -> " \"" <> field(text) <> "\""
    None -> ""
  }
  let tempo = case score.tempo {
    Some(beats) -> ["Q:1/4=" <> int.to_string(beats) <> feel]
    None -> []
  }
  list.flatten([
    ["X:" <> int.to_string(number), "T:" <> field(score.title)],
    // A second title line is how ABC writes a subtitle.
    case score.subtitle {
      "" -> []
      text -> ["T:" <> field(text)]
    },
    [
      "M:" <> int.to_string(score.time.0) <> "/" <> int.to_string(score.time.1),
      "L:1/" <> int.to_string(score.unit),
    ],
    tempo,
    // Voices only when there is more than one staff, so a single part tune
    // still comes out as plainly as it always did.
    case score.parts {
      [_] -> []
      parts ->
        list.index_map(parts, fn(part, at) {
          "V:"
          <> voice_id(at)
          <> " clef="
          <> clef_name(part.clef)
          <> " name=\""
          <> field(part.name)
          <> "\""
        })
    },
    ["K:" <> key_name(leading(score))],
  ])
}

fn leading(score: Score) -> Int {
  case score.parts {
    [first, ..] -> first.signature
    [] -> 0
  }
}

fn key_name(signature: Int) -> String {
  pitch.class_to_string(pitch.from_fifths(signature))
}

fn voice_id(at: Int) -> String {
  int.to_string(at + 1)
}

fn clef_name(clef: Clef) -> String {
  case clef {
    Treble -> "treble"
    Bass -> "bass"
  }
}

fn body(score: Score) -> List(String) {
  case score.parts {
    // A single staff tune stays exactly as plain as it always was.
    [only] -> staff_lines(only, True)
    parts -> list.flat_map(parts, fn(part) { voice_block(part, parts) })
  }
}

/// A voice, its sound, and then all of its music. Grouping a voice's lines
/// together rather than interleaving them is what lets a `%%MIDI program`
/// attach to the voice it follows rather than to the tune as a whole.
fn voice_block(part: Part, parts: List(Part)) -> List(String) {
  let at = index_of(parts, part)
  list.flatten([
    ["V:" <> voice_id(at), "%%MIDI program " <> int.to_string(part.sound)],
    staff_lines(part, at == 0),
  ])
}

/// The music of one staff, four bars to a line. A staff that is not the first
/// announces its own key, and has to repeat its clef while doing so or the
/// key change resets it to the one in the header.
fn staff_lines(part: Part, leading: Bool) -> List(String) {
  let opening = case leading {
    True -> ""
    False ->
      "[K:"
      <> key_name(part.signature)
      <> " clef="
      <> clef_name(part.clef)
      <> "] "
  }
  let systems = chunk(list.map(part.measures, measure), bars_per_line)
  let last = list.length(systems) - 1
  list.index_map(systems, fn(line, at) {
    case at {
      0 -> opening
      _ -> ""
    }
    <> string.join(line, " | ")
    <> case at == last {
      True -> " |]"
      False -> " |"
    }
  })
}

fn index_of(parts: List(Part), wanted: Part) -> Int {
  let #(found, _) =
    list.fold(parts, #(0, 0), fn(state, one) {
      let #(found, at) = state
      case one == wanted {
        True -> #(at, at + 1)
        False -> #(found, at + 1)
      }
    })
  found
}

fn measure(subject: Measure) -> String {
  // A bar that changes key says so before its first note.
  case subject.key {
    Some(signature) -> "[K:" <> key_name(signature) <> "] "
    None -> ""
  }
  <> written_measure(subject)
}

fn written_measure(subject: Measure) -> String {
  subject.events
  |> list.map(fn(one) { event(one) <> gap(one) })
  |> string.concat
  |> string.trim_end
}

/// Notes under one beam are written with nothing between them; a space is
/// what breaks the beam.
fn gap(one: Event) -> String {
  case one {
    Note(beam: StartBeam, ..) | Note(beam: ContinueBeam, ..) -> ""
    // A tuplet mark belongs against the notes it counts.
    Tuplet(..) -> ""
    _ -> " "
  }
}

fn event(one: Event) -> String {
  case one {
    Note(note, duration, accidental, chord, annotation, _, tied, phrasing) ->
      decorations(chord, annotation)
      // A mark on a note goes before the note, and so does the bracket that
      // opens a slur; the one that closes it comes after.
      <> attack(phrasing.mark)
      <> case phrasing.opens {
        True -> "("
        False -> ""
      }
      <> accidental_mark(accidental)
      <> note_name(note)
      <> length(duration)
      <> case phrasing.closes {
        True -> ")"
        False -> ""
      }
      // A hyphen after a note ties it to the next one of the same pitch.
      <> case tied {
        True -> "-"
        False -> ""
      }
    // Notes inside square brackets sound together.
    Stack(pitches, duration, accidentals, chord, annotation) ->
      decorations(chord, annotation)
      <> "["
      <> {
        list.zip(pitches, accidentals)
        |> list.map(fn(one) { accidental_mark(one.1) <> note_name(one.0) })
        |> string.concat
      }
      <> "]"
      <> length(duration)
    Rest(duration, chord, annotation) ->
      decorations(chord, annotation) <> "z" <> length(duration)
    Spacer(duration, chord, annotation) ->
      decorations(chord, annotation) <> "x" <> length(duration)
    // `(3` is three notes in the time of two and reads as a triplet. The
    // long form spells out the other cases: so many notes, in the time of
    // so many, over so many of them.
    Tuplet(3, 2, chord, annotation) -> decorations(chord, annotation) <> "(3"
    Tuplet(count, into, chord, annotation) ->
      decorations(chord, annotation)
      <> "("
      <> int.to_string(count)
      <> ":"
      <> int.to_string(into)
      <> ":"
      <> int.to_string(count)
  }
}

fn decorations(
  chord: option.Option(String),
  annotation: option.Option(String),
) -> String {
  let symbol = case chord {
    Some(text) -> quoted(text)
    None -> ""
  }
  let note = case annotation {
    Some(text) -> quoted("_" <> text)
    None -> ""
  }
  symbol <> note
}

/// ABC writes middle C as `C`, the octave above in lower case, and each
/// further octave with a comma or an apostrophe.
fn note_name(note: Pitch) -> String {
  let letter = pitch.letter_to_string(note.class.letter)
  case note.octave <= 4 {
    True -> letter <> string.repeat(",", 4 - note.octave)
    False -> string.lowercase(letter) <> string.repeat("'", note.octave - 5)
  }
}

fn accidental_mark(accidental: option.Option(Int)) -> String {
  case accidental {
    None -> ""
    Some(0) -> "="
    Some(alteration) ->
      case alteration > 0 {
        True -> string.repeat("^", alteration)
        False -> string.repeat("_", -alteration)
      }
  }
}

/// Lengths are multiples of the unit note length declared in the header, and
/// a single unit is written by leaving the number off.
fn attack(mark: Option(Articulation)) -> String {
  case mark {
    Some(Accent) -> "!accent!"
    Some(Staccato) -> "!staccato!"
    None -> ""
  }
}

fn length(duration: Int) -> String {
  case duration {
    1 -> ""
    other -> int.to_string(other)
  }
}

/// Quoted text carries chord symbols and annotations. A quote inside one
/// would end it early, so there are none.
fn quoted(text: String) -> String {
  "\"" <> string.replace(text, "\"", "") <> "\""
}

/// Header fields run to the end of the line, so they cannot contain one.
fn field(text: String) -> String {
  text
  |> string.replace("\n", " ")
  |> string.replace("\r", " ")
}

fn chunk(items: List(a), size: Int) -> List(List(a)) {
  case items {
    [] -> []
    _ -> [list.take(items, size), ..chunk(list.drop(items, size), size)]
  }
}
