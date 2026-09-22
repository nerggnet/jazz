//// Chord progressions, built from a key rather than written out per key.
////
//// Each progression is defined in scale degrees, so asking for it in all
//// twelve keys is the same work as asking for it in one. That is the whole
//// point: the reason to own a tool like this is to practise something round
//// the cycle without copying it out by hand twelve times.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jazz/chord.{type Chord, DiminishedTriad, MinorTriad}
import jazz/internal/num
import jazz/interval
import jazz/pitch.{type PitchClass, Pitch}

/// One bar of four beats, holding one or two chords.
pub type Bar {
  Bar(chords: List(Chord))
}

pub type Progression {
  Progression(
    id: String,
    name: String,
    note: String,
    key: PitchClass,
    bars: List(Bar),
  )
}

// --- Chord shorthands --------------------------------------------------------

fn root(key: PitchClass, number: Int, alteration: Int) -> PitchClass {
  interval.transpose_class(key, interval.degree(number, alteration))
}

// --- The catalogue -----------------------------------------------------------

/// Everything `jazz progression` knows how to build, with a note on what it is
/// for.
pub fn catalogue() -> List(#(String, String)) {
  [
    #("ii-V-I", "The major two-five-one. Learn this one in all twelve keys."),
    #("minor-ii-V-i", "The minor two-five-one, with an altered dominant."),
    #("turnaround", "I VI ii V. Four bars that send you back to the top."),
    #("blues", "The twelve bar jazz blues, with the bar eight detour."),
    #("rhythm-changes-a", "The A section of rhythm changes."),
    #("coltrane", "Giant Steps bars one to four. Three keys, four bars."),
    #("backdoor", "The backdoor cadence: IV to bVII7 to I."),
    #("tritone-sub", "ii V I with the dominant swapped for its tritone."),
  ]
}

/// Build a named progression in a key.
pub fn build(id: String, key: PitchClass) -> Result(Progression, String) {
  case string.lowercase(string.trim(id)) {
    "ii-v-i" | "251" | "ii-v-i-major" -> Ok(two_five_one(key))
    "minor-ii-v-i" | "minor-251" | "ii-v-i-minor" -> Ok(minor_two_five_one(key))
    "turnaround" | "1-6-2-5" -> Ok(turnaround(key))
    "blues" -> Ok(blues(key))
    "rhythm-changes-a" | "rhythm" | "rhythm-changes" ->
      Ok(rhythm_changes_a(key))
    "coltrane" | "giant-steps" -> Ok(coltrane(key))
    "backdoor" -> Ok(backdoor(key))
    "tritone-sub" | "tritone" | "sub" -> Ok(tritone_sub(key))
    _ ->
      Error("unknown progression `" <> id <> "`, try `jazz list progressions`")
  }
}

pub fn two_five_one(key: PitchClass) -> Progression {
  Progression(
    id: "ii-V-I",
    name: "Major ii-V-I",
    note: "Aim for the third of each chord and let the sevenths fall a step.",
    key: key,
    bars: [
      Bar([chord.minor_seventh(root(key, 2, 0))]),
      Bar([chord.dominant(root(key, 5, 0))]),
      Bar([chord.major_seventh(key)]),
      Bar([chord.major_seventh(key)]),
    ],
  )
}

pub fn minor_two_five_one(key: PitchClass) -> Progression {
  Progression(
    id: "minor-ii-V-i",
    name: "Minor ii-V-i",
    note: "The altered dominant is melodic minor a semitone above its root.",
    key: key,
    bars: [
      Bar([chord.half_diminished(root(key, 2, 0))]),
      Bar([chord.altered(root(key, 5, 0))]),
      Bar([chord.minor_seventh(key)]),
      Bar([chord.minor_seventh(key)]),
    ],
  )
}

pub fn turnaround(key: PitchClass) -> Progression {
  Progression(
    id: "turnaround",
    name: "I VI ii V turnaround",
    note: "The last two bars of almost every standard.",
    key: key,
    bars: [
      Bar([chord.major_seventh(key)]),
      Bar([chord.dominant_flat_nine(root(key, 6, 0))]),
      Bar([chord.minor_seventh(root(key, 2, 0))]),
      Bar([chord.dominant(root(key, 5, 0))]),
    ],
  )
}

