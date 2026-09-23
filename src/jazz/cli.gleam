//// The command line.
////
//// Argument handling and nothing else: every command reads its options,
//// hands them to the theory modules, and prints whatever the renderer gives
//// back. Nothing here knows how a scale is built.

import argv
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jazz/chord
import jazz/instrument.{type Instrument}
import jazz/lick
import jazz/notation
import jazz/pattern.{type Arpeggio, type Pattern}
import jazz/pitch.{type PitchClass}
import jazz/progression.{type Progression}
import jazz/render/abc
import jazz/render/musicxml
import jazz/render/text
import jazz/scale
import jazz/tune

pub fn run() -> Nil {
  case argv.load().arguments {
    [] -> io.println(help())
    ["help", ..] | ["--help", ..] | ["-h", ..] -> io.println(help())
    ["scale", ..rest] -> report(scale_command(rest))
    ["chord", ..rest] -> report(chord_command(rest))
    ["progression", ..rest] | ["prog", ..rest] ->
      report(progression_command(rest))
    ["lick", ..rest] | ["line", ..rest] -> report(lick_command(rest))
    ["analyse", ..rest] | ["analyze", ..rest] | ["changes", ..rest] ->
      report(analysis_command(rest))
    ["transpose", ..rest] -> report(transpose_command(rest))
    ["list", ..rest] -> report(list_command(rest))
    [unknown, ..] ->
      report(Error("unknown command `" <> unknown <> "`. Try `jazz help`."))
  }
}

fn report(outcome: Result(String, String)) -> Nil {
  case outcome {
    Ok(output) -> io.println(output)
    Error(message) -> io.println_error("jazz: " <> message)
  }
}

// --- Commands ----------------------------------------------------------------

fn scale_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use format <- result.try(format_option(options))
  use beats <- result.try(tempo_option(options))
  use shape <- result.try(pattern_option(options))
  let draw = fn(subjects) {
    case format {
      Text ->
        subjects
        |> list.map(fn(one: scale.Scale) {
          text.scale_view(one, shape, [one.root], player)
        })
        |> string.join("\n\n")
      Abc ->
        subjects
        |> list.map(fn(one: scale.Scale) {
          notation.from_pattern(one, shape, [one.root], player, beats)
        })
        |> abc.render_book
      // A MusicXML file holds one score, so the keys go into one score
      // rather than into a book of them: same music, and a notation program
      // will open it.
      MusicXml ->
        case subjects {
          [] -> ""
          [first, ..] as all ->
            musicxml.render(notation.from_pattern(
              first,
              shape,
              list.map(all, fn(one: scale.Scale) { one.root }),
              player,
              beats,
            ))
        }
    }
  }
  case options.positional {
    [root_text, kind_text] -> {
      use root <- result.try(pitch.parse_class(root_text))
      use kind <- result.try(scale.kind_from_string(kind_text))
      case flag(options, "all-keys") {
        Some(_) ->
          Ok(
            keys(root, flag(options, "cycle"))
            |> list.map(fn(key) { scale.Scale(key, kind) })
            |> draw,
          )
        None -> Ok(draw([scale.Scale(root, kind)]))
      }
    }
    _ ->
      Error(
        "usage: jazz scale <root> <scale> [--for <instrument>] [--pattern <pattern>]",
      )
  }
}

fn chord_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use format <- result.try(format_option(options))
  use beats <- result.try(tempo_option(options))
  use shape <- result.try(arpeggio_option(options))
  case options.positional {
    [symbol] -> {
      use parsed <- result.try(chord.parse(symbol))
      let round = case flag(options, "all-keys") {
        Some(_) -> keys(parsed.root, flag(options, "cycle"))
        None -> [parsed.root]
      }
      let score = notation.from_arpeggio(parsed, shape, round, player, beats)
      Ok(case format {
        Text -> text.chord_view(parsed, shape, round, player)
        Abc -> abc.render(score)
        MusicXml -> musicxml.render(score)
      })
    }
    _ ->
      Error(
        "usage: jazz chord <symbol> [--for <instrument>] [--pattern <pattern>]",
      )
  }
}

