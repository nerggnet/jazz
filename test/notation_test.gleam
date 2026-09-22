import gleam/list
import gleam/option.{None, Some}
import gleam/string
import jazz/chord
import jazz/instrument
import jazz/lick
import jazz/notation
import jazz/pitch.{type PitchClass, C, D, F, PitchClass}
import jazz/progression
import jazz/render/abc
import jazz/scale

fn concert() -> instrument.Instrument {
  instrument.concert()
}

fn scale_score(root: PitchClass, kind: scale.ScaleKind) -> notation.Score {
  notation.from_scale(
    scale.Scale(root, kind),
    concert(),
    notation.default_tempo,
  )
}

/// Everything after the K: header line, which is the music itself.
fn tune(text: String) -> String {
  case string.split(text, "\nK:") {
    [_, rest] ->
      case string.split(rest, "\n") {
        [_, ..lines] -> string.trim(string.join(lines, "\n"))
        [] -> ""
      }
    _ -> ""
  }
}

fn accidentals(score: notation.Score) -> List(option.Option(Int)) {
  notation.events(score)
  |> list.filter_map(fn(event) {
    case event {
      notation.Note(accidental: mark, ..) -> Ok(mark)
      _ -> Error(Nil)
    }
  })
}

// --- Key signatures ----------------------------------------------------------

pub fn the_signature_is_the_one_with_least_ink_test() {
  assert scale_score(PitchClass(C, 0), scale.Ionian).signature == 0
  // D Dorian is spelled with the notes of C major, so it needs no accidentals
  // of its own. For alto that is written B Dorian, which is A major.
  assert scale_score(PitchClass(D, 0), scale.Dorian).signature == 0
  let assert Ok(alto) = instrument.find("alto")
  assert notation.from_scale(
      scale.Scale(PitchClass(D, 0), scale.Dorian),
      alto,
      notation.default_tempo,
    ).signature
    == 3
  // Five flats leaves the altered scale needing only one accidental.
  assert scale_score(PitchClass(C, 0), scale.Altered).signature == -5
}

pub fn a_chart_with_no_notes_keeps_its_own_key_test() {
  let assert Ok(built) = progression.build("ii-V-I", PitchClass(F, 0))
  assert notation.from_progression(built, concert(), notation.default_tempo).signature
    == -1
}

// --- Accidentals -------------------------------------------------------------

pub fn the_key_signature_does_the_work_test() {
  assert list.all(
    accidentals(scale_score(PitchClass(C, 0), scale.Ionian)),
    fn(mark) { mark == None },
  )
}

pub fn an_accidental_lasts_to_the_end_of_its_bar_test() {
  // Coming down the blues scale, the F sharp has to be cancelled before the
  // F natural that follows it in the same bar, and written again in the next.
  assert tune(abc.render(scale_score(PitchClass(C, 0), scale.Blues)))
    == "CEF^F GBcB | G^F=FE C2 |]"
}

pub fn the_same_letter_can_be_bent_both_ways_in_one_bar_test() {
  assert tune(
      abc.render(scale_score(PitchClass(C, 0), scale.DiminishedHalfWhole)),
    )
    == "C_D^DE ^FGAB | cBAG ^FE^D_D | C2 |]"
}

// --- Bars and beams ----------------------------------------------------------

pub fn bars_are_filled_by_duration_test() {
  let score = scale_score(PitchClass(C, 0), scale.Ionian)
  let lengths =
    list.map(score.measures, fn(one) {
      list.fold(one.events, 0, fn(total, event) {
        total + notation.duration_of(event)
      })
    })
  // Holding the last note turns a seven note scale up and back down into two
  // complete bars rather than one and three quarters.
  assert lengths == [8, 8]
  assert list.all(lengths, fn(length) {
    length <= notation.measure_capacity(score)
  })
}

pub fn eighths_beam_in_half_bars_test() {
  // A space is what breaks a beam, so the groups show up in the output.
  assert tune(abc.render(scale_score(PitchClass(C, 0), scale.Ionian)))
    == "CDEF GABc | BAGF ED C2 |]"
}

pub fn a_held_note_does_not_beam_test() {
  let assert Ok(last) =
    list.last(notation.events(scale_score(PitchClass(C, 0), scale.Ionian)))
  assert last
    == notation.Note(
      pitch.note(C, 0, 4),
      2,
      None,
      None,
      None,
      notation.Alone,
      False,
    )
}

// --- Spelling ----------------------------------------------------------------

pub fn abc_octaves_test() {
  // The octave containing middle C is written in capitals with no marks.
  let assert Ok(cmaj7) = chord.parse("Cmaj7")
  assert tune(
      abc.render(notation.from_chord(cmaj7, concert(), notation.default_tempo)),
    )
    == "\"Cmaj7\"CEGB GE C2 |]"
  // The octave above is lower case, and each one after that takes an
  // apostrophe. Baritone reads more than an octave above where it sounds.
  let assert Ok(bari) = instrument.find("bari")
  assert tune(
      abc.render(notation.from_chord(cmaj7, bari, notation.default_tempo)),
    )
    == "\"Amaj7\"Aceg ec A2 |]"
  let assert Ok(alto) = instrument.find("alto")
  assert tune(
      abc.render(notation.from_scale(
        scale.Scale(PitchClass(F, 1), scale.Lydian),
        alto,
        notation.default_tempo,
      )),
    )
    == "efga bc'd'e' | d'c'ba gf e2 |]"
}

