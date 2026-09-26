// HSIN WebUI Script

const HSIN = {
    path: '/data/adb/modules/hsin',
    data: '/data/adb/hsin',
    discordUrl: atob('aHR0cHM6Ly9kaXNjb3JkLmdnL1QySFdCRmVFTg=='),
    logLines: [],
    lastErrors: {}, // throttle repeated auto-refresh errors so the log doesn't spam
    // Was 1200ms then 2000ms - each poll spawns a real su/root shell,
    // so tighter intervals just burn CPU on low-end SoCs (T615). 5000ms
    // is the sweet spot: monitor still feels live, shell churn drops 60%.
    pollIntervalMs: 5000, // PATCH v3: 2000ms still spawned su+action.sh every 2s; 5s keeps monitor useful with far less shell/CPU churn
    statusPollInFlight: false, // guards against overlapping loadLiveStatus() calls
    // Set the moment the user taps a different mode-card. While true, the
    userSelected: false,
    bridgeFailStreak: 0,
    lastUpdatedAt: null,
    unreadLogCount: 0
};

// PERF: caches so repeated identical writes during a monitor poll are
// skipped entirely (no DOM/style touch, no style recalc) instead of
// re-applying the exact same value every ~1.2s - this is most of what
// "only update changed values, avoid unnecessary DOM refresh" means here.
const HSIN_LAST_TEXT = {};
const HSIN_LAST_BAR = {};
const HSIN_LAST_STATE = {};

// Open the Discord invite once per device, first time the WebUI is opened.
function openDiscordOnce() {
    try {
        if (localStorage.getItem('hsin_discord_shown')) return;
        localStorage.setItem('hsin_discord_shown', '1');
        window.open(HSIN.discordUrl, '_blank');
    } catch (e) {
        // localStorage unavailable in some WebView hosts - not critical, skip
    }
}

// Log an error only if it's different from the last one logged for this key,
function addLogOnce(key, msg, type = '') {
    if (HSIN.lastErrors[key] === msg) return;
    HSIN.lastErrors[key] = msg;
    addLog(msg, type);
}

// Execute action.sh command. `env` (optional) is prefixed as shell
async function hsinExec(cmd, args = '', env = '') {
    const command = `${env ? env + ' ' : ''}${HSIN.path}/action.sh ${cmd} ${args}`.trim();
    try {
        // KernelSU / WebUI-X style bridge
        if (window.ksu && typeof window.ksu.exec === 'function') {
            const result = await window.ksu.exec(command);
            onBridgeSuccess();
            return (result && result.stdout) ? result.stdout.trim() : String(result).trim();
        }
        // No root bridge detected - we are not inside a WebUI host that can
        console.error(
            'HSIN: no root exec bridge (window.ksu) found. ' +
            'Open this page from KernelSU Manager / WebUI-X, not a plain browser.'
        );
        onBridgeFailure();
        return null;
    } catch (e) {
        console.error('HSIN exec error for command:', command, e);
        onBridgeFailure();
        return null;
    }
}

// Surfaces a persistent banner (instead of only a Log tab line) once the
// exec bridge fails a couple of times in a row, since a single hiccup is
// normal but repeated failures usually mean the bridge itself is dead.
function onBridgeFailure() {
    HSIN.bridgeFailStreak++;
    if (HSIN.bridgeFailStreak >= 3) {
        const el = document.getElementById('bridge-warning');
        if (el) el.classList.remove('hidden');
    }
}

function onBridgeSuccess() {
    HSIN.bridgeFailStreak = 0;
    const el = document.getElementById('bridge-warning');
    if (el) el.classList.add('hidden');
}

// Re-runs every data load in one go - used by the manual Retry button and
// by pull-to-refresh.
function refreshAll() {
    loadDeviceInfo();
    loadCapabilities();
    loadLiveStatus();
    loadConflicts();
    loadGameList();
    loadSettings();
}

