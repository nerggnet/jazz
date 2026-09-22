# jazz

Practice material for improvisers, transposed for your horn.

Scales, chord symbols and chord progressions, generated from theory rather than
looked up in tables, and printed at concert pitch or written out for E-flat and
B-flat instruments.

```sh
gleam run -- scale D dorian --for alto
gleam run -- chord Bb7#9 --for tenor
gleam run -- progression blues --key Bb --for tenor
```

## What it does

### Scales

```
$ gleam run -- scale D dorian --for alto

  B Dorian  (concert D)  --  Alto sax (Eb)

  Written  B  C#  D   E  F#  G#  A
  Concert  D  E   F   G  A   B   C
  Degree   1  2   b3  4  5   6   b7

  The default minor sound. Over im7 and iim7.
```

Add `--all-keys` to walk the same scale round the cycle of fourths, which is
the order everyone actually practises in. `--cycle fifths` and
`--cycle chromatic` go the other ways.

### Chords

```
$ gleam run -- chord Bb7#9 --for tenor

  C7#9  (concert Bb7#9)  --  Tenor sax (Bb)

  Written  C   E  G  Bb  D#
  Concert  Bb  D  F  Ab  C#
  Degree   1   3  5  b7  #9

  Guide tones  E  Bb

  Scales that fit, best first:
    C Diminished (half-whole)
    C Altered (super Locrian)
    C Phrygian dominant
```

Chord symbols accept the dialects people actually write: `Cm7`, `Cmi7`, `C-7`,
`CM7`, `C^7`, `CΔ7`, `Cø`, `Cdim7`, `C7alt`, `C7b9#11`, `Cm(maj7)`, `C6/9`,
`Am7/D`. Case matters in exactly one place, and it is the place you already
know: `CM7` is major, `Cm7` is minor.

### Progressions

```
$ gleam run -- progression blues --key Bb --for tenor

  Twelve bar jazz blues in C  (concert Bb)  --  Tenor sax (Bb)

  | C7         | F7         | C7         | Gm7  C7    |
    I7           IV7          I7           vm7  I7

  | F7         | F#dim7     | C7         | Em7  A7    |
    IV7          #ivdim7      I7           iiim7  VI7

  | Dm7        | G7         | C7  A7     | Dm7  G7    |
    iim7         V7           I7  VI7      iim7  V7

  Bars eight to ten are a two-five; the rest is the blues scale.

  Concert: Bb7 | Eb7 | Bb7 | Fm7 Bb7 | Eb7 | Edim7 | Bb7 | Dm7 G7 | Cm7 | F7 | Bb7 G7 | Cm7 F7
```

`--key` is always the **concert** key, whatever horn you are holding. Ask for
the blues in B-flat and you get the blues in B-flat, written out in C for the
tenor player.

`jazz list scales`, `jazz list instruments` and `jazz list progressions` show
what is available.

### Lines

```
$ gleam run -- lick ii-V-I --key F --for alto --level intermediate --seed 4

  Major ii-V-I in F  --  Alto sax (Eb)

  Bar  Chord  Line                     Target  How it is built
  1    Em7    G  A  B  D  A  B  A  F#  b3      1235 pattern, enclosure above then below
  2    A7     G  E  C# E  G  A  C# E   b7      arpeggio
  3    Dmaj7  F# G  A  C# G  A  B  D   3       1235 pattern
  4    Dmaj7  F# A  C# D  F# A  F# D   3       arpeggio

  Concert: Gm7 C7 Fmaj7 Fmaj7
  Written range C#4 to A5.  Same line again with --seed 4.
```

There is no library of transcribed licks here, on purpose. Stored licks belong
to whoever played them, and learning them one at a time teaches the phrases
rather than the language. What is encoded instead is the grammar that produces
them: land on a chord tone on the strong beat, usually the third or the
seventh; arrive at it by step, by chromatic approach, or by enclosure; fill the
space between with scale motion, an arpeggio, or a digital pattern. The last
column says which of those happened, so the line can be taken apart rather than
only played.

`--level` decides how much vocabulary is in play: beginners get plain
arpeggios and scale runs into their targets, advanced lines get enclosures,
double chromatics and the 1235 pattern. `--seed` makes any line reproducible,
on either compilation target. Lines are generated inside the middle two octaves
of whichever horn is chosen, so what comes out is playable.

Changes can also be given directly:

```sh
gleam run -- lick Dm7 G7 Cmaj7 --for tenor --seed 12
gleam run -- lick "Cm7b5" "F7alt" "Bbm6" --for alto --level advanced
```

## Why it is built this way

**Pitches keep their spelling.** A pitch is a letter name plus an alteration,
never a number from 0 to 11. That sounds pedantic until you transpose: concert
F-sharp major for alto is *literally* D-sharp major, and a library that stores
semitones cannot tell you whether to write `D#` or `Eb`. This one can, and it
knows that nine sharps is not a key signature anybody wants to read:

```
$ gleam run -- scale F# lydian --for alto

  Eb Lydian  (concert F#)  --  Alto sax (Eb)

  Written  Eb  F   G   A   Bb  C   D
  Concert  F#  G#  A#  B#  C#  D#  E#
  Degree   1   2   3   #4  5   6   7
```

The concert row is spelled correctly for F-sharp Lydian, sharps and all. The
written part is respelled once, as a whole, so a part never ends up mixing
`Bbm7` with `D#7`.

**Everything is stored at concert pitch.** Transposition happens in the
renderer and nowhere else, so no calculation in the middle of the library can
mix up a concert chart with an alto part.

**Scales and chords are formulas, not tables.** A scale is a list of degrees
(`1 2 b3 4 5 6 b7`) and the spelling of every note falls out of interval
arithmetic. There is no hand-written table of note names for any scale in any
key, which is why adding a scale is three lines and why none of them can be
wrong in only one key.

**The core is pure and target-agnostic.** No I/O, no platform dependencies, so
it compiles to both Erlang and JavaScript. Text output is one renderer sitting
at the edge; MusicXML, MIDI and a browser front end would sit beside it and
share everything behind.

## Layout

| Module | What lives there |
| --- | --- |
| `jazz/pitch` | Letters, alterations, octaves, the line of fifths, respelling |
| `jazz/interval` | Intervals, and spelling-correct transposition |
| `jazz/instrument` | Transposing instruments, their ranges, concert vs written |
| `jazz/scale` | Scale formulas, names, and what each one is for |
| `jazz/chord` | Chord symbols in and out, chord-scale suggestions |
| `jazz/progression` | Progressions built from degrees, roman numerals, key cycles |
| `jazz/lick` | Line generation: targets, approaches and connective devices |
| `jazz/render/text` | Terminal output |
| `jazz/cli` | Argument handling |

## Development

```sh
gleam run    # Run the CLI
gleam test   # Run the tests
gleam test --target javascript
```
