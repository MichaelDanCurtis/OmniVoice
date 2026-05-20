window.omniVoiceApplyTheme = function omniVoiceApplyTheme(payload) {
  if (!payload || !payload.css_variables) return;
  for (const [name, value] of Object.entries(payload.css_variables)) {
    document.documentElement.style.setProperty(name, value);
  }
};

const state = {
  status: null,
  transcripts: [],
  events: [],
};

let themeLoadPromise = null;

const nodes = {
  healthPill: document.querySelector("#healthPill"),
  startDesktopApp: document.querySelector("#startDesktopApp"),
  desktopAppLaunchStatus: document.querySelector("#desktopAppLaunchStatus"),
  refreshButton: document.querySelector("#refreshButton"),
  uptimeValue: document.querySelector("#uptimeValue"),
  providerValue: document.querySelector("#providerValue"),
  modelValue: document.querySelector("#modelValue"),
  transcriptValue: document.querySelector("#transcriptValue"),
  streamValue: document.querySelector("#streamValue"),
  streamAudioValue: document.querySelector("#streamAudioValue"),
  streamPartialValue: document.querySelector("#streamPartialValue"),
  providerList: document.querySelector("#providerList"),
  modelList: document.querySelector("#modelList"),
  transcriptList: document.querySelector("#transcriptList"),
  eventList: document.querySelector("#eventList"),
  copyLatestTranscript: document.querySelector("#copyLatestTranscript"),
  copyDiagnostics: document.querySelector("#copyDiagnostics"),
  emptyTemplate: document.querySelector("#emptyStateTemplate"),
};

nodes.startDesktopApp.addEventListener("click", () => startDesktopApp());
nodes.refreshButton.addEventListener("click", () => refresh());
nodes.copyLatestTranscript.addEventListener("click", () => copyLatestTranscript());
nodes.copyDiagnostics.addEventListener("click", () => copyDiagnostics());

refresh();
setInterval(refresh, 4000);

async function refresh() {
  nodes.refreshButton.disabled = true;
  try {
    try {
      await loadTheme();
    } catch (error) {
      console.warn("Unable to load dashboard theme", error);
    }
    const [status, transcripts, events] = await Promise.all([
      fetchJson("/api/status"),
      fetchJson("/api/transcripts?limit=100"),
      fetchJson("/api/events?limit=150"),
    ]);
    state.status = status;
    state.transcripts = transcripts;
    state.events = events;
    render();
  } catch (error) {
    renderOffline(error);
  } finally {
    nodes.refreshButton.disabled = false;
  }
}

async function loadTheme() {
  if (window.__OMNIVOICE_THEME__) {
    window.omniVoiceApplyTheme(window.__OMNIVOICE_THEME__);
    return;
  }
  if (!themeLoadPromise) {
    themeLoadPromise = fetchJson("/api/theme/default")
      .then((theme) => {
        window.__OMNIVOICE_THEME__ = theme;
        return theme;
      })
      .catch((error) => {
        themeLoadPromise = null;
        throw error;
      });
  }
  const theme = await themeLoadPromise;
  window.omniVoiceApplyTheme(theme);
}

async function fetchJson(path, options = {}) {
  const response = await fetch(path, options);
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(payload?.detail || `${response.status} ${response.statusText}`);
  }
  return payload;
}

function render() {
  const availableProviders = state.status.providers.filter((provider) => provider.available).length;
  const installedModels = state.status.models.filter((model) => model.installed).length;

  nodes.healthPill.textContent = "Online";
  nodes.healthPill.className = "pill";
  nodes.uptimeValue.textContent = formatDuration(state.status.uptime_seconds);
  nodes.providerValue.textContent = `${availableProviders}/${state.status.providers.length}`;
  nodes.modelValue.textContent = `${installedModels}/${state.status.models.length}`;
  nodes.transcriptValue.textContent = String(state.status.transcript_count);
  nodes.streamValue.textContent = String(state.status.streaming?.active_streams ?? 0);
  nodes.streamAudioValue.textContent = formatBytes(state.status.streaming?.total_audio_bytes ?? 0);
  nodes.streamPartialValue.textContent = String(state.status.streaming?.total_partials ?? 0);

  renderProviders(state.status.providers);
  renderModels(state.status.models);
  renderTranscripts(state.transcripts);
  renderEvents(state.events);
}

function renderOffline(error) {
  nodes.healthPill.textContent = "Offline";
  nodes.healthPill.className = "pill error";
  nodes.eventList.replaceChildren(logRow({
    timestamp: new Date().toISOString(),
    level: "error",
    kind: "dashboard.refresh",
    message: error.message,
    detail: {},
  }));
}

function renderProviders(providers) {
  if (!providers.length) {
    nodes.providerList.replaceChildren(emptyState());
    return;
  }

  nodes.providerList.replaceChildren(...providers.map((provider) => {
    const row = document.createElement("article");
    row.className = "row";

    const body = document.createElement("div");
    body.append(textBlock("p", "row-title", provider.label));
    body.append(textBlock("p", "row-detail", provider.reason || provider.id));

    const pill = document.createElement("span");
    pill.className = provider.available ? "pill" : "pill warning";
    pill.textContent = provider.available ? "Available" : "Unavailable";

    row.append(body, pill);
    return row;
  }));
}

