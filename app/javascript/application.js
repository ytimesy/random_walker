const walkButtonLabel = {
  idle: "Random step",
  loading: "Walking..."
};

document.addEventListener("DOMContentLoaded", () => {
  const frame = document.getElementById("walker-frame");
  const nextButton = document.getElementById("walker-next");
  const backButton = document.getElementById("walker-back");
  const status = document.getElementById("walker-status");
  const historyList = document.getElementById("walker-history-list");
  const autoButton = document.getElementById("walker-auto");
  const startForm = document.getElementById("walker-start-form");
  const startInput = document.getElementById("walker-start-url");
  let defaultUrl = frame?.dataset?.defaultUrl || null;
  const AUTO_INTERVAL = 5000;
  let autoTimer = null;
  let isLoading = false;

  if (!frame || !nextButton || !backButton || !historyList || !status || !autoButton) {
    return;
  }

  frame.removeAttribute("src");
  frame.srcdoc = "";

  const history = [];
  let position = -1;

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
      historyList.appendChild(item);
    });
  };

  const updateControls = () => {
    backButton.disabled = position <= 0;
  };

  const clearHistory = () => {
    history.length = 0;
    position = -1;
    frame.removeAttribute("src");
    frame.srcdoc = "";
    renderHistory();
    updateControls();
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

    performStep({ preserveStatus: true });
  };

  const normalizeEntry = ({ url, label, html }) => {
    if (!url) {
      throw new Error("Missing URL.");
    }

    const normalizedUrl = new URL(url).toString();
    const trimmedLabel = label ? label.replace(/\s+/g, " ").trim() : "";
    const finalLabel = trimmedLabel || normalizedUrl;

    return {
      url: normalizedUrl,
      label: finalLabel,
      html: typeof html === "string" ? html : ""
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
  };

  const pushEntry = (entry) => {
    history.splice(position + 1);
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

      if (!response.ok) {
        throw new Error(payload.error || "Unable to walk right now.");
      }

      if (!payload.url) {
        throw new Error("No URL returned by server.");
      }

      navigateTo(
        {
          url: payload.url,
          label: payload.label,
          html: payload.html
        },
        { pushHistory: true }
      );

      if (!preserveStatus) {
        setStatus("Found a new page!", { type: "success" });
      }
    } catch (error) {
      const message = error.message || "Failed to fetch next page.";

      if (/no navigable links found/i.test(message)) {
        const movedBack = goBack();
        const infoMessage = movedBack
          ? "No links here. Returned to a previous page."
          : "No links found on the current page.";

        setStatus(infoMessage, { type: "error" });

        if (autoTimer && movedBack) {
          setTimeout(() => {
            performStep({ preserveStatus: true });
          }, AUTO_INTERVAL);
        } else if (autoTimer) {
          stopAuto({ silent: true });
        }
      } else {
        setStatus(message, { type: "error" });
      }
    } finally {
      setLoading(false);
    }
  };

  nextButton.addEventListener("click", () => {
    performStep();
  });

  backButton.addEventListener("click", () => {
    if (position <= 0) {
      return;
    }

    goBack();
    setStatus("Returned to a previous page.", { type: "success" });
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
  setStatus(status.textContent.trim());
});
