import gleam/int
import gleam/list
import gleam/string
import jazz/chord
import jazz/harmony
import jazz/pitch.{type PitchClass, A, C, D, E, F, G, PitchClass}
import jazz/progression
import jazz/scale.{type ScaleKind}

fn on(root: PitchClass, kind: ScaleKind, flavour: harmony.Flavour) -> String {
  scale.Scale(root, kind)
  |> harmony.chords(flavour)
  |> list.map(chord.to_string)
  |> string.join(" ")
}

fn c(letter: pitch.Letter) -> PitchClass {
  PitchClass(letter, 0)
}

// --- What comes out ----------------------------------------------------------

pub fn the_major_scale_harmonises_the_way_everybody_learns_it_test() {
  // Seven chords, in order, and no eighth one.
  assert on(c(C), scale.Ionian, harmony.Triads) == "C Dm Em F G Am Bdim"
  assert on(c(C), scale.Ionian, harmony.Sevenths)
    == "Cmaj7 Dm7 Em7 Fmaj7 G7 Am7 Bm7b5"
}

pub fn a_mode_is_harmonised_from_its_own_root_test() {
  // The same seven chords as C major, started in the right place: which is
  // what makes the first one the tonic rather than the second.
  assert on(c(D), scale.Dorian, harmony.Sevenths)
    == "Dm7 Em7 Fmaj7 G7 Am7 Bm7b5 Cmaj7"
}

pub fn melodic_minor_gives_the_chords_it_is_used_for_test() {
  // The seven every book lists, and the augmented dominants that go with
  // them: the scale carries a #5 wherever it carries a b3 of the key, which
  // is what V7#5 in minor is made of.
  assert on(c(C), scale.MelodicMinor, harmony.Sevenths)
    == "Cm(maj7) Dm7 Ebmaj7#5 F7 G7 G7#5 Am7b5 Bm7b5 B7#5"
}

pub fn harmonic_minor_names_its_diminished_seventh_from_the_leading_note_test() {
  // The dim7 sits on four of the seven degrees and is the same chord on each,
  // so it is listed once -- as Bdim7, which is the one that does not need a
  // double flat to write down.
  assert on(c(C), scale.HarmonicMinor, harmony.Sevenths)
    == "Cm(maj7) Dm7b5 Ebmaj7#5 Fm7 Fm7b5 G7 G7#5 Abmaj7 Abm(maj7) Bdim7"
}

pub fn a_symmetric_chord_is_listed_once_test() {
  // Two augmented triads in the whole tone scale, not six, because the other
  // four are the same two played from another note.
  assert on(c(C), scale.WholeTone, harmony.Triads) == "Caug Daug"
  // And the same chord kept apart from one that merely shares its notes:
  // Cmaj13 and Am11 are the same six notes and nothing like each other.
  let ionian = on(c(C), scale.Ionian, harmony.Extended)
  assert string.contains(ionian, "Cmaj13")
  assert string.contains(ionian, "Am11")
}

pub fn a_symmetric_scale_gives_the_same_chord_all_the_way_up_test() {
  // Six roots, one shape: the whole tone scale has nothing else in it.
  let found = on(c(C), scale.WholeTone, harmony.Sevenths)
  assert list.length(string.split(found, " ")) == 6
  list.each(string.split(found, " "), fn(symbol) {
    assert string.ends_with(symbol, "7#5")
  })
}

pub fn the_altered_scale_carries_the_altered_chord_test() {
  // The point of the scale, and the one chord it exists for.
  let found = on(c(C), scale.Altered, harmony.Extended)
  assert string.contains(found, "C7alt")
}

pub fn lydian_dominant_carries_the_thirteen_sharp_eleven_test() {
  let found = on(c(C), scale.LydianDominant, harmony.Extended)
  assert string.contains(found, "C13#11")
}

pub fn a_scale_with_too_few_notes_carries_nothing_tall_test() {
  // Five notes and no seventh above any root worth the name. Saying so is
  // more use than making something up.
  assert on(c(C), scale.MinorPentatonic, harmony.Extended) == ""
  assert on(c(C), scale.MinorPentatonic, harmony.Sevenths) == "Cm7"
}

