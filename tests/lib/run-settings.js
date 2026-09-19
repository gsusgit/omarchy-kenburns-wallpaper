// Evaluate one expression against Settings.js in node, for tests/settings.test.sh.
//
// The module is a QML script, so node cannot load it as-is: ".pragma library" is
// not valid JavaScript and a bare script exports nothing. Strip the pragma and
// generate the export list from the source's own top-level declarations, so
// adding a function to Settings.js never needs a matching edit here (forgetting
// that edit is exactly how the dropdown test first failed).
//
// Usage: node tests/lib/run-settings.js 'S.sanitize({maxZoom: 9})'
const fs = require("fs");
const path = require("path");

// argv[0] is node and argv[1] is this script, so the expression is argv[2].
const expression = process.argv[2];
if (!expression) {
  process.stderr.write("usage: run-settings.js '<expression>'\n");
  process.exit(2);
}

const sourcePath = path.join(__dirname, "..", "..", "Settings.js");
const src = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*$/m, "");
const names = [...src.matchAll(/^(?:function|var)\s+([A-Za-z_$][\w$]*)/gm)].map(m => m[1]);

const modulePath = "/tmp/gsus-settings-module.js";
fs.writeFileSync(modulePath, src + "\nmodule.exports = { " + names.join(", ") + " };\n");

const S = require(modulePath);
const value = eval(expression);
// Strings print bare so the shell assertions read naturally; objects and arrays
// print as JSON.
process.stdout.write(typeof value === "object" && value !== null ? JSON.stringify(value) : String(value));
