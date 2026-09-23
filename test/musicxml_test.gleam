import gleam/list
import gleam/option.{None, Some}
import gleam/string
import jazz/instrument
import jazz/lick
import jazz/notation
import jazz/pattern
import jazz/pitch.{C, PitchClass}
import jazz/progression
import jazz/render/musicxml
import jazz/scale

fn alto() -> instrument.Instrument {
  let assert Ok(found) = instrument.find("alto")
  found
}

fn concert() -> instrument.Instrument {
  let assert Ok(found) = instrument.find("concert")
  found
}

fn scale_score(player: instrument.Instrument) -> String {
  musicxml.render(notation.from_scale(
    scale.Scale(PitchClass(C, 0), scale.Ionian),
    player,
    notation.default_tempo,
  ))
}

pub fn it_is_a_musicxml_document_test() {
  let written = scale_score(concert())
  assert string.starts_with(written, "<?xml version=\"1.0\"")
  assert string.contains(written, "<!DOCTYPE score-partwise")
  assert string.contains(written, "<score-partwise version=\"4.0\">")
  assert string.ends_with(written, "</score-partwise>\n")
  assert string.contains(written, "<work-title>C Ionian (major)</work-title>")
}

pub fn a_quarter_note_is_six_divisions_test() {
  // MusicXML counts in divisions of a quarter note, and there have to be
  // enough of them that a triplet eighth is still a whole number: six.
  let written = scale_score(concert())
  assert string.contains(written, "<divisions>6</divisions>")
  // The scale is eighths with a quarter to finish on.
  assert string.contains(written, "<duration>3</duration>")
  assert string.contains(written, "<type>eighth</type>")
  assert string.contains(written, "<duration>6</duration>")
  assert string.contains(written, "<type>quarter</type>")
}

pub fn a_horn_says_what_it_sounds_test() {
  // An alto reads a major sixth above what it sounds, and a file that does
  // not say so plays the part in the wrong key.
  let written = scale_score(alto())
  assert string.contains(written, "<diatonic>-5</diatonic>")
  assert string.contains(written, "<chromatic>-9</chromatic>")
  // Concert pitch has nothing to declare.
  assert !string.contains(scale_score(concert()), "<transpose>")
}

pub fn every_part_is_listed_with_its_sound_test() {
  let assert Ok(changes) = progression.parse("| Dm7 G7 | Cmaj7 |")
  let line = lick.over_progression(changes, lick.options(lick.Beginner, 1))
  let written =
    musicxml.render(notation.from_line_with_backing(
      line,
      changes,
      "test",
      alto(),
      notation.default_tempo,
    ))
  list.each(["Piano", "Bass", "Alto sax (Eb)"], fn(name) {
    assert string.contains(written, "<part-name>" <> name <> "</part-name>")
  })
  assert string.contains(written, "<part id=\"P1\">")
  assert string.contains(written, "<part id=\"P3\">")
  // General MIDI programs are numbered from one here and from zero with us:
  // an upright bass is 32 in the engine and 33 in the file.
  assert string.contains(written, "<midi-program>1</midi-program>")
  assert string.contains(written, "<midi-program>33</midi-program>")
  assert string.contains(written, "<midi-program>66</midi-program>")
}

pub fn a_triplet_is_three_in_the_time_of_two_test() {
  let assert Ok(changes) =
    progression.parse("|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|")
  let written =
    musicxml.render(notation.from_line(
      lick.over_progression(changes, lick.options(lick.Advanced, 7)),
      "test",
      PitchClass(C, 0),
      concert(),
      notation.default_tempo,
    ))
  // Written as an eighth, lasting two divisions rather than three.
  assert string.contains(written, "<actual-notes>3</actual-notes>")
  assert string.contains(written, "<normal-notes>2</normal-notes>")
  assert string.contains(written, "<duration>2</duration>")
  assert string.contains(written, "<tuplet type=\"start\" bracket=\"yes\"/>")
  assert string.contains(written, "<tuplet type=\"stop\"/>")
}

