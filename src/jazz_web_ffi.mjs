// Bridging abcjs, which wants to own a DOM node, into Lustre, which already
// does. The trick is to render into a detached element and hand back the
// markup: abcjs measures glyphs from its own font tables rather than from the
// page, so nothing needs to be on screen for this to work.

// Both renders have to agree, or the playhead would be placed using
// coordinates from a differently sized engraving than the one on the page.
const LAYOUT = {
  paddingtop: 4,
  paddingbottom: 20,
  paddingleft: 0,
  paddingright: 0,
  staffwidth: 720,
};

const SVG_NS = "http://www.w3.org/2000/svg";

let playing = null;
let timer = null;
let clock = null;
let startedAt = 0;
let frame = null;
let playhead = null;
let timings = [];
let reached = 0;
let system = null;

/// How many staves a system has. Two means somebody wrote the backing out.
function staves(tune) {
  const line = (tune.lines || []).find((one) => one.staff);
  return line ? line.staff.length : 1;
}

function library() {
  return globalThis.ABCJS;
}

function engrave(abc) {
  const abcjs = library();
  if (!abcjs) return null;
  const target = document.createElement("div");
  try {
    return { target, tunes: abcjs.renderAbc(target, abc, LAYOUT) };
  } catch (error) {
    return null;
  }
}

export function renderNotation(abc) {
  const drawn = engrave(abc);
  if (!drawn) return "";
  return responsive(drawn.target);
}

// abcjs sizes its SVG with width and height attributes and no viewBox, so
// narrowing the page clips the music instead of scaling it. Its own
// `responsive: "resize"` mode fixes that by positioning the SVG absolutely,
// which then climbs out of whatever box it was given. Adding the viewBox by
// hand keeps the notation in the flow and lets it scale.
function responsive(target) {
  const svg = target.querySelector("svg");
  if (!svg) return target.innerHTML;

  const width = svg.getAttribute("width");
  const height = svg.getAttribute("height");
  if (width && height) {
    svg.setAttribute("viewBox", `0 0 ${width} ${height}`);
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    svg.removeAttribute("width");
    svg.removeAttribute("height");
    svg.style.maxWidth = `${Math.ceil(Number(width))}px`;
  }
  return target.innerHTML;
}

// --- The playhead ------------------------------------------------------------
//
// abcjs hands back the elements it drew, but ours were drawn detached and the
// ones on the page are a copy, so highlighting them would colour nothing. The
// coordinates are just as good and come from the same engraving: a bar drawn
// inside the SVG lands exactly where the notes are, and scales with them for
// free because it lives in the same coordinate space.

function raise(tune) {
  const svg = document.querySelector(".notation svg");
  if (!svg) return false;

  tune.setTiming(0);
  timings = (tune.noteTimings || []).filter(
    (one) => typeof one.left === "number" && typeof one.top === "number",
  );
  if (timings.length === 0) return false;

  playhead = document.createElementNS(SVG_NS, "rect");
  playhead.setAttribute("class", "playhead");
  playhead.setAttribute("rx", "3");
  place(timings[0]);
  // First child, so it sits behind the notes it is lighting up rather than
  // over the top of them.
  svg.insertBefore(playhead, svg.firstChild);

  reached = 0;
  system = timings[0].top;
  return true;
}

// A hairline is easy to miss against staff lines. Lighting up the width of
// the note being played reads at a glance, which is the whole point of it.
function place(one) {
  const wide = Math.max(one.width || 0, 11) + 7;
  playhead.setAttribute("x", String(one.left - 4));
  playhead.setAttribute("y", String(one.top));
  playhead.setAttribute("width", String(wide));
  playhead.setAttribute("height", String(one.height));
}

function follow() {
  frame = null;
  if (!playhead || !clock || !playhead.isConnected) return;

  const elapsed = (clock.currentTime - startedAt) * 1000;
  while (
    reached + 1 < timings.length &&
    timings[reached + 1].milliseconds <= elapsed
  ) {
    reached += 1;
  }

  const now = timings[reached];
  place(now);

  // Only chase the music down the page when it has moved to another system
  // and gone out of sight; scrolling on every note would be unreadable.
  if (now.top !== system) {
    system = now.top;
    const box = playhead.getBoundingClientRect();
    if (box.top < 0 || box.bottom > window.innerHeight) {
      playhead.scrollIntoView({ block: "center", behavior: "smooth" });
    }
  }

  frame = requestAnimationFrame(follow);
}

function lower() {
  if (frame) {
    cancelAnimationFrame(frame);
    frame = null;
  }
  if (playhead && playhead.isConnected) playhead.remove();
  playhead = null;
  timings = [];
  clock = null;
}

// The horn is the second staff; the backing is written above it.
const HORN = 1;

/// Take a voice out of what the synth is about to play.
function mute(synth, voice) {
  const tracks = synth.flattened && synth.flattened.tracks;
  if (!tracks || tracks.length <= voice) return;
  tracks.splice(voice, 1);
}

// --- Sound -------------------------------------------------------------------

export function play(abc, quietHorn, onEnded) {
  const abcjs = library();
  if (!abcjs || !abcjs.synth.supportsAudio()) {
    onEnded();
    return undefined;
  }
  stop();

  const drawn = engrave(abc);
  if (!drawn) {
    onEnded();
    return undefined;
  }

  const context = new (window.AudioContext || window.webkitAudioContext)();
  const synth = new abcjs.synth.CreateSynth();
  playing = synth;

  synth
    // No tempo override: the score carries one, and the playhead reads its
    // timings from the same place. Telling the synth something different is
    // how the two came apart.
    //
    // Chord symbols are voiced automatically unless there is a written part
    // doing that job already, in which case hearing both is just thicker.
    .init({
      audioContext: context,
      visualObj: drawn.tunes[0],
      options: { chordsOff: staves(drawn.tunes[0]) > 1 },
    })
    .then(() => {
      // Silencing the horn has to happen here. `voicesOff` only reaches the
      // MIDI-file writer; the synth flattens the tune into one track per
      // voice and never looks at that option. The tracks are still sitting
      // on the synth untouched, though, so dropping the horn's before the
      // notes are loaded is the same edit one step later.
      if (quietHorn && staves(drawn.tunes[0]) > 1) mute(synth, HORN);
      return synth.prime();
    })
    .then((response) => {
      // A newer request may have replaced this one while the notes loaded.
      if (playing !== synth) return;
      synth.start();

      // The audio clock rather than a timer of our own, so the playhead
      // cannot drift away from what is being heard.
      if (raise(drawn.tunes[0])) {
        clock = context;
        startedAt = context.currentTime;
        frame = requestAnimationFrame(follow);
      }

      const seconds = (response && response.duration) || 0;
      timer = setTimeout(() => {
        if (playing === synth) stop();
        onEnded();
      }, seconds * 1000 + 300);
    })
    .catch(() => {
      if (playing === synth) playing = null;
      lower();
      onEnded();
    });

  return undefined;
}

export function stop() {
  if (timer) {
    clearTimeout(timer);
    timer = null;
  }
  lower();
  if (playing) {
    try {
      playing.stop();
    } catch (error) {
      // Stopping something that never started is not a problem.
    }
    playing = null;
  }
  return undefined;
}
