//// MusicXML output.
////
//// The format every notation program reads, which is the point of it: a part
//// written here opens in MuseScore or Sibelius and can be laid out, printed,
//// or put on a stand. ABC says the same things in a tenth of the characters,
//// which is why it came first; this says them in a way other software agrees
//// on.
////
//// Like the ABC backend this only spells what it is given. The one piece of
//// arithmetic it does is its own: MusicXML counts durations in divisions of a
//// quarter note rather than in eighths, and a triplet eighth has to come out
//// a whole number, so there are six to a quarter. An eighth is three of them
//// and a triplet eighth is two.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import jazz/chord.{type Chord}
import jazz/interval.{type Interval}
import jazz/notation.{
  type Clef, type Event, type Measure, type Part, type Score, Bass, ContinueBeam,
  EndBeam, Note, Rest, Spacer, Stack, StartBeam, Treble, Tuplet,
}
import jazz/pitch.{type Pitch}

/// How many of MusicXML's divisions make up one written eighth note.
const per_eighth = 3

/// And how many make a quarter, which is the number the file declares.
const per_quarter = 6

pub fn render(score: Score) -> String {
  string.join(
    list.flatten([
      [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">",
        "<score-partwise version=\"4.0\">",
        "  <work>",
        "    <work-title>" <> escape(score.title) <> "</work-title>",
        "  </work>",
      ],
      credits(score),
      part_list(score),
      list.index_map(score.parts, fn(part, at) { body(score, part, at) }),
      ["</score-partwise>"],
    ]),
    "\n",
  )
  <> "\n"
}

/// The subtitle, and the feel if there is one, as the lines of text a
/// notation program prints under the title.
fn credits(score: Score) -> List(String) {
  [score.subtitle, option.unwrap(score.feel, "")]
  |> list.filter(fn(one) { one != "" })
  |> list.map(fn(text) {
    "  <credit page=\"1\"><credit-words>"
    <> escape(text)
    <> "</credit-words></credit>"
  })
}

fn part_list(score: Score) -> List(String) {
  list.flatten([
    ["  <part-list>"],
    list.index_map(score.parts, fn(part, at) {
      let id = part_id(at)
      string.join(
        list.flatten([
          [
            "    <score-part id=\"" <> id <> "\">",
            // What the staff is labelled.
            "      <part-name>" <> escape(part.name) <> "</part-name>",
            "      <score-instrument id=\"" <> id <> "-I1\">",
            // And what is playing it, which is not the same question.
            "        <instrument-name>"
              <> escape(named(part))
              <> "</instrument-name>",
          ],
          case sound_id(part.sound) {
            Some(id) -> [
              "        <instrument-sound>" <> id <> "</instrument-sound>",
            ]
            None -> []
          },
          [
            "      </score-instrument>",
            "      <midi-instrument id=\"" <> id <> "-I1\">",
            "        <midi-channel>"
              <> int.to_string(at + 1)
              <> "</midi-channel>",
            // MusicXML numbers the General MIDI programs from one.
            "        <midi-program>"
              <> int.to_string(part.sound + 1)
              <> "</midi-program>",
            "      </midi-instrument>",
            "    </score-part>",
          ],
        ]),
        "\n",
      )
    }),
    ["  </part-list>"],
  ])
}

