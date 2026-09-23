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
import gleam/option.{None, Some}
import gleam/string
import jazz/internal/num
import jazz/notation.{
  type Clef, type Event, type Measure, type Score, Bass, ContinueBeam, Note,
  Rest, Spacer, Stack, StartBeam, Treble,
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
  let tempo = case score.tempo {
    Some(beats) -> ["Q:1/4=" <> int.to_string(beats)]
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
  let single = case score.parts {
    [_] -> True
    _ -> False
  }
  let systems =
    list.map(score.parts, fn(part) {
      chunk(list.map(part.measures, measure), bars_per_line)
    })
  let total =
    list.fold(systems, 0, fn(most, one) { int.max(most, list.length(one)) })

  num.counting(total)
  |> list.flat_map(fn(at) {
    let last = at == total - 1
    list.index_map(score.parts, fn(part, voice) {
      let bars = case list.drop(nth(systems, voice), at) {
        [line, ..] -> line
        [] -> []
      }
      let opening = case single, at, voice {
        True, _, _ -> ""
        // Each staff after the first announces its own key, and has to say
        // its clef again while doing so or the key change resets it.
        False, 0, 0 -> "[V:1] "
        False, 0, _ ->
          "[V:"
          <> voice_id(voice)
          <> "][K:"
          <> key_name(part.signature)
          <> " clef="
          <> clef_name(part.clef)
          <> "] "
        False, _, _ -> "[V:" <> voice_id(voice) <> "] "
      }
      opening
      <> string.join(bars, " | ")
      <> case last {
        True -> " |]"
        False -> " |"
      }
    })
  })
}

fn nth(systems: List(List(List(String))), at: Int) -> List(List(String)) {
  case list.drop(systems, at) {
    [one, ..] -> one
    [] -> []
  }
}

fn measure(subject: Measure) -> String {
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
    _ -> " "
  }
}

fn event(one: Event) -> String {
  case one {
    Note(note, duration, accidental, chord, annotation, _, tied) ->
      decorations(chord, annotation)
      <> accidental_mark(accidental)
      <> note_name(note)
      <> length(duration)
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