fn progression_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use format <- result.try(format_option(options))
  use beats <- result.try(tempo_option(options))
  let draw = fn(subjects) {
    case format {
      Text ->
        subjects
        |> list.map(text.progression_view(_, player))
        |> string.join("\n\n")
      Abc ->
        subjects
        |> list.map(notation.from_progression(_, player, beats))
        |> abc.render_book
      MusicXml ->
        case subjects {
          [only] ->
            musicxml.render(notation.from_progression(only, player, beats))
          _ -> ""
        }
    }
  }
  use requested <- result.try(key_option(options))
  let key = option.unwrap(requested, pitch.natural(pitch.C))

  case options.positional, flag(options, "all-keys") {
    [], _ ->
      Error(
        "usage: jazz progression <name|changes> [--key <key>] [--for <instrument>] [--all-keys]",
      )
    // Round the cycle only makes sense for something with degrees behind it.
    [name], Some(_) ->
      keys(key, flag(options, "cycle"))
      |> list.try_map(fn(each) { progression.build(name, each) })
      |> result.map(draw)
    positional, _ -> {
      use built <- result.try(changes(positional, requested, options))
      Ok(draw([built]))
    }
  }
}

fn lick_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use format <- result.try(format_option(options))
  use beats <- result.try(tempo_option(options))
  use level <- result.try(level_option(options))
  use seed <- result.try(number(options, "seed", 1))
  use requested <- result.try(key_option(options))

  case options.positional {
    [] ->
      Error(
        "usage: jazz lick <progression|changes> [--key <key>] [--level <level>] [--seed <n>]",
      )
    positional -> {
      use built <- result.try(changes(positional, requested, options))
      let #(low, high) = instrument.comfortable_range(player)
      let line =
        lick.over_progression(built, lick.Options(level, seed, low, high))
      let backed = flag(options, "backing") != None
      case flag(options, "all-keys") {
        // A lick in twelve keys is the exercise; a backing to play it
        // against once is a different one.
        Some(_) ->
          Ok(draw_keys(
            line,
            built,
            heading(built),
            player,
            format,
            beats,
            keys(built.key, flag(options, "cycle")),
          ))
        None ->
          Ok(draw_lick(
            line,
            built,
            heading(built),
            player,
            format,
            beats,
            backed,
          ))
      }
    }
  }
}

fn draw_lick(
  line: lick.Line,
  changes: Progression,
  title: String,
  player: Instrument,
  format: Format,
  tempo: Int,
  backed: Bool,
) -> String {
  case format, backed {
    Text, _ -> text.lick_view(line, title, player, changes.key)
    Abc, True ->
      abc.render(notation.from_line_with_backing(
        line,
        changes,
        title,
        player,
        tempo,
      ))
    Abc, False ->
      abc.render(notation.from_line(line, title, changes.key, player, tempo))
    MusicXml, True ->
      musicxml.render(notation.from_line_with_backing(
        line,
        changes,
        title,
        player,
        tempo,
      ))
    MusicXml, False ->
      musicxml.render(notation.from_line(
        line,
        title,
        changes.key,
        player,
        tempo,
      ))
  }
}

/// One line round the keys, on one staff.
fn draw_keys(
  line: lick.Line,
  changes: Progression,
  title: String,
  player: Instrument,
  format: Format,
  tempo: Int,
  round: List(pitch.PitchClass),
) -> String {
  let score =
    notation.from_line_in_keys(line, changes, title, player, tempo, round)
  case format {
    Text -> text.lick_view(line, title, player, changes.key)
    Abc -> abc.render(score)
    MusicXml -> musicxml.render(score)
  }
}

fn analysis_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use requested <- result.try(key_option(options))

  case options.positional {
    [] ->
      Error(
        "usage: jazz analyse <progression|changes> [--key <key>] [--for <instrument>]",
      )
    positional -> {
      use built <- result.try(changes(positional, requested, options))
      Ok(text.analysis_view(
        progression.chords(built),
        heading(built),
        player,
        built.key,
      ))
    }
  }
}

/// Changes from the catalogue, or typed out on the command line.
///
/// A single word is tried as a catalogue name first, because `blues` is a
/// progression and not a chord. Anything else is read as changes, so bar
/// lines and repeats work the same here as they do anywhere else.
fn changes(
  positional: List(String),
  requested: Option(PitchClass),
  options: Options,
) -> Result(Progression, String) {
  let key = option.unwrap(requested, pitch.natural(pitch.C))
  case positional {
    ["tune"] -> {
      use bars <- result.try(number(options, "bars", 16))
      use seed <- result.try(number(options, "seed", 1))
      use level <- result.try(level_option(options))
      Ok(tune.generate(bars, key, level, seed))
    }
    [single] ->
      case progression.build(single, key) {
        Ok(built) -> Ok(built)
        Error(unknown) ->
          case progression.parse(single) {
            Ok(built) -> Ok(in_key(built, requested))
            // If it is not changes either, the catalogue has the more
            // useful complaint.
            Error(_) -> Error(unknown)
          }
      }
    many ->
      progression.parse(string.join(many, " "))
      |> result.map(in_key(_, requested))
  }
}