// Parse JSON safely
function parseJSON(text) {
    try {
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

// Add log line - every entry is timestamped (HH:MM:SS) so the Log tab
// and the exported report both read like a real device log, not just a
// bare list of messages.
function addLog(msg, type = '') {
    const stamped = `[${new Date().toTimeString().slice(0, 8)}] ${msg}`;
    const log = document.getElementById('log-output');
    const line = document.createElement('div');
    line.className = `log-line ${type}`;
    line.textContent = `> ${stamped}`;
    log.appendChild(line);
    log.scrollTop = log.scrollHeight;

    HSIN.logLines.push(stamped);
    if (HSIN.logLines.length > 100) {
        HSIN.logLines.shift();
    }

    // Badge the Log nav item for warnings/errors the person hasn't seen
    // yet (i.e. Log tab isn't the one currently open).
    if ((type === 'error' || type === 'warning') && !document.getElementById('tab-log').classList.contains('is-active')) {
        HSIN.unreadLogCount++;
        updateLogBadge();
    }
}

function updateLogBadge() {
    const badge = document.getElementById('log-nav-badge');
    if (!badge) return;
    if (HSIN.unreadLogCount > 0) {
        badge.textContent = HSIN.unreadLogCount > 9 ? '9+' : String(HSIN.unreadLogCount);
        badge.classList.remove('hidden');
    } else {
        badge.classList.add('hidden');
    }
}

// Format temperature
function formatTemp(millidegrees) {
    // Defensive: never render a garbage/negative reading raw. This is what
    // showed up as mangled overlapping text on the Monitor tab.
    if (millidegrees == null || isNaN(millidegrees) || millidegrees < 0) return 'N/A';
    if (!millidegrees || millidegrees === 0) return 'N/A';
    if (millidegrees > 1000) return `${Math.round(millidegrees / 1000)}°C`;
    return `${millidegrees}°C`;
}

// Format frequency
function formatFreq(khz) {
    // Defensive: same as formatTemp - a negative/NaN value used to fall
    // through both range checks below untouched and print raw.
    if (khz == null || isNaN(khz) || khz < 0) return 'N/A';
    if (!khz || khz === 0) return 'N/A';
    if (khz > 1000000) return `${(khz / 1000000).toFixed(2)} GHz`;
    if (khz > 1000) return `${(khz / 1000).toFixed(0)} MHz`;
    return `${khz} kHz`;
}

// Format RAM
function formatRAM(kb) {
    if (!kb) return 'N/A';
    const mb = Math.round(kb / 1024);
    if (mb > 1024) return `${(mb / 1024).toFixed(1)} GB`;
    return `${mb} MB`;
}

// Format battery percentage (-1 = node not found on this device)
function formatBattery(pct) {
    if (pct === undefined || pct === null || pct < 0) return 'N/A';
    return `${pct}%`;
}

// Format system uptime (seconds) as a compact "1d 4h 12m" string
function formatUptime(sec) {
    if (!sec || sec <= 0) return 'N/A';
    const d = Math.floor(sec / 86400);
    const h = Math.floor((sec % 86400) / 3600);
    const m = Math.floor((sec % 3600) / 60);
    if (d > 0) return `${d}d ${h}h`;
    if (h > 0) return `${h}h ${m}m`;
    return `${m}m`;
}

// "Updated Xs ago" ticker on the Monitor tab - ticks every second on its
// own (separate from the ~1.2s data poll) so the text stays accurate
// even between polls, but only while the tab is visible (see the
// visibilitychange handling further down).
let lastUpdatedTicker;
function updateLastUpdatedText() {
    const el = document.getElementById('last-updated');
    if (!el || !HSIN.lastUpdatedAt) return;
    const secs = Math.round((Date.now() - HSIN.lastUpdatedAt) / 1000);
    el.textContent = secs < 2 ? 'Updated just now' : `Updated ${secs}s ago`;
}
function startLastUpdatedTicker() {
    clearInterval(lastUpdatedTicker);
    lastUpdatedTicker = setInterval(updateLastUpdatedText, 1000);
}
function stopLastUpdatedTicker() {
    clearInterval(lastUpdatedTicker);
}

// Percentage of current/max, clamped 0-100. Returns 0 when either side is
// missing so a bar never renders a misleading full/empty state.
function percentOf(cur, max) {
    if (!cur || !max || max <= 0) return 0;
    return Math.max(0, Math.min(100, Math.round((cur / max) * 100)));
}

function setTextIfExists(id, text) {
    if (HSIN_LAST_TEXT[id] === text) return;
    HSIN_LAST_TEXT[id] = text;
    const el = document.getElementById(id);
    if (el) el.textContent = text;
}

// Same idea as setTextIfExists but for the "value + inline unit span"
// tiles (RAM/FPS/battery-temp/CPU-load/zram) which write into a specific
// child text node rather than the element's whole textContent.
function setFirstChildText(el, cacheKey, text) {
    if (!el || !el.firstChild) return;
    if (HSIN_LAST_TEXT[cacheKey] === text) return;
    HSIN_LAST_TEXT[cacheKey] = text;
    el.firstChild.textContent = text;
}

// Toggles an action-tile (Backup/Rollback/Doctor) into/out of its "busy"
// state: spins the icon (via CSS, cheap) and swaps the label text,
// without touching/rebuilding the icon's DOM node.
function setActionTileBusy(btn, busy, label) {
    if (!btn) return;
    btn.disabled = busy;
    const icon = btn.querySelector('.action-icon');
    const labelEl = btn.querySelector('.action-label');
    if (icon) icon.classList.toggle('is-spinning', busy);
    if (labelEl) labelEl.textContent = label;
}

// Quick confirmation for actions (Backup/Rollback/Doctor/Export) whose
// result otherwise only shows up if you happen to be on the Log tab.
// Themed replacement for native confirm() - used for Extreme mode and
// Rollback, since a plain white browser dialog clashes hard with the dark
// UI. Returns a Promise<boolean> so call sites can just `await` it the
// same way they used to `if (!confirm(...))`.
function showConfirmModal({ title = 'Confirm', message = '', confirmLabel = 'Confirm', cancelLabel = 'Cancel', danger = false } = {}) {
    return new Promise((resolve) => {
        const overlay = document.getElementById('confirm-modal-overlay');
        const titleEl = document.getElementById('confirm-modal-title');
        const msgEl = document.getElementById('confirm-modal-message');
        const okBtn = document.getElementById('confirm-modal-ok');
        const cancelBtn = document.getElementById('confirm-modal-cancel');

        // Fall back to the native dialog if the modal markup is somehow
        // missing, rather than silently doing nothing.
        if (!overlay || !titleEl || !msgEl || !okBtn || !cancelBtn) {
            resolve(confirm(message));
            return;
        }

        titleEl.textContent = title;
        msgEl.innerHTML = message;
        okBtn.textContent = confirmLabel;
        cancelBtn.textContent = cancelLabel;
        okBtn.classList.toggle('btn-danger', !!danger);
        okBtn.classList.toggle('btn-primary', !danger);

        overlay.classList.remove('hidden');
        void overlay.offsetWidth;
        overlay.classList.add('open');

        function cleanup(result) {
            overlay.classList.remove('open');
            setTimeout(() => overlay.classList.add('hidden'), 200);
            okBtn.removeEventListener('click', onOk);
            cancelBtn.removeEventListener('click', onCancel);
            overlay.removeEventListener('click', onOverlay);
            resolve(result);
        }
        function onOk() { cleanup(true); }
        function onCancel() { cleanup(false); }
        function onOverlay(e) { if (e.target === overlay) cleanup(false); }

        okBtn.addEventListener('click', onOk);
        cancelBtn.addEventListener('click', onCancel);
        overlay.addEventListener('click', onOverlay);
    });
}

function showToast(message, type = 'success') {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    container.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('is-visible'));
    setTimeout(() => {
        toast.classList.remove('is-visible');
        setTimeout(() => toast.remove(), 250);
    }, 2600);
}

// Toggles a warn/danger class on a tile + its value elements so the color
// itself carries the signal (e.g. battery going low, temp running hot)
// instead of making the person read every number to notice.
function setTileState(ids, state) {
    ids.forEach(id => {
        // Cache key includes the id since the same state string can be
        // applied to several different ids in one call.
        if (HSIN_LAST_STATE[id] === state) return;
        HSIN_LAST_STATE[id] = state;
        const el = document.getElementById(id);
        if (!el) return;
        el.classList.remove('state-warn', 'state-danger');
        if (state) el.classList.add(`state-${state}`);
    });
}

function batteryState(pct) {
    if (pct < 0) return null;
    if (pct <= 10) return 'danger';
    if (pct <= 20) return 'warn';
    return null;
}

function tempState(celsius) {
    if (!celsius) return null;
    if (celsius >= 65) return 'danger';
    if (celsius >= 55) return 'warn';
    return null;
}

function setBarWidth(id, pct) {
    if (HSIN_LAST_BAR[id] === pct) return;
    HSIN_LAST_BAR[id] = pct;
    const el = document.getElementById(id);
    // transform:scaleX instead of width - compositor-only, no layout pass.
    if (el) el.style.transform = `scaleX(${pct / 100})`;
}

// Smooth count-up/down for key numbers (CPU/GPU freq & temp) instead of
// the text jumping straight to the new value. Interpolates the RAW value
// (kHz / millidegrees) over ~350ms and re-applies the same format
// function each frame - a single short-lived rAF loop per stat per poll,
// not a continuous animation, so it stays cheap. Skipped entirely when
// Reduce Motion is on.
const HSIN_LAST_RAW = {};
// PATCH v4: one-shot flash di tile saat nilai berubah. Opacity-only,
// jalan sekali ~450ms - ada feel "hidup" tanpa biaya infinite repaint.
function flashStatTile(el) {
    if (!el || document.body.classList.contains('reduce-motion')) return;
    const tile = el.closest('.stat-tile');
    if (!tile) return;
    tile.classList.remove('stat-flash');
    void tile.offsetWidth; // restart animasi kalau masih jalan
    tile.classList.add('stat-flash');
    clearTimeout(tile._flashTimer);
    tile._flashTimer = setTimeout(() => tile.classList.remove('stat-flash'), 500);
}

function animateStatValue(id, rawValue, formatFn, duration = 350) {
    const el = document.getElementById(id);
    if (!el) return;
    // BUGFIX: a bad/negative reading used to get stored as the new "from"
    // baseline and tweened through frame-by-frame, which is exactly what
    // produced the garbled decimal numbers on screen (a float mid-way
    // between the last good value and a garbage one, formatted raw).
    // Treat it as "no new data" instead: keep showing the last good value
    // and don't let it poison the next real animation's starting point.
    if (rawValue == null || isNaN(rawValue) || rawValue < 0) {
        setTextIfExists(id, formatFn(HSIN_LAST_RAW[id] !== undefined ? HSIN_LAST_RAW[id] : rawValue));
        return;
    }
    const from = HSIN_LAST_RAW[id] !== undefined ? HSIN_LAST_RAW[id] : rawValue;
    HSIN_LAST_RAW[id] = rawValue;
    if (document.body.classList.contains('reduce-motion') || from === rawValue || !rawValue) {
        // PERF: from === rawValue is the common case every poll where a
        // reading hasn't changed - setTextIfExists no-ops instead of
        // touching the DOM for a value that's already on screen.
        setTextIfExists(id, formatFn(rawValue));
        return;
    }
    const start = performance.now();
    flashStatTile(el);
    function tick(now) {
        const t = Math.min(1, (now - start) / duration);
        const eased = 1 - Math.pow(1 - t, 3);
        const current = from + (rawValue - from) * eased;
        el.textContent = formatFn(t < 1 ? current : rawValue);
        if (t < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
}

// Small rolling-window mini graphs on the Monitor tab. Keeps the last N
// samples in memory (per session only - not persisted) and redraws a
// filled sparkline as a percentage of the device's own max freq, so the
// shape is meaningful on any chipset regardless of its actual clock speed.
const GRAPH_HISTORY = { cpu: [], gpu: [] };
const GRAPH_MAX_POINTS = 20;

function pushGraphSample(key, cur, max) {
    const pct = percentOf(cur, max);
    const hist = GRAPH_HISTORY[key];

    if (hist.length === 0) {
        // Backfill so the very first paint is already a full-width line
        // instead of a lone point glued to the right edge that slowly
        // grows leftward over the next ~20 polls.
        for (let i = 0; i < GRAPH_MAX_POINTS; i++) hist.push(pct);
    } else {
        hist.push(pct);
        if (hist.length > GRAPH_MAX_POINTS) hist.shift();
    }

    const svg = document.getElementById(`${key}-graph`);
    if (!svg) return;
    const w = 200, h = 46, padTop = 6, padBottom = 6;
    const step = w / (GRAPH_MAX_POINTS - 1);

    // Auto-range to the window's own min/max (with a floor so a
    // perfectly flat trace - e.g. a CPU pinned at one freq - still draws
    // as a clean centered line instead of dividing by zero) rather than
    // 0-100, so real small fluctuations are actually visible instead of
    // being squashed flat near the same pixel row every time.
    const lo = Math.min(...hist);
    const hi = Math.max(...hist);
    const range = Math.max(hi - lo, 8);

    const coords = hist.map((v, i) => {
        const x = i * step;
        const y = padTop + (1 - (v - lo) / range) * (h - padTop - padBottom);
        return [x, y];
    });

    const points = coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' ');
    const poly = svg.querySelector('polyline');
    if (poly) poly.setAttribute('points', points);

    const areaPath = svg.querySelector('path.graph-area');
    if (areaPath) {
        const first = coords[0], last = coords[coords.length - 1];
        const d = `M${first[0]},${h} L` + coords.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(' L') + ` L${last[0]},${h} Z`;
        areaPath.setAttribute('d', d);
    }
}

// Min/avg/max CPU & GPU freq for the current session (since page load,
// not persisted). Cheap running aggregate reusing the same raw kHz values
// already polled for the graphs/stat tiles - no extra exec calls needed.
const SESSION_STATS = {
    cpu: { min: null, max: null, sum: 0, count: 0 },
    gpu: { min: null, max: null, sum: 0, count: 0 }
};
function trackSessionStat(key, value) {
    if (!value) return;
    const s = SESSION_STATS[key];
    s.min = s.min === null ? value : Math.min(s.min, value);
    s.max = s.max === null ? value : Math.max(s.max, value);
    s.sum += value;
    s.count++;
    const el = document.getElementById(`${key}-graph-stats`);
    if (!el) return;
    const avg = s.sum / s.count;
    const lines = el.querySelectorAll('.graph-stat-line b');
    if (lines[0]) lines[0].textContent = formatFreq(s.min);
    if (lines[1]) lines[1].textContent = formatFreq(avg);
    if (lines[2]) lines[2].textContent = formatFreq(s.max);
}

// Estimated battery drain rate (%/hour), derived from how far the level
// has dropped since the session's own baseline reading - no extra polling
// or persisted history required. The baseline resets whenever the level
// goes UP (charging, or a bad reading) so the estimate never shows a
// negative/nonsensical rate; needs a few minutes of data before it prints
// anything so a single noisy sample can't produce a wild figure.
const BATTERY_DRAIN_MIN_WINDOW_MS = 3 * 60 * 1000; // 3 minutes
function updateBatteryDrainRate(pct) {
    const el = document.getElementById('battery-drain-rate');
    if (!el) return;
    if (pct === undefined || pct === null || pct < 0) {
        el.textContent = '';
        return;
    }
    const now = Date.now();
    if (!HSIN.battSession || pct > HSIN.battSession.pct) {
        HSIN.battSession = { t: now, pct };
        el.textContent = '';
        return;
    }
    const elapsedMs = now - HSIN.battSession.t;
    if (elapsedMs < BATTERY_DRAIN_MIN_WINDOW_MS) {
        el.textContent = '';
        return;
    }
    const drop = HSIN.battSession.pct - pct;
    const ratePerHour = drop / (elapsedMs / 3600000);
    el.textContent = drop > 0 ? `~${ratePerHour.toFixed(1)}%/hr` : '';
}

// Per-profile accent colors - drives the CSS custom properties so the
// hero card, ACTIVE pill and selected mode-card tile all pick up the
// color of whichever profile is actually active, instead of a single
// fixed green regardless of profile.
const PROFILE_COLORS = {
    performance: { c: '#f97316', dim: 'rgba(249, 115, 22, 0.14)', dim2: 'rgba(249, 115, 22, 0.10)', glow: 'rgba(249, 115, 22, 0.18)' },
    balanced:    { c: '#3b82f6', dim: 'rgba(59, 130, 246, 0.14)', dim2: 'rgba(59, 130, 246, 0.10)', glow: 'rgba(59, 130, 246, 0.18)' },
    battery:     { c: '#22c55e', dim: 'rgba(34, 197, 94, 0.14)',  dim2: 'rgba(34, 197, 94, 0.10)',  glow: 'rgba(34, 197, 94, 0.18)' },
    extreme:     { c: '#f43f5e', dim: 'rgba(244, 63, 94, 0.14)',  dim2: 'rgba(244, 63, 94, 0.10)',  glow: 'rgba(244, 63, 94, 0.18)' }
};

function applyProfileTheme(profile) {
    const p = PROFILE_COLORS[profile] || PROFILE_COLORS.balanced;
    const root = document.documentElement.style;
    root.setProperty('--profile-color', p.c);
    root.setProperty('--profile-color-border', p.dim);
    root.setProperty('--profile-color-bg', p.dim2);
    root.setProperty('--profile-color-glow', p.glow);
}

// SVGs matching each mode-card icon, keyed by profile - keeps the hero
// banner icon in sync with whichever profile is actually active.
const PROFILE_ICONS = {
    performance: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>',
    balanced: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="2" fill="currentColor" stroke="none"/></svg>',
    battery: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="18" height="10" rx="2"/><line x1="22" y1="10" x2="22" y2="14"/><rect x="5" y="9.5" width="6" height="5" fill="currentColor" stroke="none"/></svg>',
    extreme: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"><polygon points="12 2 22 9 12 22 2 9"/><line x1="2" y1="9" x2="22" y2="9"/><line x1="12" y1="2" x2="9" y2="9"/><line x1="12" y1="2" x2="15" y2="9"/></svg>'
};

function setHeroProfileIcon(profile) {
    const icon = document.getElementById('hero-profile-icon');
    if (icon && PROFILE_ICONS[profile]) icon.innerHTML = PROFILE_ICONS[profile];
    applyProfileTheme(profile);
}

// Keep the visual "selected" state of the mode-card tiles in sync with
function syncModeCardSelection() {
    document.querySelectorAll('.mode-card').forEach((card) => {
        const input = card.querySelector('input[type="radio"]');
        card.classList.toggle('selected', !!(input && input.checked));
    });
}

// Load device info
async function loadDeviceInfo() {
    const raw = await hsinExec('device');
    const data = parseJSON(raw);
    if (!data) {
        addLogOnce('device', `Device detection failed: ${raw === null ? 'no response from exec bridge' : raw}`, 'error');
        document.getElementById('soc').textContent = 'Error';
        document.getElementById('gpu').textContent = 'Error';
        document.getElementById('kernel').textContent = 'Error';
        document.getElementById('ram').textContent = 'Error';
        return;
    }

    delete HSIN.lastErrors['device'];
    document.getElementById('soc').textContent = data.soc || 'Unknown';
    document.getElementById('gpu').textContent = data.gpu || 'Unknown';
    document.getElementById('kernel').textContent = data.kernel || 'Unknown';
    document.getElementById('ram').textContent = formatRAM(data.ram_kb);

    // Logged once per detected value, not every poll - reads as a
    // detection result rather than log spam.
    addLogOnce('device-ok', `Detected hardware: SoC ${data.soc || 'Unknown'}, GPU ${data.gpu || 'Unknown'}`, 'success');

    // Chip in the header row - short SoC label
    const socChip = document.getElementById('chip-soc');
    if (socChip) socChip.textContent = `SoC: ${data.soc || 'Unknown'}`;

    const devIdEl = document.getElementById('device-id');
    if (devIdEl) devIdEl.textContent = data.device_id || '-';
}

// Load capabilities
async function loadCapabilities() {
    const raw = await hsinExec('capabilities');
    const data = parseJSON(raw);
    if (!data) {
        addLogOnce('capabilities', `Capability scan failed: ${raw === null ? 'no response from exec bridge' : raw}`, 'error');
        return;
    }

    delete HSIN.lastErrors['capabilities'];
    setStatus('cap-cpu', data.cpu_tuning);
    setStatus('cap-gpu', data.gpu_devfreq);
    setStatus('cap-thermal', data.thermal_node);
    setStatus('cap-fpsgo', data.fpsgo);
    setStatus('cap-kgsl', data.kgsl);
    setStatus('cap-schedlat', data.sched_lat);

    const capValues = [data.cpu_tuning, data.gpu_devfreq, data.thermal_node, data.fpsgo, data.kgsl, data.sched_lat];
    const supportedCount = capValues.filter((v) => v === true).length;
    addLogOnce('capabilities-ok', `Capability scan: ${supportedCount}/${capValues.length} features supported`, 'success');
}

// Set status indicator
function setStatus(id, value) {
    const el = document.getElementById(id);
    const icon = document.getElementById(id + '-icon');
    if (value === true) {
        el.textContent = 'SUPPORTED';
        el.className = 'cap-badge cap-on';
        if (icon) {
            icon.className = 'cap-icon cap-icon-on';
            icon.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>';
        }
    } else {
        el.textContent = 'UNAVAILABLE';
        el.className = 'cap-badge cap-off';
        if (icon) {
            icon.className = 'cap-icon cap-icon-off';
            icon.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>';
        }
    }
}

// Load live status
async function loadLiveStatus() {
    // GUARD: previously no lock existed here, so if one poll's root-shell
    // exec took longer than the interval (very possible on the T615 under
    // load, e.g. while the user is actively switching tabs), the next
    // setInterval tick fired anyway and started a second overlapping call.
    // Two overlapping calls each run their own animateStatValue() tween
    // loop against the same DOM element/HSIN_LAST_RAW state, and whichever
    // one writes last "wins" - this is what produced the garbled/inflated
    // numbers on the Monitor tab (e.g. "134.05 GHz"), and the stacked
    // su/exec spawns are extra CPU load right when the UI thread is
    // already busy handling a tab switch. Skipping a tick when one is
    // still in flight fixes both.
    if (HSIN.statusPollInFlight) return;
    HSIN.statusPollInFlight = true;
    let raw;
    try {
        raw = await hsinExec('status');
    } finally {
        HSIN.statusPollInFlight = false;
    }
    const data = parseJSON(raw);
    if (!data) {
        addLogOnce('status', `Live status failed: ${raw === null ? 'no response from exec bridge' : raw}`, 'error');
        return;
    }
    // Recovered from a previous failure -> clear the throttle so a future
    delete HSIN.lastErrors['status'];

    animateStatValue('cpu-temp', data.cpu_temp, formatTemp);
    animateStatValue('gpu-temp', data.gpu_temp, formatTemp);
    animateStatValue('cpu-freq', data.cpu_freq, formatFreq);
    animateStatValue('gpu-freq', data.gpu_freq, formatFreq);
    document.getElementById('current-profile').textContent = data.profile || 'none';
    addLogOnce('profile-state', `Active profile: ${data.profile || 'none'}`, 'success');

    // Read-only status for the 4 auto-managed-per-profile features (no
    // manual toggle - value just reflects whatever the active profile set).
    if (data.global_rr_enabled === 'true') {
        const mode = data.global_rr_reduced === 'true' ? 'Reduced' : 'Range';
        setTextIfExists('status-global-rr', `${mode} ${data.global_rr_peak_hz}/${data.global_rr_min_hz}Hz`);
    } else {
        setTextIfExists('status-global-rr', 'Off');
    }
    if (data.dvfs_enabled === 'true') {
        setTextIfExists('status-dvfs', `CPU ${data.dvfs_cpu_limit}% / GPU ${data.dvfs_gpu_limit}%`);
    } else {
        setTextIfExists('status-dvfs', 'Off (100%)');
    }
    setTextIfExists('status-frame-limit', data.frame_limit_disabled === 'true' ? 'Disabled (uncapped)' : 'Default');
    setTextIfExists('status-surfaceflinger', data.surfaceflinger_enabled === 'true' ? 'On' : 'Off');

    // Home tab mini tiles - mirrors the Monitor tab so it's useful at a
    // glance without switching tabs.
    setTextIfExists('home-cpu-freq', formatFreq(data.cpu_freq));
    setTextIfExists('home-gpu-freq', formatFreq(data.gpu_freq));
    setTextIfExists('home-cpu-temp', formatTemp(data.cpu_temp));
    setTextIfExists('home-battery', formatBattery(data.battery_pct));

    // CPU/GPU frequency bars - real cur/max percentage now that the
    // backend reports the hardware ceiling, instead of a fixed width.
    setBarWidth('cpu-freq-bar', percentOf(data.cpu_freq, data.cpu_max_khz));
    setBarWidth('gpu-freq-bar', percentOf(data.gpu_freq, data.gpu_max_khz));

    // Per-cluster (big/LITTLE) breakdown, so you can spot-check the
    // averaged CPU Freq number above against each cluster individually
    // (same idea as a separate monitoring app) without leaving the WebUI.
    // Backend sends 0 for cpu_freq_little on homogeneous/single-cluster
    // CPUs - hide the row entirely in that case since there's nothing to
    // break down.
    const clusterRow = document.getElementById('cpu-cluster-row');
    if (clusterRow) {
        const wantVisible = data.cpu_freq_little > 0;
        // Guard the display write too - toggling display on an already
        // shown/hidden row every poll is a wasted style recalc.
        if (HSIN_LAST_STATE['cpu-cluster-row-visible'] !== wantVisible) {
            HSIN_LAST_STATE['cpu-cluster-row-visible'] = wantVisible;
            clusterRow.style.display = wantVisible ? '' : 'none';
        }
        if (wantVisible) {
            setTextIfExists('cpu-freq-big', formatFreq(data.cpu_freq_big));
            setTextIfExists('cpu-freq-little', formatFreq(data.cpu_freq_little));
        }
    }

    // RAM
    const ramTotalEl = document.getElementById('ram-total-inline');
    const ramUsedEl = document.getElementById('ram-used');
    if (ramUsedEl) setFirstChildText(ramUsedEl, 'ram-used-text', formatRAM(data.ram_used_kb) + ' ');
    if (ramTotalEl) setTextIfExists('ram-total-inline', `/ ${formatRAM(data.ram_total_kb)}`);
    setBarWidth('ram-used-bar', percentOf(data.ram_used_kb, data.ram_total_kb));

    // Battery
    setTextIfExists('battery-level', formatBattery(data.battery_pct));
    setBarWidth('battery-level-bar', data.battery_pct >= 0 ? data.battery_pct : 0);

    // Color-coded warning states: low battery / hot temps change color so
    // it reads at a glance instead of needing to parse every number.
    const battState = batteryState(data.battery_pct);
    setTileState(['battery-tile'], battState);
    setTileState(['battery-level'], battState);
    setTileState(['home-battery'], battState);

    const cpuTempC = data.cpu_temp > 1000 ? Math.round(data.cpu_temp / 1000) : data.cpu_temp;
    const gpuTempC = data.gpu_temp > 1000 ? Math.round(data.gpu_temp / 1000) : data.gpu_temp;
    const cpuTState = tempState(cpuTempC);
    const gpuTState = tempState(gpuTempC);
    setTileState(['cpu-temp-tile'], cpuTState);
    setTileState(['cpu-temp'], cpuTState);
    setTileState(['gpu-temp-tile'], gpuTState);
    setTileState(['gpu-temp'], gpuTState);
    setTileState(['home-cpu-temp'], cpuTState);

    // FPS (panel refresh rate - see note in action.sh) + WebUI poll interval
    const fpsEl = document.getElementById('fps-value');
    if (fpsEl) setFirstChildText(fpsEl, 'fps-value-text', (data.refresh_hz > 0 ? data.refresh_hz : '-') + ' ');

    // Battery temperature (single power_supply node read, tenths-of-C
    // already converted to whole C by action.sh).
    const battTempEl = document.getElementById('battery-temp-value');
    const battTempC = parseInt(data.battery_temp_c, 10) || 0;
    if (battTempEl) setFirstChildText(battTempEl, 'batt-temp-text', (battTempC > 0 ? battTempC : '-') + ' ');
    setTileState(['battery-temp-value'], tempState(battTempC));

    // CPU load average (1-min), sent as x100 integer so the wire stays
    // integer-only; divide back down here for display (e.g. 235 -> "2.35").
    const cpuLoadEl = document.getElementById('cpu-load-value');
    const cpuLoadX100 = parseInt(data.cpu_load_x100, 10) || 0;
    if (cpuLoadEl) setFirstChildText(cpuLoadEl, 'cpu-load-text', (cpuLoadX100 / 100).toFixed(2) + ' ');

    // Zram usage %
    const zramEl = document.getElementById('zram-usage-value');
    const zramPct = parseInt(data.zram_pct, 10) || 0;
    if (zramEl) setFirstChildText(zramEl, 'zram-text', zramPct + ' ');

    // Rolling mini-graphs for CPU/GPU freq
    pushGraphSample('cpu', data.cpu_freq, data.cpu_max_khz);
    pushGraphSample('gpu', data.gpu_freq, data.gpu_max_khz);
    setTextIfExists('cpu-graph-value', formatFreq(data.cpu_freq));
    setTextIfExists('gpu-graph-value', formatFreq(data.gpu_freq));
    setHeroProfileIcon(data.profile);
    trackSessionStat('cpu', data.cpu_freq);
    trackSessionStat('gpu', data.gpu_freq);
    updateBatteryDrainRate(data.battery_pct);

    // Uptime (Device tab)
    setTextIfExists('device-uptime', formatUptime(data.uptime_sec));

    // "Updated Xs ago" ticker (Monitor tab)
    HSIN.lastUpdatedAt = Date.now();
    updateLastUpdatedText();

    // Keep the profile radio selection in sync with what's actually active
    if (data.profile && !HSIN.pendingProfile && !HSIN.userSelected) {
        const _radio = document.querySelector(`input[name="profile"][value="${data.profile}"]`);
        if (_radio) _radio.checked = true;
        syncModeCardSelection();
    }

    // Confirm the background apply actually landed, so the log shows a
    // PATCH v4.0: konfirmasi HARUS nunggu APPLY_STATUS "done:" dari bg job -
    // ACTIVE_PROFILE ditulis di awal apply, jadi tanpa cek ini WebUI
    // bilang "beres" padahal engine masih jalan (notif "Profile applied"
    // baru muncul belakangan). Fallback "unknown" = backend lama, tetap
    // konfirmasi demi kompatibilitas.
    const _hsinApplySt = data.apply_status || 'unknown';
    const _hsinApplyDone = _hsinApplySt === 'unknown' || String(_hsinApplySt).startsWith('done:');
    if (HSIN.pendingProfile && data.profile === HSIN.pendingProfile && _hsinApplyDone) {
        addLog(`Profile ${data.profile} is now active`, 'success');
        HSIN.pendingProfile = null;
        HSIN.userSelected = false;
        clearTimeout(HSIN.pendingTimeout);
        setApplyingState(false);
        startAutoRefresh(); // PATCH v4.0: keluar fast-poll, balik 5 detik

        // Quick success pulse on the Apply button - only on actual
        // confirmed activation, not just on tap.
        const applyBtn = document.getElementById('btn-apply');
        if (applyBtn) {
            applyBtn.classList.remove('pulse-success');
            void applyBtn.offsetWidth;
            applyBtn.classList.add('pulse-success');
        }
    }
}

// Load conflicts
async function loadConflicts() {
    const data = parseJSON(await hsinExec('conflicts'));
    const container = document.getElementById('conflicts-list');

    if (!data || data.count === 0) {
        container.innerHTML = '<div class="no-conflicts"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2l8 4v6c0 5-3.5 8.5-8 10-4.5-1.5-8-5-8-10V6l8-4z"/><polyline points="9 12 11 14 15 10"/></svg> No conflicting modules detected</div>';
        return;
    }

    let html = '';
    for (const conflict of data.conflicts) {
        html += `
            <div class="conflict-item warning">
                <div class="conflict-name">⚠ ${conflict.name} detected</div>
                <div class="conflict-detail">
                    <strong>Path:</strong> ${conflict.path}<br>
                    <strong>Conflict:</strong> ${conflict.conflict}
                </div>
            </div>
        `;
    }
    container.innerHTML = html;
}

// Apply profile
// Toggles the whole "is a profile switch in flight" visual state: the
// Apply button spinner AND the hero ACTIVE->SWITCHING badge move
// together, since they're describing the same thing (a background
// engine apply that hasn't confirmed yet) - previously only the button
// text changed, and only for the duration of the initial hsinExec call
// (which returns almost instantly since the real work is backgrounded),
// so the button looked "done" seconds before the profile actually was.
function setApplyingState(isApplying) {
    const btn = document.getElementById('btn-apply');
    const label = document.getElementById('btn-apply-label');
    const badge = document.getElementById('hero-active-badge');
    const badgeLabel = document.getElementById('hero-active-label');
    if (btn) {
        btn.disabled = isApplying;
        btn.classList.toggle('is-applying', isApplying);
    }
    if (label) label.textContent = isApplying ? 'Applying...' : 'Apply';
    if (badge) badge.classList.toggle('is-switching', isApplying);
    if (badgeLabel) badgeLabel.textContent = isApplying ? 'SWITCHING' : 'ACTIVE';
}

async function applyProfile() {
    const profile = document.querySelector('input[name="profile"]:checked').value;

    let envPrefix = '';
    if (profile === 'extreme') {
        const ok = await showConfirmModal({
            title: 'Extreme Mode Warning',
            message:
                'This mode pushes CPU/GPU to their maximum limits and reduces the ' +
                'thermal safety margin. Risk of overheating, throttling, or ' +
                '(rarely) permanent damage without adequate cooling.<br><br>' +
                'Rollback is always available (Rollback button) if something goes wrong.',
            confirmLabel: 'Use Extreme',
            cancelLabel: 'Cancel',
            danger: true
        });
        if (!ok) {
            addLog('Extreme mode cancelled by user');
            return;
        }
        // Extreme is gated behind ALLOW_EXTREME in action.sh; only send this
        envPrefix = 'ALLOW_EXTREME=true';
    }

    setApplyingState(true);
    addLog(`Applying profile: ${profile}`);

    const result = await hsinExec('apply', profile, envPrefix);

    if (result && result.startsWith('OK')) {
        addLog(result, 'success');
        // action.sh runs the actual engine work in the background - the
        // spinner/SWITCHING state stays on past this point on purpose,
        // it's cleared later by loadLiveStatus() once data.profile
        // actually flips (the confirm block below) or by the timeout.
        HSIN.pendingProfile = profile;
        // PATCH v4.0: fast-poll window selama apply. Poll normal 5 detik
        // bikin 'done' baru kebaca s/d 5 detik SETELAH engine selesai;
        // selama pendingProfile aktif, poll tiap 1 detik lalu balik normal
        // pas profil ke-confirm (blok konfirmasi) atau timeout.
        clearInterval(refreshInterval);
        refreshInterval = setInterval(() => { loadLiveStatus(); }, 1000);
        // Safety net: if it never actually completes (e.g. setsid missing
        clearTimeout(HSIN.pendingTimeout);
        HSIN.pendingTimeout = setTimeout(() => {
            if (HSIN.pendingProfile === profile) {
                addLog(`Profile ${profile} not confirmed after 45s - check the Monitor tab`, 'warning');
                HSIN.pendingProfile = null;
                // FIX: userSelected was never reset here, so after one
                // timed-out apply the mode-card radio would silently stop
                // following the real active profile for the rest of the
                // session (loadLiveStatus skips re-sync while userSelected
                // is true).
                HSIN.userSelected = false;
                setApplyingState(false);
                startAutoRefresh(); // PATCH v4.0: keluar fast-poll
            }
        }, 45000);
    } else {
        addLog(result || 'Failed to apply profile', 'error');
        setApplyingState(false);
    }

    // Refresh status
    loadLiveStatus();
}

// Backup
async function backup() {
    const btn = document.getElementById('btn-backup');
    setActionTileBusy(btn, true, 'Backing up...');

    addLog('Creating backup...');

    const result = await hsinExec('backup');

    if (result && result.startsWith('OK')) {
        addLog(result, 'success');
        showToast('Backup created', 'success');
    } else {
        addLog(result || 'Backup failed', 'error');
        showToast('Backup failed', 'error');
    }

    setActionTileBusy(btn, false, 'Backup');
}

// Rollback
async function rollback() {
    const ok = await showConfirmModal({
        title: 'Rollback',
        message: 'Restore the last backup? This will overwrite your current engine configuration.',
        confirmLabel: 'Rollback',
        cancelLabel: 'Cancel',
        danger: true
    });
    if (!ok) return;

    const btn = document.getElementById('btn-rollback');
    setActionTileBusy(btn, true, 'Rolling back...');

    addLog('Rolling back...');

    const result = await hsinExec('rollback');

    if (result && result.startsWith('OK')) {
        addLog(result, 'success');
        showToast('Rollback complete', 'success');
    } else {
        addLog(result || 'Rollback failed', 'error');
        showToast('Rollback failed', 'error');
    }

    setActionTileBusy(btn, false, 'Rollback');

    loadLiveStatus();
}

// Doctor
async function doctor() {
    const btn = document.getElementById('btn-doctor');
    setActionTileBusy(btn, true, 'Diagnosing...');
    addLog('Running diagnostics...');

    const conflicts = parseJSON(await hsinExec('conflicts'));
    const caps = parseJSON(await hsinExec('capabilities'));

    if (conflicts && conflicts.count > 0) {
        addLog(`Found ${conflicts.count} conflicting module(s)`, 'warning');
        for (const c of conflicts.conflicts) {
            addLog(`  ⚠ ${c.name}: ${c.conflict}`, 'warning');
        }
        showToast(`${conflicts.count} conflict(s) found`, 'warning');
    } else {
        addLog('No conflicts detected', 'success');
        showToast('No conflicts detected', 'success');
    }

    setActionTileBusy(btn, false, 'Doctor');
    loadConflicts();
}

// ===== Settings toggles =====

async function loadSettings() {
    const data = parseJSON(await hsinExec('config-get'));
    if (!data) return;
    document.getElementById('toggle-gam-boost').checked = data.gam_boost_enabled === 'true';
    document.getElementById('toggle-allow-extreme').checked = data.allow_extreme === 'true';
    document.getElementById('toggle-downscale').checked = data.downscale_enabled === 'true';

    const savedPercent = parseInt(data.downscale_percent, 10) || 30;
    setDownscaleSliderValue(savedPercent, false);
    document.getElementById('downscale-slider-row').style.display =
        data.downscale_enabled === 'true' ? '' : 'none';

    const renderer = data.renderer || 'system';
    const input = document.querySelector(`input[name="renderer"][value="${renderer}"]`);
    if (input) input.checked = true;
    syncRendererSelection();
    refreshDownscaleNote();
}

// ===== System-wide display downscale =====
//
// Custom slider (not <input type=range>) - see the CSS comment above
// .hsin-slider for why. State lives in a plain object instead of the
// DOM's own `value` so reads are synchronous and never depend on a
// particular browser's range-input quirks.
const HSIN_DOWNSCALE_DEFAULT_PERCENT = 30; // must match HSIN_DOWNSCALE_DEFAULT_PERCENT in engine/display/downscale.sh
const hsinDownscale = { min: 1, max: 99, value: 30, dragging: false };

function setDownscaleSliderValue(value, animateThumb) {
    value = Math.min(hsinDownscale.max, Math.max(hsinDownscale.min, Math.round(value)));
    hsinDownscale.value = value;

    const pct = (value - hsinDownscale.min) / (hsinDownscale.max - hsinDownscale.min);
    const fill = document.getElementById('downscale-slider-fill');
    const thumb = document.getElementById('downscale-slider-thumb');
    if (fill) fill.style.transform = `scaleX(${pct})`;
    if (thumb) {
        // Position via left% - cheap for the browser to compute and,
        // combined with will-change:left in the CSS, stays composited
        // instead of forcing a layout pass on every pointermove.
        thumb.style.left = `${pct * 100}%`;
        if (!animateThumb) {
            // Skip the CSS scale transition on programmatic updates
            // (initial load, backend sync) so the thumb doesn't visibly
            // "pop" - only real finger drags should ever animate.
            thumb.style.transition = 'none';
            requestAnimationFrame(() => { thumb.style.transition = ''; });
        }
    }
    document.getElementById('downscale-percent-label').textContent = `${value}%`;
}

function initDownscaleSlider() {
    const el = document.getElementById('downscale-slider');
    if (!el || el._hsinInit) return;
    el._hsinInit = true;

    const valueFromEvent = (clientX) => {
        const rect = el.getBoundingClientRect();
        const pct = Math.min(1, Math.max(0, (clientX - rect.left) / rect.width));
        return hsinDownscale.min + pct * (hsinDownscale.max - hsinDownscale.min);
    };

    // Direction-lock drag (fixes "mau scroll kebawah malah kescroll
    // resolusinya"): pointerdown/touchstart on a full-width slider row
    // sitting inside a scrollable settings page WILL catch the start of
    // a vertical scroll swipe too - there's no way around that, the
    // element is right there under the finger. What was missing is not
    // committing to "this is a drag" immediately. Now we wait for the
    // first real movement and check its direction: mostly horizontal ->
    // it's a slider drag, capture the pointer and proceed as before.
    // Mostly vertical -> it's a page scroll, so we back off completely
    // (no preventDefault, no capture) and let the browser scroll
    // natively; touch-action: pan-y on the element (see style.css) is
    // what makes the browser willing to do that instead of the touch
    // being swallowed by having a pointer/touch listener at all.
    const DRAG_SLOP = 6; // px of movement before committing to a direction

    let pointerId = null;
    let pending = null; // {x, y, clientX} while direction is still undecided
    let confirmed = false; // true once we've committed to "this is a drag"

    const beginPending = (e, clientX, clientY) => {
        pointerId = e.pointerId !== undefined ? e.pointerId : null;
        pending = { x: clientX, y: clientY };
        confirmed = false;
        // Deliberately no preventDefault() and no setPointerCapture()
        // here yet - grabbing either now is what used to hijack page
        // scroll from the very first touch, before we even know if the
        // gesture is a drag or a scroll.
    };

    // BUGFIX (kept from before): el.setPointerCapture() throws on some
    // OEM/older Android WebView builds (common on budget Unisoc devices
    // + some KernelSU Manager webview forks with partial Pointer Events
    // support). Wrapped so a throw here can't abort the drag.
    const confirmDrag = (clientX) => {
        confirmed = true;
        try {
            if (pointerId !== null) el.setPointerCapture(pointerId);
        } catch (_) {
            // Unsupported/failed capture - keep dragging via move/up
            // listeners on the element itself instead of aborting.
        }
        el.classList.add('is-dragging');
        hsinDownscale.dragging = true;
        // Pausing the 1.2s status poll for the duration of the drag:
        // hsinExec() round-trips through the native root-shell bridge,
        // and on some bridge implementations that call blocks the JS
        // main thread until the shell command returns. If a poll lands
        // mid-drag, every queued pointermove is delayed until it
        // resolves - that's the "delay + ngelag + patah-patah" feeling.
        stopAutoRefresh();
        setDownscaleSliderValue(valueFromEvent(clientX), true);
    };

    const moveDrag = (clientX) => {
        if (!hsinDownscale.dragging) return;
        // Direct 1:1 update, no easing/debounce - this is what keeps it
        // glued to the finger instead of feeling like it's catching up.
        setDownscaleSliderValue(valueFromEvent(clientX), true);
    };

    const endDrag = () => {
        pending = null;
        if (!hsinDownscale.dragging) return;
        hsinDownscale.dragging = false;
        confirmed = false;
        el.classList.remove('is-dragging');
        if (pointerId !== null) {
            try { el.releasePointerCapture(pointerId); } catch (_) { /* already released */ }
        }
        pointerId = null;
        startAutoRefresh();
        // No auto-commit here anymore - the drag now only previews a
        // value locally. Committing it to the backend (the actual `wm
        // size`/`wm density` call) is now an explicit tap on the Apply
        // button, exactly so a slip mid-scroll can never silently change
        // the running resolution.
    };

    el.addEventListener('pointerdown', (e) => {
        beginPending(e, e.clientX, e.clientY);
    });
    el.addEventListener('pointermove', (e) => {
        if (pointerId !== null && e.pointerId !== pointerId) return;
        if (confirmed) {
            e.preventDefault();
            moveDrag(e.clientX);
            return;
        }
        if (!pending) return;
        const dx = e.clientX - pending.x;
        const dy = e.clientY - pending.y;
        if (Math.abs(dx) < DRAG_SLOP && Math.abs(dy) < DRAG_SLOP) return; // not enough movement yet
        if (Math.abs(dx) > Math.abs(dy)) {
            e.preventDefault();
            confirmDrag(e.clientX);
        } else {
            // Vertical intent won - this is a scroll, not a drag. Drop
            // out entirely for the rest of this gesture; browser handles
            // the scroll on its own from here.
            pending = null;
            pointerId = null;
        }
    });
    el.addEventListener('pointerup', endDrag);
    el.addEventListener('pointercancel', endDrag);

    // Touch-event fallback for WebViews that expose Pointer Events but
    // implement them badly (the exact failure mode above) rather than
    // not at all, so feature-detecting PointerEvent isn't enough on its
    // own - only wire this up if setPointerCapture is missing entirely,
    // which is the more reliable signal of a broken/partial impl.
    if (!el.setPointerCapture) {
        el.addEventListener('touchstart', (e) => {
            const t = e.touches[0];
            beginPending(e, t.clientX, t.clientY);
        }, { passive: true });
        el.addEventListener('touchmove', (e) => {
            const t = e.touches[0];
            if (confirmed) {
                moveDrag(t.clientX);
                e.preventDefault();
                return;
            }
            if (!pending) return;
            const dx = t.clientX - pending.x;
            const dy = t.clientY - pending.y;
            if (Math.abs(dx) < DRAG_SLOP && Math.abs(dy) < DRAG_SLOP) return;
            if (Math.abs(dx) > Math.abs(dy)) {
                confirmDrag(t.clientX);
                e.preventDefault();
            } else {
                pending = null;
            }
        }, { passive: false });
        el.addEventListener('touchend', endDrag);
        el.addEventListener('touchcancel', endDrag);
    }

    // Also usable via keyboard for accessibility - arrow keys nudge by 1.
    el.setAttribute('tabindex', '0');
    el.setAttribute('role', 'slider');
    el.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowRight' || e.key === 'ArrowUp') {
            setDownscaleSliderValue(hsinDownscale.value + 1, true);
            onDownscalePercentChange(hsinDownscale.value);
        } else if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') {
            setDownscaleSliderValue(hsinDownscale.value - 1, true);
            onDownscalePercentChange(hsinDownscale.value);
        }
    });
}