pub fn blues(key: PitchClass) -> Progression {
  Progression(
    id: "blues",
    name: "Twelve bar jazz blues",
    note: "Bars eight to ten are a two-five; the rest is the blues scale.",
    key: key,
    bars: [
      Bar([chord.dominant(key)]),
      Bar([chord.dominant(root(key, 4, 0))]),
      Bar([chord.dominant(key)]),
      Bar([chord.minor_seventh(root(key, 5, 0)), chord.dominant(key)]),
      Bar([chord.dominant(root(key, 4, 0))]),
      Bar([chord.diminished_seventh(root(key, 4, 1))]),
      Bar([chord.dominant(key)]),
      Bar([
        chord.minor_seventh(root(key, 3, 0)),
        chord.dominant(root(key, 6, 0)),
      ]),
      Bar([chord.minor_seventh(root(key, 2, 0))]),
      Bar([chord.dominant(root(key, 5, 0))]),
      Bar([chord.dominant(key), chord.dominant(root(key, 6, 0))]),
      Bar([
        chord.minor_seventh(root(key, 2, 0)),
        chord.dominant(root(key, 5, 0)),
      ]),
    ],
  )
}

pub fn rhythm_changes_a(key: PitchClass) -> Progression {
  Progression(
    id: "rhythm-changes-a",
    name: "Rhythm changes, A section",
    note: "Two chords a bar. Guide tones matter more than scales here.",
    key: key,
    bars: [
      Bar([chord.sixth(key), chord.dominant_flat_nine(root(key, 6, 0))]),
      Bar([
        chord.minor_seventh(root(key, 2, 0)),
        chord.dominant(root(key, 5, 0)),
      ]),
      Bar([
        chord.minor_seventh(root(key, 3, 0)),
        chord.dominant_flat_nine(root(key, 6, 0)),
      ]),
      Bar([
        chord.minor_seventh(root(key, 2, 0)),
        chord.dominant(root(key, 5, 0)),
      ]),
      Bar([chord.dominant(key)]),
      Bar([
        chord.dominant(root(key, 4, 0)),
        chord.diminished_seventh(root(key, 4, 1)),
      ]),
      Bar([chord.sixth(key), chord.dominant_flat_nine(root(key, 6, 0))]),
      Bar([
        chord.minor_seventh(root(key, 2, 0)),
        chord.dominant(root(key, 5, 0)),
      ]),
    ],
  )
}

pub fn coltrane(key: PitchClass) -> Progression {
  Progression(
    id: "coltrane",
    name: "Coltrane changes",
    note: "Three tonics a major third apart. Play the arpeggios before the scales.",
    key: key,
    bars: {
      // Each tonic is a major third below the last, and each dominant is the
      // five of wherever the tune is about to land.
      let second = root(key, 6, -1)
      let third = root(second, 6, -1)
      [
        Bar([chord.major_seventh(key), chord.dominant(root(second, 5, 0))]),
        Bar([chord.major_seventh(second), chord.dominant(root(third, 5, 0))]),
        Bar([chord.major_seventh(third)]),
        Bar([
          chord.minor_seventh(root(second, 2, 0)),
          chord.dominant(root(second, 5, 0)),
        ]),
      ]
    },
  )
}

pub fn backdoor(key: PitchClass) -> Progression {
  Progression(
    id: "backdoor",
    name: "Backdoor cadence",
    note: "bVII7 resolves to I through its own flat seventh. Use Lydian dominant.",
    key: key,
    bars: [
      Bar([chord.major_seventh(root(key, 4, 0))]),
      Bar([chord.minor_seventh(root(key, 4, 0))]),
      Bar([chord.dominant(root(key, 7, -1))]),
      Bar([chord.major_seventh(key)]),
    ],
  )
}

pub fn tritone_sub(key: PitchClass) -> Progression {
  Progression(
    id: "tritone-sub",
    name: "ii V I with a tritone substitute",
    note: "bII7 shares its third and seventh with V7, so one line covers both halves.",
    key: key,
    bars: [
      Bar([
        chord.minor_seventh(root(key, 2, 0)),
        chord.dominant(root(key, 5, 0)),
      ]),
      Bar([chord.major_seventh(key)]),
      Bar([
        chord.minor_seventh(root(key, 2, 0)),
        chord.dominant(root(key, 2, -1)),
      ]),
      Bar([chord.major_seventh(key)]),
    ],
  )
}

// --- Reading changes ---------------------------------------------------------

type Token {
  Word(String)
  BarLine
  RepeatStart
  RepeatEnd
}