fn in_key(built: Progression, requested: Option(PitchClass)) -> Progression {
  case requested {
    Some(key) -> progression.Progression(..built, key: key)
    None -> built
  }
}

fn heading(built: Progression) -> String {
  built.name <> " in " <> pitch.class_to_string(built.key)
}

fn level_option(options: Options) -> Result(lick.Level, String) {
  case flag(options, "level") {
    Some(text) -> lick.level_from_string(text)
    None -> Ok(lick.Beginner)
  }
}

fn number(
  options: Options,
  name: String,
  fallback: Int,
) -> Result(Int, String) {
  case flag(options, name) {
    None -> Ok(fallback)
    Some(text) ->
      int.parse(text)
      |> result.replace_error(
        "`--" <> name <> "` wants a whole number, not `" <> text <> "`",
      )
  }
}

fn key_option(options: Options) -> Result(Option(PitchClass), String) {
  case flag(options, "key") {
    Some(text) -> result.map(pitch.parse_class(text), Some)
    None -> Ok(None)
  }
}

fn transpose_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use from <- result.try(named_instrument(flag(options, "from")))
  use to <- result.try(named_instrument(flag(options, "to")))
  case options.positional {
    [] ->
      Error(
        "usage: jazz transpose <notes...> --from <instrument> --to <instrument>",
      )
    notes ->
      notes
      |> list.try_map(pitch.parse_class)
      |> result.map(text.transpose_view(_, from, to))
  }
}

fn list_command(args: List(String)) -> Result(String, String) {
  case args {
    ["scales"] -> Ok(text.scale_listing())
    ["instruments"] -> Ok(text.instrument_listing())
    ["progressions"] -> Ok(text.progression_listing())
    _ -> Error("usage: jazz list scales|instruments|progressions")
  }
}

// --- Options -----------------------------------------------------------------

