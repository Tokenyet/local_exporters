(function () {
  "use strict";

  const storageKey = "local-exporters-language";
  const traditionalChineseLocales = ["zh-tw", "zh-hk", "zh-mo", "zh-hant"];
  const url = new URL(window.location.href);
  const requestedLanguage = url.searchParams.get("lang");
  const isTraditionalChinesePage = url.pathname.includes("/zh-TW/");

  function normalizeLanguage(value) {
    if (!value) {
      return null;
    }
    const normalized = value.toLowerCase();
    return normalized === "zh-tw" || normalized === "zh-hant" ? "zh-TW" : normalized === "en" ? "en" : null;
  }

  function preferredBrowserLanguage() {
    const languages = navigator.languages && navigator.languages.length
      ? navigator.languages
      : [navigator.language];
    const wantsTraditionalChinese = languages.some((language) => {
      const normalized = String(language || "").toLowerCase();
      return traditionalChineseLocales.some((locale) => normalized === locale || normalized.startsWith(`${locale}-`));
    });
    return wantsTraditionalChinese ? "zh-TW" : "en";
  }

  function localizedPath(language) {
    const path = url.pathname;
    if (language === "zh-TW") {
      if (isTraditionalChinesePage) {
        return path;
      }
      if (path.endsWith("/")) {
        return `${path}zh-TW/`;
      }
      const separator = path.lastIndexOf("/");
      return `${path.slice(0, separator)}/zh-TW${path.slice(separator)}`;
    }
    return path.replace("/zh-TW/", "/");
  }

  function redirectTo(language) {
    const target = new URL(window.location.href);
    target.pathname = localizedPath(language);
    target.searchParams.delete("lang");
    window.location.replace(target.href);
  }

  const explicitLanguage = normalizeLanguage(requestedLanguage);
  if (explicitLanguage) {
    try {
      localStorage.setItem(storageKey, explicitLanguage);
    } catch {
      // Language selection still works when storage is unavailable.
    }
    url.searchParams.delete("lang");
    window.history.replaceState(null, "", `${url.pathname}${url.search}${url.hash}`);
    if ((explicitLanguage === "zh-TW") !== isTraditionalChinesePage) {
      redirectTo(explicitLanguage);
      return;
    }
  }

  let savedLanguage = null;
  try {
    savedLanguage = normalizeLanguage(localStorage.getItem(storageKey));
  } catch {
    // Fall back to browser language detection.
  }

  if (savedLanguage && (savedLanguage === "zh-TW") !== isTraditionalChinesePage) {
    redirectTo(savedLanguage);
    return;
  }

  if (!savedLanguage && !isTraditionalChinesePage && preferredBrowserLanguage() === "zh-TW") {
    redirectTo("zh-TW");
  }
})();