// Explicit Apply/Reset buttons (added instead of committing on drag-end):
// with drag-end no longer auto-committing (see initDownscaleSlider), the
// only way the actual system resolution changes now is a deliberate tap
// on one of these two - a value the slider merely PREVIEWS while being
// dragged never reaches `wm size` by accident.
function initDownscaleButtons() {
    const applyBtn = document.getElementById('downscale-apply-btn');
    const resetBtn = document.getElementById('downscale-reset-btn');
    if (applyBtn && !applyBtn._hsinInit) {
        applyBtn._hsinInit = true;
        applyBtn.addEventListener('click', () => {
            if (!document.getElementById('toggle-downscale').checked) {
                showToast('Turn on System Downscale above first', 'warning');
                return;
            }
            onDownscalePercentChange(hsinDownscale.value);
        });
    }
    if (resetBtn && !resetBtn._hsinInit) {
        resetBtn._hsinInit = true;
        resetBtn.addEventListener('click', () => {
            setDownscaleSliderValue(HSIN_DOWNSCALE_DEFAULT_PERCENT, true);
            if (document.getElementById('toggle-downscale').checked) {
                onDownscalePercentChange(hsinDownscale.value);
            }
        });
    }
}

async function refreshDownscaleNote() {
    const noteEl = document.getElementById('downscale-note');
    if (!noteEl) return;
    const status = parseJSON(await hsinExec('downscale-status'));
    if (!status) return;
    if (status.enabled === 'true' && status.current && status.native) {
        noteEl.textContent = `Active: ${status.current} @ ${status.current_dpi}dpi (native: ${status.native} @ ${status.native_dpi}dpi). Persists across reboots.`;
    } else if (status.native && status.native !== 'unknown') {
        noteEl.textContent = `Native: ${status.native} @ ${status.native_dpi}dpi. Will persist across reboots once enabled.`;
    } else {
        noteEl.textContent = 'Persists across reboots. Turn off anytime to restore native resolution.';
    }
}