type Options {
  Options(positional: List(String), flags: List(#(String, String)))
}

/// Flags that stand on their own rather than taking a value.
fn is_switch(name: String) -> Bool {
  list.contains(["all-keys", "help", "backing"], name)
}

fn parse(args: List(String)) -> Result(Options, String) {
  parse_loop(args, Options([], []))
  |> result.map(fn(options) {
    Options(..options, positional: list.reverse(options.positional))
  })
}

fn parse_loop(args: List(String), acc: Options) -> Result(Options, String) {
  case args {
    [] -> Ok(acc)
    ["-f", ..rest] -> parse_loop(["--for", ..rest], acc)
    ["-k", ..rest] -> parse_loop(["--key", ..rest], acc)
    ["--" <> name, ..rest] ->
      case is_switch(name) {
        True -> parse_loop(rest, with_flag(acc, name, "yes"))
        False ->
          case rest {
            [value, ..more] -> parse_loop(more, with_flag(acc, name, value))
            [] -> Error("`--" <> name <> "` needs a value")
          }
      }
    [value, ..rest] ->
      parse_loop(rest, Options(..acc, positional: [value, ..acc.positional]))
  }
}

fn with_flag(options: Options, name: String, value: String) -> Options {
  Options(..options, flags: [#(name, value), ..options.flags])
}

fn flag(options: Options, name: String) -> Option(String) {
  case list.find(options.flags, fn(entry) { entry.0 == name }) {
    Ok(entry) -> Some(entry.1)
    Error(_) -> None
  }
}

pub type Format {
  Text
  Abc
  MusicXml
}

fn tempo_option(options: Options) -> Result(Int, String) {
  use beats <- result.try(number(options, "tempo", notation.default_tempo))
  case beats >= 20 && beats <= 400 {
    True -> Ok(beats)
    False -> Error("`--tempo` wants a sensible number of beats a minute")
  }
}

/// The chord view reads the same flag, from its own list of shapes.
fn arpeggio_option(options: Options) -> Result(Arpeggio, String) {
  case flag(options, "pattern") {
    None -> Ok(pattern.UpAndDown)
    Some(name) ->
      pattern.arpeggio_from_string(string.lowercase(string.trim(name)))
  }
}

fn pattern_option(options: Options) -> Result(Pattern, String) {
  case flag(options, "pattern") {
    None -> Ok(pattern.Straight)
    Some(name) -> pattern.from_string(string.lowercase(string.trim(name)))
  }
}

fn format_option(options: Options) -> Result(Format, String) {
  case flag(options, "format") {
    None -> Ok(Text)
    Some(name) ->
      case string.lowercase(string.trim(name)) {
        "text" | "plain" -> Ok(Text)
        "abc" -> Ok(Abc)
        "musicxml" | "xml" -> Ok(MusicXml)
        _ -> Error("unknown format `" <> name <> "`, try text, abc or musicxml")
      }
  }
}

fn instrument_option(options: Options) -> Result(Instrument, String) {
  named_instrument(flag(options, "for"))
}

fn named_instrument(name: Option(String)) -> Result(Instrument, String) {
  case name {
    Some(text) -> instrument.find(text)
    None -> Ok(instrument.concert())
  }
}

fn keys(start: PitchClass, order: Option(String)) -> List(PitchClass) {
  case order {
    Some("fifths") -> progression.cycle_of_fifths(start)
    Some("chromatic") -> progression.chromatic(start)
    _ -> progression.cycle_of_fourths(start)
  }
}

// --- Help --------------------------------------------------------------------

fn help() -> String {
  "jazz -- practice material for improvisers, transposed for your horn

USAGE
  jazz scale <root> <scale> [options]
  jazz chord <symbol> [options]
  jazz progression <name|changes|tune> [options]
  jazz lick <progression|changes|tune> [options]
  jazz analyse <progression|changes|tune> [options]
  jazz transpose <notes...> --from <instrument> --to <instrument>
  jazz list scales|instruments|progressions

OPTIONS
  --for, -f <instrument>   Write the part for this instrument (default: concert)
  --key, -k <key>          Concert key for a progression (default: C)
  --all-keys               Repeat through all twelve keys
  --pattern <pattern>      scales: straight (default), thirds, fourths,
                           triads, sevenths, digital; chords: up-and-down
                           (default), inversions, from-the-top, threes
  --level <level>          beginner (default), intermediate, or advanced
  --seed <n>               Pick a different line; the same seed always repeats
  --format <format>        text (default), abc, or musicxml
  --bars <n>               How long a generated tune should be (default: 16)
  --tempo <n>              Quarter notes a minute (default: 120)
  --backing                Write the piano part out on a staff of its own
  --cycle <order>          fourths (default), fifths, or chromatic

EXAMPLES
  jazz scale D dorian --for alto
  jazz scale C bebop-dominant --for tenor --all-keys
  jazz scale F dorian --for alto --pattern thirds
  jazz chord Bb7#9 --for tenor
  jazz chord Cmaj7 --for alto --pattern inversions --all-keys
  jazz progression ii-V-I --key F --for alto
  jazz progression blues --key Bb --for tenor
  jazz lick ii-V-I --key C --for alto --level intermediate
  jazz lick Dm7 G7 Cmaj7 --for tenor --seed 12
  jazz lick ii-V-I --key C --for alto --all-keys --format musicxml
  jazz lick \"|: Dm7 | G7 | Cmaj7 | Cmaj7 :|\" --for alto
  jazz scale C bebop-dominant --for tenor --format abc
  jazz lick blues --key Bb --for tenor --format abc > blues.abc
  jazz lick blues --key Bb --for tenor --backing --format musicxml > blues.musicxml
  jazz progression tune --bars 32 --key F --level advanced --seed 3
  jazz lick tune --bars 16 --for alto --level intermediate
  jazz analyse blues --key F
  jazz analyse Cmaj7 A7b9 Dm7 Db7 Cmaj7
  jazz transpose C E G --from concert --to alto

NOTES
  Everything is stored at concert pitch and transposed when it is printed, so
  --key always means the concert key, whatever horn you are holding.

  Changes are written as they are on a chart: bars separated by |, chords
  sharing a bar separated by spaces, % to hold the bar before, and |: :| for
  a repeat. With no bar lines, each chord gets a bar of its own.

  Chord symbols accept the usual dialects: Cm7, Cmi7, C-7, CM7, C^7, C\u{0394}7,
  C\u{00F8}, Cdim7, C7alt, C7b9#11, Cm(maj7), C6/9, Am7/D. Case matters in one
  place only: CM7 is major, Cm7 is minor."
}
