const walkButtonLabel = {
  idle: "Random step",
  loading: "Walking…"
};

document.addEventListener("DOMContentLoaded", () => {
  const frame = document.getElementById("walker-frame");
  const nextButton = document.getElementById("walker-next");
  const backButton = document.getElementById("walker-back");
  const status = document.getElementById("walker-status");
  const historyList = document.getElementById("walker-history-list");

  if (!frame || !nextButton || !backButton || !historyList || !status) {
    return;
  }

  const history = [];
  let position = -1;

  const setStatus = (message = "", { success = false } = {}) => {
    status.textContent = message;
    status.classList.toggle("is-success", !!message && success);
  };

  const renderHistory = () => {
    historyList.innerHTML = "";

    history.forEach((url, index) => {
      const item = document.createElement("li");
      item.className = "walker-history-list-item";
      if (index === position) {
        item.classList.add("is-current");
      }
      item.textContent = url;
      historyList.appendChild(item);
    });
  };

  const updateControls = () => {
    backButton.disabled = position <= 0;
  };

  const navigateTo = (url, { pushHistory = true } = {}) => {
    try {
      const normalized = new URL(url).toString();

      if (pushHistory) {
        history.splice(position + 1);
        history.push(normalized);
        position = history.length - 1;
      }

      frame.src = normalized;
      renderHistory();
      updateControls();
      setStatus();
    } catch (error) {
      setStatus("Received an invalid URL.");
    }
  };

  const setLoading = (loading) => {
    nextButton.disabled = loading;
    nextButton.textContent = loading ? walkButtonLabel.loading : walkButtonLabel.idle;
  };

  const currentUrl = () => {
    if (position >= 0) {
      return history[position];
    }

    return frame.getAttribute("src");
  };

  nextButton.addEventListener("click", async () => {
    setStatus("", { success: false });
    setLoading(true);

    try {
      const url = currentUrl();
      if (!url) {
        throw new Error("No current URL available.");
      }
      const response = await fetch(`/walk?url=${encodeURIComponent(url)}`, {
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

      navigateTo(payload.url, { pushHistory: true });
      setStatus("Found a new page!", { success: true });
    } catch (error) {
      setStatus(error.message || "Failed to fetch next page.");
    } finally {
      setLoading(false);
    }
  });

  backButton.addEventListener("click", () => {
    if (position <= 0) {
      return;
    }

    position -= 1;
    frame.src = history[position];
    renderHistory();
    updateControls();
    setStatus("Returned to a previous page.", { success: true });
  });

  const initial = frame.getAttribute("src");
  if (initial) {
    history.push(initial);
    position = history.length - 1;
    renderHistory();
    updateControls();
  }

  nextButton.textContent = walkButtonLabel.idle;
});
