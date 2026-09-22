//// Making up changes.
////
//// Random chords would be useless. What makes a set of changes sound like
//// jazz is that it is built out of a small number of cells that hand on to
//// each other, and `jazz/analysis` already knows what those cells are,
//// because it spends its life finding them. This module is that same grammar
//// run backwards: two-fives, turnarounds, substitutions and modulations,
//// chained so the end of one is the start of the next.
////
//// Which means everything that comes out is idiomatic by construction rather
//// than by luck, and that the analyser can be pointed at the result to say
//// what went into it.

import gleam/int
import gleam/list
import jazz/chord.{type Chord}
import jazz/internal/random.{type Random}
import jazz/interval
import jazz/lick.{type Level}
import jazz/pitch.{type PitchClass}
import jazz/progression.{type Bar, type Progression, Bar, Progression}

/// Where the changes are standing, and whether it is a minor place.
type Key {
  Key(root: PitchClass, minor: Bool)
}

/// A few bars that go somewhere. Every one of these is something the analyser
/// can name.
type Cell {
  /// ii V I, over four bars.
  Cadence
  /// The same thing said in two.
  ShortCadence
  /// I VI ii V.
  Turnaround
  /// Staying put, which a tune needs as much as it needs movement.
  Sit
  /// ii bII7 I: the dominant swapped for its tritone.
  Tritone
  /// iv bVII7 I, borrowed from the parallel minor.
  Backdoor
  /// A diminished chord climbing between the tonic and the two.
  Passing
  /// A two five that lands somewhere else: the modulation.
  ToFourth
  ToRelativeMinor
  /// And the way back out of a minor key.
  ToRelativeMajor
}

// --- The cells ---------------------------------------------------------------

fn span(cell: Cell) -> Int {
  case cell {
    Cadence -> 4
    ShortCadence -> 2
    Turnaround -> 2
    Sit -> 2
    Tritone -> 3
    Backdoor -> 3
    Passing -> 2
    ToFourth -> 2
    ToRelativeMinor -> 2
    ToRelativeMajor -> 2
  }
}

/// Minor keys get the cells that know what to do in one.
fn fits(cell: Cell, key: Key) -> Bool {
  case key.minor {
    True ->
      case cell {
        Cadence | ShortCadence | Sit | ToRelativeMajor -> True
        _ -> False
      }
    False ->
      case cell {
        ToRelativeMajor -> False
        _ -> True
      }
  }
}

fn vocabulary(level: Level) -> List(Cell) {
  case level {
    lick.Beginner -> [Cadence, Cadence, ShortCadence, Turnaround, Sit]
    lick.Intermediate -> [
      Cadence,
      ShortCadence,
      ShortCadence,
      Turnaround,
      Sit,
      Passing,
      ToFourth,
      ToRelativeMinor,
      ToRelativeMajor,
    ]
    lick.Advanced -> [
      Cadence,
      ShortCadence,
      Turnaround,
      Tritone,
      Backdoor,
      Passing,
      ToFourth,
      ToFourth,
      ToRelativeMinor,
      ToRelativeMajor,
    ]
  }
}

/// The bars a cell makes, and where it leaves the changes standing.
fn shape(cell: Cell, key: Key) -> #(List(Bar), Key) {
  case cell {
    Cadence -> #(
      [Bar([two(key)]), Bar([five(key)]), Bar([tonic(key)]), Bar([tonic(key)])],
      key,
    )
    ShortCadence -> #([Bar([two(key), five(key)]), Bar([tonic(key)])], key)
    Turnaround -> #(
      [
        Bar([tonic(key), chord.dominant_flat_nine(at(key, 6, 0))]),
        Bar([
          chord.minor_seventh(at(key, 2, 0)),
          chord.dominant(at(key, 5, 0)),
        ]),
      ],
      key,
    )
    Sit -> #([Bar([tonic(key)]), Bar([tonic(key)])], key)
    Tritone -> #(
      [
        Bar([chord.minor_seventh(at(key, 2, 0))]),
        Bar([chord.dominant(at(key, 2, -1))]),
        Bar([tonic(key)]),
      ],
      key,
    )
    Backdoor -> #(
      [
        Bar([chord.minor_seventh(at(key, 4, 0))]),
        Bar([chord.dominant(at(key, 7, -1))]),
        Bar([tonic(key)]),
      ],
      key,
    )
    Passing -> #(
      [
        Bar([tonic(key)]),
        Bar([
          chord.diminished_seventh(at(key, 1, 1)),
          chord.minor_seventh(at(key, 2, 0)),
        ]),
      ],
      key,
    )
    ToFourth -> arriving(Key(at(key, 4, 0), False))
    ToRelativeMinor -> arriving(Key(at(key, 6, 0), True))
    ToRelativeMajor -> arriving(Key(at(key, 3, 0), False))
  }
}