async function onToggleDownscale(checked) {
    const toggle = document.getElementById('toggle-downscale');
    const sliderRow = document.getElementById('downscale-slider-row');
    const percent = hsinDownscale.value;

    if (checked) {
        const confirmed = window.confirm(
            `Lower system resolution to about ${percent}% of native?\n\nApplies system-wide (not just games) and persists across reboots until you turn it off here. Icon and text size stay the same - only render sharpness is reduced.`
        );
        if (!confirmed) {
            toggle.checked = false;
            return;
        }
        const result = await hsinExec('downscale-enable', percent);
        const failed = !result || result.startsWith('ERROR');
        addLog(result || `Downscale enabled (${percent}%)`, failed ? 'error' : 'success');
        showToast(failed ? 'Failed to enable downscale' : `System downscale active (${percent}%)`, failed ? 'warning' : 'success');
        toggle.checked = !failed;
        sliderRow.style.display = failed ? 'none' : '';
    } else {
        const result = await hsinExec('downscale-disable');
        const failed = !result || result.startsWith('ERROR');
        addLog(result || 'Downscale disabled', failed ? 'error' : 'success');
        showToast(failed ? 'Failed to restore resolution' : 'Native resolution restored', failed ? 'warning' : 'success');
        toggle.checked = failed;
        sliderRow.style.display = failed ? '' : 'none';
    }

    refreshDownscaleNote();
}

