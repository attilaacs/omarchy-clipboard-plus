#!/usr/bin/env node

const assert = require("node:assert/strict");
const history = require("../ClipboardHistory.js");

assert.equal(history.detectColor("#a954f4"), "#A954F4");
assert.equal(history.detectColor(" 3bd671 "), "#3BD671");
assert.equal(history.detectColor("color #a954f4"), "");
assert.equal(history.detectColor("#abcd"), "");

const entries = history.parseHistory(
  JSON.stringify([
    { type: "text", text: "#a954f4" },
    { type: "text", text: "ordinary text" },
    { type: "image", path: "/tmp/example.png", mime: "image/png" },
    { type: "text", text: "file:///tmp/file.txt" },
  ]),
);

assert.equal(entries[0].color, "#A954F4");
assert.deepEqual(
  history.displayRows(entries, "", 50, "colors").map((row) => row.entryType),
  ["color"],
);
assert.equal(history.displayRows(entries, "", 50, "colors")[0].index, 0);
assert.deepEqual(
  history.displayRows(entries, "", 50, "images").map((row) => row.entryType),
  ["image"],
);
assert.equal(history.displayRows(entries, "", 50, "images")[0].index, 2);
assert.deepEqual(
  history.displayRows(entries, "ordinary", 50, "all").map((row) => row.previewText),
  ["ordinary text"],
);
assert.equal(history.displayRows(entries, "ordinary", 50, "all")[0].index, 1);
assert.equal(history.displayRows(entries, "", 50, "text").length, 2);

assert.equal(history.findTextIndex(entries, "#a954f4"), 0);
assert.equal(history.findTextIndex(entries, "ordinary text"), 1);
assert.equal(history.findTextIndex(entries, "missing"), -1);

const externallyShifted = history.addEntry(
  entries,
  { type: "text", text: "new capture" },
  50,
);
assert.equal(history.findTextIndex(externallyShifted, "ordinary text"), 2);
const promoted = history.addEntry(
  externallyShifted,
  { type: "text", text: "ordinary text" },
  50,
);
assert.equal(history.findTextIndex(promoted, "ordinary text"), 0);
assert.notEqual(
  JSON.stringify(history.storageEntries(promoted, 50)),
  JSON.stringify(history.storageEntries(externallyShifted, 50)),
);

const longText = "x".repeat(140000);
const longEntries = history.parseHistory(
  JSON.stringify([{ type: "text", text: longText }]),
);
const preview = history.textPreview(longEntries, 0, 65536);
assert.equal(preview.text.length, 65536);
assert.equal(preview.totalLength, 140000);
assert.equal(preview.truncated, true);
assert.equal(history.entryText(longEntries, 0).length, 140000);

const removed = history.removeEntryAt(entries, 1);
assert.deepEqual(
  removed.map((entry) => entry.type === "text" ? entry.text : entry.path),
  ["#a954f4", "/tmp/example.png", "file:///tmp/file.txt"],
);
assert.deepEqual(history.removeEntryAt(entries, 99), entries);

const stored = history.storageEntries(entries, 50);
assert.deepEqual(stored[0], { type: "text", text: "#a954f4" });
assert.equal(Object.hasOwn(stored[0], "color"), false);
assert.deepEqual(stored[2], {
  type: "image",
  path: "/tmp/example.png",
  mime: "image/png",
});

const edited = history.addEntry(
  entries,
  { type: "text", text: "--copy-only" },
  50,
);
assert.equal(edited[0].text, "--copy-only");
assert.equal(edited.length, entries.length + 1);
assert.equal(
  history.addEntry(edited, { type: "text", text: "--copy-only" }, 50).length,
  edited.length,
);
assert.deepEqual(
  history.addEntry(entries, { type: "text", text: " \n\t" }, 50),
  entries,
);

const editedLarge = history.addEntry(
  entries,
  { type: "text", text: longText + "X" },
  50,
);
const storedLarge = history.storageEntries(editedLarge, 50);
assert.equal(storedLarge[0].text.length, 140001);
assert.equal(JSON.parse(JSON.stringify(storedLarge))[0].text, longText + "X");

console.log("clipboard history model: ok");
