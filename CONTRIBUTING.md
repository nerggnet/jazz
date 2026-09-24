# Contributing

Thanks for looking. This is a small project with strong opinions about how it
is put together; most of them are explained under **Why it is built this way**
in the [README](README.md), and the rest are in [CLAUDE.md](CLAUDE.md), which
is written for an assistant but is the honest description of the conventions.

## Getting set up

You need [Gleam](https://gleam.run/getting-started/installing/) 1.18 or later
and an Erlang/OTP install. Node is needed for the JavaScript target and the web
interface.

```sh
gleam deps download
gleam test
gleam test --target javascript
gleam run -- lick ii-V-I --key F --for alto
```

## Before opening a pull request

```sh
gleam format src test
gleam test
gleam test --target javascript
```

Both targets have to pass. The core library is pure and compiles to Erlang and
JavaScript, so a change that only works on one is not finished. Formatting is
`gleam format`, and CI checks all of this on every push.

## What a good change looks like

**Add a test that would have failed before.** Every musical rule in here is
pinned by a test that says what the rule is, often across the whole catalogue
of progressions and all twelve keys. Tests are named for the claim they make,
not for the function they call.

**Measure musical claims instead of asserting them.** If a change is supposed
to make lines breathe more, or leave the comp more air, or keep a figure's
shape when it repeats, count it over a few hundred bars and assert on the
proportion. Several existing tests do exactly this, and they have caught real
problems that eyeballing one example did not.

**Check output against something that reads it.** ABC goes through abcjs;
MusicXML gets parsed back to confirm the bars add up, the tuplets and slurs
close, and the elements are in the order the format demands. A file that looks
right and is rejected by a notation program is not right.

**Keep the layers apart.** Theory modules work at concert pitch and know
nothing about file formats. `jazz/notation` decides key signatures, accidentals
and beams. Renderers only spell what they are given. The web front end holds no
music theory at all — that lives in `jazz/session`, which is pure and tested.

**Pitches keep their spelling.** A note is a letter plus an alteration, never a
number from 0 to 11, because that is the only way transposition can tell you
whether to write `D#` or `Eb`. Anything that turns a pitch into a semitone
count and back has lost information.

**Generation stays deterministic.** The same seed gives the same line, on both
targets, forever. Randomness comes from the passed generator and nowhere else.

## Adding to the musical vocabulary

Scales, chord qualities and progressions are formulas rather than tables, which
is why adding one is usually a few lines and why none of them can be wrong in
only one key. Put a scale's degrees in `jazz/scale`, a progression's in
`jazz/progression`, and the tests that walk the whole catalogue will pick it up
and check it in every key for you.

## Reporting something

If it is a wrong note, please say what you asked for, what came out, and what
you expected — the command line is the quickest way to show all three:

```sh
gleam run -- scale F# lydian --for alto
```

Lines and tunes are reproducible from their seed, and every readout ends by
telling you what it was, so quoting that is enough for anyone to see exactly
what you saw.
