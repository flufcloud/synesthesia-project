const samplingRate = 10;
const samplesByFrame = new Map();

const audioInput = document.querySelector("#audio-file");
const audioPlayer = document.querySelector("#audio-player");
const fileName = document.querySelector("#file-name");
const fileDuration = document.querySelector("#file-duration");
const recordButton = document.querySelector("#record-button");
const downloadButton = document.querySelector("#download-button");
const sampleCount = document.querySelector("#sample-count");
const recordingStatus = document.querySelector("#recording-status");
const statusDot = document.querySelector("#status-dot");
const fileButton = document.querySelector(".file-button");

let audioFile = null;
let audioUrl = null;
let isRecording = false;

class ColorField {
  constructor(card) {
    this.card = card;
    this.channel = card.dataset.channel;
    this.canvas = card.querySelector("[data-color-field]");
    this.context = this.canvas.getContext("2d");
    this.nullToggle = card.querySelector("[data-null-toggle]");
    this.swatch = card.querySelector("[data-color-swatch]");
    this.label = card.querySelector("[data-color-label]");
    this.hue = 0;
    this.lightness = 0.5;
    this.dragging = false;
    this.color = hslToRgb(this.hue, 1, this.lightness);

    this.bindEvents();
    new ResizeObserver(() => this.draw()).observe(this.canvas);
    this.updateNullState();
  }

  get isNull() {
    return this.nullToggle.checked;
  }

  get value() {
    if (this.isNull) {
      return null;
    }

    return {
      hex: rgbToHex(this.color),
      red: round(this.color.red / 255),
      green: round(this.color.green / 255),
      blue: round(this.color.blue / 255),
    };
  }

  bindEvents() {
    this.nullToggle.addEventListener("change", () => this.updateNullState());
    this.canvas.addEventListener("pointerdown", (event) => {
      if (this.isNull) {
        return;
      }
      this.dragging = true;
      this.canvas.setPointerCapture(event.pointerId);
      this.updateFromPointer(event);
    });
    this.canvas.addEventListener("pointermove", (event) => {
      if (this.dragging) {
        this.updateFromPointer(event);
      }
    });
    this.canvas.addEventListener("pointerup", () => {
      this.dragging = false;
    });
    this.canvas.addEventListener("pointercancel", () => {
      this.dragging = false;
    });
    this.canvas.addEventListener("keydown", (event) => this.updateFromKeyboard(event));
  }

  updateNullState() {
    this.card.classList.toggle("is-null", this.isNull);
    this.canvas.setAttribute("aria-disabled", String(this.isNull));
    this.label.textContent = this.isNull ? "None" : rgbToHex(this.color);
    this.swatch.style.background = this.isNull ? "transparent" : rgbToHex(this.color);
  }

  updateFromPointer(event) {
    const bounds = this.canvas.getBoundingClientRect();
    this.hue = clamp((event.clientX - bounds.left) / bounds.width, 0, 1);
    this.lightness = 1 - clamp((event.clientY - bounds.top) / bounds.height, 0, 1);
    this.updateColor();
  }

