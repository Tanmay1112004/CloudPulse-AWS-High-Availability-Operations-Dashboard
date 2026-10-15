(() => {
  const initial = window.CLOUDPULSE_INITIAL || {};
  const $ = (id) => document.getElementById(id);
  const fmtDuration = (seconds) => {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    return days ? `${days}d ${hours}h` : hours ? `${hours}h ${minutes}m` : `${minutes}m ${secs}s`;
  };
  const setText = (id, value) => { const el = $(id); if (el) el.textContent = value ?? "--"; };
  function showCounter() {
    if (initial.visits !== null && initial.visits !== undefined) {
      setText("globalVisits", Number(initial.visits).toLocaleString());
      setText("counterNote", "Persistent shared page-request total");
    } else {
      setText("globalVisits", "Unavailable");
      setText("counterNote", initial.counter_error || "Counter service unavailable");
    }
  }
  async function pollCounter() {
    try {
      const response = await fetch("/api/visits", { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (data.available && data.visits !== null) {
        setText("globalVisits", Number(data.visits).toLocaleString());
        setText("counterNote", "Shared total - refreshed every 10 seconds");
      } else {
        setText("globalVisits", "Unavailable");
        setText("counterNote", data.error || "Counter service unavailable");
      }
    } catch (_) {
      setText("globalVisits", "Unavailable");
      setText("counterNote", "Could not refresh shared counter");
    }
  }
  async function poll() {
    try {
      const response = await fetch("/api/status", { cache: "no-store" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      const healthy = data.status === "ok";
      setText("uptime", fmtDuration(data.uptime_seconds || 0));
      setText("instanceRequests", Number(data.instance_requests || 0).toLocaleString());
      setText("instanceId", data.instance_id || "Unavailable");
      setText("az", data.availability_zone || "Unavailable");
      setText("region", data.region || "Unavailable");
      setText("hostname", data.hostname || "Unavailable");
      setText("buildTag", `BUILD ${data.build_version || "--"}`);
      setText("footerBuild", data.build_version || "--");
      setText("healthLabel", healthy ? "Healthy" : "Degraded");
      setText("serviceTitle", healthy ? "Service is up and running." : "Service needs attention.");
      setText("lastUpdated", `Updated ${new Date().toLocaleTimeString()}`);
      setText("footerStatus", "Live - refreshed every 5 seconds");
    } catch (_) {
      setText("healthLabel", "Unavailable");
      setText("serviceTitle", "Telemetry temporarily unavailable.");
      setText("lastUpdated", "Could not fetch instance telemetry");
      setText("footerStatus", "Status endpoint unavailable");
    }
  }
  showCounter();
  poll();
  pollCounter();
  window.setInterval(poll, 5000);
  window.setInterval(pollCounter, 10000);
  const savedTheme = window.localStorage.getItem("cloudpulse-theme");
  if (savedTheme === "light") document.body.classList.add("light");
  document.documentElement.style.colorScheme = document.body.classList.contains("light") ? "light" : "dark";
  const themeButton = $("themeToggle");
  themeButton.setAttribute("aria-pressed", String(document.body.classList.contains("light")));
  themeButton.addEventListener("click", () => {
    document.body.classList.toggle("light");
    const light = document.body.classList.contains("light");
    document.documentElement.style.colorScheme = light ? "light" : "dark";
    themeButton.setAttribute("aria-pressed", String(light));
    window.localStorage.setItem("cloudpulse-theme", light ? "light" : "dark");
  });
  const refreshButton = $("refreshButton");
  refreshButton.addEventListener("click", async () => {
    refreshButton.disabled = true;
    refreshButton.setAttribute("aria-busy", "true");
    await Promise.allSettled([poll(), pollCounter()]);
    refreshButton.disabled = false;
    refreshButton.removeAttribute("aria-busy");
  });
  const navLinks = Array.from(document.querySelectorAll(".nav-item[href^='#']"));
  const updateNavigation = () => {
    const activeHash = window.location.hash || "#overview";
    navLinks.forEach((link) => {
      const active = link.getAttribute("href") === activeHash;
      link.classList.toggle("active", active);
      if (active) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    });
  };
  window.addEventListener("hashchange", updateNavigation);
  updateNavigation();
})();