// Fires once per completed drag/keypress (not per pointermove) - wm size
// is a heavyish call (force-refreshes the display pipeline), so firing
// it continuously during a drag would feel janky and spam the log.
async function onDownscalePercentChange(percent) {
    if (!document.getElementById('toggle-downscale').checked) return; // not active yet, just previewing

    const result = await hsinExec('downscale-enable', percent);
    const failed = !result || result.startsWith('ERROR');
    addLog(result || `Downscale set to ${percent}%`, failed ? 'error' : 'success');
    if (failed) showToast('Failed to update downscale percent', 'warning');
    refreshDownscaleNote();
}

// ===== Renderer (Skia GL/Vulkan) =====

const RENDERER_LABELS = {
    system: 'System Default',
    skiagl: 'Skia GL',
    skiavk: 'Skia Vulkan'
};

function syncRendererSelection() {
    document.querySelectorAll('.renderer-pick').forEach((el) => {
        const input = el.querySelector('input[name="renderer"]');
        el.classList.toggle('selected', !!(input && input.checked));
    });
}

async function onRendererPick(target) {
    const label = RENDERER_LABELS[target] || target;
    const confirmed = window.confirm(
        `Switch render backend to ${label}?\n\nAll open apps will be force-closed and reopened automatically. This choice persists across reboots.`
    );
    if (!confirmed) {
        // Revert the radio to whatever is actually saved, since the user
        // cancelled - otherwise the UI shows a selection that never applied.
        await loadSettings();
        return;
    }

    const result = await hsinExec('renderer-apply', target);
    addLog(result || `Renderer set to ${target}`, result && result.startsWith('ERROR') ? 'error' : 'success');
    showToast(result && result.startsWith('ERROR') ? 'Failed to switch renderer' : `Renderer: ${label}`, result && result.startsWith('ERROR') ? 'warning' : 'success');

    const check = document.getElementById('check-renderer');
    if (check) {
        check.classList.add('is-visible');
        clearTimeout(check._hideTimer);
        check._hideTimer = setTimeout(() => check.classList.remove('is-visible'), 1400);
    }

    syncRendererSelection();
}

