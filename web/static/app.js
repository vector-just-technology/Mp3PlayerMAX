/* ── Mp3PlayerMAX frontend ── */

// ── SocketIO ─────────────────────────────────────────────────
const socket = io();

socket.on("connect",    () => setStatus("Connected"));
socket.on("disconnect", () => setStatus("Disconnected"));
socket.on("state",      applyState);

// ── State ────────────────────────────────────────────────────
let state = {};
let library = [];
let camRecording = false;

// ── Init ─────────────────────────────────────────────────────
window.addEventListener("DOMContentLoaded", () => {
  loadLibrary();
  fetchState();
});

// ── API helpers ──────────────────────────────────────────────
async function apiPost(url, body = {}) {
  try {
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return await r.json();
  } catch (e) {
    setStatus("Error: " + e.message);
  }
}

async function apiGet(url) {
  const r = await fetch(url);
  return await r.json();
}

// ── State rendering ──────────────────────────────────────────
async function fetchState() {
  state = await apiGet("/api/state");
  applyState(state);
}

function applyState(s) {
  state = s;

  // Track info
  const name = s.current_file
    ? s.current_file.split("/").pop().replace(/\.[^.]+$/, "")
    : "No track selected";
  document.getElementById("track-name").textContent = name;

  const statusMap = { playing: "▶ Playing", paused: "⏸ Paused", stopped: "⏹ Stopped" };
  document.getElementById("track-status").textContent = statusMap[s.status] || s.status;

  // Play button icon
  document.getElementById("btn-play").textContent =
    s.status === "playing" ? "⏸" : "▶";

  // Shuffle highlight
  document.getElementById("btn-shuffle").style.color =
    s.shuffle ? "var(--accent2)" : "";

  // Volume
  document.getElementById("volume-slider").value = s.volume;
  document.getElementById("volume-label").textContent = s.volume + "%";

  // Audio output buttons
  document.getElementById("btn-jack").classList.toggle("active", s.audio_output === "jack");
  document.getElementById("btn-bt").classList.toggle("active", s.audio_output === "bluetooth");

  // BT label
  document.getElementById("bt-output-label").textContent =
    s.audio_output === "bluetooth"
      ? "Bluetooth (" + (s.bt_device || "?") + ")"
      : "3.5mm Jack";

  // Library highlight
  document.querySelectorAll("#library-list li").forEach((li, i) => {
    li.classList.toggle("playing", i === s.current_index && s.status !== "stopped");
  });

  setStatus(statusMap[s.status] || "");
}

// ── Library ──────────────────────────────────────────────────
async function loadLibrary() {
  const list = document.getElementById("library-list");
  list.innerHTML = '<li class="placeholder">Loading...</li>';
  library = await apiGet("/api/library");
  list.innerHTML = "";
  if (!library.length) {
    list.innerHTML = '<li class="placeholder">No music files found in ~/Music</li>';
    return;
  }
  library.forEach((track, i) => {
    const li = document.createElement("li");
    li.innerHTML = `<span>🎵</span><span>${track.name.replace(/\.[^.]+$/, "")}</span>`;
    li.onclick = () => apiPost("/api/play", { index: i });
    list.appendChild(li);
  });
}

// ── Player controls ──────────────────────────────────────────
function togglePlay() {
  if (state.status === "stopped" && library.length) {
    apiPost("/api/play", { index: state.current_index >= 0 ? state.current_index : 0 });
  } else {
    apiPost("/api/pause");
  }
}

function setVolume(v) {
  document.getElementById("volume-label").textContent = v + "%";
  apiPost("/api/volume", { volume: parseInt(v) });
}

// ── Audio output ─────────────────────────────────────────────
async function switchOutput(mode, mac = "") {
  if (mode === "bluetooth" && !mac) {
    mac = document.getElementById("bt-mac-input")?.value?.trim();
    if (!mac) { showTab("bluetooth"); return; }
  }
  const r = await apiPost("/api/audio/switch", { mode, bt_mac: mac });
  setStatus(r?.ok ? `Output: ${mode}` : "Switch failed");
}

// ── Camera ───────────────────────────────────────────────────
async function snapshot() {
  const r = await apiPost("/api/webcam/snapshot");
  const el = document.getElementById("cam-message");
  if (r?.ok) {
    el.textContent = "📷 Saved: " + r.file.split("/").pop();
    el.style.color = "var(--success)";
  } else {
    el.textContent = "Snapshot failed: " + (r?.error || "unknown error");
    el.style.color = "var(--danger)";
  }
  setTimeout(() => { el.textContent = ""; }, 4000);
}

async function toggleRecord() {
  const btn = document.getElementById("btn-record");
  if (!camRecording) {
    const r = await apiPost("/api/webcam/record/start");
    if (r?.ok) {
      camRecording = true;
      btn.textContent = "⏹ Stop Recording";
      btn.style.background = "var(--danger)";
      setStatus("Recording…");
    }
  } else {
    await apiPost("/api/webcam/record/stop");
    camRecording = false;
    btn.textContent = "⏺ Record";
    btn.style.background = "";
    setStatus("Recording saved");
  }
}

// ── Bluetooth ────────────────────────────────────────────────
async function btScan() {
  const spinner = document.getElementById("bt-spinner");
  const btn = document.getElementById("btn-scan");
  const list = document.getElementById("bt-device-list");
  btn.disabled = true;
  spinner.classList.remove("hidden");
  list.innerHTML = "";
  setStatus("Scanning for Bluetooth devices…");

  const devices = await apiGet("/api/bluetooth/scan");
  spinner.classList.add("hidden");
  btn.disabled = false;

  if (!devices.length) {
    list.innerHTML = "<li style='color:var(--muted)'>No devices found. Make sure your device is in pairing mode.</li>";
    return;
  }

  devices.forEach(d => {
    const li = document.createElement("li");
    li.innerHTML = `<span>📶 ${d.name} <small style="color:var(--muted)">${d.mac}</small></span>
                    <button onclick="btConnect('${d.mac}')">Connect</button>`;
    list.appendChild(li);
  });
  setStatus("Scan complete — " + devices.length + " device(s) found");
}

async function btConnect(mac) {
  setStatus("Connecting to " + mac + "…");
  const r = await apiPost("/api/bluetooth/connect", { mac });
  if (r?.ok) {
    await apiPost("/api/audio/switch", { mode: "bluetooth", bt_mac: mac });
    setStatus("Connected: " + mac);
  } else {
    setStatus("Failed to connect: " + (r?.output || "unknown error"));
  }
}

async function btConnectManual() {
  const mac = document.getElementById("bt-mac-input").value.trim();
  if (!mac) return;
  await btConnect(mac);
}

// ── Tab switching ────────────────────────────────────────────
function showTab(name) {
  document.querySelectorAll(".tab").forEach(t => {
    t.classList.toggle("active", t.dataset.tab === name);
  });
  document.querySelectorAll(".tab-content").forEach(s => {
    s.classList.toggle("active", s.id === "tab-" + name);
  });

  // Restart stream when switching to camera tab
  if (name === "camera") {
    const img = document.getElementById("cam-stream");
    img.src = "/api/webcam/stream?" + Date.now();
  }
}

document.querySelectorAll(".tab").forEach(t => {
  t.addEventListener("click", () => showTab(t.dataset.tab));
});

// ── Status bar ───────────────────────────────────────────────
function setStatus(msg) {
  document.getElementById("status-bar").textContent = msg;
}
