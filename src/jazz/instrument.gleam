//// Transposing instruments.
////
//// Everything in this library is stored at concert pitch. An instrument is
//// the thing that turns concert pitch into the notes a player actually reads,
//// and it is applied at the edge, when rendering. That one rule is what keeps
//// a concert chart and an alto part from ever getting mixed up in the middle
//// of a calculation.

import gleam/list
import gleam/string
import jazz/interval.{type Interval}
import jazz/pitch.{type Pitch, type PitchClass, A, B, C, E, F}

pub type Instrument {
  Instrument(
    id: String,
    name: String,
    /// The key the instrument is described as being in: `C`, `Bb`, `Eb`.
    key: String,
    aliases: List(String),
    /// Added to a concert pitch to get the pitch this instrument reads.
    write_interval: Interval,
    lowest_written: Pitch,
    highest_written: Pitch,
  )
}

/// Anything that already reads at concert pitch: piano, guitar, flute, voice.
pub fn concert() -> Instrument {
  Instrument(
    id: "concert",
    name: "Concert pitch",
    key: "C",
    aliases: ["c", "piano", "guitar", "flute", "voice", "none"],
    write_interval: interval.degree(1, 0),
    lowest_written: pitch.note(A, 0, 0),
    highest_written: pitch.note(C, 0, 8),
  )
}

/// Soprano saxophone: written a major second above concert.
pub fn soprano_sax() -> Instrument {
  Instrument(
    id: "soprano",
    name: "Soprano sax",
    key: "Bb",
    aliases: ["soprano-sax", "ss"],
    write_interval: interval.degree(2, 0),
    lowest_written: pitch.note(B, -1, 3),
    highest_written: pitch.note(F, 0, 6),
  )
}

/// Alto saxophone: written a major sixth above concert.
pub fn alto_sax() -> Instrument {
  Instrument(
    id: "alto",
    name: "Alto sax",
    key: "Eb",
    aliases: ["alto-sax", "as"],
    write_interval: interval.degree(6, 0),
    lowest_written: pitch.note(B, -1, 3),
    highest_written: pitch.note(F, 0, 6),
  )
}

/// Tenor saxophone: written a major ninth above concert.
pub fn tenor_sax() -> Instrument {
  Instrument(
    id: "tenor",
    name: "Tenor sax",
    key: "Bb",
    aliases: ["tenor-sax", "ts"],
    write_interval: interval.degree(9, 0),
    lowest_written: pitch.note(B, -1, 3),
    highest_written: pitch.note(F, 0, 6),
  )
}

/// Baritone saxophone: written an octave and a major sixth above concert.
pub fn baritone_sax() -> Instrument {
  Instrument(
    id: "baritone",
    name: "Baritone sax",
    key: "Eb",
    aliases: ["bari", "bari-sax", "baritone-sax", "bs"],
    write_interval: interval.degree(13, 0),
    lowest_written: pitch.note(B, -1, 3),
    highest_written: pitch.note(F, 0, 6),
  )
}

/// Trumpet, and any other B-flat instrument reading a major second up.
pub fn trumpet() -> Instrument {
  Instrument(
    id: "trumpet",
    name: "Trumpet",
    key: "Bb",
    aliases: ["tpt", "bb", "cornet", "flugelhorn"],
    write_interval: interval.degree(2, 0),
    lowest_written: pitch.note(F, 1, 3),
    highest_written: pitch.note(C, 0, 6),
  )
}

/// B-flat clarinet.
pub fn clarinet() -> Instrument {
  Instrument(
    id: "clarinet",
    name: "Clarinet",
    key: "Bb",
    aliases: ["cl"],
    write_interval: interval.degree(2, 0),
    lowest_written: pitch.note(E, 0, 3),
    highest_written: pitch.note(C, 0, 7),
  )
}

/// Any E-flat instrument, for when the range does not matter.
pub fn eb_instrument() -> Instrument {
  Instrument(
    id: "eb",
    name: "Eb instrument",
    key: "Eb",
    aliases: ["e-flat"],
    write_interval: interval.degree(6, 0),
    lowest_written: pitch.note(A, 0, 0),
    highest_written: pitch.note(C, 0, 8),
  )
}

pub fn all() -> List(Instrument) {
  [
    concert(),
    soprano_sax(),
    alto_sax(),
    tenor_sax(),
    baritone_sax(),
    trumpet(),
    clarinet(),
    eb_instrument(),
  ]
}

/// Look an instrument up by id or alias, case insensitively.
pub fn find(name: String) -> Result(Instrument, String) {
  let wanted = string.lowercase(string.trim(name))
  let found =
    list.find(all(), fn(instrument) {
      instrument.id == wanted || list.contains(instrument.aliases, wanted)
    })
  case found {
    Ok(instrument) -> Ok(instrument)
    Error(_) ->
      Error(
        "unknown instrument `"
        <> name
        <> "`, try one of: "
        <> string.join(list.map(all(), fn(i) { i.id }), ", "),
      )
  }
}

