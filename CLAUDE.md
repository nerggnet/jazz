# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The README explains what the tool does, why it is built the way it is, and
which module holds what. Read it first. This file covers what is not obvious
from reading one file at a time.

## Commands

```sh
gleam run -- <command>          # the CLI: scale, chord, progression, lick, analyse, transpose, list
gleam test                      # Erlang target
gleam test --target javascript  # and the JavaScript one, which is not optional
gleam format src test
gleam build

# The web interface, served from dist/
gleam run -m lustre/dev build jazz_web --no-html --outdir=dist
cp web/index.html web/styles.css dist/
python3 -m http.server 8137 --directory dist
```

gleeunit runs the whole suite and ignores arguments, so there is no way to run
a single test. The suite is about two seconds; run all of it.

## Both targets, always

Everything under `src/jazz/` is pure and compiles to Erlang and JavaScript. A
change that passes `gleam test` and fails `gleam test --target javascript` is a
broken change. Nothing in the core may do I/O or reach for a platform.

`@external` is only for the web front end, and every external function needs a
Gleam body as well or the module stops compiling for Erlang — see the bottom of
`src/jazz_web.gleam` for the pattern.

## Invariants worth knowing before changing anything

**A pitch is a letter plus an alteration, never a number from 0 to 11.** The
whole library depends on this: `D#` and `Eb` are different notes here, and
transposition is interval arithmetic, not addition. `pitch.to_midi` exists for
comparisons and ranges; nothing should ever build a pitch from one.

**Everything is stored at concert pitch.** Transposition happens in the
renderers and in `notation`, at the edge, and nowhere else.

**Generation is deterministic from a seed**, on both targets, via the Lehmer
generator in `jazz/internal/random`. The same seed must give the same line
forever, so:

- do not add randomness that is not drawn from the passed generator;
- do not draw from the generator on a branch that cannot happen (a zero-percent
  chance still advances it and shifts every draw after it);
- use the high bits — `random.pick` and friends already do.

**`jazz/notation` decides, renderers spell.** Key signatures, which accidentals
print, beaming, how bars are filled: all of it happens once in `notation`.
`render/abc` and `render/musicxml` only write down what they are handed. Adding
a third renderer should need no changes behind it.

## The notation IR

Enough of it is unusual that a change can look right and be wrong.

- **Durations are counted in eighths**, eight to a bar of 4/4.
- **`duration_of` is the written length; `sounding` is the room it takes.**
  They differ inside a tuplet, where three eighths last two. Anything that has
  to add up to a bar wants `sounding`.
- **A tuplet is a mark in the flat event list**, not a box round the notes:
  `Tuplet(count, into, ...)` followed by `count` events. Every pass moves a
  group as one unit — a bar line may never fall inside one — which is what the
  private `step` function is for.
- **A slur is a pair of edges** on `Note.phrasing`, not a span, for the same
  reason: both notations write it that way and it survives a note moving bar.
- **`Measure.key` is a key change part way through a score**, used by the
  round-the-keys exercises. `apply_accidentals` follows it along.
- Articulation is decided in `jazz/lick` (it is idiom, not engraving) and
  handed to `notation` one mark per note.

## abcjs, which is full of traps

The browser front end drives abcjs through `src/jazz_web_ffi.mjs`. These were
all found the hard way:

- **`voicesOff` does nothing in the synth.** It is only read by the MIDI *file*
  writer. Muting a part means dropping its track from `synth.flattened.tracks`
  between `init` and `prime`. `chordsOff` does work in the synth.
- **Verify audio options against the synth, not `getMidiFile`** — they are
  different renderers, and an option can work in one and be ignored by the
  other.
- **The tempo goes in the score** as `Q:`, never as a `millisecondsPerMeasure`
  override. Giving the synth one number and the playhead another is how they
  come apart.
- **abcjs fetches one mp3 per note per instrument**, on demand, from a
  soundfont on the web. That is why the sounds are pre-fetched; see `warm` and
  `prefetch` in the FFI.
- Swing and the count-in are playback instructions, not notation. The chart
  says straight eighths and "Swing"; the off-beats are moved on the way to the
  synth, and the playhead is moved by the same amount.

## How changes are checked here

Claims about output are verified rather than asserted, and it is worth keeping
that up:

- ABC is run through abcjs (there is a scratch setup with `jsdom` and `abcjs`
  in the session scratchpad) to confirm it parses with no warnings and that
  bars, slurs and tuplets come out as intended.
- MusicXML is parsed back to check every measure adds up, every tuplet and slur
  closes, and each note's children are in the order the DTD demands.
- Musical properties are measured rather than eyeballed: what proportion of a
  line is slurred, how much silence a comp leaves, how often a figure repeats.
  Several tests assert on those proportions.

## The web front end

`jazz/session` holds the model and every decision about what to show. It is
pure, compiles to both targets, and is tested. `jazz_web` is elements and the
bridge to abcjs; there is no music theory in it, and none should be added.