/// Which instrument a part is for, as opposed to what its staff is called.
///
/// A staff labelled "Bass" in a jazz score is a bassist. A part called
/// "Bass" in a file is the lowest voice in a choir, which is what MuseScore
/// reads it as, and it then plays the walking line with a choir. The name a
/// reader identifies the instrument by and the name printed on the staff are
/// different fields for exactly this reason, so they are allowed to differ.
///
/// Keyed on the General MIDI program, because that is the instrument: the
/// part already carries it and there is nothing else to be got from.
fn named(part: Part) -> String {
  case voice(part.sound) {
    Some(#(name, _)) -> name
    None -> part.name
  }
}

/// The Sound ID from MusicXML's own list, which is the field a reader is
/// meant to work this out from rather than by guessing at names.
fn sound_id(program: Int) -> Option(String) {
  case voice(program) {
    Some(#(_, id)) -> Some(id)
    None -> None
  }
}

fn voice(program: Int) -> Option(#(String, String)) {
  case program {
    0 -> Some(#("Piano", "keyboard.piano"))
    32 -> Some(#("Acoustic Bass", "pluck.bass.acoustic"))
    56 -> Some(#("Trumpet", "brass.trumpet"))
    64 -> Some(#("Soprano Saxophone", "wind.reed.saxophone.soprano"))
    65 -> Some(#("Alto Saxophone", "wind.reed.saxophone.alto"))
    66 -> Some(#("Tenor Saxophone", "wind.reed.saxophone.tenor"))
    67 -> Some(#("Baritone Saxophone", "wind.reed.saxophone.baritone"))
    71 -> Some(#("Clarinet", "wind.reed.clarinet"))
    _ -> None
  }
}

fn part_id(at: Int) -> String {
  "P" <> int.to_string(at + 1)
}

fn body(score: Score, part: Part, at: Int) -> String {
  string.join(
    list.flatten([
      ["  <part id=\"" <> part_id(at) <> "\">"],
      list.index_map(part.measures, fn(measure, number) {
        written_measure(score, part, measure, number)
      }),
      ["  </part>"],
    ]),
    "\n",
  )
}

fn written_measure(
  score: Score,
  part: Part,
  measure: Measure,
  number: Int,
) -> String {
  let opening = case number {
    0 -> attributes(score, part, part.signature, True)
    _ ->
      case measure.key {
        Some(signature) -> attributes(score, part, signature, False)
        None -> []
      }
  }
  let heading = case number {
    0 -> tempo_mark(score)
    _ -> []
  }
  string.join(
    list.flatten([
      ["    <measure number=\"" <> int.to_string(number + 1) <> "\">"],
      opening,
      heading,
      notes(measure.events, None, 0),
      ["    </measure>"],
    ]),
    "\n",
  )
}

/// Divisions, key, time and clef at the top; a key on its own wherever the
/// music changes key part way through.
fn attributes(
  score: Score,
  part: Part,
  signature: Int,
  opening: Bool,
) -> List(String) {
  list.flatten([
    ["      <attributes>"],
    case opening {
      True -> [
        "        <divisions>" <> int.to_string(per_quarter) <> "</divisions>",
      ]
      False -> []
    },
    [
      "        <key>",
      "          <fifths>" <> int.to_string(signature) <> "</fifths>",
      "        </key>",
    ],
    case opening {
      True -> [
        "        <time>",
        "          <beats>" <> int.to_string(score.time.0) <> "</beats>",
        "          <beat-type>" <> int.to_string(score.time.1) <> "</beat-type>",
        "        </time>",
        "        <clef>",
        "          <sign>" <> clef_sign(part.clef) <> "</sign>",
        "          <line>" <> clef_line(part.clef) <> "</line>",
        "        </clef>",
      ]
      False -> []
    },
    case opening, part.transpose {
      True, Some(by) -> transposition(by)
      _, _ -> []
    },
    ["      </attributes>"],
  ])
}

/// What a horn sounds relative to what it reads, which is exactly the
/// interval this program has been carrying around all along.
///
/// A part that reads where it sounds has nothing to declare, and a
/// transposition of nothing is noise in the file.
fn transposition(by: Interval) -> List(String) {
  case interval.steps(by) == 0 && interval.semitones(by) == 0 {
    True -> []
    False -> [
      "        <transpose>",
      "          <diatonic>"
        <> int.to_string(interval.steps(by))
        <> "</diatonic>",
      "          <chromatic>"
        <> int.to_string(interval.semitones(by))
        <> "</chromatic>",
      "        </transpose>",
    ]
  }
}

fn clef_sign(clef: Clef) -> String {
  case clef {
    Treble -> "G"
    Bass -> "F"
  }
}

fn clef_line(clef: Clef) -> String {
  case clef {
    Treble -> "2"
    Bass -> "4"
  }
}

fn tempo_mark(score: Score) -> List(String) {
  case score.tempo {
    None -> []
    Some(beats) -> [
      "      <direction placement=\"above\">",
      "        <direction-type>",
      "          <metronome>",
      "            <beat-unit>quarter</beat-unit>",
      "            <per-minute>" <> int.to_string(beats) <> "</per-minute>",
      "          </metronome>",
      "        </direction-type>",
      "        <sound tempo=\"" <> int.to_string(beats) <> "\"/>",
      "      </direction>",
    ]
  }
}

// --- Notes -------------------------------------------------------------------

/// How a note is written, told apart from how long it lasts.
///
/// Inside a tuplet the two part company: three eighths are written as eighths
/// and last two eighths between them, and `scale` is what relates them.
type Inside {
  Inside(count: Int, into: Int, left: Int)
}

fn notes(
  events: List(Event),
  group: Option(Inside),
  tied: Int,
) -> List(String) {
  case events {
    [] -> []
    [Tuplet(count, into, symbol, _), ..rest] ->
      list.append(
        harmony(symbol),
        notes(rest, Some(Inside(count, into, count)), tied),
      )
    [one, ..rest] -> {
      let held = case one {
        Note(tied: True, ..) -> 1
        _ -> 0
      }
      list.append(
        written_event(one, group, tied, closing(group)),
        notes(rest, remaining(group), held),
      )
    }
  }
}

/// Whether this is the last note the tuplet mark was counting.
fn closing(group: Option(Inside)) -> Bool {
  case group {
    Some(Inside(left: 1, ..)) -> True
    _ -> False
  }
}

fn remaining(group: Option(Inside)) -> Option(Inside) {
  case group {
    Some(Inside(count, into, left)) if left > 1 ->
      Some(Inside(count, into, left - 1))
    _ -> None
  }
}

/// How many divisions an event actually lasts.
fn divisions(written: Int, group: Option(Inside)) -> Int {
  case group {
    None -> written * per_eighth
    Some(one) -> written * per_eighth * one.into / one.count
  }
}

fn written_event(
  one: Event,
  group: Option(Inside),
  tied: Int,
  last: Bool,
) -> List(String) {
  case one {
    Note(note, length, accidental, symbol, _, beam, holds, phrasing) ->
      list.append(
        harmony(symbol),
        printed(
          pitched(note),
          accidental,
          length,
          group,
          tied,
          holds,
          last,
          beam_mark(beam),
          False,
          phrasing,
        ),
      )
    Stack(pitches, length, accidentals, symbol, _) ->
      list.append(
        harmony(symbol),
        list.zip(pitches, accidentals)
          |> list.index_map(fn(entry, at) {
            printed(
              pitched(entry.0),
              entry.1,
              length,
              group,
              tied,
              False,
              last,
              [],
              at > 0,
              notation.plainly,
            )
          })
          |> list.flatten,
      )
    Rest(length, symbol, _) ->
      list.append(
        harmony(symbol),
        printed(
          ["        <rest/>"],
          None,
          length,
          group,
          0,
          False,
          last,
          [],
          False,
          notation.plainly,
        ),
      )
    // Time that passes with nothing printed in it: exactly what `forward` is.
    Spacer(length, symbol, _) ->
      list.append(harmony(symbol), [
        "      <forward>",
        "        <duration>"
          <> int.to_string(divisions(length, group))
          <> "</duration>",
        "      </forward>",
      ])
    Tuplet(..) -> []
  }
}

/// One note, with its parts in the order the format insists on.
///
/// MusicXML is defined by a DTD and the DTD is a sequence, not a set: a tie
/// belongs after the duration, an accidental after the note value, and a
/// reader is entitled to reject anything else. Nothing here is free to move.
fn printed(
  head: List(String),
  accidental: Option(Int),
  length: Int,
  group: Option(Inside),
  tied: Int,
  holds: Bool,
  last: Bool,
  beam: List(String),
  stacked: Bool,
  phrasing: notation.Phrasing,
) -> List(String) {
  list.flatten([
    ["      <note>"],
    case stacked {
      True -> ["        <chord/>"]
      False -> []
    },
    head,
    [
      "        <duration>"
      <> int.to_string(divisions(length, group))
      <> "</duration>",
    ],
    case tied {
      0 -> []
      _ -> ["        <tie type=\"stop\"/>"]
    },
    case holds {
      True -> ["        <tie type=\"start\"/>"]
      False -> []
    },
    ["        <voice>1</voice>"],
    kind(length),
    case accidental {
      None -> []
      Some(mark) -> [
        "        <accidental>" <> accidental_name(mark) <> "</accidental>",
      ]
    },
    case group {
      Some(one) -> [
        "        <time-modification>",
        "          <actual-notes>"
          <> int.to_string(one.count)
          <> "</actual-notes>",
        "          <normal-notes>"
          <> int.to_string(one.into)
          <> "</normal-notes>",
        "        </time-modification>",
      ]
      None -> []
    },
    beam,
    notations(group, last, tied, holds, phrasing),
    ["      </note>"],
  ])
}

fn notations(
  group: Option(Inside),
  last: Bool,
  tied: Int,
  holds: Bool,
  phrasing: notation.Phrasing,
) -> List(String) {
  let marks =
    list.flatten([
      case tied {
        0 -> []
        _ -> ["          <tied type=\"stop\"/>"]
      },
      case holds {
        True -> ["          <tied type=\"start\"/>"]
        False -> []
      },
      case group, last {
        Some(Inside(left: left, count: count, ..)), _ if left == count -> [
          "          <tuplet type=\"start\" bracket=\"yes\"/>",
        ]
        Some(_), True -> ["          <tuplet type=\"stop\"/>"]
        _, _ -> []
      },
      case phrasing.closes {
        True -> ["          <slur type=\"stop\" number=\"1\"/>"]
        False -> []
      },
      case phrasing.opens {
        True -> ["          <slur type=\"start\" number=\"1\"/>"]
        False -> []
      },
      case phrasing.mark {
        Some(notation.Accent) -> [
          "          <articulations>",
          "            <accent/>",
          "          </articulations>",
        ]
        Some(notation.Staccato) -> [
          "          <articulations>",
          "            <staccato/>",
          "          </articulations>",
        ]
        None -> []
      },
    ])
  case marks {
    [] -> []
    _ ->
      list.flatten([["        <notations>"], marks, ["        </notations>"]])
  }
}

fn pitched(note: Pitch) -> List(String) {
  list.flatten([
    ["        <pitch>"],
    [
      "          <step>"
      <> pitch.letter_to_string(note.class.letter)
      <> "</step>",
    ],
    case note.class.alteration {
      0 -> []
      other -> ["          <alter>" <> int.to_string(other) <> "</alter>"]
    },
    ["          <octave>" <> int.to_string(note.octave) <> "</octave>"],
    ["        </pitch>"],
  ])
}

fn accidental_name(alteration: Int) -> String {
  case alteration {
    -2 -> "flat-flat"
    -1 -> "flat"
    0 -> "natural"
    1 -> "sharp"
    2 -> "double-sharp"
    _ -> "other"
  }
}

/// The note value something is written as, dots and all, from its length in
/// eighths.
fn kind(length: Int) -> List(String) {
  let #(name, dots) = case length {
    1 -> #("eighth", 0)
    2 -> #("quarter", 0)
    3 -> #("quarter", 1)
    4 -> #("half", 0)
    6 -> #("half", 1)
    7 -> #("half", 2)
    8 -> #("whole", 0)
    12 -> #("whole", 1)
    _ -> #("eighth", 0)
  }
  list.append(
    ["        <type>" <> name <> "</type>"],
    list.repeat("        <dot/>", dots),
  )
}

fn beam_mark(beam: notation.Beam) -> List(String) {
  case beam {
    StartBeam -> ["        <beam number=\"1\">begin</beam>"]
    ContinueBeam -> ["        <beam number=\"1\">continue</beam>"]
    EndBeam -> ["        <beam number=\"1\">end</beam>"]
    _ -> []
  }
}

// --- Chord symbols -----------------------------------------------------------

/// A chord symbol, as a chord rather than as a piece of text.
///
/// The symbol arrives here as the string a reader sees, so it is read back
/// with the same dialect parser that wrote it. Anything that will not parse
/// is left off rather than guessed at: a wrong chord above the staff is worse
/// than none.
fn harmony(symbol: Option(String)) -> List(String) {
  case symbol {
    None -> []
    Some(text) ->
      case chord.parse(text) {
        Error(_) -> []
        Ok(one) ->
          list.flatten([
            ["      <harmony>"],
            [
              "        <root>",
              "          <root-step>"
                <> pitch.letter_to_string(one.root.letter)
                <> "</root-step>",
            ],
            case one.root.alteration {
              0 -> []
              other -> [
                "          <root-alter>"
                <> int.to_string(other)
                <> "</root-alter>",
              ]
            },
            ["        </root>"],
            [
              "        <kind text=\""
              <> escape(chord.quality_string(one))
              <> "\">"
              <> kind_name(one)
              <> "</kind>",
            ],
            list.flat_map(one.tensions, fn(one) {
              [
                "        <degree>",
                "          <degree-value>"
                  <> int.to_string(one.degree)
                  <> "</degree-value>",
                "          <degree-alter>"
                  <> int.to_string(one.alteration)
                  <> "</degree-alter>",
                "          <degree-type>"
                  <> case one.alteration {
                  0 -> "add"
                  _ -> "alter"
                }
                  <> "</degree-type>",
                "        </degree>",
              ]
            }),
            case one.bass {
              None -> []
              Some(low) ->
                list.flatten([
                  [
                    "        <bass>",
                    "          <bass-step>"
                      <> pitch.letter_to_string(low.letter)
                      <> "</bass-step>",
                  ],
                  case low.alteration {
                    0 -> []
                    other -> [
                      "          <bass-alter>"
                      <> int.to_string(other)
                      <> "</bass-alter>",
                    ]
                  },
                  ["        </bass>"],
                ])
            },
            ["      </harmony>"],
          ])
      }
  }
}

fn kind_name(one: Chord) -> String {
  case one.triad, one.seventh, one.sixth {
    chord.Sus4, _, _ -> "suspended-fourth"
    chord.Sus2, _, _ -> "suspended-second"
    chord.MajorTriad, chord.MajorSeventh, _ -> "major-seventh"
    chord.MajorTriad, chord.MinorSeventh, _ -> "dominant"
    chord.MajorTriad, chord.NoSeventh, True -> "major-sixth"
    chord.MajorTriad, chord.NoSeventh, False -> "major"
    chord.MinorTriad, chord.MajorSeventh, _ -> "major-minor"
    chord.MinorTriad, chord.MinorSeventh, _ -> "minor-seventh"
    chord.MinorTriad, chord.NoSeventh, True -> "minor-sixth"
    chord.MinorTriad, chord.NoSeventh, False -> "minor"
    chord.DiminishedTriad, chord.DiminishedSeventh, _ -> "diminished-seventh"
    chord.DiminishedTriad, chord.MinorSeventh, _ -> "half-diminished"
    chord.DiminishedTriad, _, _ -> "diminished"
    chord.AugmentedTriad, chord.MinorSeventh, _ -> "augmented-seventh"
    chord.AugmentedTriad, _, _ -> "augmented"
    _, _, _ -> "other"
  }
}

/// Five characters cannot appear in XML as themselves.
fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&apos;")
}