async function onToggleSetting(key, checked, checkElId) {
    const value = checked ? 'true' : 'false';
    const result = await hsinExec('config-set', `${key} ${value}`);
    addLog(result || `Setting updated: ${key} = ${value}`, 'success');

    // Brief checkmark flash to confirm the save landed
    const check = checkElId ? document.getElementById(checkElId) : null;
    if (check) {
        check.classList.add('is-visible');
        clearTimeout(check._hideTimer);
        check._hideTimer = setTimeout(() => check.classList.remove('is-visible'), 1400);
    }
}

// ===== Game Profiles list + Add Game picker =====

const GAME_PROFILE_LABELS = {
    battery: 'Battery',
    balanced: 'Balanced',
    performance: 'Performance',
    extreme: 'Extreme'
};

let gamePickerSelectedPkg = null;
let gamePickerAllApps = [];

let cachedGameList = [];

async function loadGameList() {
    const data = parseJSON(await hsinExec('game-list'));
    cachedGameList = Array.isArray(data) ? data : [];
    renderGameListItems(cachedGameList);
}

function renderGameListItems(data) {
    const container = document.getElementById('game-list');
    if (!container) return;

    if (!data || data.length === 0) {
        const emptyMsg = 'No games added yet - tap "+ Add Game" to boost your first one.';
        container.innerHTML = `<div class="empty-state"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="10" rx="5"/><line x1="6" y1="12" x2="10" y2="12"/><line x1="8" y1="10" x2="8" y2="14"/><circle cx="16" cy="10.5" r="1" fill="currentColor" stroke="none"/><circle cx="18" cy="13" r="1" fill="currentColor" stroke="none"/></svg><span>${emptyMsg}</span></div>`;
        return;
    }

    let html = '';
    for (const g of data) {
        const label = GAME_PROFILE_LABELS[g.profile] || g.profile;
        html += `
            <div class="game-item">
                <span class="game-item-left">
                    <span class="game-item-icon profile-${g.profile}"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="7" width="20" height="10" rx="5"/><line x1="6" y1="12" x2="10" y2="12"/><line x1="8" y1="10" x2="8" y2="14"/><circle cx="16" cy="10.5" r="1" fill="currentColor" stroke="none"/><circle cx="18" cy="13" r="1" fill="currentColor" stroke="none"/></svg></span>
                    <span class="game-item-pkg">${g.package}</span>
                </span>
                <span class="game-item-right">
                    <span class="game-profile-badge profile-${g.profile}">${label}</span>
                    <button class="game-item-remove" data-pkg="${g.package}" title="Remove">✕</button>
                </span>
            </div>
        `;
    }
    container.innerHTML = html;

    container.querySelectorAll('.game-item-remove').forEach((btn) => {
        btn.addEventListener('click', () => removeGame(btn.dataset.pkg));
    });
}

