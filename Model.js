// Pure helpers: profile-file parsing/serialization and the Lua translation
// hyprland.lua actually understands. No QML dependencies, so this stays easy
// to reason about (and reuse) on its own.
//
// A monitor object looks like:
//   { name, enabled, width, height, refresh, x, y, scale, transform }
// transform: 0/1/2/3 (0 = normal, 1 = 90°, 2 = 180°, 3 = 270°), same
// encoding Hyprland's own `transform` keyword uses.

// ---- safety helpers --------------------------------------------------
//
// Names (profile names, monitor/output names) are untrusted no matter
// where they came from: free-typed in the naming field, parsed out of a
// hand-editable profiles/*.conf file, or read from `hyprctl monitors -j`.
// Two different things need guarding against a hostile name:
//  - it becomes part of a filesystem path (save/delete/load a profile)
//  - it gets concatenated into generated Lua that hyprctl reload then
//    executes (hl.monitor({ output = "<name>" ... }) and the leading
//    "-- Active profile: <name>" comment)

// Conservative whitelist-by-exclusion for anything used as a *.conf
// filename component: no path separators, no control characters
// (newline included -- otherwise "../../x" or an embedded "\n" could
// steer the save/delete path outside profilesDir), no leading "." (also
// rules out "." and ".."), and a sane length cap.
function isValidProfileName(name) {
  var n = String(name === undefined || name === null ? "" : name)
  if (n.length === 0 || n.length > 64) return false
  if (n.charAt(0) === ".") return false
  if (/[\/\\\x00-\x1f\x7f]/.test(n)) return false
  return true
}

// Escapes a value for use inside a double-quoted Lua string literal:
// backslash and quote first (order matters), then every control
// character as a zero-padded \ddd decimal escape so it can never be
// misread as a longer escape by whatever literal digit follows it.
function luaStringEscape(value) {
  var str = String(value === undefined || value === null ? "" : value)
  var out = ""
  for (var i = 0; i < str.length; i++) {
    var ch = str.charAt(i)
    var code = str.charCodeAt(i)
    if (ch === "\\") out += "\\\\"
    else if (ch === "\"") out += "\\\""
    else if (code === 10) out += "\\n"
    else if (code === 13) out += "\\r"
    else if (code < 0x20 || code === 0x7f) out += "\\" + ("00" + code).slice(-3)
    else out += ch
  }
  return out
}

// For text dropped into a "-- ..." line comment rather than a quoted
// string: quoting doesn't help there (nothing about a Lua line comment
// respects backslash escapes), the only thing that can break out of it
// is a literal line break, so that's what has to go.
function sanitizeCommentText(value) {
  return String(value === undefined || value === null ? "" : value).replace(/[\x00-\x1f\x7f]+/g, " ").trim()
}

// Coerces to a finite number in [min, max], falling back to `fallback`
// for anything that isn't one -- NaN/Infinity/non-numeric input included.
// Guards fields that get written into generated Lua unquoted (scale,
// transform), where a non-numeric value wouldn't be "wrong", it would be
// arbitrary Lua source text.
function safeNumber(value, fallback, min, max) {
  var n = Number(value)
  if (!isFinite(n)) n = fallback
  if (min !== undefined && n < min) n = min
  if (max !== undefined && n > max) n = max
  return n
}

function defaultMonitor(name) {
  return {
    name: name || "",
    enabled: true,
    width: 1920,
    height: 1080,
    refresh: 60,
    x: 0,
    y: 0,
    scale: 1.0,
    transform: 0
  }
}

// ---- profiles/*.conf (this plugin's own storage format) ------------------