/// A two five that hands the changes to somewhere new without resolving, so
/// whatever comes next lands on it.
fn arriving(destination: Key) -> #(List(Bar), Key) {
  #([Bar([two(destination)]), Bar([five(destination)])], destination)
}

fn at(key: Key, number: Int, alteration: Int) -> PitchClass {
  interval.transpose_class(key.root, interval.degree(number, alteration))
}

fn tonic(key: Key) -> Chord {
  case key.minor {
    True -> chord.minor_seventh(key.root)
    False -> chord.major_seventh(key.root)
  }
}

fn two(key: Key) -> Chord {
  case key.minor {
    True -> chord.half_diminished(at(key, 2, 0))
    False -> chord.minor_seventh(at(key, 2, 0))
  }
}

fn five(key: Key) -> Chord {
  case key.minor {
    True -> chord.altered(at(key, 5, 0))
    False -> chord.dominant(at(key, 5, 0))
  }
}

// --- Putting a tune together -------------------------------------------------

/// Changes of a given length, in a given key, reproducible from the seed.
pub fn generate(
  bars: Int,
  key: PitchClass,
  level: Level,
  seed: Int,
) -> Progression {
  let generator = random.new(int.max(1, seed))
  let home = Key(key, False)
  let wanted = int.max(2, bars)

  let #(made, form) = case wanted >= 32 && wanted % 4 == 0 {
    True -> {
      let #(all, _) = aaba(wanted, home, level, generator)
      #(all, "AABA")
    }
    False -> {
      let #(all, _) = stretch(wanted, home, home, level, generator, [])
      #(all, "straight through")
    }
  }

  Progression(
    id: "generated",
    name: "Tune",
    note: int.to_string(list.length(made))
      <> " bars, "
      <> form
      <> ". Point the Analyse view at it to see what went in.",
    key: key,
    bars: made,
  )
}

/// Thirty two bars where the first eight come round three times, because a
/// form needs something to come back to for the same reason a line does.
fn aaba(
  bars: Int,
  home: Key,
  level: Level,
  generator: Random,
) -> #(List(Bar), Random) {
  let section = bars / 4
  let #(first, generator) = stretch(section, home, home, level, generator, [])
  let #(middle, generator) = bridge(section, home, level, generator)
  #(list.flatten([first, first, middle, first]), generator)
}

/// The bridge goes somewhere else and hands back a two five, so the last A
/// has something to arrive from.
fn bridge(
  section: Int,
  home: Key,
  level: Level,
  generator: Random,
) -> #(List(Bar), Random) {
  let away = Key(at(home, 4, 0), False)
  let #(body, generator) =
    stretch(int.max(2, section - 2), away, away, level, generator, [])
  #(
    list.append(body, [
      Bar([chord.minor_seventh(at(home, 2, 0))]),
      Bar([chord.dominant(at(home, 5, 0))]),
    ]),
    generator,
  )
}

/// Fill a stretch of bars with cells, keeping back enough room to come home.
fn stretch(
  room: Int,
  from: Key,
  home: Key,
  level: Level,
  generator: Random,
  acc: List(Bar),
) -> #(List(Bar), Random) {
  case room >= 6 {
    False -> #(list.append(acc, landing(home, room)), generator)
    True -> {
      let choices =
        list.filter(vocabulary(level), fn(cell) {
          fits(cell, from) && span(cell) <= room - 4
        })
      case choices {
        [] -> #(list.append(acc, landing(home, room)), generator)
        _ -> {
          let #(cell, generator) = random.pick(generator, choices, Sit)
          let #(bars, next) = shape(cell, from)
          stretch(
            room - span(cell),
            next,
            home,
            level,
            generator,
            list.append(acc, bars),
          )
        }
      }
    }
  }
}

/// However far the changes wandered, a tune comes home.
fn landing(home: Key, room: Int) -> List(Bar) {
  case room {
    room if room <= 0 -> []
    1 -> [Bar([tonic(home)])]
    2 -> [Bar([two(home), five(home)]), Bar([tonic(home)])]
    3 -> [Bar([two(home)]), Bar([five(home)]), Bar([tonic(home)])]
    4 -> [
      Bar([two(home)]),
      Bar([five(home)]),
      Bar([tonic(home)]),
      Bar([tonic(home)]),
    ]
    room -> [Bar([tonic(home)]), ..landing(home, room - 1)]
  }
}