async function removeGame(pkg) {
    if (!pkg) return;
    const result = await hsinExec('game-remove', pkg);
    addLog(result || `Removed ${pkg}`, 'success');
    loadGameList();
}

function openGamePicker() {
    gamePickerSelectedPkg = null;
    const overlay = document.getElementById('game-picker-overlay');
    overlay.classList.remove('hidden');
    // Force a reflow so the .open transition actually plays instead of
    // snapping instantly (removing "hidden" and adding "open" in the same
    // frame would skip the transition).
    void overlay.offsetWidth;
    overlay.classList.add('open');

    document.getElementById('game-picker-step-list').classList.remove('hidden');
    document.getElementById('game-picker-step-profile').classList.add('hidden');
    document.getElementById('game-picker-title').textContent = 'Select a game';
    document.getElementById('game-search').value = '';

    const listEl = document.getElementById('app-list');
    listEl.innerHTML = '<p class="picker-loading">Loading installed apps...</p>';

    hsinExec('list-apps').then((result) => {
        const apps = parseJSON(result);
        gamePickerAllApps = Array.isArray(apps) ? apps : [];
        if (gamePickerAllApps.length === 0) {
            listEl.innerHTML = '<p class="picker-loading">No apps found (or "pm" unavailable).</p>';
            return;
        }
        renderAppList(gamePickerAllApps);
    });
}

function renderAppList(apps) {
    const listEl = document.getElementById('app-list');
    if (apps.length === 0) {
        listEl.innerHTML = '<p class="picker-loading">No matches.</p>';
        return;
    }
    let html = '';
    for (const pkg of apps) {
        html += `<div class="app-list-item" data-pkg="${pkg}">${pkg}</div>`;
    }
    listEl.innerHTML = html;
    listEl.querySelectorAll('.app-list-item').forEach((el) => {
        el.addEventListener('click', () => selectAppForProfile(el.dataset.pkg));
    });
}

function filterAppList(query) {
    const q = query.trim().toLowerCase();
    const filtered = q
        ? gamePickerAllApps.filter((pkg) => pkg.toLowerCase().includes(q))
        : gamePickerAllApps;
    renderAppList(filtered);
}

function selectAppForProfile(pkg) {
    gamePickerSelectedPkg = pkg;
    document.getElementById('game-picker-step-list').classList.add('hidden');
    document.getElementById('game-picker-step-profile').classList.remove('hidden');
    document.getElementById('game-picker-title').textContent = 'Choose profile';
    document.getElementById('picker-selected-pkg-name').textContent = pkg;
}

function backToAppList() {
    document.getElementById('game-picker-step-list').classList.remove('hidden');
    document.getElementById('game-picker-step-profile').classList.add('hidden');
    document.getElementById('game-picker-title').textContent = 'Select a game';
}

async function confirmGameProfile(profile) {
    if (!gamePickerSelectedPkg) return;
    const pkg = gamePickerSelectedPkg;
    closeGamePicker();
    addLog(`Adding ${pkg} -> ${profile}...`);
    const result = await hsinExec('game-add', `${pkg} ${profile}`);
    addLog(result || `Added ${pkg} -> ${profile}`, 'success');
    loadGameList();
}

