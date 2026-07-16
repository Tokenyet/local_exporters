const MESSAGE_TYPE = "youtube-local-exporter";
const HOST_NAME = "com.dowen.youtube_local_exporter";
const SETTINGS_KEY = "youtubeLocalExporterSettings";
const JOBS_KEY = "youtubeLocalExporterJobs";

const DEFAULT_SETTINGS = {
  version: 2,
  outputDir: "",
  defaultMode: "video",
  defaultVideoQuality: "best",
  defaultAudioFormat: "m4a",
  defaultSubtitleFormat: "srt",
  defaultSubtitleLanguage: "zh",
  subtitleSource: "auto",
  forceWhisper: false,
  askOutputDirOnExport: true,
  useBrowserCookies: true,
  whisperModel: "small"
};

let nativePort = null;
let pendingRequests = new Map();

chrome.runtime.onInstalled.addListener(async () => {
  const existing = await chrome.storage.sync.get(SETTINGS_KEY);
  if (!existing[SETTINGS_KEY]) {
    await chrome.storage.sync.set({ [SETTINGS_KEY]: DEFAULT_SETTINGS });
  }
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== MESSAGE_TYPE) {
    return false;
  }

  handleRuntimeMessage(message, sender)
    .then((payload) => sendResponse({ ok: true, ...payload }))
    .catch((error) => sendResponse({ ok: false, error: error.message || String(error) }));
  return true;
});

async function handleRuntimeMessage(message) {
  switch (message.action) {
    case "getSettings":
      return { settings: await loadSettings() };
    case "saveSettings":
      return { settings: await saveSettings(message.settings) };
    case "getPageInfo":
      return { page: await getCurrentPageInfo() };
    case "openOptions":
      await chrome.runtime.openOptionsPage();
      return {};
    case "ping":
      return { response: await sendNative({ action: "ping" }, 15000) };
    case "probe":
      return { response: await probeWithCookies(message.url) };
    case "export":
      return { response: await startExport(message.request) };
    case "jobStatus":
      return { response: await getJobStatus(message.jobId) };
    case "getRecentJobs":
      return { jobs: await getRecentJobs(message.limit || 5) };
    case "cancelJob":
      return { response: await cancelJob(message.jobId) };
    case "openOutputFolder":
      return { response: await sendNative({ action: "openOutputFolder", path: message.path }, 15000) };
    case "chooseOutputFolder":
      return { response: await sendNative({ action: "chooseOutputFolder", initialDir: message.initialDir || "" }, 300000) };
    case "updateTools":
      return { response: await sendNative({ action: "updateTools" }, 15000) };
    case "pageUpdated":
      await chrome.storage.session?.set?.({ currentPage: message.page });
      return {};
    default:
      throw new Error(`Unknown action: ${message.action}`);
  }
}

async function startExport(request) {
  const settings = await loadSettings();
  const requestWithCookies = {
    ...(request || {}),
    cookies: await collectBrowserCookies(settings)
  };
  const response = await sendNative({ action: "export", request: requestWithCookies }, 15000);
  if (response.jobId) {
    await persistJobEvent({
      jobId: response.jobId,
      kind: requestWithCookies?.kind || "",
      event: "queued",
      percent: 0,
      detail: "Queued",
      request: buildStoredJobRequest(requestWithCookies)
    });
  }
  return response;
}

async function probeWithCookies(url) {
  const settings = await loadSettings();
  return sendNative({
    action: "probe",
    url,
    cookies: await collectBrowserCookies(settings)
  }, 90000);
}

async function getJobStatus(jobId) {
  const response = await sendNative({ action: "jobStatus", jobId }, 15000);
  if (response.job) {
    await persistJobEvent(response.job);
  }
  return response;
}

async function cancelJob(jobId) {
  const response = await sendNative({ action: "cancelJob", jobId }, 15000);
  if (response.job) {
    await persistJobEvent(response.job);
  }
  return response;
}

async function loadSettings() {
  const result = await chrome.storage.sync.get({ [SETTINGS_KEY]: DEFAULT_SETTINGS });
  return normalizeSettings(result[SETTINGS_KEY]);
}

