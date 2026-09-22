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
import jazz/pitch.{type PitchClass}
import jazz/progression
import jazz/render/text
import jazz/scale

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
  case options.positional {
    [root_text, kind_text] -> {
      use root <- result.try(pitch.parse_class(root_text))
      use kind <- result.try(scale.kind_from_string(kind_text))
      case flag(options, "all-keys") {
        Some(_) ->
          Ok(
            keys(root, flag(options, "cycle"))
            |> list.map(fn(key) {
              text.scale_view(scale.Scale(key, kind), player)
            })
            |> string.join("\n\n"),
          )
        None -> Ok(text.scale_view(scale.Scale(root, kind), player))
      }
    }
    _ -> Error("usage: jazz scale <root> <scale> [--for <instrument>]")
  }
}

fn chord_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  case options.positional {
    [symbol] -> {
      use parsed <- result.try(chord.parse(symbol))
      Ok(text.chord_view(parsed, player))
    }
    _ -> Error("usage: jazz chord <symbol> [--for <instrument>]")
  }
}

fn progression_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use key <- result.try(case flag(options, "key") {
    Some(text) -> pitch.parse_class(text)
    None -> Ok(pitch.natural(pitch.C))
  })
  case options.positional {
    [name] ->
      case flag(options, "all-keys") {
        Some(_) ->
          keys(key, flag(options, "cycle"))
          |> list.try_map(fn(each) { progression.build(name, each) })
          |> result.map(fn(built) {
            built
            |> list.map(text.progression_view(_, player))
            |> string.join("\n\n")
          })
        None ->
          progression.build(name, key)
          |> result.map(text.progression_view(_, player))
      }
    _ ->
      Error(
        "usage: jazz progression <name> [--key <key>] [--for <instrument>] [--all-keys]",
      )
  }
}

fn lick_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use level <- result.try(case flag(options, "level") {
    Some(text) -> lick.level_from_string(text)
    None -> Ok(lick.Beginner)
  })
  use seed <- result.try(case flag(options, "seed") {
    Some(text) ->
      int.parse(text)
      |> result.replace_error(
        "`--seed` wants a whole number, not `" <> text <> "`",
      )
    None -> Ok(1)
  })
  use requested <- result.try(case flag(options, "key") {
    Some(text) -> result.map(pitch.parse_class(text), Some)
    None -> Ok(None)
  })

  let #(low, high) = instrument.comfortable_range(player)
  let settings = lick.Options(level, seed, low, high)
  let key = option.unwrap(requested, pitch.natural(pitch.C))

  case options.positional {
    [] ->
      Error(
        "usage: jazz lick <progression|chords...> [--key <key>] [--level <level>] [--seed <n>]",
      )
    [single] ->
      case progression.build(single, key) {
        Ok(built) ->
          Ok(text.lick_view(
            lick.over_progression(built, settings),
            built.name <> " in " <> pitch.class_to_string(built.key),
            player,
            built.key,
          ))
        Error(unknown) ->
          case chord.parse(single) {
            Ok(_) -> custom_lick([single], requested, settings, player)
            Error(_) -> Error(unknown)
          }
      }
    many -> custom_lick(many, requested, settings, player)
  }
}

/// A line over whatever changes were typed on the command line, a bar each.
fn custom_lick(
  symbols: List(String),
  requested: Option(PitchClass),
  settings: lick.Options,
  player: Instrument,
) -> Result(String, String) {
  use chords <- result.try(list.try_map(symbols, chord.parse))
  // Without a key given, assume the changes end where they mean to.
  let key = case requested, list.last(chords) {
    Some(given), _ -> given
    None, Ok(final) -> final.root
    None, Error(_) -> pitch.natural(pitch.C)
  }
  let line =
    lick.over_chords(list.map(chords, fn(one) { #(one, lick.bar) }), settings)
  Ok(text.lick_view(line, string.join(symbols, " "), player, key))
}

fn analysis_command(args: List(String)) -> Result(String, String) {
  use options <- result.try(parse(args))
  use player <- result.try(instrument_option(options))
  use requested <- result.try(case flag(options, "key") {
    Some(text) -> result.map(pitch.parse_class(text), Some)
    None -> Ok(None)
  })
  let key = option.unwrap(requested, pitch.natural(pitch.C))

  case options.positional {
    [] ->
      Error(
        "usage: jazz analyse <progression|chords...> [--key <key>] [--for <instrument>]",
      )
    [single] ->
      case progression.build(single, key) {
        Ok(built) ->
          Ok(text.analysis_view(
            progression.chords(built),
            built.name <> " in " <> pitch.class_to_string(built.key),
            player,
            built.key,
          ))
        Error(unknown) ->
          case chord.parse(single) {
            Ok(_) -> custom_analysis([single], requested, player)
            Error(_) -> Error(unknown)
          }
      }
    many -> custom_analysis(many, requested, player)
  }
}

fn custom_analysis(
  symbols: List(String),
  requested: Option(PitchClass),
  player: Instrument,
) -> Result(String, String) {
  use chords <- result.try(list.try_map(symbols, chord.parse))
  let key = case requested, list.last(chords) {
    Some(given), _ -> given
    None, Ok(final) -> final.root
    None, Error(_) -> pitch.natural(pitch.C)
  }
  Ok(text.analysis_view(chords, string.join(symbols, " "), player, key))
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
  list.contains(["all-keys", "help"], name)
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
  jazz progression <name> [options]
  jazz lick <progression|chords...> [options]
  jazz analyse <progression|chords...> [options]
  jazz transpose <notes...> --from <instrument> --to <instrument>
  jazz list scales|instruments|progressions

OPTIONS
  --for, -f <instrument>   Write the part for this instrument (default: concert)
  --key, -k <key>          Concert key for a progression (default: C)
  --all-keys               Repeat through all twelve keys
  --level <level>          beginner (default), intermediate, or advanced
  --seed <n>               Pick a different line; the same seed always repeats
  --cycle <order>          fourths (default), fifths, or chromatic

EXAMPLES
  jazz scale D dorian --for alto
  jazz scale C bebop-dominant --for tenor --all-keys
  jazz chord Bb7#9 --for tenor
  jazz progression ii-V-I --key F --for alto
  jazz progression blues --key Bb --for tenor
  jazz lick ii-V-I --key C --for alto --level intermediate
  jazz lick Dm7 G7 Cmaj7 --for tenor --seed 12
  jazz analyse blues --key F
  jazz analyse Cmaj7 A7b9 Dm7 Db7 Cmaj7
  jazz transpose C E G --from concert --to alto

NOTES
  Everything is stored at concert pitch and transposed when it is printed, so
  --key always means the concert key, whatever horn you are holding.

  Chord symbols accept the usual dialects: Cm7, Cmi7, C-7, CM7, C^7, C\u{0394}7,
  C\u{00F8}, Cdim7, C7alt, C7b9#11, Cm(maj7), C6/9, Am7/D. Case matters in one
  place only: CM7 is major, Cm7 is minor."
}
