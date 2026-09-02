// Pure reducer for the native Flow Bar. Shared by FlowBar.qml (Qt JS) and the
// node-driven bats test, so it must stay free of QML/Node-only APIs.
//
// Message shape (one JSON object per socket line): { t: "<channel>", p: <payload> }
// Channels mirror Wispr Flow's main -> status-window IPC verbatim, plus the
// bridge's own "hello" announcing the app's resources path.
//
// State shape:
//   mode:          "hidden" | "listening" | "processing" | "error"
//   level:         0..1  smoothed microphone level (status:audioLevel)
//   indicator:     last status:setIndicatorState .state string
//   notification:  null | { title, body, type, timeout, callbackOperationId,
//                           actions: [{ text, callback, style }] }
//   resourcesPath: "" | app resources dir (from hello)

function initial() {
  return { mode: "hidden", level: 0, indicator: "hidden", notification: null, resourcesPath: "" };
}

function clamp01(v) {
  return v < 0 ? 0 : (v > 1 ? 1 : v);
}

// Text for notifications upstream renders with a bespoke React component
// (variant "custom"): our own wording, keyed by notification type.
var CUSTOM_TEXT = {
  AudioQualityIssue: { titleKey: "audio_quality_title", bodyKey: "audio_quality_body", title: "Poor audio quality", body: "Flow could barely hear you. Check the microphone and try again." },
  VoidDictation: { titleKey: "void_dictation_hint", title: "Nothing to type", body: "No speech was detected in that dictation." },
  UpdateSettingsConfirmation: { title: "Settings updated", body: "" },
  DomainCaptureRequiredBlocked: { titleKey: "domain_capture_required_blocked_title", bodyKey: "domain_capture_required_blocked_body", title: "Dictation blocked", body: "Your organization requires a refresh before dictating." }
};

function customText(custom, which, strings) {
  if (!custom) return "";
  var key = custom[which + "Key"];
  if (key && strings && typeof strings[key] === "string") return strings[key];
  return custom[which] || "";
}

function humanize(key) {
  if (typeof key !== "string" || key === "") return "";
  var words = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").replace(/[_-]+/g, " ").trim().toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

// Resolve a text field main sends either as a string, an i18n reference
// ({ key, params? }) or the literal "custom".
function tr(value, strings, type) {
  if (value === undefined || value === null) return "";
  if (typeof value === "string") {
    if (value === "custom") return "";
    return value;
  }
  if (typeof value === "object" && typeof value.key === "string") {
    var raw = strings && typeof strings[value.key] === "string" ? strings[value.key] : humanize(value.key);
    var params = value.params || value.values || value.options || {};
    return raw.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, function (m, name) {
      return params[name] !== undefined ? String(params[name]) : "";
    });
  }
  return "";
}

function buildNotification(p, strings) {
  if (!p || typeof p !== "object") return null;
  var type = typeof p.type === "string" ? p.type : "";
  var custom = CUSTOM_TEXT[type] || null;
  var title = tr(p.title, strings, type);
  var body = tr(p.body, strings, type);
  if (title === "" && custom) title = customText(custom, "title", strings);
  if (body === "" && custom) body = customText(custom, "body", strings);
  if (title === "" && body === "") title = humanize(type);
  var actions = [];
  if (p.actions && p.actions.length) {
    for (var i = 0; i < p.actions.length; i++) {
      var a = p.actions[i];
      if (!a || typeof a.callback !== "string") continue;
      actions.push({ text: tr(a.text, strings, type) || humanize(a.callback), callback: a.callback, style: a.style || "text" });
    }
  }
  return {
    title: title,
    body: body,
    type: type,
    timeout: (typeof p.timeout === "number" && p.timeout > 0) ? p.timeout : 6000,
    callbackOperationId: p.callbackOperationId === undefined ? null : p.callbackOperationId,
    actions: actions
  };
}

function reduce(s, m, strings) {
  var n = { mode: s.mode, level: s.level, indicator: s.indicator, notification: s.notification, resourcesPath: s.resourcesPath || "" };
  if (!m || typeof m.t !== "string") return n;
  switch (m.t) {
  case "hello":
    n.resourcesPath = (m.p && typeof m.p.resourcesPath === "string") ? m.p.resourcesPath : n.resourcesPath;
    break;
  case "status:dictationStatus":
    switch (m.p) {
    case "initializing":
    case "listening":
      n.mode = "listening";
      break;
    case "stopping":
    case "processing":
    case "retrying":
      n.mode = "processing";
      n.level = 0;
      break;
    case "error":
      n.mode = "error";
      n.level = 0;
      break;
    case "idle":
    case "dismissed":
    case "testing":
      n.mode = "hidden";
      n.level = 0;
      break;
    }
    break;
  case "status:setIndicatorState":
    n.indicator = (m.p && typeof m.p.state === "string") ? m.p.state : "hidden";
    if (n.indicator === "polish_processing" || n.indicator === "processing") {
      n.mode = "processing";
    } else if (n.indicator === "error" || n.indicator === "polish_failed") {
      n.mode = "error";
    } else if (n.indicator === "active_ptt" || n.indicator === "active_popo") {
      n.mode = "listening";
    } else if ((n.indicator === "hidden" || n.indicator === "resting") && n.mode !== "listening") {
      n.mode = "hidden";
    }
    break;
  case "status:audioLevel": {
    var raw = typeof m.p === "number" ? m.p : parseFloat(m.p);
    if (isFinite(raw)) {
      // Wispr sends a scaled level that is usually 0..1 but can overshoot;
      // smooth a little so the bars don't strobe.
      var target = clamp01(raw);
      n.level = n.level + (target - n.level) * 0.6;
    }
    break;
  }
  case "notification:show": {
    var built = buildNotification(m.p, strings);
    if (built) n.notification = built;
    break;
  }
  case "notification:clear":
    n.notification = null;
    break;
  }
  return n;
}

// The payload the renderer sends for an action button; mirrored verbatim.
function callbackPayload(notification, action) {
  return {
    callback: action.callback,
    type: notification ? notification.type : undefined,
    callbackOperationId: notification ? notification.callbackOperationId : undefined
  };
}

// The layer-shell surface only carries the pill; notifications go to the
// desktop notification daemon, so they never keep the surface mapped.
function visible(s) {
  return s.mode !== "hidden";
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { initial: initial, reduce: reduce, visible: visible, tr: tr, humanize: humanize, callbackPayload: callbackPayload };
}