/// Parse changes the way they are written on a chart.
///
/// Bars are separated by `|`, and chords sharing a bar share it evenly. `%`
/// holds the bar before it. Anything between `|:` and `:|` is played twice.
///
///     | Dm7 | G7 | Cmaj7 | Cmaj7 |
///     |: Cm7 F7 | Bbmaj7 | Am7b5 D7alt | Gm7 :|
///
/// With no bar lines at all, each chord gets a bar of its own, so a quick
/// `Dm7 G7 Cmaj7` still means what it looks like.
///
/// The key is taken from the last chord, because changes usually end where
/// they mean to.
pub fn parse(text: String) -> Result(Progression, String) {
  use tokens <- result.try(scan(text, []))
  use bars <- result.try(case list.any(tokens, is_bar_line) {
    True -> assemble(tokens, [], [], None)
    False -> one_chord_each(tokens, [])
  })
  case list.last(list.flat_map(bars, fn(one) { one.chords })) {
    Error(_) -> Error("no chords found")
    Ok(final) ->
      Ok(Progression(
        id: "typed",
        name: "Changes",
        note: "",
        key: final.root,
        bars: bars,
      ))
  }
}

fn is_bar_line(token: Token) -> Bool {
  case token {
    Word(_) -> False
    _ -> True
  }
}

fn one_chord_each(
  tokens: List(Token),
  bars: List(Bar),
) -> Result(List(Bar), String) {
  case tokens {
    [] -> Ok(bars)
    [Word(symbol), ..rest] ->
      case chord.parse(symbol) {
        Ok(one) -> one_chord_each(rest, list.append(bars, [Bar([one])]))
        Error(message) -> Error(message)
      }
    [_, ..rest] -> one_chord_each(rest, bars)
  }
}

// --- Scanning ---

