const walkButtonLabel = {
  idle: "1 Walk",
  loading: "Walking..."
};

document.addEventListener("DOMContentLoaded", () => {
  const frame = document.getElementById("walker-frame");
  const nextButton = document.getElementById("walker-next");
  const backButton = document.getElementById("walker-back");
  const stopButton = document.getElementById("walker-stop");
  const status = document.getElementById("walker-status");
  const historyList = document.getElementById("walker-history-list");
  const autoButton = document.getElementById("walker-auto");
  const startForm = document.getElementById("walker-start-form");
  const startInput = document.getElementById("walker-start-url");
  const currentUrlValue = document.getElementById("walker-current-url");
  const DEFAULT_CURRENT_URL_TEXT = "No page loaded.";
  let defaultUrl = frame?.dataset?.defaultUrl || null;
  const AUTO_INTERVAL = 5000;
  let autoTimer = null;
  let isLoading = false;
  let failureStreak = 0;

  if (!frame || !nextButton || !historyList || !status || !autoButton || !stopButton) {
    return;
  }

  frame.removeAttribute("src");
  frame.srcdoc = "";

  const history = [];
  let position = -1;

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

    stopButton.disabled = !autoTimer;
  };

  const updateCurrentUrlDisplay = () => {
    if (!currentUrlValue) {
      return;
    }

    const activeEntry = position >= 0 ? history[position] : null;
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
    if (!autoTimer) {
      return;
    }

    clearInterval(autoTimer);
    autoTimer = null;
    autoButton.classList.remove("is-active");
    autoButton.setAttribute("aria-pressed", "false");
    updateControls();
    if (!silent) {
      setStatus("Auto walk stopped.", { type: "success" });
    }
  };

  const startAuto = () => {
    if (autoTimer) {
      return;
    }

    if (!currentUrl()) {
      setStatus("Set a start URL first.", { type: "error" });
      return;
    }

    autoButton.classList.add("is-active");
    autoButton.setAttribute("aria-pressed", "true");
    setStatus("Auto walk started.", { type: "success" });

    autoTimer = setInterval(() => {
      performStep({ preserveStatus: true });
    }, AUTO_INTERVAL);

    updateControls();
    performStep({ preserveStatus: true });
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

  const navigateTo = (entryData, { pushHistory = true } = {}) => {
    try {
      const entry = normalizeEntry(entryData);

      if (!entry.html) {
        throw new Error("No preview available for this page.");
      }

      if (pushHistory) {
        pushEntry(entry);
      }

      showCurrentEntry();
    } catch (error) {
      setStatus(error.message || "Received an invalid URL.", { type: "error" });
    }
  };

  const setLoading = (loading) => {
    isLoading = loading;
    nextButton.disabled = loading;
    nextButton.textContent = loading ? walkButtonLabel.loading : walkButtonLabel.idle;
  };

  const currentUrl = () => {
    if (position >= 0 && history[position]) {
      return history[position].url;
    }

    return defaultUrl;
  };

  const performStep = async ({ preserveStatus = false } = {}) => {
    if (isLoading) {
      return;
    }

    if (!preserveStatus) {
      setStatus("");
    }

    setLoading(true);

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
      setLoading(false);
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

  stopButton.addEventListener("click", () => {
    stopAuto();
  });

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
        setStatus("Start URL updated.", { type: "success" });
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

  window.addEventListener("beforeunload", () => {
    stopAuto({ silent: true });
  });

  nextButton.textContent = walkButtonLabel.idle;
  updateControls();
  updateCurrentUrlDisplay();
  setStatus(status.textContent.trim());
});
