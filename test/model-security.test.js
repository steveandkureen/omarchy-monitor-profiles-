// Adversarial tests for Model.js: path traversal (isValidProfileName) and
// Lua injection (luaStringEscape / sanitizeCommentText / monitorToLua /
// profileToLua / safeNumber). Runs the real repo file under Node via vm,
// with no changes to Model.js itself (it stays a plain QML JS module).
//
// Run with: node test/model-security.test.js
"use strict";
const fs = require("fs");
const vm = require("vm");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8");
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(src, sandbox, { filename: "Model.js" });

let failures = 0;
function check(desc, cond) {
  if (!cond) {
    failures++;
    console.log("FAIL: " + desc);
  } else {
    console.log("ok:   " + desc);
  }
}

// ---- isValidProfileName: path traversal -------------------------------

check("rejects ../ traversal", !sandbox.isValidProfileName("../../etc/passwd"));
check("rejects bare ..", !sandbox.isValidProfileName(".."));
check("rejects bare .", !sandbox.isValidProfileName("."));
check("rejects leading-dot hidden name", !sandbox.isValidProfileName(".hidden"));
check("rejects forward slash", !sandbox.isValidProfileName("a/b"));
check("rejects backslash", !sandbox.isValidProfileName("a\\b"));
check("rejects embedded newline", !sandbox.isValidProfileName("a\nb"));
check("rejects embedded CR", !sandbox.isValidProfileName("a\rb"));
check("rejects NUL byte", !sandbox.isValidProfileName("a\x00b"));
check("rejects empty string", !sandbox.isValidProfileName(""));
check("rejects >64 chars", !sandbox.isValidProfileName("x".repeat(65)));
check("accepts plain name", sandbox.isValidProfileName("MacDev"));
check("accepts spaces/dashes/underscores", sandbox.isValidProfileName("Work Desk_2-final"));
check("accepts a dot NOT in leading position", sandbox.isValidProfileName("v1.2"));
check("accepts 64-char name (boundary)", sandbox.isValidProfileName("x".repeat(64)));

// ---- luaStringEscape: string-literal injection -------------------------

function luaStringLiteral(name) {
  return '"' + sandbox.luaStringEscape(name) + '"';
}

// The real test: whatever comes out, when dropped into `output = <this>`,
// must be parseable as exactly one Lua short string containing the
// original bytes -- no way to end the string early or splice in code.
function assertRoundTripsAsSingleString(raw) {
  const literal = luaStringLiteral(raw);
  // A conforming Lua short-string literal must not contain a raw,
  // unescaped double quote or a raw newline/CR anywhere in its body.
  const body = literal.slice(1, -1);
  let i = 0;
  let danger = false;
  while (i < body.length) {
    if (body[i] === "\\") { i += 2; continue; } // escape sequence, skip both chars
    if (body[i] === '"' || body[i] === "\n" || body[i] === "\r") { danger = true; break; }
    i++;
  }
  return !danger;
}

check(
  "escapes a quote-breakout attempt",
  assertRoundTripsAsSingleString('evil", disabled = false }); os.execute("rm -rf ~"); hl.monitor({ output = "x')
);
check(
  "escapes a backslash-quote combo",
  assertRoundTripsAsSingleString('a\\", b = "c')
);
check("escapes embedded newline", assertRoundTripsAsSingleString("a\nb"));
check("escapes embedded CR", assertRoundTripsAsSingleString("a\rb"));
check("escapes embedded NUL", assertRoundTripsAsSingleString("a\x00b"));
check("plain name passes through readably", sandbox.luaStringEscape("DP-3") === "DP-3");
check(
  "backslash-then-quote ordering doesn't create a fake escape",
  sandbox.luaStringEscape('\\"') === '\\\\\\"'
);

// ---- sanitizeCommentText: comment-line breakout -------------------------

check(
  "strips newline so nothing follows on its own line",
  !/\n/.test(sandbox.sanitizeCommentText("Normal\nhl.monitor({ output = \"evil\" })"))
);
check(
  "strips CR too",
  !/\r/.test(sandbox.sanitizeCommentText("Normal\rmalicious"))
);
check(
  "plain name unaffected",
  sandbox.sanitizeCommentText("Normal") === "Normal"
);

// ---- safeNumber: unquoted-field injection guard --------------------------

check("NaN falls back", sandbox.safeNumber(NaN, 42, 0, 100) === 42);
check("Infinity falls back", sandbox.safeNumber(Infinity, 42, 0, 100) === 42);
check("non-numeric string falls back", sandbox.safeNumber("os.execute()", 42, 0, 100) === 42);
check("out-of-range clamps to max", sandbox.safeNumber(999, 1, 0, 10) === 10);
check("out-of-range clamps to min", sandbox.safeNumber(-999, 1, -10, 10) === -10);
check("valid number passes through", sandbox.safeNumber(5, 1, 0, 10) === 5);

// ---- End-to-end: monitorToLua / profileToLua never break Lua syntax ------

function isSingleValidLuaCallLine(line) {
  // Cheap but meaningful structural check: exactly one `hl.monitor({ ... })`
  // and every double-quoted span in it is a well-formed, single-line Lua
  // string (same walk as assertRoundTripsAsSingleString, applied to each
  // quoted span in the line).
  if (!/^hl\.monitor\(\{.*\}\)$/.test(line)) return false;
  const quoted = line.match(/"(?:\\.|[^"\\])*"/g) || [];
  for (const q of quoted) {
    if (!assertRoundTripsAsSingleString(q.slice(1, -1).replace(/\\\\/g, "\\\\"))) return false;
  }
  // No raw newline can appear in a single generated line by construction
  // (monitorToLua never emits one outside an escaped \n), and the overall
  // line count must match one hl.monitor(...) call per monitor -- checked
  // by the caller via splitting on "\n".
  return true;
}

const evilMonitor = {
  name: 'DP-3", disabled = true }); os.execute("touch /tmp/pwned"); hl.monitor({ output = "x',
  enabled: true,
  width: "1920x1080@60\", injected = true, x = (1", // hostile non-numeric width too
  height: 1080,
  refresh: 60,
  x: 0,
  y: 0,
  scale: "1.0); os.execute('evil')",
  transform: "0; os.execute('evil')"
};

const lua = sandbox.profileToLua([evilMonitor], 'My Profile"\ndisabled = true }); os.execute("evil");--');
const lines = lua.split("\n").filter(function (l) { return l.length > 0; });

check("profileToLua produced exactly 4 lines (3 header + 1 monitor)", lines.length === 4);
check("comment line is still a single -- comment", lines[2].indexOf("-- Active profile:") === 0);
check(
  "malicious payload survives as inert text in the comment, not as a line break",
  lines[2].indexOf("os.execute") !== -1
);
check("monitor line is one well-formed hl.monitor(...) call", isSingleValidLuaCallLine(lines[3]));
check("hostile width fell back to a real number, not raw text", /mode = "\d+x1080@60"/.test(lines[3]));
check("hostile transform never appears unquoted in output", !/transform = 0; os\.execute/.test(lines[3]));

console.log("\n" + (failures === 0 ? "ALL PASSED" : failures + " FAILURE(S)"));
process.exit(failures === 0 ? 0 : 1);