function closeGamePicker() {
    const overlay = document.getElementById('game-picker-overlay');
    overlay.classList.remove('open');
    gamePickerSelectedPkg = null;
    // Wait for the close transition to finish before actually hiding it,
    // otherwise it'd just vanish instantly instead of sliding down.
    setTimeout(() => overlay.classList.add('hidden'), 200);
}

// Auto-refresh
let refreshInterval;

function startAutoRefresh() {
    // Poll interval is HSIN.pollIntervalMs (2000ms). The real fix for the
    // tab-switch lag was on the shell side (action.sh's status command
    // was forking 100+ processes and calling dumpsys 3x per poll) - see
    // core/profile_loader.sh and action.sh for the details. This ONLY
    // runs while the WebUI page itself is open/alive - closing the WebUI
    // destroys this JS context, so nothing keeps polling in the
    // background on its own.
    clearInterval(refreshInterval);
    refreshInterval = setInterval(() => {
        loadLiveStatus();
    }, HSIN.pollIntervalMs);
    startLastUpdatedTicker();
}

function stopAutoRefresh() {
    clearInterval(refreshInterval);
    stopLastUpdatedTicker();
}

// Pause polling the instant the WebUI is backgrounded/minimized (screen
// off, app-switched away, tab hidden inside a WebView host) instead of
// quietly hammering sysfs while nobody's looking at it, and resume the
// moment it's foregrounded again with an immediate refresh so the
// numbers aren't stale.
document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
        stopAutoRefresh();
    } else {
        loadLiveStatus();
        startAutoRefresh();
    }
});

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    openDiscordOnce();

    // Boot sequence: engine start, then root bridge status, then
    // hardware/capability detection results as loadDeviceInfo() and
    // loadCapabilities() resolve below - reads like a real device log.
    addLog('HSIN engine initialized', 'success');

    // Report bridge status up front so a broken bridge shows in the log
    if (window.ksu && typeof window.ksu.exec === 'function') {
        addLog('Root bridge detected (window.ksu)', 'success');
    } else {
        addLog('No root bridge found - open via KernelSU Manager or WebUI-X', 'error');
    }

    // Default theme so the hero card isn't uncolored before the first
    // status poll resolves; loadLiveStatus() will correct it immediately.
    applyProfileTheme('balanced');

    // Load initial data
    loadDeviceInfo();
    loadCapabilities();
    loadLiveStatus();
    loadConflicts();
    loadGameList();
    loadSettings();

    // Event listeners
    document.getElementById('btn-apply').addEventListener('click', applyProfile);
    document.getElementById('btn-backup').addEventListener('click', backup);
    document.getElementById('btn-rollback').addEventListener('click', rollback);
    document.getElementById('btn-doctor').addEventListener('click', doctor);

    document.getElementById('toggle-gam-boost').addEventListener('change', (e) => {
        onToggleSetting('GAM_BOOST_ENABLED', e.target.checked, 'check-gam-boost');
    });
    document.getElementById('toggle-allow-extreme').addEventListener('change', (e) => {
        onToggleSetting('ALLOW_EXTREME', e.target.checked, 'check-allow-extreme');
    });

    document.querySelectorAll('input[name="renderer"]').forEach((input) => {
        input.addEventListener('change', () => onRendererPick(input.value));
    });

    document.getElementById('toggle-downscale').addEventListener('change', (e) => {
        onToggleDownscale(e.target.checked);
    });
    initDownscaleSlider();
    initDownscaleButtons();

    // Add Game picker
    document.getElementById('btn-add-game').addEventListener('click', openGamePicker);
    document.getElementById('btn-close-picker').addEventListener('click', closeGamePicker);
    document.getElementById('btn-picker-back').addEventListener('click', backToAppList);
    document.getElementById('game-search').addEventListener('input', (e) => filterAppList(e.target.value));
    document.querySelectorAll('.profile-pick-btn').forEach((btn) => {
        btn.addEventListener('click', () => confirmGameProfile(btn.dataset.profile));
    });

    // Mode-card tiles: reflect selection instantly on tap instead of
    document.querySelectorAll('input[name="profile"]').forEach((input) => {
        input.addEventListener('change', () => {
            HSIN.userSelected = true;
            syncModeCardSelection();
            applyProfileTheme(input.value);
        });
    });
    syncModeCardSelection();

    const clearLogBtn = document.getElementById('btn-clear-log');
    if (clearLogBtn) {
        clearLogBtn.addEventListener('click', () => {
            document.getElementById('log-output').innerHTML = '';
            HSIN.logLines = [];
        });
    }

    // Export button was previously dead (no listener at all). Downloads
    // the log currently visible in the WebUI as a .txt file directly in
    // the browser/WebView (works with no storage permission needed), and
    // separately asks action.sh to also write the full multi-source
    // debug bundle into HSIN_DATA for deeper troubleshooting.
    const exportLogBtn = document.getElementById('btn-export-log');
    if (exportLogBtn) {
        exportLogBtn.addEventListener('click', async () => {
            const text = HSIN.logLines.length ? HSIN.logLines.join('\n') : 'Log kosong.';
            try {
                const blob = new Blob([text], { type: 'text/plain' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = `hsin-log-${Date.now()}.txt`;
                document.body.appendChild(a);
                a.click();
                a.remove();
                URL.revokeObjectURL(url);
            } catch (e) {
                console.error('Export log download failed:', e);
            }
            const result = await hsinExec('export-debug');
            addLog(result || 'Debug report written to HSIN data folder', 'success');
            showToast('Log exported', 'success');
        });
    }

    // Root bridge chip in the header row
    const rootDot = document.getElementById('chip-root-dot');
    const rootText = document.getElementById('chip-root-text');
    if (window.ksu && typeof window.ksu.exec === 'function') {
        if (rootDot) rootDot.classList.add('dot-green');
        if (rootText) rootText.textContent = 'Root Granted';
    } else {
        if (rootDot) rootDot.classList.add('dot-red');
        if (rootText) rootText.textContent = 'Root Not Found';
    }

    // Bridge health retry button
    const bridgeRetryBtn = document.getElementById('btn-bridge-retry');
    if (bridgeRetryBtn) {
        bridgeRetryBtn.addEventListener('click', () => {
            addLog('Manual retry requested');
            refreshAll();
        });
    }

    // Display preferences - persisted locally since they're purely
    // cosmetic (nothing here touches the engine itself).
    const reduceMotionToggle = document.getElementById('toggle-reduce-motion');
    try {
        const reduceMotion = localStorage.getItem('hsin_reduce_motion') === '1';
        document.body.classList.toggle('reduce-motion', reduceMotion);
        if (reduceMotionToggle) reduceMotionToggle.checked = reduceMotion;
    } catch (e) {
        // localStorage unavailable in some WebView hosts - defaults apply
    }
    if (reduceMotionToggle) {
        reduceMotionToggle.addEventListener('change', (e) => {
            document.body.classList.toggle('reduce-motion', e.target.checked);
            try { localStorage.setItem('hsin_reduce_motion', e.target.checked ? '1' : '0'); } catch (e2) {}
        });
    }

    // Night tint: cosmetic only, recalculated once at load
    const hour = new Date().getHours();
    document.body.classList.toggle('is-night', hour >= 20 || hour < 6);

    // Reset the unread Log badge whenever the Log tab is actually opened
    const logNavItem = document.querySelector('.nav-item[data-tab="log"]');
    if (logNavItem) {
        logNavItem.addEventListener('click', () => {
            HSIN.unreadLogCount = 0;
            updateLogBadge();
        });
    }

    // Swipe left/right between tabs, in addition to tapping the bottom nav
    setupSwipeNavigation();

    // Start auto-refresh
    startAutoRefresh();

    addLog('HSIN WebUI initialized', 'success');
});

// Swipe between tabs. Deliberately simple: no live drag-following visual,
// just detects a clear horizontal swipe on release and switches to the
// next/previous tab in nav order - keeps it cheap and avoids fighting the
// page's own vertical scroll.
function setupSwipeNavigation() {
    const content = document.querySelector('.tab-content');
    const navItems = Array.from(document.querySelectorAll('.nav-item'));
    if (!content || navItems.length === 0) return;

    let startX = 0, startY = 0, tracking = false;

    content.addEventListener('touchstart', (e) => {
        if (e.touches.length !== 1) return;
        startX = e.touches[0].clientX;
        startY = e.touches[0].clientY;
        tracking = true;
    }, { passive: true });

    content.addEventListener('touchend', (e) => {
        if (!tracking) return;
        tracking = false;
        const dx = e.changedTouches[0].clientX - startX;
        const dy = e.changedTouches[0].clientY - startY;
        // Require a clearly horizontal, clearly intentional swipe so it
        // doesn't fire during normal vertical scrolling.
        if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.5) return;

        const activeIdx = navItems.findIndex((b) => b.classList.contains('is-active'));
        if (activeIdx === -1) return;
        const nextIdx = dx < 0
            ? Math.min(navItems.length - 1, activeIdx + 1)
            : Math.max(0, activeIdx - 1);
        if (nextIdx !== activeIdx) navItems[nextIdx].click();
    }, { passive: true });
}


