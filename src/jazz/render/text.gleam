//// Terminal output.
////
//// This is the only place that knows about transposing instruments: the
//// theory modules work at concert pitch throughout, and the part a player
//// reads is produced here, at the edge. A MusicXML or MIDI renderer would sit
//// beside this one and share everything behind it.

import gleam/int
import gleam/list
import gleam/string
import jazz/chord.{type Chord}
import jazz/instrument.{type Instrument}
import jazz/interval.{type Interval}
import jazz/lick.{type Line, type Segment}
import jazz/pitch.{type PitchClass}
import jazz/progression.{type Progression}
import jazz/scale.{type Scale}

const indent = "  "

// --- Scales ------------------------------------------------------------------

pub fn scale_view(subject: Scale, instrument: Instrument) -> String {
  let shift = instrument.write_interval_for_key(instrument, subject.root)
  let concert = list.map(scale.notes(subject), pitch.class_to_string)
  let written =
    scale.notes(subject)
    |> list.map(interval.transpose_class(_, shift))
    |> list.map(pitch.class_to_string)
  let written_root =
    interval.transpose_class(subject.root, shift) |> pitch.class_to_string

  let heading = case instrument.is_concert(instrument) {
    True ->
      pitch.class_to_string(subject.root) <> " " <> scale.name(subject.kind)
    False ->
      written_root
      <> " "
      <> scale.name(subject.kind)
      <> "  (concert "
      <> pitch.class_to_string(subject.root)
      <> ")"
  }

  let rows = case instrument.is_concert(instrument) {
    True -> [#("Notes", concert), #("Degree", scale.degrees(subject.kind))]
    False -> [
      #("Written", written),
      #("Concert", concert),
      #("Degree", scale.degrees(subject.kind)),
    ]
  }

  string.join(
    [
      title(heading, instrument),
      "",
      table(rows),
      "",
      indent <> scale.usage(subject.kind),
    ],
    "\n",
  )
}

// --- Chords ------------------------------------------------------------------

pub fn chord_view(subject: Chord, instrument: Instrument) -> String {
  let shift = instrument.write_interval_for_key(instrument, subject.root)
  let written_chord = chord.transpose(subject, shift)
  let concert = list.map(chord.notes(subject), pitch.class_to_string)
  let written = list.map(chord.notes(written_chord), pitch.class_to_string)

  let heading = case instrument.is_concert(instrument) {
    True -> chord.to_string(subject)
    False ->
      chord.to_string(written_chord)
      <> "  (concert "
      <> chord.to_string(subject)
      <> ")"
  }

  let rows = case instrument.is_concert(instrument) {
    True -> [#("Notes", concert), #("Degree", chord.degrees(subject))]
    False -> [
      #("Written", written),
      #("Concert", concert),
      #("Degree", chord.degrees(subject)),
    ]
  }

  let guides = case instrument.is_concert(instrument) {
    True -> chord.guide_tones(subject)
    False -> chord.guide_tones(written_chord)
  }

  let scales =
    chord.chord_scales(subject)
    |> list.map(fn(kind) {
      let root = interval.transpose_class(subject.root, shift)
      pitch.class_to_string(root) <> " " <> scale.name(kind)
    })

  string.join(
    [
      title(heading, instrument),
      "",
      table(rows),
      "",
      indent
        <> "Guide tones  "
        <> string.join(list.map(guides, pitch.class_to_string), "  "),
      "",
      indent <> "Scales that fit, best first:",
      ..list.map(scales, fn(name) { indent <> indent <> name })
    ],
    "\n",
  )
}

// --- Progressions ------------------------------------------------------------

pub fn progression_view(
  subject: Progression,
  instrument: Instrument,
) -> String {
  let shift = instrument.write_interval_for_key(instrument, subject.key)
  let written = progression.transpose(subject, shift)

  let heading =
    subject.name
    <> " in "
    <> pitch.class_to_string(written.key)
    <> case instrument.is_concert(instrument) {
      True -> ""
      False -> "  (concert " <> pitch.class_to_string(subject.key) <> ")"
    }

  let numerals =
    list.map(subject.bars, fn(bar) {
      bar.chords
      |> list.map(progression.roman(subject.key, _))
      |> string.join("  ")
    })
  let symbols =
    list.map(written.bars, fn(bar) {
      bar.chords |> list.map(chord.to_string) |> string.join("  ")
    })

  let width =
    list.fold(list.append(numerals, symbols), 0, fn(widest, cell) {
      int.max(widest, string.length(cell))
    })

  let staff =
    list.zip(symbols, numerals)
    |> chunk(4)
    |> list.map(fn(line) { bar_line(line, width) })
    |> string.join("\n\n")

  let voice = case instrument.is_concert(instrument) {
    True -> []
    False -> [
      "",
      indent
        <> "Concert: "
        <> string.join(
        list.map(subject.bars, fn(bar) {
          bar.chords |> list.map(chord.to_string) |> string.join(" ")
        }),
        " | ",
      ),
    ]
  }

  string.join(
    list.flatten([
      [title(heading, instrument), "", staff, "", indent <> subject.note],
      voice,
    ]),
    "\n",
  )
}

fn bar_line(bars: List(#(String, String)), width: Int) -> String {
  let symbols =
    bars
    |> list.map(fn(bar) { string.pad_end(bar.0, width, " ") })
    |> string.join(" | ")
  let numerals =
    bars
    |> list.map(fn(bar) { string.pad_end(bar.1, width, " ") })
    |> string.join("   ")
  indent
  <> "| "
  <> symbols
  <> " |\n"
  <> indent
  <> "  "
  <> string.trim_end(numerals)
}

// --- Licks -------------------------------------------------------------------

pub fn lick_view(
  line: Line,
  heading: String,
  player: Instrument,
  key: PitchClass,
) -> String {
  let shift = instrument.write_interval_for_key(player, key)
  let written = lick.transpose(line, shift) |> lick.simplify_spelling
  let rows = lick_rows(written.segments, 0, [])

  let chord_width = int.max(column_width(rows, fn(row) { row.1 }), 5)
  let note_width = int.max(column_width(rows, fn(row) { row.2 }), 4)
  let target_width = int.max(column_width(rows, fn(row) { row.3 }), 6)

  let body =
    list.map(rows, fn(row) {
      indent
      <> string.pad_end(row.0, 5, " ")
      <> string.pad_end(row.1, chord_width + 2, " ")
      <> string.pad_end(row.2, note_width + 2, " ")
      <> string.pad_end(row.3, target_width + 2, " ")
      <> row.4
      |> string.trim_end
    })

  let header =
    indent
    <> string.pad_end("Bar", 5, " ")
    <> string.pad_end("Chord", chord_width + 2, " ")
    <> string.pad_end("Line", note_width + 2, " ")
    <> string.pad_end("Target", target_width + 2, " ")
    <> "How it is built"

  let footer = case lick.span(written) {
    Ok(#(low, high)) ->
      indent
      <> case instrument.is_concert(player) {
        True -> "Range "
        False -> "Written range "
      }
      <> pitch.to_string(low)
      <> " to "
      <> pitch.to_string(high)
      <> ".  Same line again with --seed "
      <> int.to_string(line.seed)
      <> "."
    Error(_) -> indent <> "Empty line."
  }

  let concert = case instrument.is_concert(player) {
    True -> []
    False -> [
      indent
      <> "Concert: "
      <> string.join(
        list.map(line.segments, fn(one) { chord.to_string(one.chord) }),
        " ",
      ),
    ]
  }

  string.join(
    list.flatten([
      [title(heading, player), "", header],
      body,
      [""],
      concert,
      [footer],
    ]),
    "\n",
  )
}

/// One row per chord, carrying the bar it starts in.
fn lick_rows(
  segments: List(Segment),
  elapsed: Int,
  acc: List(#(String, String, String, String, String)),
) -> List(#(String, String, String, String, String)) {
  case segments {
    [] -> list.reverse(acc)
    [one, ..rest] -> {
      let length =
        list.fold(one.events, 0, fn(total, event) {
          case event {
            lick.Tone(_, beats) -> total + beats
            lick.Rest(beats) -> total + beats
          }
        })
      let names =
        one.events
        |> list.map(fn(event) {
          case event {
            lick.Tone(note, _) ->
              string.pad_end(pitch.class_to_string(note.class), 3, " ")
            lick.Rest(_) -> string.pad_end("-", 3, " ")
          }
        })
        |> string.concat
        |> string.trim_end
      let row = #(
        int.to_string(elapsed / lick.bar + 1),
        chord.to_string(one.chord),
        names,
        one.target,
        one.device,
      )
      lick_rows(rest, elapsed + length, [row, ..acc])
    }
  }
}

fn column_width(
  rows: List(#(String, String, String, String, String)),
  get: fn(#(String, String, String, String, String)) -> String,
) -> Int {
  list.fold(rows, 0, fn(widest, row) {
    int.max(widest, string.length(get(row)))
  })
}

// --- Transposition -----------------------------------------------------------

pub fn transpose_view(
  notes: List(PitchClass),
  from: Instrument,
  to: Instrument,
) -> String {
  let concert = list.map(notes, instrument.sounds_class(from, _))
  let shift = case concert {
    [first, ..] -> instrument.write_interval_for_key(to, first)
    [] -> to.write_interval
  }
  let written = list.map(concert, interval.transpose_class(_, shift))
  table([
    #(from.name, list.map(notes, pitch.class_to_string)),
    #("Concert", list.map(concert, pitch.class_to_string)),
    #(to.name, list.map(written, pitch.class_to_string)),
  ])
}

// --- Listings ----------------------------------------------------------------

pub fn scale_listing() -> String {
  scale.all_kinds()
  |> list.map(fn(kind) {
    indent
    <> string.pad_end(scale.id(kind), 24, " ")
    <> string.pad_end(scale.name(kind), 26, " ")
    <> scale.usage(kind)
  })
  |> string.join("\n")
}

pub fn instrument_listing() -> String {
  instrument.all()
  |> list.map(fn(entry) {
    indent
    <> string.pad_end(entry.id, 12, " ")
    <> string.pad_end(instrument.label(entry), 22, " ")
    <> "written "
    <> pitch.to_string(entry.lowest_written)
    <> " to "
    <> pitch.to_string(entry.highest_written)
  })
  |> string.join("\n")
}

pub fn progression_listing() -> String {
  progression.catalogue()
  |> list.map(fn(entry) {
    indent <> string.pad_end(entry.0, 20, " ") <> entry.1
  })
  |> string.join("\n")
}

// --- Layout ------------------------------------------------------------------

fn title(heading: String, instrument: Instrument) -> String {
  indent <> heading <> "  --  " <> instrument.label(instrument)
}

fn table(rows: List(#(String, List(String)))) -> String {
  let label_width =
    list.fold(rows, 0, fn(widest, row) { int.max(widest, string.length(row.0)) })
  let widths = list.fold(rows, [], fn(acc, row) { merge_widths(acc, row.1) })

  rows
  |> list.map(fn(row) {
    let cells =
      list.zip(row.1, widths)
      |> list.map(fn(pair) { string.pad_end(pair.0, pair.1, " ") })
      |> string.join("  ")
    indent
    <> string.pad_end(row.0, label_width + 2, " ")
    <> string.trim_end(cells)
  })
  |> string.join("\n")
}

fn merge_widths(widths: List(Int), cells: List(String)) -> List(Int) {
  case widths, cells {
    [], rest -> list.map(rest, string.length)
    kept, [] -> kept
    [width, ..more_widths], [cell, ..more_cells] -> [
      int.max(width, string.length(cell)),
      ..merge_widths(more_widths, more_cells)
    ]
  }
}

fn chunk(items: List(a), size: Int) -> List(List(a)) {
  case items {
    [] -> []
    _ -> [list.take(items, size), ..chunk(list.drop(items, size), size)]
  }
}

/// A shared interval helper for callers that want the written spelling.
pub fn written_shift(instrument: Instrument, key: PitchClass) -> Interval {
  instrument.write_interval_for_key(instrument, key)
}