pub fn suspensions_are_kept_out_of_the_triads_test() {
  // A fourth in place of a third is a sound of its own, not a thinner triad,
  // so the plain triads stay seven and the sus chords have a flavour of their
  // own to live in.
  assert list.length(harmony.chords(
      scale.Scale(c(C), scale.Ionian),
      harmony.Triads,
    ))
    == 7
  assert string.contains(on(c(D), scale.Dorian, harmony.Suspended), "D7sus4")
}

// --- The property that has to hold everywhere --------------------------------

pub fn every_chord_is_inside_its_scale_test() {
  // The whole claim the module makes, measured over every scale and every
  // flavour rather than asserted for the ones that were easy to check.
  list.each(scale.all_kinds(), fn(kind) {
    list.each([c(C), PitchClass(A, -1), PitchClass(F, 1)], fn(root) {
      let subject = scale.Scale(root, kind)
      let tones = scale.notes(subject) |> list.map(pitch.class_semitones)
      list.each(harmony.all_flavours(), fn(flavour) {
        list.each(harmony.chords(subject, flavour), fn(one) {
          list.each(chord.notes(one), fn(note) {
            assert list.contains(tones, pitch.class_semitones(note))
          })
          // And it is rooted on a note of the scale, not beside one.
          assert list.contains(tones, pitch.class_semitones(one.root))
        })
      })
    })
  })
}

pub fn chords_come_out_in_the_order_the_scale_runs_test() {
  // Up the scale, root by root, so the degree column only ever counts
  // forwards and the tonic chord -- where there is one -- comes first.
  list.each(scale.all_kinds(), fn(kind) {
    let subject = scale.Scale(c(E), kind)
    let order =
      scale.notes(subject)
      |> list.map(pitch.class_semitones)
    list.each(harmony.all_flavours(), fn(flavour) {
      let places =
        harmony.chords(subject, flavour)
        |> list.map(fn(one) {
          case
            list.split_while(order, fn(at) {
              at != pitch.class_semitones(one.root)
            })
          {
            #(before, _) -> list.length(before)
          }
        })
      assert places == list.sort(places, int.compare)
    })
  })
}

pub fn the_degree_is_the_place_in_the_scale_test() {
  let found =
    harmony.chords(scale.Scale(c(C), scale.Dorian), harmony.Sevenths)
    |> list.map(progression.numeral(c(C), _))
  assert found == ["i", "ii", "bIII", "IV", "v", "vi", "bVII"]
}

// --- As changes --------------------------------------------------------------

pub fn the_chart_holds_one_chord_to_a_bar_test() {
  let changes =
    harmony.as_progression(
      scale.Scale(c(G), scale.Mixolydian),
      harmony.Sevenths,
    )
  assert list.length(changes.bars) == 7
  list.each(changes.bars, fn(bar) {
    assert list.length(bar.chords) == 1
  })
  assert pitch.same(changes.key, c(G))
}

pub fn a_chart_with_nothing_on_it_is_still_a_bar_test() {
  // An empty score is not a score, and the front end has to draw something.
  let changes =
    harmony.as_progression(scale.Scale(c(C), scale.Blues), harmony.Extended)
  assert list.length(changes.bars) == 1
  assert changes.bars == [progression.Bar([])]
}

pub fn the_chart_carries_the_flavour_into_its_name_test() {
  let changes =
    harmony.as_progression(scale.Scale(c(G), scale.Mixolydian), harmony.Triads)
  assert changes.name == "Triads from Mixolydian"
  assert changes.note == harmony.usage(harmony.Triads)
}

// --- Naming ------------------------------------------------------------------

pub fn every_flavour_can_be_asked_for_by_name_test() {
  list.each(harmony.all_flavours(), fn(one) {
    assert harmony.flavour_from_string(harmony.id(one)) == Ok(one)
    assert harmony.name(one) != ""
    assert harmony.usage(one) != ""
  })
  assert harmony.flavour_from_string("SUS") == Ok(harmony.Suspended)
  assert harmony.flavour_from_string(" Extended ") == Ok(harmony.Extended)
  assert harmony.flavour_from_string("sevenths") == Ok(harmony.Sevenths)
  let assert Error(_) = harmony.flavour_from_string("ninths and things")
}
