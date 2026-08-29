function detectColor(text) {
  var match = String(text || "").trim().match(/^#?([0-9a-fA-F]{6})$/)
  return match ? "#" + match[1].toUpperCase() : ""
}

function normalizeStoredColor(value, text) {
  var color = String(value || "")
  if (/^#[0-9a-fA-F]{6}$/.test(color)) return color.toUpperCase()
  return detectColor(text)
}

function normalizeEntry(value) {
  if (typeof value === "string") {
    if (value.trim().length === 0) return null
    return { type: "text", text: value, color: detectColor(value) }
  }

  if (!value || typeof value !== "object") return null
  var type = String(value.type || value.kind || "")

  if (type === "text") {
    var text = String(value.text || "")
    if (text.trim().length === 0) return null
    return { type: "text", text: text, color: normalizeStoredColor(value.color, text) }
  }

  if (type === "image") {
    var path = String(value.path || "")
    if (!path) return null
    var entry = {
      type: "image",
      path: path,
      mime: String(value.mime || "image/png")
    }
    if (value.capturedAt !== undefined && value.capturedAt !== null)
      entry.capturedAt = String(value.capturedAt)
    return entry
  }

  return null
}


function entryKey(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image:" + String(entry.path || "")
  return "text:" + String(entry.text || "")
}

function parseHistory(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    var next = []
    if (!Array.isArray(parsed)) return next

    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return next
  } catch (e) {
    return []
  }
}

function addEntry(history, entry, limit) {
  var normalized = normalizeEntry(entry)
  var max = limit === undefined || limit === null ? 100 : Number(limit)
  if (isNaN(max)) max = 100
  max = Math.max(0, max)
  if (!normalized) return Array.isArray(history) ? history.slice(0, max) : []
  if (max === 0) return []

  var key = entryKey(normalized)
  var next = [normalized]
  var values = Array.isArray(history) ? history : []

  for (var i = 0; i < values.length && next.length < max; i++) {
    var existing = normalizeEntry(values[i])
    if (!existing || entryKey(existing) === key) continue
    next.push(existing)
  }

  return next
}

function storageEntries(history, limit) {
  var values = Array.isArray(history) ? history : []
  var max = limit === undefined || limit === null ? values.length : Number(limit)
  if (isNaN(max)) max = values.length
  max = Math.max(0, max)

  var stored = []
  for (var i = 0; i < values.length && stored.length < max; i++) {
    var entry = normalizeEntry(values[i])
    if (!entry) continue

    if (entry.type === "text") {
      stored.push({ type: "text", text: entry.text })
      continue
    }

    var image = { type: "image", path: entry.path, mime: entry.mime }
    if (entry.capturedAt !== undefined) image.capturedAt = entry.capturedAt
    stored.push(image)
  }

  return stored
}

function removeEntryAt(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return values.slice()

  var next = values.slice()
  next.splice(target, 1)
  return next
}

function clearHistory() {
  return []
}

function searchableText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  return String(entry.text || "") + " " + fileEntryText(entry) + " " + String(entry.color || "")
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

function filePaths(entry) {
  if (!entry || entry.type !== "text") return []

  var lines = String(entry.text || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

function fileEntryText(entry) {
  var paths = filePaths(entry)
  if (paths.length === 0) return ""
  if (paths.length === 1) return fileName(paths[0])
  return paths.length + " files"
}

function imagePreviewText(entry) {
  var timestamp = String(entry && entry.capturedAt || "")
  if (!timestamp) return "Image"

  var label = String(entry && entry.mime || "") === "image/png" ? "Screenshot" : "Image"
  return label + " from " + timestamp
}

function previewText(entry) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry)
  var fileText = fileEntryText(entry)
  if (fileText) return fileText
  return String(entry.text || "").replace(/\s+/g, " ")
}

function fullText(entry) {
  if (!entry) return ""
  var paths = filePaths(entry)
  if (paths.length > 0) return paths.join("\n")
  return String(entry.text || "")
}

// Search and ordinary previews only need a bounded prefix. Expanded previews
// and the editor retrieve the selected entry lazily by history index.
var displayTextLimit = 8192

function cappedEntry(entry) {
  if (!entry || entry.type !== "text" || entry.text.length <= displayTextLimit) return entry

  var cut = entry.text.lastIndexOf("\n", displayTextLimit)
  return {
    type: "text",
    text: entry.text.slice(0, cut > 0 ? cut : displayTextLimit),
    color: entry.color || ""
  }
}

function normalizedTypeFilter(value) {
  var filter = String(value || "all").toLowerCase()
  return filter === "text" || filter === "images" || filter === "colors" ? filter : "all"
}

function displayRows(history, query, limit, typeFilter) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "").trim().toLowerCase()
  var filter = normalizedTypeFilter(typeFilter)
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  max = Math.max(0, max)
  if (max === 0) return []

  var rows = []

  for (var i = 0; i < values.length; i++) {
    var normalized = normalizeEntry(values[i])
    if (!normalized) continue
    var entry = cappedEntry(normalized)
    if (needle && searchableText(entry).toLowerCase().indexOf(needle) < 0) continue

    var paths = filePaths(entry)
    var isFile = paths.length > 0
    var isImage = entry.type === "image"
    var isImageFile = isFile && paths.length === 1 && isImagePath(paths[0])
    var color = entry.type === "text" ? String(entry.color || "") : ""

    if (filter === "colors" && !color) continue
    if (filter === "images" && !isImage && !isImageFile) continue
    if (filter === "text" && (isImage || isImageFile || color)) continue

    var previewPath = isImage ? String(entry.path || "") : (isImageFile ? paths[0] : "")
    rows.push({
      entryType: color ? "color" : (isFile ? "file" : entry.type),
      fullText: isImage ? "" : fullText(entry),
      previewText: previewText(entry),
      previewImage: previewPath,
      color: color,
      path: isImage ? String(entry.path || "") : (isFile && paths.length === 1 ? paths[0] : ""),
      mime: isImage ? String(entry.mime || "image/png") : "text/plain",
      index: i
    })
    if (rows.length >= max) break
  }

  return rows
}

function findTextIndex(history, text) {
  var values = Array.isArray(history) ? history : []
  var target = String(text || "")
  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (entry && entry.type === "text" && entry.text === target) return i
  }
  return -1
}

function entryText(history, index) {
  var values = Array.isArray(history) ? history : []
  var target = Number(index)
  if (isNaN(target) || target < 0 || target >= values.length) return ""
  var entry = normalizeEntry(values[target])
  return entry && entry.type === "text" ? String(entry.text || "") : ""
}

function textPreview(history, index, limit) {
  var text = entryText(history, index)
  var max = Number(limit)
  if (isNaN(max) || max <= 0 || text.length <= max)
    return { text: text, truncated: false, totalLength: text.length }

  return { text: text.slice(0, max), truncated: true, totalLength: text.length }
}

if (typeof module !== "undefined") {
  module.exports = {
    detectColor: detectColor,
    parseHistory: parseHistory,
    addEntry: addEntry,
    storageEntries: storageEntries,
    removeEntryAt: removeEntryAt,
    findTextIndex: findTextIndex,
    clearHistory: clearHistory,
    searchableText: searchableText,
    previewText: previewText,
    imagePreviewText: imagePreviewText,
    filePaths: filePaths,
    fileEntryText: fileEntryText,
    fullText: fullText,
    displayRows: displayRows,
    entryText: entryText,
    textPreview: textPreview
  }
}