function renderModels(models) {
  if (!models.length) {
    nodes.modelList.replaceChildren(emptyState());
    return;
  }

  nodes.modelList.replaceChildren(...models.map((model) => {
    const row = document.createElement("article");
    row.className = "row";

    const body = document.createElement("div");
    body.append(textBlock("p", "row-title", model.label));
    body.append(textBlock("p", "row-detail", model.repo_id));
    body.append(textBlock("p", "row-detail", model.download_message || model.local_path));
    if (model.missing_files.length) {
      body.append(textBlock("p", "row-detail", `Missing: ${model.missing_files.join(", ")}`));
    }

    const actions = document.createElement("div");
    actions.className = "row-actions";
    const status = document.createElement("span");
    status.className = model.installed ? "pill" : "pill warning";
    status.textContent = model.installed ? "Ready" : model.download_state;

    const update = button("Check", async () => {
      await fetchJson(`/models/${encodeURIComponent(model.provider_id)}/update`);
      await refresh();
    });
    const download = button(model.installed ? "Update" : "Download", async () => {
      await fetchJson(`/models/${encodeURIComponent(model.provider_id)}/download`, { method: "POST" });
      await refresh();
    });
    const remove = button("Delete", async () => {
      if (!confirm(`Delete local files for ${model.label}?`)) return;
      await fetchJson(`/models/${encodeURIComponent(model.provider_id)}`, { method: "DELETE" });
      await refresh();
    });
    remove.disabled = !model.installed || model.download_state === "queued" || model.download_state === "downloading";
    actions.append(status, update, download, remove);

    row.append(body, actions);
    return row;
  }));
}

function renderTranscripts(transcripts) {
  if (!transcripts.length) {
    nodes.transcriptList.replaceChildren(emptyState());
    return;
  }

  nodes.transcriptList.replaceChildren(...transcripts.map((item) => {
    const article = document.createElement("article");
    article.className = "transcript";

    const meta = document.createElement("div");
    meta.className = "transcript-meta";
    meta.append(
      span(formatTime(item.created_at)),
      span(item.source),
      span(item.provider || item.style || "engine"),
      span(item.duration_ms == null ? "" : `${item.duration_ms} ms`),
    );

    const text = item.cleaned_text || item.raw_text || "";
    const content = textBlock("p", "transcript-text", text);

    const actions = document.createElement("div");
    actions.className = "transcript-actions";
    actions.append(button("Copy", () => navigator.clipboard.writeText(text)));

    article.append(meta, content, actions);
    return article;
  }));
}

function renderEvents(events) {
  if (!events.length) {
    nodes.eventList.replaceChildren(emptyState());
    return;
  }

  nodes.eventList.replaceChildren(...events.map(logRow));
}

function logRow(event) {
  const row = document.createElement("article");
  row.className = "log-row";

  const meta = document.createElement("div");
  meta.className = "log-meta";
  meta.append(textBlock("span", `level-${event.level}`, event.level), textBlock("span", "", formatTime(event.timestamp)));

  const body = document.createElement("div");
  body.append(textBlock("strong", "", `${event.kind}: ${event.message}`));
  const detail = Object.keys(event.detail || {}).length ? JSON.stringify(event.detail, null, 2) : "";
  if (detail) {
    body.append(textBlock("code", "", detail));
  }

  row.append(meta, body);
  return row;
}

function copyLatestTranscript() {
  const latest = state.transcripts[0];
  if (!latest) return;
  navigator.clipboard.writeText(latest.cleaned_text || latest.raw_text || "");
}

function copyDiagnostics() {
  const payload = {
    status: state.status,
    latest_transcript: state.transcripts[0] || null,
    recent_events: state.events.slice(0, 20),
  };
  navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
}

async function startDesktopApp() {
  nodes.startDesktopApp.disabled = true;
  nodes.desktopAppLaunchStatus.textContent = "Starting";
  nodes.desktopAppLaunchStatus.className = "action-status";

  try {
    await fetchJson("/api/desktop-app/start", { method: "POST" });
    nodes.desktopAppLaunchStatus.textContent = "Launch requested";
    nodes.desktopAppLaunchStatus.className = "action-status success";
    await refresh();
  } catch (error) {
    nodes.desktopAppLaunchStatus.textContent = error.message;
    nodes.desktopAppLaunchStatus.className = "action-status error";
  } finally {
    nodes.startDesktopApp.disabled = false;
  }
}

function button(label, onClick) {
  const element = document.createElement("button");
  element.type = "button";
  element.textContent = label;
  element.addEventListener("click", async () => {
    element.disabled = true;
    try {
      await onClick();
    } finally {
      element.disabled = false;
    }
  });
  return element;
}

function textBlock(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  element.textContent = text;
  return element;
}

function span(text) {
  const element = document.createElement("span");
  element.textContent = text;
  return element;
}

function emptyState() {
  return nodes.emptyTemplate.content.firstElementChild.cloneNode(true);
}

function formatDuration(seconds) {
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  if (minutes > 0) return `${minutes}m ${seconds % 60}s`;
  return `${seconds}s`;
}

function formatBytes(value) {
  if (value >= 1_048_576) return `${(value / 1_048_576).toFixed(1)} MB`;
  if (value >= 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${value} B`;
}

function formatTime(value) {
  if (!value) return "";
  return new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit",
  }).format(new Date(value));
}