fn scan(text: String, acc: List(Token)) -> Result(List(Token), String) {
  case string.pop_grapheme(text) {
    Error(_) -> Ok(list.reverse(acc))
    Ok(#(" ", rest))
    | Ok(#("\n", rest))
    | Ok(#("\t", rest))
    | Ok(#("\r", rest)) -> scan(rest, acc)
    Ok(#("|", rest)) ->
      case string.pop_grapheme(rest) {
        // `|:` opens a repeat; `||` and `|]` are just heavier bar lines.
        Ok(#(":", more)) -> scan(more, [RepeatStart, ..acc])
        Ok(#("|", more)) | Ok(#("]", more)) -> scan(more, [BarLine, ..acc])
        _ -> scan(rest, [BarLine, ..acc])
      }
    Ok(#(":", rest)) ->
      case string.pop_grapheme(rest) {
        Ok(#("|", more)) -> scan(more, [RepeatEnd, ..acc])
        _ ->
          Error("a `:` only means anything beside a bar line, as `|:` or `:|`")
      }
    Ok(_) -> {
      let #(word, rest) = take_word(text, "")
      scan(rest, [Word(word), ..acc])
    }
  }
}

fn take_word(text: String, acc: String) -> #(String, String) {
  case string.pop_grapheme(text) {
    Error(_) -> #(acc, "")
    Ok(#(" ", _))
    | Ok(#("\n", _))
    | Ok(#("\t", _))
    | Ok(#("\r", _))
    | Ok(#("|", _))
    | Ok(#(":", _)) -> #(acc, text)
    Ok(#(grapheme, rest)) -> take_word(rest, acc <> grapheme)
  }
}

// --- Assembling ---

fn assemble(
  tokens: List(Token),
  current: List(String),
  bars: List(Bar),
  repeat: Option(Int),
) -> Result(List(Bar), String) {
  case tokens {
    [] ->
      case repeat {
        Some(_) -> Error("a `|:` was opened and never closed with `:|`")
        None -> flush(current, bars)
      }
    [Word(symbol), ..rest] ->
      assemble(rest, list.append(current, [symbol]), bars, repeat)
    [BarLine, ..rest] -> {
      use done <- result.try(flush(current, bars))
      assemble(rest, [], done, repeat)
    }
    [RepeatStart, ..rest] ->
      case repeat {
        Some(_) -> Error("one repeat cannot sit inside another")
        None -> {
          use done <- result.try(flush(current, bars))
          assemble(rest, [], done, Some(list.length(done)))
        }
      }
    [RepeatEnd, ..rest] ->
      case repeat {
        None -> Error("found `:|` with no `|:` to go with it")
        Some(from) -> {
          use done <- result.try(flush(current, bars))
          assemble(rest, [], list.append(done, list.drop(done, from)), None)
        }
      }
  }
}

/// Close off a bar.
///
/// Nothing between two bar lines makes no bar at all, because a trailing `|`
/// and a double bar line look exactly like an empty bar and are far more
/// common. `%` is the way to say hold.
fn flush(current: List(String), bars: List(Bar)) -> Result(List(Bar), String) {
  let at = list.length(bars) + 1
  case current, list.last(bars) {
    [], _ -> Ok(bars)
    ["%"], Error(_) ->
      Error("bar 1: `%` repeats the bar before it, and there is none")
    ["%"], Ok(previous) -> Ok(list.append(bars, [previous]))
    words, _ ->
      case list.contains(words, "%") {
        True ->
          Error(
            "bar "
            <> int.to_string(at)
            <> ": `%` stands for a whole bar on its own",
          )
        False ->
          case list.try_map(words, chord.parse) {
            Ok(chords) -> Ok(list.append(bars, [Bar(chords)]))
            Error(message) ->
              Error("bar " <> int.to_string(at) <> ": " <> message)
          }
      }
  }
}

/// Split a bar between the chords sharing it, handing the odd eighth to the
/// earlier ones so that three chords in a bar still add up to a bar.
pub fn shares(count: Int, total: Int) -> List(Int) {
  case count <= 0 {
    True -> []
    False -> {
      let each = total / count
      let over = total % count
      num.counting(count)
      |> list.map(fn(at) {
        case at < over {
          True -> each + 1
          False -> each
        }
      })
    }
  }
}

// --- Views -------------------------------------------------------------------

/// Every chord in the progression, in order.
pub fn chords(progression: Progression) -> List(Chord) {
  list.flat_map(progression.bars, fn(bar) { bar.chords })
}

/// Move a whole progression to another key.
pub fn transpose(
  progression: Progression,
  by: interval.Interval,
) -> Progression {
  Progression(
    ..progression,
    key: interval.transpose_class(progression.key, by),
    bars: list.map(progression.bars, fn(bar) {
      Bar(list.map(bar.chords, chord.transpose(_, by)))
    }),
  )
}

/// The roman numeral for a chord in a key, such as `iim7`, `V7` or `bVII7`.
pub fn roman(key: PitchClass, of: Chord) -> String {
  let steps =
    num.modulo(
      pitch.diatonic_position(Pitch(of.root, 4))
        - pitch.diatonic_position(Pitch(key, 4)),
      7,
    )
  let semitones =
    num.modulo(
      pitch.to_midi(Pitch(of.root, 4)) - pitch.to_midi(Pitch(key, 4)),
      12,
    )
  let plain = interval.semitones(interval.degree(steps + 1, 0))
  let alteration = wrap_alteration(semitones - plain)
  let numeral = case of.triad {
    MinorTriad | DiminishedTriad -> string.lowercase(numeral_of(steps))
    _ -> numeral_of(steps)
  }
  pitch.accidental_to_string(alteration) <> numeral <> chord.quality_string(of)
}

fn wrap_alteration(alteration: Int) -> Int {
  case alteration > 6, alteration < -6 {
    True, _ -> alteration - 12
    _, True -> alteration + 12
    _, _ -> alteration
  }
}

fn numeral_of(steps: Int) -> String {
  case steps {
    0 -> "I"
    1 -> "II"
    2 -> "III"
    3 -> "IV"
    4 -> "V"
    5 -> "VI"
    _ -> "VII"
  }
}

// --- Keys --------------------------------------------------------------------

/// The twelve keys in the order jazz practises them: down a fifth each time,
/// respelled whenever the key signature would run away.
pub fn cycle_of_fourths(start: PitchClass) -> List(PitchClass) {
  let base = pitch.fifths(start)
  num.counting(12)
  |> list.map(fn(step) { pitch.simplify_key(pitch.from_fifths(base - step)) })
}

/// The same twelve keys, going the other way.
pub fn cycle_of_fifths(start: PitchClass) -> List(PitchClass) {
  let base = pitch.fifths(start)
  num.counting(12)
  |> list.map(fn(step) { pitch.simplify_key(pitch.from_fifths(base + step)) })
}

/// Twelve keys in chromatic order.
pub fn chromatic(start: PitchClass) -> List(PitchClass) {
  num.counting(12)
  |> list.map(fn(step) {
    pitch.simplify_key(interval.transpose_class(
      start,
      interval.degree(2, -1 + step),
    ))
  })
}