pub fn a_note_is_written_in_the_order_the_format_wants_test() {
  // The DTD is a sequence, not a set. A tie belongs after the duration and
  // an accidental after the note value, and a reader may reject anything
  // else, which would make the whole exercise pointless.
  let assert Ok(changes) =
    progression.parse("|: Dm7 | G7 | Em7 | A7 | Dm7 | G7 | Cmaj7 | Cmaj7 :|")
  // An anticipation ties over the bar line, so a chorus long enough to hold
  // one is what this needs; the seeds are searched rather than guessed at.
  let assert Ok(written) =
    [1, 2, 3, 4, 5, 6, 7, 8]
    |> list.map(fn(seed) {
      musicxml.render(notation.from_line(
        lick.over_progression(changes, lick.options(lick.Advanced, seed)),
        "test",
        PitchClass(C, 0),
        concert(),
        notation.default_tempo,
      ))
    })
    |> list.find(fn(one) {
      string.contains(one, "<tie type=") && string.contains(one, "<accidental>")
    })
  let assert Ok(#(_, rest)) = string.split_once(written, "<accidental>")
  let assert Ok(#(one, _)) = string.split_once(rest, "</note>")
  let note = "<accidental>" <> one
  // Nothing that belongs before an accidental may appear after it.
  list.each(["<pitch>", "<duration>", "<voice>", "<type>"], fn(earlier) {
    assert !string.contains(note, earlier)
  })

  let assert Ok(#(_, tail)) = string.split_once(written, "<tie type=")
  let assert Ok(#(after, _)) = string.split_once(tail, "</note>")
  assert !string.contains(after, "<duration>")
}

pub fn a_chord_symbol_becomes_a_chord_test() {
  let assert Ok(changes) = progression.parse("| Dm7 | G7b9 | Cmaj7 | Am7b5 |")
  let written =
    musicxml.render(notation.from_progression(
      changes,
      concert(),
      notation.default_tempo,
    ))
  assert string.contains(written, "<root-step>D</root-step>")
  assert string.contains(written, "minor-seventh</kind>")
  assert string.contains(written, "dominant</kind>")
  assert string.contains(written, "major-seventh</kind>")
  assert string.contains(written, "half-diminished</kind>")
  // The flat ninth is a degree hung off the chord rather than part of it.
  assert string.contains(written, "<degree-value>9</degree-value>")
  assert string.contains(written, "<degree-alter>-1</degree-alter>")
  // A chart has no notes on it, only time passing under the symbols.
  assert string.contains(written, "<forward>")
  assert !string.contains(written, "<pitch>")
}

pub fn round_the_keys_changes_key_part_way_through_test() {
  let written =
    musicxml.render(notation.from_pattern(
      scale.Scale(PitchClass(C, 0), scale.Ionian),
      pattern.Thirds,
      progression.cycle_of_fourths(PitchClass(C, 0)),
      concert(),
      notation.default_tempo,
    ))
  // Twelve keys, so twelve key signatures: one in the opening attributes
  // and eleven arriving later.
  let announcements = list.length(string.split(written, "<fifths>")) - 1
  assert announcements == 12
  // A key on its own carries no clef or time with it.
  assert list.length(string.split(written, "<clef>")) - 1 == 1
}

pub fn the_feel_is_printed_with_the_title_test() {
  let plain =
    notation.from_scale(
      scale.Scale(PitchClass(C, 0), scale.Ionian),
      concert(),
      notation.default_tempo,
    )
  assert !string.contains(musicxml.render(plain), "Swing")
  let swung = notation.Score(..plain, feel: Some("Swing"))
  assert string.contains(
    musicxml.render(swung),
    "<credit-words>Swing</credit-words>",
  )
}

pub fn text_that_would_break_the_file_is_escaped_test() {
  let subject =
    notation.from_scale(
      scale.Scale(PitchClass(C, 0), scale.Ionian),
      concert(),
      notation.default_tempo,
    )
  let written =
    musicxml.render(
      notation.Score(..subject, title: "Bill & \"Ted\" <live>", feel: None),
    )
  assert string.contains(
    written,
    "<work-title>Bill &amp; &quot;Ted&quot; &lt;live&gt;</work-title>",
  )
  assert !string.contains(written, "<live>")
}
