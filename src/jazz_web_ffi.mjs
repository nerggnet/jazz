// Bridging abcjs, which wants to own a DOM node, into Lustre, which already
// does. The trick is to render into a detached element and hand back the
// markup: abcjs measures glyphs from its own font tables rather than from the
// page, so nothing needs to be on screen for this to work.

let playing = null;
let timer = null;

function library() {
  return globalThis.ABCJS;
}

export function renderNotation(abc) {
  const abcjs = library();
  if (!abcjs) return "";
  const target = document.createElement("div");
  try {
    abcjs.renderAbc(target, abc, {
      paddingtop: 4,
      paddingbottom: 20,
      paddingleft: 0,
      paddingright: 0,
      staffwidth: 720,
    });
  } catch (error) {
    return "";
  }
  return responsive(target);
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

export function play(abc, onEnded) {
  const abcjs = library();
  if (!abcjs || !abcjs.synth.supportsAudio()) {
    onEnded();
    return undefined;
  }
  stop();

  const target = document.createElement("div");
  const tunes = abcjs.renderAbc(target, abc);
  const context = new (window.AudioContext || window.webkitAudioContext)();
  const synth = new abcjs.synth.CreateSynth();
  playing = synth;

  synth
    .init({
      audioContext: context,
      visualObj: tunes[0],
      millisecondsPerMeasure: 1900,
    })
    .then(() => synth.prime())
    .then((response) => {
      // A newer request may have replaced this one while the notes loaded.
      if (playing !== synth) return;
      synth.start();
      const seconds = (response && response.duration) || 0;
      timer = setTimeout(() => {
        if (playing === synth) stop();
        onEnded();
      }, seconds * 1000 + 300);
    })
    .catch(() => {
      if (playing === synth) playing = null;
      onEnded();
    });

  return undefined;
}

export function stop() {
  if (timer) {
    clearTimeout(timer);
    timer = null;
  }
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

export function audioAvailable() {
  const abcjs = library();
  return Boolean(abcjs && abcjs.synth && abcjs.synth.supportsAudio());
}