pub fn chord_symbols_are_quoted_test() {
  let assert Ok(built) = progression.build("ii-V-I", PitchClass(C, 0))
  assert tune(
      abc.render(notation.from_progression(
        built,
        concert(),
        notation.default_tempo,
      )),
    )
    == "\"Dm7\"x8 | \"G7\"x8 | \"Cmaj7\"x8 | \"Cmaj7\"x8 |]"
}

pub fn a_chart_has_one_bar_per_bar_test() {
  let assert Ok(built) = progression.build("blues", PitchClass(F, 0))
  assert list.length(
      notation.from_progression(built, concert(), notation.default_tempo).measures,
    )
    == 12
}

pub fn every_duration_can_be_written_down_test() {
  // Notation has an eighth, a quarter, a dotted quarter and so on, and
  // nothing in between: five eighths is not a rest, it is two rests.
  let writable = [1, 2, 3, 4, 6, 8]
  let assert Ok(changes) =
    progression.parse("|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|")
  list.each([lick.Beginner, lick.Intermediate, lick.Advanced], fn(level) {
    list.each([1, 2, 3, 5, 8, 13], fn(seed) {
      let line = lick.over_progression(changes, lick.options(level, seed))
      let score =
        notation.from_line(
          line,
          "test",
          PitchClass(C, 0),
          concert(),
          notation.default_tempo,
        )
      list.each(score.measures, fn(measure) {
        let #(_, total) =
          list.fold(measure.events, #(0, 0), fn(state, event) {
            let #(at, sum) = state
            let length = notation.duration_of(event)
            assert list.contains(writable, length)
            // Anything longer than an eighth has to start on a beat.
            assert length == 1 || at % 2 == 0
            #(at + length, sum + length)
          })
        assert total <= notation.measure_capacity(score)
      })
    })
  })
}

pub fn a_bar_shared_three_ways_still_adds_up_test() {
  assert progression.shares(1, 8) == [8]
  assert progression.shares(2, 8) == [4, 4]
  // The odd eighth goes to the earlier chords rather than off the end.
  assert progression.shares(3, 8) == [3, 3, 2]
  assert progression.shares(5, 8) == [2, 2, 2, 1, 1]
  assert progression.shares(0, 8) == []

  let assert Ok(changes) = progression.parse("| Dm7 G7 Cmaj7 | Cmaj7 |")
  let score =
    notation.from_progression(changes, concert(), notation.default_tempo)
  list.each(score.measures, fn(measure) {
    let total =
      list.fold(measure.events, 0, fn(sum, event) {
        sum + notation.duration_of(event)
      })
    assert total == notation.measure_capacity(score)
  })
  // And a line over it fills the same two bars.
  let line = lick.over_progression(changes, lick.options(lick.Advanced, 2))
  assert lick.duration(line) == 2 * lick.bar
}

// --- Instruments -------------------------------------------------------------

pub fn exercises_land_on_the_horn_test() {
  // Whatever octave the theory was worked out in, what gets printed has to be
  // playable on the instrument it is printed for.
  list.each(instrument.all(), fn(player) {
    list.each([scale.Ionian, scale.Altered, scale.BebopDominant], fn(kind) {
      list.each(progression.cycle_of_fourths(PitchClass(C, 0)), fn(key) {
        let score =
          notation.from_scale(
            scale.Scale(key, kind),
            player,
            notation.default_tempo,
          )
        list.each(notation.pitches(score), fn(one) {
          assert instrument.in_range(player, one)
        })
      })
    })
  })
}

pub fn a_score_says_how_fast_it_goes_test() {
  // Without a tempo in the music, anything reading the score invents one,
  // and two readers inventing different ones is how a playhead ends up
  // running ahead of the sound it is supposed to be following.
  let assert Ok(cmaj7) = chord.parse("Cmaj7")
  let assert Ok(built) = progression.build("ii-V-I", PitchClass(C, 0))
  let scores = [
    scale_score(PitchClass(C, 0), scale.Ionian),
    notation.from_chord(cmaj7, concert(), notation.default_tempo),
    notation.from_progression(built, concert(), notation.default_tempo),
    notation.from_line(
      lick.over_progression(built, lick.options(lick.Beginner, 1)),
      "test",
      PitchClass(C, 0),
      concert(),
      notation.default_tempo,
    ),
  ]
  list.each(scores, fn(score) {
    assert score.tempo == Some(notation.default_tempo)
    assert string.contains(abc.render(score), "Q:1/4=")
  })
}

pub fn the_header_says_what_it_is_test() {
  let assert Ok(alto) = instrument.find("alto")
  let text =
    abc.render(notation.from_scale(
      scale.Scale(PitchClass(D, 0), scale.Dorian),
      alto,
      notation.default_tempo,
    ))
  assert string.contains(text, "X:1")
  assert string.contains(text, "T:B Dorian")
  assert string.contains(text, "T:Alto sax (Eb)")
  assert string.contains(text, "M:4/4")
  assert string.contains(text, "L:1/8")
  assert string.contains(text, "K:A")
}

pub fn lines_carry_their_changes_test() {
  let assert Ok(built) = progression.build("ii-V-I", PitchClass(C, 0))
  let line = lick.over_progression(built, lick.options(lick.Beginner, 1))
  let score =
    notation.from_line(
      line,
      "test",
      PitchClass(C, 0),
      concert(),
      notation.default_tempo,
    )
  let symbols =
    notation.events(score)
    |> list.filter_map(fn(event) {
      case event {
        notation.Note(chord: Some(symbol), ..) -> Ok(symbol)
        _ -> Error(Nil)
      }
    })
  assert symbols == ["Dm7", "G7", "Cmaj7", "Cmaj7"]
}
