# jazz

Practice material for improvisers, transposed for your horn.

Scales, chord symbols and chord progressions, generated from theory rather than
looked up in tables, and printed at concert pitch or written out for E-flat and
B-flat instruments.

```sh
gleam run -- scale D dorian --for alto
gleam run -- chord Bb7#9 --for tenor
gleam run -- progression blues --key Bb --for tenor
gleam run -- lick ii-V-I --key F --for alto --format abc
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

### Typing out changes

Both `lick` and `analyse` take changes written the way they are on a chart,
so a line can be generated over a whole tune rather than a four bar cell:

```sh
gleam run -- lick "|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|" --for alto
gleam run -- analyse "| Fmaj7 | Fm7 | Bb7 | Cmaj7 |"
```

Bars are separated by `|`, and chords sharing a bar share it evenly. `%` holds
the bar before it, and anything between `|:` and `:|` is played twice — so
those eight bars above become sixteen to play over. Newlines are just spaces,
which means a tune can be pasted in the shape it was written:

```
|: Cm7    | Fm7     | Cm7  | Cm7 :|
 | Abmaj7 | G7alt   | Cm7  | Am7b5 D7alt |
```

With no bar lines at all, each chord gets a bar of its own, so the short way
still means what it looks like:

```sh
gleam run -- lick Dm7 G7 Cmaj7 --for tenor --seed 12
```

There is no library of standards here, for the same reason there is no library
of licks: the changes to somebody's tune are theirs. What is here is the
notation for writing them down.

### Reading changes back

```
$ gleam run -- analyse Cmaj7 A7b9 Dm7 Db7 Cmaj7 --for tenor

  Cmaj7 A7b9 Dm7 Db7 Cmaj7  --  Tenor sax (Bb)

  Chords  What is going on

  3-5     Em7 Eb7 Dmaj7
          ii bII7 I in D
          Eb7 is standing in for the dominant a tritone away. Same third
          and seventh, swapped over, so the bass walks down by semitones.

  Guide tones. The seventh of one chord is the third of the next.

  Chord  Dmaj7  B7b9  Em7  Eb7  Dmaj7
  3rd    F#     D#    G    G    F#
  7th    C#     A     D    Db   C#

  Concert: Cmaj7 A7b9 Dm7 Db7 Cmaj7
```

`analyse` looks for the cells a player already knows how to handle: major and
minor two-fives, turnarounds, tritone substitutes, the backdoor cadence,
borrowed minor fourths, passing diminished chords, and Coltrane's major third
cycle. Recognising them is most of what separates reading a tune from playing
one, because a two-five is one idea to prepare rather than two unrelated chords
to react to. A cell sitting inside a longer one is left out, so a turnaround is
reported as a turnaround and not also as the two-five inside it.

Matching is by sound, not by spelling, because the next chart will write `C#7`
where the last one wrote `Db7`.

The guide tone table underneath is the harmony in two voices. Read across the
`7th` row and then the `3rd` row of the next chord: they are a semitone apart,
which is why a two-five sounds like one idea. In the example above the tritone
substitute gives the game away, with `Eb7` holding the same two notes as the
`A7` it replaced, upside down.

### Printed notation

Any command that produces notes takes `--format abc`:

```
$ gleam run -- lick ii-V-I --key Bb --for alto --level advanced --seed 3 --format abc

X:1
T:Major ii-V-I in Bb
T:Alto sax (Eb)
M:4/4
L:1/8
K:G
"Am7"cBAF BA^EG | "D7"FEDC B,CC^C | "Gmaj7"DEFG ABE^C | "Gmaj7"DFGB dfgf |]
```

That is a complete tune: paste it into any ABC renderer, or pipe it to
`abcm2ps` for a PDF. `abcjs` will both draw it and play it back, which is the
reason ABC came first — it is the format you can check by reading, and the one
that will carry a web front end later.

`--all-keys` produces a numbered tune book rather than twelve separate files,
so a whole cycle prints as one document.

Two things happen on the way out, and both belong to notation rather than to
either format:

**The key signature is chosen, not asked for.** Whichever one leaves the fewest
accidentals on the page wins. D Dorian gets no sharps or flats, the altered
scale gets five flats and needs a single accidental, and a chord chart simply
keeps its own key.

**Accidentals follow the real rule.** One lasts to the end of its bar at its
own octave, so the part reads like a part:

```
$ gleam run -- scale C blues --format abc
...
CEF^F GBcB | G^F=FE C2 |]
```

The F sharp is cancelled before the F natural that follows it in the same bar,
and written again in the next one. Nothing else is printed, because the two
flats in the signature have already said the rest.

`jazz/notation` holds the score — bars, durations, beams, key signature, chord
symbols — and knows nothing about any file format. `jazz/render/abc` only
spells what it is handed: it decides no accidentals, chooses no key, and groups
no beams. A MusicXML backend is a second module over the same scores.

## The web interface

Live at <https://nerggnet.github.io/jazz/>, rebuilt from `master` on every push.

To run it locally:

```sh
gleam run -m lustre/dev build jazz_web --no-html --outdir=dist
cp web/index.html web/styles.css dist/
python3 -m http.server 8137 --directory dist
```

Then open <http://127.0.0.1:8137>. Five views over the same theory — scales,
chords, changes, generated lines, analysis — each showing engraved notation
above the text the command line prints, for whichever horn is selected. The
notation is drawn by [abcjs](https://www.abcjs.net/) from the same ABC the CLI
emits, and the **Play** button plays it back, which is the thing a terminal
cannot do and the reason the browser was worth the trouble.

The model, the update and every decision about what to show live in
`jazz/session`, which is pure and tested on both compilation targets. What is
in `jazz_web` is elements and the bridge to abcjs; there is no music theory in
the view layer at all.

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
| `jazz/progression` | Progressions built from degrees, and changes read off a chart |
| `jazz/lick` | Line generation: targets, approaches and connective devices |
| `jazz/analysis` | Finding two-fives, substitutes and guide tone lines in changes |
| `jazz/notation` | Scores: bars, beams, key signatures, which accidentals print |
| `jazz/render/text` | Terminal output |
| `jazz/render/abc` | ABC notation output |
| `jazz/session` | The state an interactive front end holds, and what to show |
| `jazz_web` | The Lustre web interface, and the bridge to abcjs |
| `jazz/cli` | Argument handling |

## Development

```sh
gleam run    # Run the CLI
gleam test   # Run the tests
gleam test --target javascript

# The web interface, served from dist/
gleam run -m lustre/dev build jazz_web --no-html --outdir=dist
cp web/index.html web/styles.css dist/
```