/// Whether this instrument reads at concert pitch.
pub fn is_concert(instrument: Instrument) -> Bool {
  interval.semitones(instrument.write_interval) == 0
}

// --- Transposition -----------------------------------------------------------

/// The pitch this instrument reads in order to sound the given concert pitch.
pub fn write(instrument: Instrument, concert_pitch: Pitch) -> Pitch {
  interval.transpose(concert_pitch, instrument.write_interval)
}

/// The pitch class this instrument reads for a concert pitch class.
pub fn write_class(
  instrument: Instrument,
  concert_class: PitchClass,
) -> PitchClass {
  interval.transpose_class(concert_class, instrument.write_interval)
}

/// The concert pitch produced when this instrument plays a written pitch.
pub fn sounds(instrument: Instrument, written: Pitch) -> Pitch {
  interval.transpose(written, interval.negate(instrument.write_interval))
}

/// The concert pitch class for a written pitch class.
pub fn sounds_class(instrument: Instrument, written: PitchClass) -> PitchClass {
  interval.transpose_class(written, interval.negate(instrument.write_interval))
}

// --- Range -------------------------------------------------------------------

/// Whether a written pitch is inside the instrument's normal range.
pub fn in_range(instrument: Instrument, written: Pitch) -> Bool {
  let note = pitch.to_midi(written)
  note >= pitch.to_midi(instrument.lowest_written)
  && note <= pitch.to_midi(instrument.highest_written)
}

/// Shift a written pitch by whole octaves until it fits the range, keeping its
/// spelling. Returns the nearest octave if nothing fits.
pub fn fit_to_range(instrument: Instrument, written: Pitch) -> Pitch {
  let low = pitch.to_midi(instrument.lowest_written)
  let high = pitch.to_midi(instrument.highest_written)
  fit_loop(written, low, high, 0)
}

fn fit_loop(written: Pitch, low: Int, high: Int, tries: Int) -> Pitch {
  let note = pitch.to_midi(written)
  case tries > 10, note < low, note > high {
    True, _, _ -> written
    _, True, _ ->
      fit_loop(
        interval.transpose(written, interval.octaves(1)),
        low,
        high,
        tries + 1,
      )
    _, _, True ->
      fit_loop(
        interval.transpose(written, interval.octaves(-1)),
        low,
        high,
        tries + 1,
      )
    _, _, _ -> written
  }
}

/// The General MIDI voice that sounds most like this instrument, so a part
/// plays back as the thing it was written for rather than as a piano.
pub fn sound(instrument: Instrument) -> Int {
  case instrument.id {
    "soprano" -> 64
    "alto" | "eb" -> 65
    "tenor" -> 66
    "baritone" -> 67
    "trumpet" -> 56
    "clarinet" -> 71
    // Concert pitch covers anything, so it gets the instrument everything
    // else is measured against.
    _ -> 0
  }
}

/// The voice a written out backing is played with.
pub const piano = 0

/// A short label such as `Alto sax (Eb)`.
pub fn label(instrument: Instrument) -> String {
  case is_concert(instrument) {
    True -> instrument.name
    False -> instrument.name <> " (" <> instrument.key <> ")"
  }
}

/// The interval to transpose by when writing a part in a given concert key.
///
/// Normally this is just the instrument's transposition, but concert F-sharp
/// for alto works out as D-sharp major and its nine sharps. When that happens
/// the same enharmonic nudge is applied to every note, so the part stays
/// internally consistent rather than mixing `Bbm7` with `D#7`.
pub fn write_interval_for_key(
  instrument: Instrument,
  concert_key: PitchClass,
) -> Interval {
  let written = interval.transpose_class(concert_key, instrument.write_interval)
  let diminished_second = interval.degree(2, -2)
  case pitch.fifths(written) > 6, pitch.fifths(written) < -6 {
    True, _ -> interval.add(instrument.write_interval, diminished_second)
    _, True ->
      interval.add(
        instrument.write_interval,
        interval.negate(diminished_second),
      )
    _, _ -> instrument.write_interval
  }
}

/// Two octaves through the middle of the instrument, given at concert pitch.
///
/// Generated lines need somewhere to live. The full range of a horn is wide
/// enough that a line wandering across all of it leaps about; the middle two
/// octaves are where the practice actually happens.
pub fn comfortable_range(instrument: Instrument) -> #(Pitch, Pitch) {
  let octaves =
    {
      pitch.to_midi(instrument.highest_written)
      - pitch.to_midi(instrument.lowest_written)
    }
    / 12
  let low =
    interval.transpose(
      instrument.lowest_written,
      interval.octaves({ octaves - 1 } / 2),
    )
  let high = interval.transpose(low, interval.octaves(2))
  #(sounds(instrument, low), sounds(instrument, high))
}
