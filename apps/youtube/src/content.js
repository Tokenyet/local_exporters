(() => {
  const MESSAGE_TYPE = "youtube-local-exporter";
  let lastUrl = location.href;

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || message.type !== MESSAGE_TYPE) {
      return false;
    }

    if (message.action === "getPageInfo") {
      sendResponse({ ok: true, page: getPageInfo() });
      return true;
    }

    return false;
  });

  window.setInterval(() => {
    if (location.href === lastUrl) {
      return;
    }
    lastUrl = location.href;
    try {
      chrome.runtime.sendMessage({
        type: MESSAGE_TYPE,
        action: "pageUpdated",
        page: getPageInfo()
      });
    } catch {
      // The popup/background may be asleep; the next popup open will query again.
    }
  }, 1000);

  function getPageInfo() {
    const url = new URL(location.href);
    const videoId = getVideoId(url);
    const title = getVideoTitle();

    return {
      url: normalizeWatchUrl(url, videoId),
      rawUrl: location.href,
      videoId,
      title,
      supported: Boolean(videoId),
      host: url.hostname,
      pageType: getPageType(url)
    };
  }

  function getVideoId(url) {
    if (url.hostname === "youtu.be") {
      return cleanVideoId(url.pathname.split("/").filter(Boolean)[0]);
    }

    if (url.pathname.startsWith("/shorts/")) {
      return cleanVideoId(url.pathname.split("/").filter(Boolean)[1]);
    }

    return cleanVideoId(url.searchParams.get("v"));
  }

  function cleanVideoId(value) {
    const text = String(value || "").trim();
    return /^[a-zA-Z0-9_-]{6,20}$/.test(text) ? text : "";
  }

  function normalizeWatchUrl(url, videoId) {
    if (!videoId) {
      return location.href;
    }
    return `https://www.youtube.com/watch?v=${videoId}`;
  }

  function getPageType(url) {
    if (url.pathname.startsWith("/shorts/")) {
      return "shorts";
    }
    if (url.searchParams.has("v")) {
      return "watch";
    }
    return "other";
  }

  function getVideoTitle() {
    const selectors = [
      "h1.ytd-watch-metadata yt-formatted-string",
      "h1.title yt-formatted-string",
      "yt-formatted-string.ytd-watch-metadata",
      "title"
    ];

    for (const selector of selectors) {
      const element = document.querySelector(selector);
      const text = element?.textContent?.trim();
      if (text) {
        return text.replace(/\s+-\s+YouTube$/, "").trim();
      }
    }

    return document.title.replace(/\s+-\s+YouTube$/, "").trim();
  }
})();