function parseProfileLine(line) {
  var trimmed = String(line || "").trim()
  if (!trimmed || trimmed.indexOf("monitor") !== 0) return null

  var parts = trimmed.split(",").map(function(s) { return s.trim() })
  if (parts.length < 2) return null

  var nameParts = parts[0].split("=").map(function(s) { return s.trim() })
  if (nameParts.length < 2) return null
  var name = nameParts[1]

  if (parts[1] === "disable") {
    var disabled = defaultMonitor(name)
    disabled.enabled = false
    return disabled
  }

  var resParts = parts[1].split("@")
  var res = resParts[0].split("x")
  if (res.length < 2) return null
  var width = parseInt(res[0], 10)
  var height = parseInt(res[1], 10)
  var refresh = resParts.length > 1 ? parseFloat(resParts[1]) : 60

  var pos = (parts[2] || "0x0").split("x")
  var x = parseInt(pos[0], 10) || 0
  var y = parseInt(pos[1], 10) || 0

  var scale = parts.length > 3 ? parseFloat(parts[3]) : 1.0

  var transform = 0
  if (parts.length > 5 && parts[4] === "transform") transform = parseInt(parts[5], 10) || 0

  if (!isFinite(width) || !isFinite(height)) return null
  if (!isFinite(refresh)) refresh = 60
  if (!isFinite(scale)) scale = 1.0

  return { name: name, enabled: true, width: width, height: height, refresh: refresh, x: x, y: y, scale: scale, transform: transform }
}

function parseProfileText(text) {
  var lines = String(text || "").split("\n")
  var monitors = []
  for (var i = 0; i < lines.length; i++) {
    var m = parseProfileLine(lines[i])
    if (m) monitors.push(m)
  }
  return monitors
}

function monitorToProfileLine(m) {
  if (!m.enabled) return "monitor = " + m.name + ", disable"
  var line = "monitor = " + m.name + ", " + m.width + "x" + m.height + "@" + m.refresh + ", " + m.x + "x" + m.y + ", " + m.scale
  if (m.transform) line += ", transform, " + m.transform
  return line
}

function profileToText(monitors) {
  return monitors.map(monitorToProfileLine).join("\n") + "\n"
}

// ---- hypr_screen.lua (what hyprland.lua actually requires and applies) ----

function monitorToLua(m) {
  // The generation boundary every monitor object passes through on its way
  // into hyprland's config, regardless of whether it came from the live UI
  // (already-safe numbers, see EditorView's InspectorField handlers), a
  // hand-edited profiles/*.conf file, or `hyprctl monitors -j` -- so names
  // are escaped and numbers are validated here rather than trusting each
  // source to have done it already.
  var name = luaStringEscape(m.name)
  var width = safeNumber(m.width, 1920, 1, 16384)
  var height = safeNumber(m.height, 1080, 1, 16384)
  var refresh = safeNumber(m.refresh, 60, 1, 1000)
  var x = safeNumber(m.x, 0, -1000000, 1000000)
  var y = safeNumber(m.y, 0, -1000000, 1000000)
  var scale = safeNumber(m.scale, 1.0, 0.1, 10)
  var transformIn = safeNumber(m.transform, 0, 0, 3)
  var transform = [0, 1, 2, 3].indexOf(Math.round(transformIn)) !== -1 ? Math.round(transformIn) : 0

  if (!m.enabled) return "hl.monitor({ output = \"" + name + "\", disabled = true })"
  var line = "hl.monitor({ output = \"" + name + "\", mode = \"" + width + "x" + height + "@" + refresh + "\", " +
    "position = \"" + x + "x" + y + "\", scale = " + scale
  if (transform) line += ", transform = " + transform
  line += " })"
  return line
}

function profileToLua(monitors, profileName) {
  var lines = [
    "-- Generated by the Monitor Profiles plugin. Do not edit by hand;",
    "-- changes are overwritten the next time a profile is applied.",
    "-- Active profile: " + sanitizeCommentText(profileName)
  ]
  monitors.forEach(function(m) { lines.push(monitorToLua(m)) })
  return lines.join("\n") + "\n"
}

// ---- live `hyprctl monitors -j` -> the same monitor shape ----------------

function monitorFromHyprctlJson(j) {
  return {
    name: String(j.name === undefined || j.name === null ? "" : j.name),
    enabled: !j.disabled,
    width: safeNumber(j.width, 1920, 1, 16384),
    height: safeNumber(j.height, 1080, 1, 16384),
    refresh: Math.round(safeNumber(j.refreshRate, 60, 1, 1000) * 100) / 100,
    x: safeNumber(j.x, 0, -1000000, 1000000),
    y: safeNumber(j.y, 0, -1000000, 1000000),
    scale: Math.round(safeNumber(j.scale, 1, 0.1, 10) * 100) / 100,
    transform: safeNumber(j.transform, 0, 0, 3)
  }
}
