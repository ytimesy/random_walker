const walkButtonLabel = {
  idle: "1 Walk",
  loading: "Walking..."
};
const RIBBON_STORAGE_KEY = "randomWalker.ribbonMode";
const SWEET_STORAGE_KEY = "randomWalker.sweetClick";
const LUCKY_STORAGE_KEY = "randomWalker.luckyJump";
const SAVED_TRAILS_STORAGE_KEY = "randomWalker.savedTrails";
const MAX_VISITED_URLS_SENT = 20;
const MAX_SAVED_TRAILS = 12;

document.addEventListener("DOMContentLoaded", () => {
  const previewCard = document.getElementById("walker-preview-card");
  const previewSite = document.getElementById("walker-preview-site");
  const previewTitle = document.getElementById("walker-preview-title");
  const previewDescription = document.getElementById("walker-preview-description");
  const previewUrl = document.getElementById("walker-preview-url");
  const previewLabel = document.getElementById("walker-preview-label");
  const previewLink = document.getElementById("walker-preview-link");
  const nextButton = document.getElementById("walker-next");
  const backButton = document.getElementById("walker-back");
  const stopButton = document.getElementById("walker-stop");
  const saveTrailButton = document.getElementById("walker-save-trail");
  const exportTrailButton = document.getElementById("walker-export-trail");
  const status = document.getElementById("walker-status");
  const historyList = document.getElementById("walker-history-list");
  const savedList = document.getElementById("walker-saved-list");
  const autoButton = document.getElementById("walker-auto");
  const startForm = document.getElementById("walker-start-form");
  const startInput = document.getElementById("walker-start-url");
  const currentUrlValue = document.getElementById("walker-current-url");
  const ribbonToggle = document.getElementById("walker-ribbon-toggle");
  const ribbonSummary = document.getElementById("walker-ribbon-summary");
  const sweetToggle = document.getElementById("walker-sweet-toggle");
  const sweetSummary = document.getElementById("walker-sweet-summary");
  const luckyToggle = document.getElementById("walker-lucky-toggle");
  const luckySummary = document.getElementById("walker-lucky-summary");
  const DEFAULT_CURRENT_URL_TEXT = "No page loaded.";
  const DEFAULT_PREVIEW_SITE = "Preview mode";
  const DEFAULT_PREVIEW_TITLE = "Pick a start URL and press 1 Walk.";
  const DEFAULT_PREVIEW_DESCRIPTION = "Random Walker now shows a short discovery preview and sends you to the original site in a new tab.";
  const DEFAULT_PREVIEW_LABEL = "A selected link will show up here.";
  const DEFAULT_PREVIEW_NOTE = "Open the original page in a new tab to keep wandering.";
  let defaultUrl = startInput?.value?.trim() || null;
  const AUTO_INTERVAL = 5000;
  let autoTimer = null;
  let isLoading = false;
  let failureStreak = 0;
  let ribbonMode = false;
  let sweetClickMode = false;
  let luckyJumpMode = false;

  if (
    !previewCard ||
    !previewSite ||
    !previewTitle ||
    !previewDescription ||
    !previewUrl ||
    !previewLabel ||
    !previewLink ||
    !nextButton ||
    !saveTrailButton ||
    !exportTrailButton ||
    !historyList ||
    !savedList ||
    !status ||
    !autoButton ||
    !stopButton
  ) {
    return;
  }

  const history = [];
  let position = -1;
  let savedTrails = [];


  const setPreviewLinkState = (url) => {
    const hasUrl = Boolean(url);
    previewLink.classList.toggle("is-disabled", !hasUrl);
    previewLink.setAttribute("aria-disabled", String(!hasUrl));
    previewLink.tabIndex = hasUrl ? 0 : -1;
    previewLink.href = hasUrl ? url : "#";
  };

  const resetPreview = () => {
    previewSite.textContent = DEFAULT_PREVIEW_SITE;
    previewTitle.textContent = DEFAULT_PREVIEW_TITLE;
    previewDescription.textContent = DEFAULT_PREVIEW_DESCRIPTION;
    previewUrl.textContent = defaultUrl || DEFAULT_CURRENT_URL_TEXT;
    previewLabel.textContent = DEFAULT_PREVIEW_LABEL;
    setPreviewLinkState(defaultUrl);
  };

  const renderPreview = (entry) => {
    previewSite.textContent = entry.siteName || entry.host || DEFAULT_PREVIEW_SITE;
    previewTitle.textContent = entry.title || entry.label || entry.url;
    previewDescription.textContent = entry.description || DEFAULT_PREVIEW_NOTE;
    previewUrl.textContent = entry.url || DEFAULT_CURRENT_URL_TEXT;
    previewLabel.textContent = entry.rawLabel ? `Picked via: ${entry.rawLabel}` : "Picked via: unlabeled link";
    setPreviewLinkState(entry.url);
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
      anchor.textContent = entry.title || entry.label || entry.url;
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

  const formatSavedTrailTime = (value) => {
    try {
      return new Intl.DateTimeFormat("ja-JP", {
        year: "numeric",
        month: "short",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit"
      }).format(new Date(value));
    } catch (error) {
      return value;
    }
  };

  const readSavedTrails = () => {
    try {
      const raw = window.localStorage.getItem(SAVED_TRAILS_STORAGE_KEY);
      const parsed = raw ? JSON.parse(raw) : [];
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  };

  const persistSavedTrails = () => {
    try {
      window.localStorage.setItem(SAVED_TRAILS_STORAGE_KEY, JSON.stringify(savedTrails));
      return true;
    } catch (error) {
      setStatus("Saved trails could not be written in this browser.", { type: "error" });
      return false;
    }
  };

  const normalizeTrailEntries = (entries) => {
    return Array.isArray(entries)
      ? entries.map((entry) => normalizeEntry(entry)).filter(Boolean)
      : [];
  };

  const deriveTrailName = () => {
    const activeEntry = position >= 0 ? history[position] : null;

    if (activeEntry?.title) {
      return activeEntry.title;
    }

    if (activeEntry?.siteName) {
      return `${activeEntry.siteName} trail`;
    }

    if (defaultUrl) {
      return `Trail from ${new URL(defaultUrl).host}`;
    }

    return "Untitled trail";
  };

  const buildTrailSnapshot = ({ name = deriveTrailName() } = {}) => {
    if (!history.length) {
      return null;
    }

    const normalizedName = typeof name === "string" ? name.trim() : "";

    return {
      id: `trail-${Date.now()}`,
      name: normalizedName || deriveTrailName(),
      savedAt: new Date().toISOString(),
      startUrl: defaultUrl,
      position,
      entries: history.map((entry) => ({
        url: entry.url,
        label: entry.rawLabel || entry.label,
        title: entry.title,
        description: entry.description,
        siteName: entry.siteName,
        host: entry.host,
        error: entry.error || ""
      }))
    };
  };

  const downloadTrail = (trail) => {
    if (!trail) {
      return;
    }

    const filename = `${(trail.name || "random-walker-trail")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "") || "random-walker-trail"}.json`;
    const blob = new Blob([JSON.stringify(trail, null, 2)], { type: "application/json" });
    const objectUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    URL.revokeObjectURL(objectUrl);
  };

  const loadTrail = (trail) => {
    const entries = normalizeTrailEntries(trail?.entries);
    if (!entries.length) {
      setStatus("That saved trail is empty.", { type: "error" });
      return;
    }

    stopAuto({ silent: true });
    history.length = 0;
    history.push(...entries);
    defaultUrl = trail.startUrl || entries[0].url;

    if (startInput) {
      startInput.value = defaultUrl;
    }

    const restoredPosition = Number.isInteger(trail.position) ? trail.position : entries.length - 1;
    position = Math.min(Math.max(restoredPosition, 0), entries.length - 1);
    showCurrentEntry();
    setStatus(`Loaded saved trail: ${trail.name}`, { type: "success" });
  };

  const renderSavedTrails = () => {
    savedList.innerHTML = "";

    if (!savedTrails.length) {
      const empty = document.createElement("li");
      empty.className = "walker-saved-empty";
      empty.textContent = "Save a trail to keep your cutest discoveries around.";
      savedList.appendChild(empty);
      return;
    }

    savedTrails.forEach((trail) => {
      const item = document.createElement("li");
      item.className = "walker-saved-item";

      const heading = document.createElement("p");
      heading.className = "walker-saved-name";
      heading.textContent = trail.name || "Untitled trail";
      item.appendChild(heading);

      const meta = document.createElement("p");
      meta.className = "walker-saved-meta";
      meta.textContent = `${formatSavedTrailTime(trail.savedAt)} · ${trail.entries?.length || 0} stops`;
      item.appendChild(meta);

      const actions = document.createElement("div");
      actions.className = "walker-saved-actions";

      [
        { action: "load", label: "Load" },
        { action: "export", label: "Export" },
        { action: "delete", label: "Delete" }
      ].forEach(({ action, label }) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = `walker-saved-button is-${action}`;
        button.dataset.action = action;
        button.dataset.trailId = trail.id;
        button.textContent = label;
        actions.appendChild(button);
      });

      item.appendChild(actions);
      savedList.appendChild(item);
    });
  };

  const updateControls = () => {
    if (backButton) {
      backButton.disabled = position <= 0;
    }

    stopButton.disabled = !autoTimer;
    saveTrailButton.disabled = history.length === 0;
    exportTrailButton.disabled = history.length === 0;
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
    resetPreview();
    renderHistory();
    updateControls();
    updateCurrentUrlDisplay();
  };

  const saveCurrentTrail = () => {
    const snapshot = buildTrailSnapshot();
    if (!snapshot) {
      setStatus("Walk at least one step before saving a trail.", { type: "error" });
      return;
    }

    const suggestedName = snapshot.name;
    const chosenName = window.prompt("Save this trail as:", suggestedName);
    if (chosenName === null) {
      return;
    }

    snapshot.name = chosenName.trim() || suggestedName;
    savedTrails = [snapshot, ...savedTrails].slice(0, MAX_SAVED_TRAILS);

    if (persistSavedTrails()) {
      renderSavedTrails();
      setStatus(`Saved trail: ${snapshot.name}`, { type: "success" });
    }
  };

  const exportCurrentTrail = () => {
    const snapshot = buildTrailSnapshot();
    if (!snapshot) {
      setStatus("Walk at least one step before exporting a trail.", { type: "error" });
      return;
    }

    downloadTrail(snapshot);
    setStatus("Current trail exported as JSON.", { type: "success" });
  };

  const readStoredRibbonMode = () => {
    try {
      return window.localStorage.getItem(RIBBON_STORAGE_KEY) === "true";
    } catch (error) {
      return false;
    }
  };

  const readStoredLuckyJumpMode = () => {
    try {
      return window.localStorage.getItem(LUCKY_STORAGE_KEY) === "true";
    } catch (error) {
      return false;
    }
  };

  const readStoredSweetClickMode = () => {
    try {
      return window.localStorage.getItem(SWEET_STORAGE_KEY) === "true";
    } catch (error) {
      return false;
    }
  };

  const persistRibbonMode = () => {
    try {
      window.localStorage.setItem(RIBBON_STORAGE_KEY, String(ribbonMode));
    } catch (error) {
      // Ignore storage failures in private browsing or restricted contexts.
    }
  };

  const persistLuckyJumpMode = () => {
    try {
      window.localStorage.setItem(LUCKY_STORAGE_KEY, String(luckyJumpMode));
    } catch (error) {
      // Ignore storage failures in private browsing or restricted contexts.
    }
  };

  const persistSweetClickMode = () => {
    try {
      window.localStorage.setItem(SWEET_STORAGE_KEY, String(sweetClickMode));
    } catch (error) {
      // Ignore storage failures in private browsing or restricted contexts.
    }
  };

  const updateRibbonUi = () => {
    if (!ribbonToggle) {
      return;
    }

    ribbonToggle.classList.toggle("is-active", ribbonMode);
    ribbonToggle.setAttribute("aria-pressed", String(ribbonMode));

    if (ribbonSummary) {
      ribbonSummary.textContent = ribbonMode
        ? "オン: 同じサイト内と、読みやすいラベル付きリンクを優先します。"
        : "オフ: 使えるリンク全体をランダム寄りに辿ります。";
    }
  };

  const updateLuckyUi = () => {
    if (!luckyToggle) {
      return;
    }

    luckyToggle.classList.toggle("is-active", luckyJumpMode);
    luckyToggle.setAttribute("aria-pressed", String(luckyJumpMode));

    if (luckySummary) {
      luckySummary.textContent = luckyJumpMode
        ? "オン: ときどき新しいドメインを優先して大きく跳びます。"
        : "オフ: ふつうのルールで次のリンクを探します。";
    }
  };

  const updateSweetUi = () => {
    if (!sweetToggle) {
      return;
    }

    sweetToggle.classList.toggle("is-active", sweetClickMode);
    sweetToggle.setAttribute("aria-pressed", String(sweetClickMode));

    if (sweetSummary) {
      sweetSummary.textContent = sweetClickMode
        ? "オン: 読みやすくて、気持ちよく辿れるリンクを優先します。"
        : "オフ: リンクの選び方は通常ルールに戻ります。";
    }
  };

  const setRibbonMode = (enabled, { announce = true } = {}) => {
    ribbonMode = Boolean(enabled);
    persistRibbonMode();
    updateRibbonUi();

    if (announce) {
      setStatus(
        ribbonMode
          ? "りぼんモードON: 同じサイト内と、ラベル付きリンクを優先します。"
          : "りぼんモードOFF: ふつうのランダム移動に戻りました。",
        { type: "success" }
      );
    }
  };

  const setLuckyJumpMode = (enabled, { announce = true } = {}) => {
    luckyJumpMode = Boolean(enabled);
    persistLuckyJumpMode();
    updateLuckyUi();

    if (announce) {
      setStatus(
        luckyJumpMode
          ? "ラッキージャンプON: ときどき大胆に別ドメインへ飛びます。"
          : "ラッキージャンプOFF: 通常のジャンプ規則に戻りました。",
        { type: "success" }
      );
    }
  };

  const setSweetClickMode = (enabled, { announce = true } = {}) => {
    sweetClickMode = Boolean(enabled);
    persistSweetClickMode();
    updateSweetUi();

    if (announce) {
      setStatus(
        sweetClickMode
          ? "スイートクリックON: 読みやすくて気持ちいいリンクを優先します。"
          : "スイートクリックOFF: 通常のリンク選択に戻りました。",
        { type: "success" }
      );
    }
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

  const normalizeEntry = ({ url, label, title, description, siteName, host, error }) => {
    if (!url) {
      throw new Error("Missing URL.");
    }

    const normalizedUrl = new URL(url).toString();
    const trimmedLabel = label ? label.replace(/\s+/g, " ").trim() : "";
    const trimmedTitle = title ? title.replace(/\s+/g, " ").trim() : "";
    const trimmedDescription = description ? description.replace(/\s+/g, " ").trim() : "";
    const parsedHost = new URL(normalizedUrl).host;

    return {
      url: normalizedUrl,
      rawLabel: trimmedLabel,
      label: trimmedLabel || trimmedTitle || normalizedUrl,
      title: trimmedTitle || trimmedLabel || normalizedUrl,
      description: trimmedDescription || DEFAULT_PREVIEW_NOTE,
      siteName: siteName ? siteName.replace(/\s+/g, " ").trim() : parsedHost,
      host: host ? host.replace(/\s+/g, " ").trim() : parsedHost,
      error: error || ""
    };
  };

  const showCurrentEntry = () => {
    if (position < 0 || position >= history.length) {
      return;
    }

    renderPreview(history[position]);
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

  const recentVisitedUrls = () => {
    return history
      .map((entry) => entry.url)
      .filter(Boolean)
      .slice(-MAX_VISITED_URLS_SENT);
  };

  const performStep = async ({ preserveStatus = false, forceLuckyJump = false } = {}) => {
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
      const params = new URLSearchParams();
      if (url) {
        params.set("url", url);
      }
      if (ribbonMode) {
        params.set("mode", "ribbon");
      }
      if (sweetClickMode) {
        params.set("sweet", "true");
      }
      if (luckyJumpMode) {
        params.set("lucky", "true");
      }
      if (forceLuckyJump) {
        params.set("force_lucky_jump", "true");
      }
      recentVisitedUrls().forEach((visitedUrl) => {
        params.append("visited[]", visitedUrl);
      });
      const endpoint = params.toString() ? `/walk?${params.toString()}` : "/walk";
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
          title: payload.title,
          description: payload.description,
          siteName: payload.site_name,
          host: payload.host
        },
        { pushHistory: true }
      );

      failureStreak = 0;

      if (payload.lucky_jump) {
        setStatus("ラッキージャンプ! 新しいドメインへ飛びました。", { type: "success" });
      } else if (sweetClickMode) {
        setStatus("スイートクリック! 読みやすいページを優先して見つけました。", { type: "success" });
      } else if (!preserveStatus || statusWasError) {
        setStatus("Found a new preview!", { type: "success" });
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

        if (luckyJumpMode && movedBack) {
          setStatus("行き止まりだったので、ラッキージャンプを発動します。", { type: "success" });
          setTimeout(() => {
            performStep({ preserveStatus: true, forceLuckyJump: true });
          }, 10);
        } else if (autoTimer && movedBack) {
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

  saveTrailButton.addEventListener("click", () => {
    saveCurrentTrail();
  });

  exportTrailButton.addEventListener("click", () => {
    exportCurrentTrail();
  });

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
        clearHistory();
        stopAuto({ silent: true });
        setStatus("Start URL updated. Preview mode is ready.", { type: "success" });
      } catch (error) {
        setStatus(error.message || "Invalid start URL.", { type: "error" });
      }
    });
  }

  if (ribbonToggle) {
    ribbonToggle.addEventListener("click", () => {
      setRibbonMode(!ribbonMode);
    });
  }

  if (sweetToggle) {
    sweetToggle.addEventListener("click", () => {
      setSweetClickMode(!sweetClickMode);
    });
  }

  if (luckyToggle) {
    luckyToggle.addEventListener("click", () => {
      setLuckyJumpMode(!luckyJumpMode);
    });
  }

  autoButton.addEventListener("click", () => {
    if (autoTimer) {
      stopAuto();
    } else {
      startAuto();
    }
  });

  savedList.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action][data-trail-id]");
    if (!button) {
      return;
    }

    const trail = savedTrails.find((item) => item.id === button.dataset.trailId);
    if (!trail) {
      setStatus("That saved trail could not be found.", { type: "error" });
      return;
    }

    if (button.dataset.action === "load") {
      loadTrail(trail);
      return;
    }

    if (button.dataset.action === "export") {
      downloadTrail(trail);
      setStatus(`Exported saved trail: ${trail.name}`, { type: "success" });
      return;
    }

    if (button.dataset.action === "delete") {
      savedTrails = savedTrails.filter((item) => item.id !== trail.id);
      if (persistSavedTrails()) {
        renderSavedTrails();
        setStatus(`Deleted saved trail: ${trail.name}`, { type: "success" });
      }
    }
  });

  window.addEventListener("beforeunload", () => {
    stopAuto({ silent: true });
  });

  previewLink.addEventListener("click", (event) => {
    if (previewLink.getAttribute("aria-disabled") === "true") {
      event.preventDefault();
    }
  });

  nextButton.textContent = walkButtonLabel.idle;
  setRibbonMode(readStoredRibbonMode(), { announce: false });
  setSweetClickMode(readStoredSweetClickMode(), { announce: false });
  setLuckyJumpMode(readStoredLuckyJumpMode(), { announce: false });
  savedTrails = readSavedTrails();
  renderSavedTrails();
  resetPreview();
  updateControls();
  updateCurrentUrlDisplay();
  setStatus(status.textContent.trim());
});