async function saveSettings(nextSettings) {
  const settings = normalizeSettings(nextSettings);
  await chrome.storage.sync.set({ [SETTINGS_KEY]: settings });
  return settings;
}

function normalizeSettings(value) {
  const source = value && typeof value === "object" ? value : {};
  const storedVersion = Number(source.version) || 0;
  const defaultSubtitleLanguage = storedVersion < 2 && source.defaultSubtitleLanguage === "auto" ?
    DEFAULT_SETTINGS.defaultSubtitleLanguage :
    String(source.defaultSubtitleLanguage || DEFAULT_SETTINGS.defaultSubtitleLanguage);
  return {
    ...DEFAULT_SETTINGS,
    ...source,
    outputDir: String(source.outputDir || ""),
    defaultMode: normalizeChoice(source.defaultMode, ["video", "audio", "subtitles"], DEFAULT_SETTINGS.defaultMode),
    defaultVideoQuality: String(source.defaultVideoQuality || DEFAULT_SETTINGS.defaultVideoQuality),
    defaultAudioFormat: normalizeChoice(source.defaultAudioFormat, ["best", "m4a", "mp3", "wav", "opus"], DEFAULT_SETTINGS.defaultAudioFormat),
    defaultSubtitleFormat: normalizeChoice(source.defaultSubtitleFormat, ["srt", "vtt"], DEFAULT_SETTINGS.defaultSubtitleFormat),
    defaultSubtitleLanguage,
    subtitleSource: normalizeChoice(source.subtitleSource, ["auto", "youtube", "whisper"], DEFAULT_SETTINGS.subtitleSource),
    forceWhisper: Boolean(source.forceWhisper),
    askOutputDirOnExport: source.askOutputDirOnExport !== false,
    useBrowserCookies: source.useBrowserCookies !== false,
    whisperModel: normalizeChoice(source.whisperModel, ["tiny", "base", "small", "medium", "large"], DEFAULT_SETTINGS.whisperModel),
    version: 2
  };
}

function normalizeChoice(value, choices, fallback) {
  return choices.includes(value) ? value : fallback;
}

async function getCurrentPageInfo() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) {
    throw new Error("No active tab");
  }

  try {
    const response = await chrome.tabs.sendMessage(tab.id, { type: MESSAGE_TYPE, action: "getPageInfo" });
    if (response?.ok && response.page) {
      return response.page;
    }
  } catch {
    // Content script may not be available on non-YouTube pages.
  }

  return buildPageInfoFromTab(tab);
}

function buildPageInfoFromTab(tab) {
  try {
    const url = new URL(tab.url || "");
    const videoId = url.hostname === "youtu.be" ?
      url.pathname.split("/").filter(Boolean)[0] :
      (url.pathname.startsWith("/shorts/") ? url.pathname.split("/").filter(Boolean)[1] : url.searchParams.get("v"));

    return {
      url: videoId ? `https://www.youtube.com/watch?v=${videoId}` : (tab.url || ""),
      rawUrl: tab.url || "",
      videoId: videoId || "",
      title: (tab.title || "").replace(/\s+-\s+YouTube$/, ""),
      supported: Boolean(videoId),
      host: url.hostname,
      pageType: url.pathname.startsWith("/shorts/") ? "shorts" : (videoId ? "watch" : "other")
    };
  } catch {
    return {
      url: tab.url || "",
      rawUrl: tab.url || "",
      videoId: "",
      title: tab.title || "",
      supported: false,
      host: "",
      pageType: "other"
    };
  }
}

function getNativePort() {
  if (nativePort) {
    return nativePort;
  }

  nativePort = chrome.runtime.connectNative(HOST_NAME);
  nativePort.onMessage.addListener(handleNativeMessage);
  nativePort.onDisconnect.addListener(handleNativeDisconnect);
  return nativePort;
}

function sendNative(payload, timeoutMs) {
  const id = createRequestId();
  const message = { id, ...payload };

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pendingRequests.delete(id);
      reject(new Error("Native host did not respond in time"));
    }, timeoutMs);

    pendingRequests.set(id, { resolve, reject, timeout });

    try {
      getNativePort().postMessage(message);
    } catch (error) {
      clearTimeout(timeout);
      pendingRequests.delete(id);
      reject(error);
    }
  });
}

