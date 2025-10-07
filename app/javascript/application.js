const walkButtonLabel = {
  idle: "1 Walk",
  loading: "Walking..."
};

const SEARCH_ENDPOINT = "/search_walk";
const PREVIEW_ENDPOINT = "/preview";
const STOP_WORDS = new Set([
  "the", "and", "that", "have", "this", "with", "from", "your", "about", "would",
  "there", "their", "what", "when", "where", "which", "will", "shall", "been",
  "upon", "into", "also", "such", "than", "like", "some", "most", "other", "more",
  "over", "after", "before", "because", "while", "those", "these", "each", "many",
  "much", "very", "com", "net", "org", "www", "http", "https"
]);

document.addEventListener("DOMContentLoaded", () => {
  const frame = document.getElementById("walker-frame");
  const nextButton = document.getElementById("walker-next");
  const backButton = document.getElementById("walker-back");
  const stopButton = document.getElementById("walker-stop");
  const searchButton = document.getElementById("walker-search");
  const status = document.getElementById("walker-status");
  const historyList = document.getElementById("walker-history-list");
  const autoButton = document.getElementById("walker-auto");
  const startForm = document.getElementById("walker-start-form");
  const startInput = document.getElementById("walker-start-url");
  const currentUrlValue = document.getElementById("walker-current-url");
  const DEFAULT_CURRENT_URL_TEXT = "No page loaded.";
  let defaultUrl = frame?.dataset?.defaultUrl || null;
  const AUTO_INTERVAL = 5000;
  const SEARCH_AUTO_INTERVAL = 5000;
  let autoTimer = null;
  let searchAutoTimer = null;
  let isLoading = false;
  let manualLabelActive = false;
  let failureStreak = 0;

  if (!frame || !nextButton || !historyList || !status || !autoButton || !stopButton || !searchButton) {
    return;
  }

  frame.removeAttribute("src");
  frame.srcdoc = "";

  const history = [];
  let position = -1;

  const currentEntry = () => {
    if (position < 0 || position >= history.length) {
      return null;
    }

    return history[position];
  };

  const annotateHistoryError = (index, message) => {
    if (index < 0 || index >= history.length) {
      return;
    }

    history[index] = { ...history[index], error: message };
    renderHistory();
  };

  const setStatus = (message = "", { type = null } = {}) => {
    status.textContent = message;
    status.classList.remove("is-success", "is-error");

    if (!message) {
      return;
    }

    if (type === "success") {
      status.classList.add("is-success");
    } else if (type === "error") {
      status.classList.add("is-error");
    }
  };

  const renderHistory = () => {
    historyList.innerHTML = "";

    history.forEach((entry, index) => {
      const item = document.createElement("li");
      item.className = "walker-history-list-item";
      if (index === position) {
        item.classList.add("is-current");
      }

      const anchor = document.createElement("a");
      anchor.href = entry.url;
      anchor.textContent = entry.label || entry.url;
      anchor.target = "_blank";
      anchor.rel = "noopener noreferrer";

      item.appendChild(anchor);

      if (entry.error) {
        const errorText = document.createElement("span");
        errorText.className = "walker-history-error";
        errorText.textContent = ` — ${entry.error}`;
        item.appendChild(errorText);
      }

      historyList.appendChild(item);
    });
  };

  const updateControls = () => {
    if (backButton) {
      backButton.disabled = position <= 0;
    }

    stopButton.disabled = !autoTimer && !searchAutoTimer;
    searchButton.disabled = isLoading;
    if (searchAutoTimer) {
      searchButton.classList.add("is-active");
      searchButton.setAttribute("aria-pressed", "true");
    } else {
      searchButton.classList.remove("is-active");
      searchButton.setAttribute("aria-pressed", "false");
    }
  };

  const updateCurrentUrlDisplay = () => {
    if (!currentUrlValue) {
      return;
    }

    const activeEntry = currentEntry();
    if (activeEntry && activeEntry.url) {
      currentUrlValue.textContent = activeEntry.url;
      return;
    }

    if (defaultUrl) {
      currentUrlValue.textContent = defaultUrl;
      return;
    }

    currentUrlValue.textContent = DEFAULT_CURRENT_URL_TEXT;
  };

  const clearHistory = () => {
    history.length = 0;
    position = -1;
    frame.removeAttribute("src");
    frame.srcdoc = "";
    renderHistory();
    updateControls();
    updateCurrentUrlDisplay();
  };

  const goBack = () => {
    if (position <= 0) {
      return false;
    }

    position -= 1;
    showCurrentEntry();
    return true;
  };

  const stopAuto = ({ silent = false } = {}) => {
    let stopped = false;

    if (autoTimer) {
      clearInterval(autoTimer);
      autoTimer = null;
      autoButton.classList.remove("is-active");
      autoButton.setAttribute("aria-pressed", "false");
      stopped = true;
    }

    updateControls();

    if (stopped && !silent) {
      setStatus("Auto walk stopped.", { type: "success" });
    }

    return stopped;
  };

  const startAuto = () => {
    if (autoTimer) {
      return;
    }

    stopSearchAuto({ silent: true });

    if (!currentUrl()) {
      setStatus("Set a start URL first.", { type: "error" });
      return;
    }

    autoButton.classList.add("is-active");
    autoButton.setAttribute("aria-pressed", "true");
    setStatus("Auto walk started.", { type: "success" });

    autoTimer = setInterval(() => {
      performStep({ preserveStatus: true, updateLabel: false });
    }, AUTO_INTERVAL);

    updateControls();
    performStep({ preserveStatus: true, updateLabel: false });
  };

  const normalizeEntry = ({ url, label, html, error }) => {
    if (!url) {
      throw new Error("Missing URL.");
    }

    const normalizedUrl = new URL(url).toString();
    const trimmedLabel = label ? label.replace(/\s+/g, " ").trim() : "";
    const finalLabel = trimmedLabel || normalizedUrl;

    return {
      url: normalizedUrl,
      label: finalLabel,
      html: typeof html === "string" ? html : "",
      error: error || ""
    };
  };

  const showCurrentEntry = () => {
    if (position < 0 || position >= history.length) {
      return;
    }

    frame.removeAttribute("src");
    frame.srcdoc = history[position].html || "";
    renderHistory();
    updateControls();
    updateCurrentUrlDisplay();
  };

  const pushEntry = (entry) => {
    const insertAt = position + 1;

    if (insertAt < history.length) {
      const tail = history.splice(insertAt);
      const retained = tail.filter((item) => item && item.error);
      if (retained.length) {
        history.push(...retained);
      }
    }

    history.push(entry);
    position = history.length - 1;
  };

  const navigateTo = (
    entryData,
    { pushHistory = true, allowDuplicate = true, silenceErrors = false } = {}
  ) => {
    try {
      const entry = normalizeEntry(entryData);

      if (!entry.html) {
        throw new Error("No preview available for this page.");
      }

      if (!allowDuplicate) {
        const activeUrl = currentEntry()?.url || null;
        if (activeUrl && entry.url === activeUrl) {
          const message = "Search result matches the current page.";
          if (!silenceErrors) {
            setStatus(message, { type: "error" });
          }
          return { ok: false, error: new Error(message) };
        }
      }

      if (pushHistory) {
        pushEntry(entry);
      }

      showCurrentEntry();
      return { ok: true, entry };
    } catch (error) {
      if (!silenceErrors) {
        setStatus(error.message || "Received an invalid URL.", { type: "error" });
      }
      return { ok: false, error };
    }
  };

  const setLoading = (loading, { updateLabel = true } = {}) => {
    isLoading = loading;
    nextButton.disabled = loading;

    if (loading && updateLabel) {
      nextButton.textContent = walkButtonLabel.loading;
      manualLabelActive = true;
    } else if (!loading && (updateLabel || manualLabelActive)) {
      nextButton.textContent = walkButtonLabel.idle;
      manualLabelActive = false;
    }

    updateControls();
  };

  const currentUrl = () => {
    const entry = currentEntry();
    if (entry && entry.url) {
      return entry.url;
    }

    return defaultUrl;
  };

  const performStep = async ({ preserveStatus = false, updateLabel = true } = {}) => {
    if (isLoading) {
      return;
    }

    if (!preserveStatus) {
      setStatus("");
    }

    setLoading(true, { updateLabel });

    let lastPayload = null;

    try {
      const url = currentUrl();
      const endpoint = url ? `/walk?url=${encodeURIComponent(url)}` : "/walk";
      const response = await fetch(endpoint, {
        headers: { Accept: "application/json" }
      });

      let payload = {};
      let bodyText = "";

      try {
        bodyText = await response.text();
        payload = bodyText ? JSON.parse(bodyText) : {};
      } catch (parseError) {
        payload = {};
      }

      lastPayload = payload;

      if (!response.ok) {
        throw new Error(payload.error || "Unable to walk right now.");
      }

      if (!payload.url) {
        throw new Error("No URL returned by server.");
      }

      const statusWasError = status.classList.contains("is-error");

      navigateTo(
        {
          url: payload.url,
          label: payload.label,
          html: payload.html
        },
        { pushHistory: true }
      );

      failureStreak = 0;

      if (!preserveStatus || statusWasError) {
        setStatus("Found a new page!", { type: "success" });
      }
    } catch (error) {
      const payload = lastPayload || {};
      const message = error.message || payload.error || "Failed to fetch next page.";
      const unsafeReasons = Array.isArray(payload.reasons) ? payload.reasons : [];
      const isUnsafe = Boolean(payload.unsafe) || /blocked unsafe url/i.test(message);

      if (isUnsafe) {
        const detail = unsafeReasons.length ? unsafeReasons.join("; ") : null;
        const statusMessage = detail
          ? `Safety filter blocked navigation: ${detail}`
          : message;

        annotateHistoryError(position, statusMessage);
        stopAuto({ silent: true });
        stopSearchAuto({ silent: true });
        setStatus(statusMessage, { type: "error" });
        return;
      }

      if (/no navigable links found/i.test(message)) {
        const problematicIndex = position;
        const movedBack = goBack();
        const infoMessage = movedBack
          ? "No links here. Returned to a previous page."
          : "No links found on the current page.";

        failureStreak += 1;
        annotateHistoryError(problematicIndex, infoMessage);
        setStatus(infoMessage, { type: "error" });

        if (failureStreak >= 5) {
          const skipped = goBack();
          if (skipped) {
            annotateHistoryError(position + 1, "Skipping page after repeated failures.");
            failureStreak = 0;
          }
        }

        if (autoTimer && movedBack) {
          setTimeout(() => {
            performStep({ preserveStatus: true });
          }, 10);
        } else if (autoTimer) {
          stopAuto({ silent: true });
        }
      } else {
        failureStreak += 1;
        setStatus(message, { type: "error" });
        annotateHistoryError(position, message);
      }
    } finally {
      setLoading(false, { updateLabel });
    }
  };

  const stopSearchAuto = ({ silent = false } = {}) => {
    if (!searchAutoTimer) {
      return false;
    }

    clearInterval(searchAutoTimer);
    searchAutoTimer = null;
    updateControls();
    if (!silent) {
      setStatus("Search walk stopped.", { type: "success" });
    }

    return true;
  };

  const startSearchAuto = () => {
    if (searchAutoTimer) {
      return;
    }

    stopAuto({ silent: true });

    const term = extractSearchTerm();
    if (!term) {
      setStatus("No suitable words found for search.", { type: "error" });
      return;
    }

    setStatus(`Auto searching (starting with "${term}")`, { type: "success" });
    performSearchWalk({ presetTerm: term, preserveStatus: true });

    searchAutoTimer = setInterval(() => {
      performSearchWalk({ preserveStatus: true });
    }, SEARCH_AUTO_INTERVAL);

    updateControls();
  };

  const toggleSearchAuto = () => {
    if (searchAutoTimer) {
      stopSearchAuto();
    } else {
      startSearchAuto();
    }
  };

  const pickRandom = (values) => {
    if (!values.length) {
      return null;
    }

    const unique = Array.from(new Set(values));
    const index = Math.floor(Math.random() * unique.length);
    return unique[index];
  };

  const collectSearchTerms = () => {
    const entry = currentEntry();
    let text = "";

    if (entry?.html) {
      try {
        const parser = new DOMParser();
        const parsed = parser.parseFromString(entry.html, "text/html");
        text = parsed?.body?.innerText || "";
      } catch (error) {
        text = "";
      }
    }

    if (!text) {
      const doc = frame?.contentDocument;
      text = doc?.body?.innerText || "";
    }

    const englishMatches = text.match(/[A-Za-z][A-Za-z\-]{2,}/g) || [];
    const unicodeMatches = text.match(/\p{L}{2,}/gu) || [];

    const normalizedEnglish = englishMatches
      .map((word) => word.replace(/[^A-Za-z]/g, "").toLowerCase())
      .filter((word) => word.length >= 3 && !STOP_WORDS.has(word));

    const normalizedUnicode = unicodeMatches
      .map((word) => word.replace(/[^\p{L}]/gu, ""))
      .filter((word) => word.length >= 2);

    return Array.from(new Set([...normalizedEnglish, ...normalizedUnicode]));
  };

  const extractSearchTerm = ({ exclude = [] } = {}) => {
    const excluded = new Set(exclude);
    const candidates = collectSearchTerms().filter((term) => !excluded.has(term));
    return pickRandom(candidates);
  };

  const performSearchWalk = async ({ presetTerm = null, preserveStatus = false } = {}) => {
    if (isLoading) {
      return;
    }

    const collectedTerms = collectSearchTerms();
    const availableTerms = presetTerm
      ? Array.from(new Set([presetTerm, ...collectedTerms]))
      : collectedTerms.slice();

    if (!availableTerms.length) {
      setStatus("No suitable words found for search.", { type: "error" });
      stopSearchAuto({ silent: true });
      return;
    }

    const triedTerms = new Set();
    const pickNextTerm = () => {
      const remaining = availableTerms.filter((term) => !triedTerms.has(term));
      if (!remaining.length) {
        return null;
      }

      if (presetTerm && remaining.includes(presetTerm)) {
        return presetTerm;
      }

      return pickRandom(remaining);
    };

    let currentTerm = pickNextTerm();
    if (!currentTerm) {
      setStatus("No suitable words found for search.", { type: "error" });
      stopSearchAuto({ silent: true });
      return;
    }

    let success = false;
    let finalErrorMessage = "";
    let unsafeHandled = false;
    let lastPayload = null;

    setLoading(true, { updateLabel: false });
    searchButton.disabled = true;

    try {
      while (currentTerm) {
        triedTerms.add(currentTerm);
        setStatus(`Searching for "${currentTerm}"...`);

        lastPayload = null;

        try {
          const response = await fetch(`${SEARCH_ENDPOINT}?q=${encodeURIComponent(currentTerm)}`, {
            headers: { Accept: "application/json" }
          });

          let payload = {};
          try {
            const bodyText = await response.text();
            payload = bodyText ? JSON.parse(bodyText) : {};
          } catch (parseError) {
            payload = {};
          }

          lastPayload = payload;

          if (!response.ok) {
            throw new Error(payload.error || "Search failed.");
          }

          if (!payload.url) {
            throw new Error("Search did not return a URL.");
          }

          const navigation = navigateTo(
            {
              url: payload.url,
              label: payload.label,
              html: payload.html
            },
            { pushHistory: true, allowDuplicate: false, silenceErrors: true }
          );

          if (navigation.ok) {
            setStatus(`Visited result for "${currentTerm}"`, { type: "success" });
            success = true;
            break;
          }

          finalErrorMessage = navigation.error?.message || "Search result could not be displayed.";

          const nextTerm = pickNextTerm();
          if (!nextTerm) {
            break;
          }

          currentTerm = nextTerm;
          continue;
        } catch (error) {
          const payload = lastPayload || {};
          const message = error.message || payload.error || "Search walk failed.";
          const unsafeReasons = Array.isArray(payload.reasons) ? payload.reasons : [];
          const isUnsafe = Boolean(payload.unsafe) || /blocked unsafe url/i.test(message);

          if (isUnsafe) {
            const detail = unsafeReasons.length ? unsafeReasons.join("; ") : null;
            const statusMessage = detail
              ? `Safety filter blocked search result: ${detail}`
              : message;

            annotateHistoryError(position, statusMessage);
            stopAuto({ silent: true });
            stopSearchAuto({ silent: true });
            setStatus(statusMessage, { type: "error" });
            unsafeHandled = true;
            break;
          }

          finalErrorMessage = message;

          const nextTerm = pickNextTerm();
          if (!nextTerm) {
            break;
          }

          currentTerm = nextTerm;
        }
      }
    } finally {
      searchButton.disabled = false;
      setLoading(false, { updateLabel: false });
    }

    if (!success && !unsafeHandled) {
      if (!finalErrorMessage) {
        finalErrorMessage = "Search walk failed.";
      }

      annotateHistoryError(position, finalErrorMessage);
      stopSearchAuto({ silent: true });
      setStatus(finalErrorMessage, { type: "error" });
    }
  };

  const loadPreview = async (url) => {
    setLoading(true, { updateLabel: false });

    let payload = {};

    try {
      const response = await fetch(`${PREVIEW_ENDPOINT}?url=${encodeURIComponent(url)}`, {
        headers: { Accept: "application/json" }
      });

      try {
        const bodyText = await response.text();
        payload = bodyText ? JSON.parse(bodyText) : {};
      } catch (parseError) {
        payload = {};
      }

      if (!response.ok) {
        throw new Error(payload.error || "Failed to load start URL.");
      }

      if (!payload.html) {
        throw new Error("No preview available for this page.");
      }

      navigateTo(
        {
          url: payload.url || url,
          label: payload.label || payload.url || url,
          html: payload.html
        },
        { pushHistory: true }
      );

      failureStreak = 0;
      setStatus("Start URL loaded.", { type: "success" });
    } catch (error) {
      const reasons = Array.isArray(payload.reasons) ? payload.reasons : [];
      const message = error.message || "Failed to load start URL.";
      const isUnsafe = Boolean(payload.unsafe);

      if (isUnsafe) {
        const detail = reasons.length ? reasons.join("; ") : null;
        const statusMessage = detail
          ? `Safety filter blocked start URL: ${detail}`
          : message;

        stopAuto({ silent: true });
        stopSearchAuto({ silent: true });
        setStatus(statusMessage, { type: "error" });
      } else {
        setStatus(message, { type: "error" });
      }
    } finally {
      setLoading(false, { updateLabel: false });
    }
  };

  nextButton.addEventListener("click", () => {
    performStep();
  });

  if (backButton) {
    backButton.addEventListener("click", () => {
      if (position <= 0) {
        return;
      }

      goBack();
      setStatus("Returned to a previous page.", { type: "success" });
    });
  }

  const initial = frame.getAttribute("src");
  if (initial && initial !== "about:blank") {
    try {
      pushEntry(normalizeEntry({ url: initial }));
      showCurrentEntry();
    } catch (error) {
      setStatus("Failed to initialize walker.", { type: "error" });
    }
  }

  if (startForm && startInput) {
    startForm.addEventListener("submit", (event) => {
      event.preventDefault();

      const rawValue = startInput.value.trim();

      try {
        if (!rawValue) {
          throw new Error("URL is required.");
        }

        const normalized = new URL(rawValue).toString();
        if (!/^https?:/i.test(normalized)) {
          throw new Error("Only http/https URLs are supported.");
        }

        defaultUrl = normalized;
        startInput.value = normalized;
        frame.dataset.defaultUrl = normalized;
        clearHistory();
        stopAuto({ silent: true });
        stopSearchAuto({ silent: true });
        setStatus("Loading start URL...");
        loadPreview(normalized);
      } catch (error) {
        setStatus(error.message || "Invalid start URL.", { type: "error" });
      }
    });
  }

  autoButton.addEventListener("click", () => {
    if (autoTimer) {
      stopAuto();
    } else {
      startAuto();
    }
  });

  stopButton.addEventListener("click", () => {
    const stoppedLink = stopAuto({ silent: true });
    const stoppedSearch = stopSearchAuto({ silent: true });

    if (stoppedLink || stoppedSearch) {
      setStatus("Stopped.", { type: "success" });
    }
  });

  searchButton.addEventListener("click", () => {
    toggleSearchAuto();
  });

  window.addEventListener("beforeunload", () => {
    stopAuto({ silent: true });
    stopSearchAuto({ silent: true });
  });

  nextButton.textContent = walkButtonLabel.idle;
  updateControls();
  updateCurrentUrlDisplay();
  setStatus(status.textContent.trim());
});