  updateFromKeyboard(event) {
    if (this.isNull || !["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) {
      return;
    }

    event.preventDefault();
    const amount = event.shiftKey ? 0.05 : 0.01;
    if (event.key === "ArrowLeft") this.hue = clamp(this.hue - amount, 0, 1);
    if (event.key === "ArrowRight") this.hue = clamp(this.hue + amount, 0, 1);
    if (event.key === "ArrowUp") this.lightness = clamp(this.lightness + amount, 0, 1);
    if (event.key === "ArrowDown") this.lightness = clamp(this.lightness - amount, 0, 1);
    this.updateColor();
  }

  updateColor() {
    this.color = hslToRgb(this.hue, 1, this.lightness);
    this.label.textContent = rgbToHex(this.color);
    this.swatch.style.background = rgbToHex(this.color);
    this.draw();
  }

  draw() {
    const bounds = this.canvas.getBoundingClientRect();
    if (!bounds.width || !bounds.height) {
      return;
    }

    const density = window.devicePixelRatio || 1;
    this.canvas.width = Math.round(bounds.width * density);
    this.canvas.height = Math.round(bounds.height * density);
    this.context.setTransform(density, 0, 0, density, 0, 0);

    const hueGradient = this.context.createLinearGradient(0, 0, bounds.width, 0);
    for (let step = 0; step <= 6; step += 1) {
      hueGradient.addColorStop(step / 6, `hsl(${step * 60} 100% 50%)`);
    }
    this.context.fillStyle = hueGradient;
    this.context.fillRect(0, 0, bounds.width, bounds.height);

    const lightnessGradient = this.context.createLinearGradient(0, 0, 0, bounds.height);
    lightnessGradient.addColorStop(0, "rgba(255, 255, 255, 1)");
    lightnessGradient.addColorStop(0.5, "rgba(255, 255, 255, 0)");
    lightnessGradient.addColorStop(0.5, "rgba(0, 0, 0, 0)");
    lightnessGradient.addColorStop(1, "rgba(0, 0, 0, 1)");
    this.context.fillStyle = lightnessGradient;
    this.context.fillRect(0, 0, bounds.width, bounds.height);

    const markerX = clamp(this.hue * bounds.width, 8, bounds.width - 8);
    const markerY = clamp((1 - this.lightness) * bounds.height, 8, bounds.height - 8);
    this.context.beginPath();
    this.context.arc(markerX, markerY, 7, 0, Math.PI * 2);
    this.context.lineWidth = 3;
    this.context.strokeStyle = "white";
    this.context.stroke();
    this.context.lineWidth = 1;
    this.context.strokeStyle = "black";
    this.context.stroke();
  }
}

const colorFields = Object.fromEntries(
  [...document.querySelectorAll("[data-channel]")].map((card) => {
    const field = new ColorField(card);
    return [field.channel, field];
  }),
);

audioInput.addEventListener("change", () => {
  const [selectedFile] = audioInput.files;
  if (!selectedFile) {
    return;
  }

  if (audioUrl) {
    URL.revokeObjectURL(audioUrl);
  }
  audioFile = selectedFile;
  audioUrl = URL.createObjectURL(selectedFile);
  audioPlayer.src = audioUrl;
  fileName.textContent = selectedFile.name;
  fileDuration.textContent = "Reading duration…";
  samplesByFrame.clear();
  updateSampleCount();
  downloadButton.disabled = true;
  recordButton.disabled = true;
  recordingStatus.textContent = "Reading audio metadata";
});

audioPlayer.addEventListener("loadedmetadata", () => {
  fileDuration.textContent = formatTime(audioPlayer.duration);
  recordButton.disabled = false;
  recordingStatus.textContent = "Ready to record";
});

recordButton.addEventListener("click", () => {
  if (isRecording) {
    stopRecording();
  } else {
    startRecording();
  }
});

downloadButton.addEventListener("click", downloadDataset);

window.setInterval(() => {
  if (!isRecording || audioPlayer.paused || audioPlayer.ended) {
    return;
  }

  const frame = Math.floor(audioPlayer.currentTime * samplingRate);
  samplesByFrame.set(frame, {
    timeSeconds: round(frame / samplingRate),
    primary: colorFields.primary.value,
    secondary: colorFields.secondary.value,
    tertiary: colorFields.tertiary.value,
  });
  updateSampleCount();
}, 50);

window.addEventListener("beforeunload", () => {
  if (audioUrl) {
    URL.revokeObjectURL(audioUrl);
  }
});

function startRecording() {
  if (!audioFile || !Number.isFinite(audioPlayer.duration)) {
    return;
  }

  samplesByFrame.clear();
  updateSampleCount();
  isRecording = true;
  audioInput.disabled = true;
  fileButton.classList.add("is-disabled");
  recordButton.textContent = "Stop recording";
  recordButton.classList.add("is-recording");
  downloadButton.disabled = true;
  statusDot.classList.add("is-recording");
  recordingStatus.textContent = audioPlayer.paused ? "Recording armed — press play" : "Recording";
}

function stopRecording() {
  isRecording = false;
  audioInput.disabled = false;
  fileButton.classList.remove("is-disabled");
  recordButton.textContent = "Start recording";
  recordButton.classList.remove("is-recording");
  statusDot.classList.remove("is-recording");
  downloadButton.disabled = samplesByFrame.size === 0;
  recordingStatus.textContent = samplesByFrame.size ? "Recording ready to download" : "No samples recorded";
}

function downloadDataset() {
  if (!audioFile || samplesByFrame.size === 0) {
    return;
  }

  const dataset = {
    formatVersion: 5,
    createdAt: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    audio: {
      fileName: audioFile.name,
      path: "",
      durationSeconds: round(audioPlayer.duration),
    },
    sampling: {
      rateHz: samplingRate,
      colorSpace: "sRGB",
    },
    samples: [...samplesByFrame.values()].sort((left, right) => left.timeSeconds - right.timeSeconds),
  };

  const data = new Blob([JSON.stringify(dataset, null, 2)], { type: "application/json" });
  const downloadUrl = URL.createObjectURL(data);
  const link = document.createElement("a");
  link.href = downloadUrl;
  link.download = `${removeExtension(audioFile.name)}.colors.json`;
  document.body.append(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(downloadUrl), 0);
  recordingStatus.textContent = "Color data downloaded";
}

function updateSampleCount() {
  sampleCount.textContent = samplesByFrame.size.toLocaleString();
  if (isRecording && !audioPlayer.paused) {
    recordingStatus.textContent = "Recording";
  }
}

function hslToRgb(hue, saturation, lightness) {
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const sector = hue * 6;
  const second = chroma * (1 - Math.abs((sector % 2) - 1));
  let red = 0;
  let green = 0;
  let blue = 0;

  if (sector < 1) [red, green] = [chroma, second];
  else if (sector < 2) [red, green] = [second, chroma];
  else if (sector < 3) [green, blue] = [chroma, second];
  else if (sector < 4) [green, blue] = [second, chroma];
  else if (sector < 5) [red, blue] = [second, chroma];
  else [red, blue] = [chroma, second];

  const match = lightness - chroma / 2;
  return {
    red: Math.round((red + match) * 255),
    green: Math.round((green + match) * 255),
    blue: Math.round((blue + match) * 255),
  };
}

function rgbToHex(color) {
  return `#${[color.red, color.green, color.blue]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("")}`.toUpperCase();
}

function formatTime(seconds) {
  const minutes = Math.floor(seconds / 60);
  const remainder = (seconds % 60).toFixed(1).padStart(4, "0");
  return `${minutes}:${remainder}`;
}

function removeExtension(name) {
  const index = name.lastIndexOf(".");
  return index > 0 ? name.slice(0, index) : name;
}

function round(value) {
  return Math.round(value * 10_000) / 10_000;
}

function clamp(value, minimum, maximum) {
  return Math.min(Math.max(value, minimum), maximum);
}