function handleNativeMessage(message) {
  if (message?.id && pendingRequests.has(message.id)) {
    const pending = pendingRequests.get(message.id);
    clearTimeout(pending.timeout);
    pendingRequests.delete(message.id);
    if (message.ok === false) {
      pending.reject(new Error(message.error || "Native host request failed"));
      return;
    }
    pending.resolve(message);
    return;
  }

  if (message?.event && message.jobId) {
    persistJobEvent(message);
    try {
      chrome.runtime.sendMessage({ type: MESSAGE_TYPE, action: "jobEvent", event: message });
    } catch {
      // No visible extension page is listening.
    }
  }
}

async function persistJobEvent(event) {
  const result = await chrome.storage.local.get({ [JOBS_KEY]: {} });
  const jobs = result[JOBS_KEY] && typeof result[JOBS_KEY] === "object" ? result[JOBS_KEY] : {};
  jobs[event.jobId] = {
    ...(jobs[event.jobId] || {}),
    ...event,
    updatedAt: Date.now()
  };
  await chrome.storage.local.set({ [JOBS_KEY]: jobs });
}

async function getRecentJobs(limit) {
  const result = await chrome.storage.local.get({ [JOBS_KEY]: {} });
  const jobs = result[JOBS_KEY] && typeof result[JOBS_KEY] === "object" ? result[JOBS_KEY] : {};
  return Object.values(jobs)
    .filter((job) => job && typeof job === "object" && job.jobId)
    .sort((left, right) => (right.updatedAt || 0) - (left.updatedAt || 0))
    .slice(0, Math.max(1, Math.min(20, Number(limit) || 5)));
}

function buildStoredJobRequest(request) {
  const source = request && typeof request === "object" ? request : {};
  return {
    kind: String(source.kind || ""),
    url: String(source.url || ""),
    title: String(source.title || ""),
    videoId: String(source.videoId || ""),
    quality: String(source.quality || ""),
    audioFormat: String(source.audioFormat || ""),
    outputDir: String(source.outputDir || ""),
    subtitles: source.subtitles && typeof source.subtitles === "object" ? {
      language: String(source.subtitles.language || ""),
      format: String(source.subtitles.format || ""),
      source: String(source.subtitles.source || "")
    } : null
  };
}

async function collectBrowserCookies(settings) {
  if (settings?.useBrowserCookies === false || !chrome.cookies?.getAll) {
    return [];
  }

  const domains = ["youtube.com", ".youtube.com", "google.com", ".google.com"];
  const byKey = new Map();
  for (const domain of domains) {
    try {
      const cookies = await chrome.cookies.getAll({ domain });
      for (const cookie of cookies) {
        if (!isYoutubeAuthRelatedCookie(cookie)) {
          continue;
        }
        byKey.set(`${cookie.domain}\t${cookie.path}\t${cookie.name}`, {
          domain: cookie.domain,
          hostOnly: Boolean(cookie.hostOnly),
          path: cookie.path || "/",
          secure: Boolean(cookie.secure),
          httpOnly: Boolean(cookie.httpOnly),
          expirationDate: Number(cookie.expirationDate) || 0,
          name: cookie.name,
          value: cookie.value
        });
      }
    } catch {
      // Some browsers require narrower host grants; missing cookies should not block all exports.
    }
  }
  return Array.from(byKey.values());
}

function isYoutubeAuthRelatedCookie(cookie) {
  const domain = String(cookie.domain || "").toLowerCase();
  return Boolean(
    cookie.name &&
    typeof cookie.value === "string" &&
    (domain.endsWith("youtube.com") || domain.endsWith("google.com"))
  );
}

function handleNativeDisconnect() {
  const error = chrome.runtime.lastError?.message || "Native host disconnected";
  for (const pending of pendingRequests.values()) {
    clearTimeout(pending.timeout);
    pending.reject(new Error(error));
  }
  pendingRequests = new Map();
  nativePort = null;
}

function createRequestId() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}
