import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property string filterText: ""
  property string typeFilter: "all"
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property bool previewExpanded: false
  property bool editorOpen: false
  property string editorError: ""
  property bool pendingEditedCopyOnly: false
  property bool pendingEditedAction: false
  property bool pendingEditedSave: false
  property var pendingPreviousHistory: null
  property var history: []

  property string expandedKind: ""
  property string expandedText: ""
  property string expandedImage: ""
  property string expandedColor: ""
  property bool expandedTruncated: false
  property int expandedTotalLength: 0

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(38), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(28), Style.font.caption + Style.spacing.controlPaddingY)
  property int cardWidth: Math.min(Style.space(940), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int historyLimit: 300
  property int displayLimit: 60

  readonly property var typeFilters: ["all", "text", "images", "colors"]

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.typeFilter = "all"
    root.selectedIndex = 0
    root.cursorActive = true
    root.previewExpanded = false
    root.editorOpen = false
    root.editorError = ""
    root.disarmPointer()
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelEditedHistoryAction()
    root.cancelClearHistory(false)
    root.previewExpanded = false
    root.editorOpen = false
    root.editorError = ""
    textEditor.text = ""
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function loadHistory(raw) {
    root.history = ClipboardHistory.parseHistory(raw)
    if (root.opened) root.rebuildDisplay()
  }

  function saveHistory() {
    var stored = ClipboardHistory.storageEntries(root.history, root.historyLimit)
    historyFile.setText(JSON.stringify(stored, null, 2) + "\n")
  }

  function requestClearHistory() {
    if (root.history.length === 0) return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory(refocus) {
    root.clearConfirmOpen = false
    root.disarmPointer()
    if (refocus === undefined || refocus)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearHistory() {
    root.history = ClipboardHistory.clearHistory()
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function removeDisplayIndex(index) {
    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    root.saveHistory()

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, root.displayLimit, root.typeFilter)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        swatchColor: row.color || "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function selectedRow() {
    if (displayModel.count === 0 || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    return displayModel.get(root.selectedIndex)
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + displayModel.count) % displayModel.count
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, displayModel.count - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function setTypeFilter(nextFilter) {
    if (root.typeFilters.indexOf(nextFilter) < 0) return
    root.typeFilter = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function cycleTypeFilter(delta) {
    var index = root.typeFilters.indexOf(root.typeFilter)
    root.setTypeFilter(root.typeFilters[(index + delta + root.typeFilters.length) % root.typeFilters.length])
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.applySelected(displayModel.get(index))
  }

  function copyIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.copySelected(displayModel.get(index))
  }

  function openIndex(index) {
    if (index < 0 || index >= displayModel.count) return
    root.openSelected(displayModel.get(index))
  }

  function applySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copySelected(row) {
    if (!row) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  function openSelected(row) {
    if (!row) return
    root.opened = false
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.historyIndex)])
  }

  function openExpandedPreview() {
    var row = root.selectedRow()
    if (!row) return

    root.expandedKind = row.swatchColor ? "color" : (row.previewImage ? "image" : "text")
    root.expandedImage = row.previewImage || ""
    root.expandedColor = row.swatchColor || ""
    root.expandedText = ""
    root.expandedTruncated = false
    root.expandedTotalLength = 0

    if (root.expandedKind === "text") {
      var preview = ClipboardHistory.textPreview(root.history, row.historyIndex, 65536)
      root.expandedText = preview.text
      root.expandedTruncated = preview.truncated
      root.expandedTotalLength = preview.totalLength
    }

    root.previewExpanded = true
    expandedTextScroll.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeExpandedPreview() {
    root.previewExpanded = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startEditor() {
    var row = root.selectedRow()
    if (!row || row.entryType === "image") return

    var text = ClipboardHistory.entryText(root.history, row.historyIndex)
    root.previewExpanded = false
    root.editorError = ""
    root.editorOpen = true
    textEditor.text = text
    editorScroll.contentY = 0
    Qt.callLater(function() {
      textEditor.forceActiveFocus()
      textEditor.cursorPosition = textEditor.length
    })
  }

  function cancelEditedHistoryAction() {
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
  }

  function closeEditor() {
    root.cancelEditedHistoryAction()
    root.editorOpen = false
    root.editorError = ""
    textEditor.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function finishEditing(copyOnly) {
    var text = textEditor.text
    if (text.trim().length === 0) {
      root.editorError = "Clipboard text cannot be blank"
      return
    }
    if (root.pendingEditedSave) {
      root.editorError = "Clipboard operation already in progress"
      return
    }

    var existingIndex = ClipboardHistory.findTextIndex(root.history, text)
    if (existingIndex === 0) {
      var row = { entryType: "text", historyIndex: 0 }
      root.editorOpen = false
      root.editorError = ""
      textEditor.text = ""
      if (copyOnly) root.copySelected(row)
      else root.applySelected(row)
      return
    }

    root.pendingPreviousHistory = root.history
    root.history = ClipboardHistory.addEntry(
      root.history,
      { type: "text", text: text },
      root.historyLimit
    )
    root.pendingEditedCopyOnly = copyOnly
    root.pendingEditedAction = true
    root.pendingEditedSave = true
    root.editorError = ""
    root.saveHistory()
  }

  function completeEditedHistoryAction() {
    if (!root.pendingEditedSave) return

    var shouldInvoke = root.pendingEditedAction
    var copyOnly = root.pendingEditedCopyOnly
    root.pendingEditedSave = false
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
    root.pendingPreviousHistory = null
    if (!shouldInvoke) return

    var command = [root.omarchyPath + "/bin/omarchy-clipboard-paste-text"]
    if (copyOnly) command.push("--copy-only")
    command.push("--history-index", "0")

    root.editorOpen = false
    root.editorError = ""
    textEditor.text = ""
    root.opened = false
    Quickshell.execDetached(command)
  }

  function failEditedHistoryAction() {
    if (!root.pendingEditedSave) return

    var shouldReport = root.pendingEditedAction
    if (root.pendingPreviousHistory) root.history = root.pendingPreviousHistory
    root.pendingEditedSave = false
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
    root.pendingPreviousHistory = null
    if (root.opened) root.rebuildDisplay()
    if (shouldReport) root.editorError = "Could not save edited clipboard text"
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
    onFileChanged: reload()
    onSaved: root.completeEditedHistoryAction()
    onSaveFailed: root.failEditedHistoryAction()
  }


  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.clearConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }

          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0

          if (root.previewExpanded) {
            if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_Space)) {
              root.closeExpandedPreview()
              event.accepted = true
            } else if (ctrl && event.key === Qt.Key_E && root.expandedKind === "text") {
              root.startEditor()
              event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              expandedTextScroll.contentY = Math.max(0, expandedTextScroll.contentY - expandedTextScroll.height * 0.8)
              event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              expandedTextScroll.contentY = Math.min(Math.max(0, expandedTextScroll.contentHeight - expandedTextScroll.height), expandedTextScroll.contentY + expandedTextScroll.height * 0.8)
              event.accepted = true
            }
            return
          }

          if (root.editorOpen) return

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_J) {
            root.select(1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_K) {
            root.select(-1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Space) {
            root.openExpandedPreview()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_E) {
            root.startEditor()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_R) {
            historyFile.reload()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_1) {
            root.setTypeFilter("all")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_2) {
            root.setTypeFilter("text")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_3) {
            root.setTypeFilter("images")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_4) {
            root.setTypeFilter("colors")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_T) {
            root.cycleTypeFilter(shift ? -1 : 1)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (shift) root.requestClearHistory()
            else root.removeDisplayIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(displayModel.count - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && (event.modifiers & Qt.AltModifier)) root.openIndex(root.selectedIndex)
            else if (root.cursorActive && shift) root.copyIndex(root.selectedIndex)
            else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete entire clipboard history?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }
      }

      Column {
        id: normalView
        visible: !root.previewExpanded && !root.editorOpen
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Row {
          width: parent.width
          height: root.headerHeight
          spacing: Style.space(12)

          Text {
            width: parent.width - filterLabel.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Search clipboard…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: filterLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.typeFilter === "all" ? "ALL" : root.typeFilter.toUpperCase()
            color: root.selectedText
            opacity: 0.72
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: parent.width * 0.45
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: displayModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string entryType
                  required property string previewText
                  required property string fullText
                  required property string previewImage
                  required property string swatchColor

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.topMargin: Style.space(8)
                    anchors.bottomMargin: Style.space(8)
                    spacing: Style.space(10)

                    Rectangle {
                      visible: row.swatchColor.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      radius: Math.max(Style.space(4), height * 0.22)
                      color: row.swatchColor || "transparent"
                      border.width: visible ? Style.normalBorderWidth : 0
                      border.color: root.border
                    }

                    Image {
                      visible: row.swatchColor.length === 0 && row.previewImage.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      source: row.previewImage
                      sourceSize.width: width
                      sourceSize.height: height
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      width: parent.width - ((row.swatchColor.length > 0 || row.previewImage.length > 0) ? parent.height + parent.spacing : 0)
                      height: parent.height
                      text: row.previewText
                      color: row.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      opacity: row.entryType === "image" || row.entryType === "file" ? 0.72 : 1
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                      textFormat: Text.PlainText
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateIndex(row.index)
                    }
                  }
                }
              }
            }

            Item {
              id: previewPane
              width: parent.width * 0.55
              height: parent.height
              clip: true

              property var activeRow: displayModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex) : null

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Flickable {
                id: compactTextScroll
                visible: previewPane.activeRow && !previewPane.activeRow.previewImage && !previewPane.activeRow.swatchColor
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, compactPreviewText.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                Text {
                  id: compactPreviewText
                  width: compactTextScroll.width
                  text: previewPane.activeRow ? previewPane.activeRow.fullText : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.WrapAnywhere
                  textFormat: Text.PlainText
                }
              }

              Image {
                visible: previewPane.activeRow && previewPane.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                source: previewPane.activeRow ? previewPane.activeRow.previewImage : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
              }

              Column {
                visible: previewPane.activeRow && previewPane.activeRow.swatchColor
                anchors.centerIn: parent
                spacing: Style.space(16)

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Style.space(170)
                  height: width
                  radius: root.cornerRadius
                  color: previewPane.activeRow ? previewPane.activeRow.swatchColor : "transparent"
                  border.width: Style.normalBorderWidth
                  border.color: root.border
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: previewPane.activeRow ? previewPane.activeRow.swatchColor : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0

            Text {
              text: "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.history.length === 0 ? "Clipboard is empty" : "No matches for “" + root.filterText + "”"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          text: "Ctrl+J/K move  ·  Ctrl+Space expand  ·  Ctrl+E edit  ·  Ctrl+1–4 filter  ·  Enter paste  ·  Shift+Enter copy"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
      }

      Item {
        id: expandedView
        visible: root.previewExpanded
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: expandedTitle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight
          text: root.expandedKind === "image" ? "Image preview" : root.expandedKind === "color" ? "Color preview" : "Text preview"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: expandedTitle.verticalCenter
          text: "Ctrl+Space or Esc to return"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Image {
          visible: root.expandedKind === "image"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: expandedTitle.bottom
          anchors.bottom: parent.bottom
          source: root.expandedImage
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }

        Column {
          visible: root.expandedKind === "color"
          anchors.centerIn: parent
          spacing: Style.space(20)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(Style.space(320), expandedView.width * 0.55)
            height: width
            radius: root.cornerRadius
            color: root.expandedColor || "transparent"
            border.width: Style.normalBorderWidth
            border.color: root.border
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.expandedColor
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }
        }

        Flickable {
          id: expandedTextScroll
          visible: root.expandedKind === "text"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: expandedTitle.bottom
          anchors.bottom: expandedTruncation.top
          clip: true
          contentWidth: width
          contentHeight: Math.max(height, expandedTextItem.implicitHeight)
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: expandedTextItem
            width: expandedTextScroll.width
            text: root.expandedText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
          }
        }

        Text {
          id: expandedTruncation
          visible: root.expandedKind === "text" && root.expandedTruncated
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? root.footerHeight : 0
          text: "Preview capped at 64 KiB; Ctrl+E opens the complete text"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }
      }

      Item {
        id: editorView
        visible: root.editorOpen
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: editorTitle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight
          text: "Edit clipboard text"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: editorTitle.verticalCenter
          text: "Ctrl+Enter paste  ·  Ctrl+Shift+Enter or Ctrl+S copy  ·  Esc cancel"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: editorTitle.bottom
          anchors.bottom: editorErrorText.top
          color: Util.alpha(root.foreground, 0.035)
          radius: root.cornerRadius
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(root.border, 0.5)

          Flickable {
            id: editorScroll
            anchors.fill: parent
            anchors.margins: Style.space(14)
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, textEditor.implicitHeight)
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
              id: textEditor
              width: editorScroll.width
              height: Math.max(editorScroll.height, implicitHeight)
              color: root.foreground
              selectionColor: root.selectedBackground
              selectedTextColor: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              wrapMode: TextEdit.WrapAnywhere
              textFormat: TextEdit.PlainText
              selectByMouse: true

              onCursorRectangleChanged: {
                if (cursorRectangle.y < editorScroll.contentY)
                  editorScroll.contentY = cursorRectangle.y
                else if (cursorRectangle.y + cursorRectangle.height > editorScroll.contentY + editorScroll.height)
                  editorScroll.contentY = cursorRectangle.y + cursorRectangle.height - editorScroll.height
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                if (event.key === Qt.Key_Escape) {
                  root.closeEditor()
                  event.accepted = true
                } else if (ctrl && shift && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.finishEditing(true)
                  event.accepted = true
                } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.finishEditing(false)
                  event.accepted = true
                } else if (ctrl && event.key === Qt.Key_S) {
                  root.finishEditing(true)
                  event.accepted = true
                }
              }
            }
          }
        }

        Text {
          id: editorErrorText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.editorError ? root.footerHeight : 0
          text: root.editorError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
