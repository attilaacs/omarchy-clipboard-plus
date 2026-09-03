.pragma library

// Pure string transforms for the clipboard editor. No Qt types and no shell
// calls, so this stays a plain library: the editor hands it text and gets text
// back, and it can be exercised outside the shell with any JS runtime.

// Words that stay lowercase inside a title unless they land first or last.
// This is the AP-style rule; without it "Notes On The Migration" reads wrong.
var MINOR_WORDS = {
  a: 1, an: 1, and: 1, as: 1, at: 1, but: 1, by: 1, for: 1, from: 1, in: 1,
  into: 1, nor: 1, of: 1, on: 1, onto: 1, or: 1, over: 1, per: 1, so: 1,
  the: 1, to: 1, up: 1, via: 1, vs: 1, with: 1, yet: 1
}

// ALL-CAPS words are deliberate (NASA, API, SQL) and must survive title case.
function isAcronym(word) {
  var letters = word.replace(/[^A-Za-z]/g, "")
  return letters.length > 1 && letters === letters.toUpperCase()
}

function capitalize(word) {
  if (!word) return word
  if (isAcronym(word)) return word

  // Inside a compound the minor-word rule still applies after the first part,
  // so "state-of-the-art" becomes "State-of-the-Art", not "State-Of-The-Art".
  var seps = ["-", "/"]
  for (var s = 0; s < seps.length; s++) {
    var sep = seps[s]
    if (word.indexOf(sep) !== -1) {
      var parts = word.split(sep)
      var out = [capitalize(parts[0])]
      for (var i = 1; i < parts.length; i++) {
        var last = i === parts.length - 1
        if (!last && MINOR_WORDS[parts[i].toLowerCase()])
          out.push(parts[i].toLowerCase())
        else
          out.push(capitalize(parts[i]))
      }
      return out.join(sep)
    }
  }
  return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
}

function title(text) {
  if (!text) return text

  // A run of ALL-CAPS words is an acronym; a whole input in caps is shouting.
  // Normalising the latter first stops "MEETING NOTES" surviving untouched
  // while "the NASA API" keeps its acronyms.
  if (text.replace(/[^A-Za-z]/g, "") !== "" && text === text.toUpperCase())
    text = text.toLowerCase()

  // Split on whitespace but keep it, so newlines and runs of spaces survive.
  var parts = text.split(/(\s+)/)
  var wordIdx = []
  for (var i = 0; i < parts.length; i++)
    if (i % 2 === 0 && parts[i].replace(/\s/g, "") !== "") wordIdx.push(i)
  if (wordIdx.length === 0) return text

  var first = wordIdx[0]
  var last = wordIdx[wordIdx.length - 1]

  for (var w = 0; w < wordIdx.length; w++) {
    var idx = wordIdx[w]
    // A word may carry leading/trailing punctuation: ("hello", -> hello
    var m = parts[idx].match(/^(\W*)([\s\S]*?)(\W*)$/)
    if (!m || !m[2]) continue
    var lead = m[1], core = m[2], trail = m[3], out

    if (isAcronym(core))
      out = core
    else if (idx !== first && idx !== last && MINOR_WORDS[core.toLowerCase()])
      out = core.toLowerCase()
    else
      out = capitalize(core)

    parts[idx] = lead + out + trail
  }
  return parts.join("")
}

// Acronyms are not preserved here: telling "API" from a shouted word needs a
// dictionary, and guessing wrong in prose is worse than being consistent.
function sentence(text) {
  var out = ""
  var capitalise = true
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    if (capitalise && /[A-Za-z]/.test(ch)) {
      out += ch.toUpperCase()
      capitalise = false
    } else {
      out += ch.toLowerCase()
    }
    if (".!?\n".indexOf(ch) !== -1) capitalise = true
  }
  return out
}

function upper(text) { return text.toUpperCase() }
function lower(text) { return text.toLowerCase() }

// Accented Latin folded to ASCII so a slug stays URL-safe. Done with an
// explicit map rather than String.normalize("NFD"): normalize is not
// guaranteed across the QML JS engines this may run on, and silently dropping
// every accented letter would mangle names.
var FOLD = {
  "à": "a", "á": "a", "â": "a", "ã": "a", "ä": "a", "å": "a", "ā": "a", "ă": "a", "ą": "a",
  "è": "e", "é": "e", "ê": "e", "ë": "e", "ē": "e", "ĕ": "e", "ė": "e", "ę": "e", "ě": "e",
  "ì": "i", "í": "i", "î": "i", "ï": "i", "ī": "i", "į": "i", "ı": "i",
  "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ø": "o", "ō": "o", "ő": "o",
  "ù": "u", "ú": "u", "û": "u", "ü": "u", "ū": "u", "ů": "u", "ű": "u", "ų": "u",
  "ç": "c", "ć": "c", "č": "c", "ñ": "n", "ń": "n", "ň": "n",
  "ś": "s", "š": "s", "ş": "s", "ß": "ss",
  "ý": "y", "ÿ": "y", "ź": "z", "ż": "z", "ž": "z",
  "ł": "l", "ĺ": "l", "ľ": "l", "ď": "d", "đ": "d", "ť": "t", "ţ": "t",
  "ř": "r", "ŕ": "r", "ğ": "g", "ĝ": "g", "ħ": "h", "þ": "th",
  "æ": "ae", "œ": "oe", "ð": "d"
}

function fold(text) {
  var out = ""
  for (var i = 0; i < text.length; i++) {
    var ch = text.charAt(i)
    var low = ch.toLowerCase()
    if (FOLD[low] !== undefined) {
      var rep = FOLD[low]
      // Preserve case so folding can run before lowercasing in other uses.
      out += (ch === low) ? rep : rep.charAt(0).toUpperCase() + rep.slice(1)
    } else {
      out += ch
    }
  }
  return out
}

// URL/filename-safe slug: folded to ASCII, lowercased, runs of anything
// non-alphanumeric collapsed to a single hyphen, no leading or trailing dash.
function slug(text) {
  return fold(text)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
}

// Named so the editor can show what a key did without duplicating strings.
var LABELS = {
  title: "Title Case",
  sentence: "Sentence case",
  upper: "UPPERCASE",
  lower: "lowercase",
  slug: "slug-case"
}

// Named run() rather than apply(): `apply` exists on Function.prototype, so
// TextTransforms.apply(...) is ambiguous at a glance and a trap if the import
// namespace ever resolves it there instead.
function run(name, text) {
  if (name === "title") return title(text)
  if (name === "sentence") return sentence(text)
  if (name === "upper") return upper(text)
  if (name === "lower") return lower(text)
  if (name === "slug") return slug(text)
  return text
}
