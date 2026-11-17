import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Full-featured Clockify Control bar widget & popup panel.
Panel {
  id: root
  moduleName: "io.github.abdulrahmanhr.clockify"
  ipcTarget: "io.github.abdulrahmanhr.clockify"
  manageIpc: false

  readonly property string helperPath: String(Qt.resolvedUrl("clockify.py")).replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true
  readonly property bool showTimerInBar: setting("showTimerInBar", true) === true
  readonly property bool showTaskInBar: setting("showTaskInBar", false) === true
  readonly property bool isPrimaryMonitor: {
    var win = root.QsWindow ? root.QsWindow.window : null
    if (!win || !win.screen || Quickshell.screens.length === 0) return true
    return String(win.screen.name) === String(Quickshell.screens[0].name)
  }

  readonly property int elapsedSeconds: clockify.timing ? Model.elapsedSeconds(clockify.running.start, clock.date) : 0
  readonly property int todaySeconds: clockify.todaySeconds + elapsedSeconds
  readonly property int weekSeconds: clockify.weekSeconds + elapsedSeconds
  readonly property int monthSeconds: clockify.monthSeconds + elapsedSeconds
  readonly property int todayBillableSeconds: clockify.todayBillableSeconds + (clockify.timing && clockify.running.billable ? elapsedSeconds : 0)
  readonly property int weekBillableSeconds: clockify.weekBillableSeconds + (clockify.timing && clockify.running.billable ? elapsedSeconds : 0)
  readonly property int monthBillableSeconds: clockify.monthBillableSeconds + (clockify.timing && clockify.running.billable ? elapsedSeconds : 0)

  // Navigation & mode state
  property string activeTab: "tracker"     // "tracker" | "history" | "manage" | "settings"
  property string trackerMode: "timer"     // "timer" | "manual"
  property string manageTab: "project"     // "project" | "task" | "tag" | "client"

  // Dashboard / History state
  property string periodMode: "week"       // "day" | "week" | "month" | "year" | "all" | "custom"
  property int periodOffset: 0
  property string customFrom: ""
  property string customTo: ""
  property string filterProjectId: ""
  property string filterTaskId: ""
  property string filterTagId: ""
  property string filterBillable: "all"    // "all" | "billable" | "non-billable"
  property bool filtersExpanded: false
  property string breakdownMode: "projects" // "projects" | "tasks" | "tags" | "days"

  readonly property var periodBounds: Model.computePeriodBounds(
    root.periodMode, root.periodOffset, clockify.weekStart, root.customFrom, root.customTo, clock.date
  )
  readonly property var filteredHistoryEntries: Model.filterDashboardEntries(
    clockify.recentEntries,
    root.periodBounds,
    {
      projectId: root.filterProjectId,
      taskId: root.filterTaskId,
      tagId: root.filterTagId,
      billableMode: root.filterBillable,
      query: root.historyQuery
    }
  )
  readonly property var dashboardData: Model.buildDashboard(
    root.filteredHistoryEntries, root.periodBounds, root.periodMode, clockify.weekStart, clock.date
  )
  readonly property int activeFilterCount: (
    (filterProjectId !== "" ? 1 : 0) +
    (filterTaskId !== "" ? 1 : 0) +
    (filterTagId !== "" ? 1 : 0) +
    (filterBillable !== "all" ? 1 : 0)
  )
  readonly property var activeBreakdownList: {
    if (breakdownMode === "tasks") return dashboardData.taskBreakdown
    if (breakdownMode === "tags") return dashboardData.tagBreakdown
    if (breakdownMode === "days") return dashboardData.dayBreakdown
    return dashboardData.projectBreakdown
  }

  // Tracker / Manual draft state
  property string draftDescription: ""
  property string draftProjectId: ""
  property string draftTaskId: ""
  property var draftTagIds: []
  property bool draftBillable: false
  property string manualDate: "today"
  property string manualStart: ""
  property string manualEnd: ""

  // Live running entry editor state
  property bool editRunningOpen: false
  property string runEditDesc: ""
  property string runEditProjectId: ""
  property string runEditTaskId: ""
  property var runEditTagIds: []
  property bool runEditBillable: false
  property string runEditStart: ""
  property int runEditAdjustMin: 0
  property bool confirmDiscard: false

  // History filter & inline entry editor state
  property string historyQuery: ""
  property string editingEntryId: ""
  property string entryEditDesc: ""
  property string entryEditProjectId: ""
  property string entryEditTaskId: ""
  property var entryEditTagIds: []
  property bool entryEditBillable: false
  property string entryEditDate: ""
  property string entryEditStart: ""
  property string entryEditEnd: ""
  property string confirmDeleteId: ""

  // Manage tab creation state
  property string newProjectName: ""
  property string newProjectClientId: ""
  property string newProjectColor: "#039BE5"
  property bool newProjectBillable: true
  property bool newProjectPublic: true
  property string newTaskProjectId: ""
  property string newTaskName: ""
  property string newTagName: ""
  property string newClientName: ""

  readonly property var projectColorPalette: [
    "#039BE5", "#009688", "#4CAF50", "#8BC34A", "#FF9800",
    "#F44336", "#E91E63", "#9C27B0", "#673AB7", "#607D8B"
  ]

  readonly property string statusText: Model.statusLine(clockify.lastError, clockify.note, clockify.configured)
  readonly property bool statusIsError: clockify.lastError !== ""

  readonly property bool anyPopupOrInputFocused: (
    keyField.activeFocus ||
    descriptionField.activeFocus ||
    manualDateField.activeFocus ||
    manualStartField.activeFocus ||
    manualEndField.activeFocus ||
    runEditDescField.activeFocus ||
    runEditStartField.activeFocus ||
    historyFilterField.activeFocus ||
    customFromField.activeFocus ||
    customToField.activeFocus ||
    newProjectNameField.activeFocus ||
    newTaskNameField.activeFocus ||
    newTagNameField.activeFocus ||
    newClientNameField.activeFocus ||
    projectDropdown.popupOpen ||
    taskDropdown.popupOpen ||
    tagsMulti.popupOpen ||
    runEditProjectDropdown.popupOpen ||
    runEditTaskDropdown.popupOpen ||
    runEditTagsMulti.popupOpen ||
    filterProjectDropdown.popupOpen ||
    filterTaskDropdown.popupOpen ||
    filterTagDropdown.popupOpen ||
    newProjectClientDropdown.popupOpen ||
    newTaskProjectDropdown.popupOpen ||
    workspaceDropdown.popupOpen ||
    editingEntryId !== ""
  )

  function clearDashboardFilters() {
    historyQuery = ""
    historyFilterField.text = ""
    filterProjectId = ""
    filterTaskId = ""
    filterTagId = ""
    filterBillable = "all"
  }

  function stepPeriod(delta) {
    periodOffset += delta
    if (periodMode !== "all" && periodBounds.startIso && clockify.loadedStartDate && periodBounds.startIso < clockify.loadedStartDate) {
      clockify.fetchRange(periodBounds.startIso, periodBounds.endIso)
    }
  }

  function toggleBreakdownFilter(item) {
    if (!item) return
    if (breakdownMode === "projects") {
      filterProjectId = (filterProjectId === item.id) ? "" : String(item.id || "")
      filterTaskId = ""
    } else if (breakdownMode === "tasks") {
      filterTaskId = (filterTaskId === item.id) ? "" : String(item.id || "")
    } else if (breakdownMode === "tags") {
      filterTagId = (filterTagId === item.id) ? "" : String(item.id || "")
    } else if (breakdownMode === "days" && item.id) {
      var parsed = Model.parseLocalDateIso(item.id)
      if (parsed) {
        var nowD = new Date()
        var today = new Date(nowD.getFullYear(), nowD.getMonth(), nowD.getDate(), 0, 0, 0, 0)
        periodMode = "day"
        periodOffset = Math.round((parsed.getTime() - today.getTime()) / 86400000)
      }
    }
  }

  function syncDraftDefaults() {
    if (draftProjectId === "" && clockify.defaultProjectId !== "") {
      draftProjectId = clockify.defaultProjectId
    }
    if (draftTaskId === "" && clockify.defaultTaskId !== "") {
      draftTaskId = clockify.defaultTaskId
    }
    if ((!draftTagIds || draftTagIds.length === 0) && clockify.defaultTagIds && clockify.defaultTagIds.length > 0) {
      draftTagIds = clockify.defaultTagIds.slice()
    }
    draftBillable = clockify.defaultBillable
    if (newTaskProjectId === "" && clockify.projects.length > 0) {
      newTaskProjectId = clockify.defaultProjectId !== "" ? clockify.defaultProjectId : String(clockify.projects[0].id || "")
    }
  }

  function clearDraftDescription() {
    draftDescription = ""
    descriptionField.text = ""
  }

  function toggleTimer() {
    if (clockify.actionBusy) return
    if (clockify.timing) {
      clockify.stop()
    } else {
      clockify.start(draftDescription, draftProjectId, draftTaskId, draftTagIds, draftBillable)
      clearDraftDescription()
    }
  }

  function openRunningEditor() {
    if (!clockify.running) return
    var r = clockify.running
    runEditDesc = String(r.description || "")
    runEditDescField.text = runEditDesc
    runEditProjectId = String(r.projectId || "")
    runEditTaskId = String(r.taskId || "")
    runEditTagIds = Array.isArray(r.tagIds) ? r.tagIds.slice() : []
    runEditBillable = r.billable === true
    runEditStart = String(r.startLocal || "")
    runEditStartField.text = runEditStart
    runEditAdjustMin = 0
    editRunningOpen = true
  }

  function saveRunningEdits() {
    clockify.updateRunning(
      runEditDescField.text,
      runEditProjectId,
      runEditTaskId,
      runEditTagIds,
      runEditBillable,
      runEditAdjustMin,
      runEditStartField.text !== String((clockify.running && clockify.running.startLocal) || "") ? runEditStartField.text : ""
    )
    editRunningOpen = false
  }

  function openEntryEditor(entry) {
    if (!entry) return
    editingEntryId = String(entry.id || "")
    entryEditDesc = String(entry.description || "")
    entryEditProjectId = String(entry.projectId || "")
    entryEditTaskId = String(entry.taskId || "")
    entryEditTagIds = Array.isArray(entry.tagIds) ? entry.tagIds.slice() : []
    entryEditBillable = entry.billable === true
    entryEditDate = String(entry.dateIso || "today")
    entryEditStart = String(entry.startLocal || "")
    entryEditEnd = String(entry.endLocal || "")
  }

  function commitKey() {
    var key = keyField.text
    if (String(key).trim() === "") return
    keyField.text = ""
    keyField.focus = false
    clockify.saveKey(key)
  }

  function submitManualEntry() {
    clockify.addManual(
      draftDescription,
      draftProjectId,
      draftTaskId,
      draftTagIds,
      draftBillable,
      manualDateField.text,
      manualStartField.text,
      manualEndField.text
    )
    clearDraftDescription()
  }

  visible: clockify.timing || !hideWhenIdle || !clockify.configured
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      confirmDiscard = false
      confirmDeleteId = ""
      if (panelFlick) panelFlick.contentY = 0
      syncDraftDefaults()
      if (manualStart === "" || manualEnd === "") {
        var now = new Date()
        var earlier = new Date(now.getTime() - 30 * 60000)
        manualStart = Model.pad2(earlier.getHours()) + ":" + Model.pad2(earlier.getMinutes())
        manualEnd = Model.pad2(now.getHours()) + ":" + Model.pad2(now.getMinutes())
        manualStartField.text = manualStart
        manualEndField.text = manualEnd
      }
      if (customFrom === "" || customTo === "") {
        var cur = new Date()
        var weekAgo = new Date(cur.getFullYear(), cur.getMonth(), cur.getDate() - 6)
        customFrom = Model.toLocalDateIso(weekAgo)
        customTo = Model.toLocalDateIso(cur)
        customFromField.text = customFrom
        customToField.text = customTo
      }
      clockify.refresh(true)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      editRunningOpen = false
      editingEntryId = ""
      confirmDiscard = false
      confirmDeleteId = ""
    }
  }

  Service {
    id: clockify
    settings: root.settings
    helperPath: root.helperPath
    isPrimaryMonitor: root.isPrimaryMonitor
    onKeyRejected: function(message) { Qt.callLater(function() { keyField.forceActiveFocus() }) }
  }

  SystemClock {
    id: clock
    precision: (clockify.timing && (root.opened || root.showTimerInBar)) ? SystemClock.Seconds : SystemClock.Minutes
  }

  Connections {
    target: clockify
    function onDefaultProjectIdChanged() { root.syncDraftDefaults() }
    function onProjectsChanged() { root.syncDraftDefaults() }
    function onRunningChanged() {
      if (!clockify.timing) {
        root.editRunningOpen = false
        root.confirmDiscard = false
      }
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { clockify.refresh(true); return "ok" }
    function startTimer(description: string, projectId: string): string {
      clockify.start(description, projectId, "", [], clockify.defaultBillable)
      return "ok"
    }
    function stopTimer(): string { clockify.stop(); return "ok" }
    function toggleTimer(): string { root.toggleTimer(); return "ok" }
    function discardTimer(): string { clockify.discard(); return "ok" }
    function status(): string {
      if (!clockify.configured) return "not configured"
      if (!clockify.timing) return "idle, today " + Model.formatDuration(root.todaySeconds)
      return Model.describeEntry(clockify.running) + " " + Model.formatClock(root.elapsedSeconds)
    }
    function debug(): string {
      var window = root.QsWindow ? root.QsWindow.window : null
      return JSON.stringify({
        screen: window && window.screen ? String(window.screen.name) : "unknown",
        configured: clockify.configured,
        authSource: clockify.authSource,
        timing: clockify.timing,
        running: clockify.running,
        todaySeconds: root.todaySeconds,
        weekSeconds: root.weekSeconds,
        projectCount: clockify.projects.length,
        tagCount: clockify.tags.length,
        clientCount: clockify.clients.length,
        recentCount: clockify.recentEntries.length,
        workspaceName: clockify.workspaceName,
        fetchedAt: clockify.fetchedAt,
        lastError: clockify.lastError,
        helperPath: root.helperPath
      })
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.barLabel(clockify.running, root.elapsedSeconds, root.showTimerInBar, root.showTaskInBar)
    labelVisible: true
    dimmed: !clockify.timing
    useActiveColor: false
    tooltipText: Model.barTooltip(clockify.running, root.elapsedSeconds, root.todaySeconds, root.weekSeconds)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleTimer()
      else if (buttonCode === Qt.MiddleButton) clockify.refresh(true)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(510))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.anyPopupOrInputFocused
      onCloseRequested: {
        if (root.editRunningOpen) root.editRunningOpen = false
        else if (root.editingEntryId !== "") root.editingEntryId = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "s" || text === "S") root.toggleTimer()
        else if (text === "r" || text === "R") clockify.refresh(true)
        else if (text === "1") root.activeTab = "tracker"
        else if (text === "2") root.activeTab = "history"
        else if (text === "3") root.activeTab = "manage"
        else if (text === "4") root.activeTab = "settings"
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          // ---------------------------------------------------------- hero
          PanelHero {
            id: hero
            width: parent.width
            title: clockify.timing ? Model.neutralizeMarkup(Model.describeEntry(clockify.running)) : "No timer running"
            meta: clockify.timing
              ? [
                  Model.formatClock(root.elapsedSeconds),
                  Model.projectLabel(clockify.running),
                  Model.taskLabel(clockify.running),
                  clockify.running.billable ? "Billable" : ""
                ].filter(function(x) { return x !== "" }).join("  ·  ")
              : (clockify.configured ? "Today " + Model.formatDuration(root.todaySeconds) + "  ·  Week " + Model.formatDuration(root.weekSeconds) : "Not connected")
            detail: clockify.pomodoroRunning
              ? (clockify.pomodoroPhase === "work" ? "Focus " : "Break ") + Model.formatClock(clockify.pomodoroSecondsLeft)
              : (clockify.timing ? "Today " + Model.formatDuration(root.todaySeconds) : "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: clockify.timing ? 1.0 : 0.55
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󱎫"
                color: clockify.timing ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // Active running entry tag chips & quick controls
          Column {
            visible: clockify.configured && clockify.timing
            width: parent.width
            spacing: Style.space(6)

            Text {
              visible: Model.tagsLabel(clockify.running) !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: "Tags: " + Model.tagsLabel(clockify.running)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Button {
                text: "Stop"
                iconText: "󰓛"
                bordered: true
                enabled: !clockify.actionBusy
                foreground: root.urgent
                fontFamily: root.fontFamily
                onClicked: clockify.stop()
              }

              Button {
                text: root.editRunningOpen ? "Close Editor" : "Edit Live"
                iconText: "󰏫"
                bordered: true
                selected: root.editRunningOpen
                enabled: !clockify.actionBusy
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  if (root.editRunningOpen) root.editRunningOpen = false
                  else root.openRunningEditor()
                }
              }

              Button {
                text: root.confirmDiscard ? "Confirm Discard" : "Discard"
                iconText: "󰆴"
                bordered: true
                enabled: !clockify.actionBusy
                foreground: root.confirmDiscard ? root.urgent : root.dim
                fontFamily: root.fontFamily
                onClicked: {
                  if (!root.confirmDiscard) {
                    root.confirmDiscard = true
                  } else {
                    root.confirmDiscard = false
                    clockify.discard()
                  }
                }
              }

              Item { Layout.fillWidth: true }
            }

            // Inline Running Timer Editor
            BorderSurface {
              visible: root.editRunningOpen
              width: parent.width
              implicitHeight: runEditCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Column {
                id: runEditCol
                anchors.fill: parent
                anchors.margins: Style.space(8)
                spacing: Style.space(8)

                PanelSectionHeader {
                  text: "EDIT RUNNING TIMER"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                TextField {
                  id: runEditDescField
                  width: parent.width
                  placeholderText: "Description"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onTextChanged: root.runEditDesc = text
                  Keys.onEscapePressed: focus = false
                }

                SearchableDropdown {
                  id: runEditProjectDropdown
                  width: parent.width
                  showLabel: false
                  placeholderText: "Filter projects"
                  triggerLabel: "No project"
                  options: Model.projectOptions(clockify.projects, root.runEditProjectId)
                  value: root.runEditProjectId
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(val) {
                    root.runEditProjectId = val
                    root.runEditTaskId = ""
                  }
                }

                SearchableDropdown {
                  id: runEditTaskDropdown
                  width: parent.width
                  visible: root.runEditProjectId !== ""
                  showLabel: false
                  placeholderText: "Filter tasks"
                  triggerLabel: "No task"
                  options: Model.taskOptions(clockify.projects, root.runEditProjectId, root.runEditTaskId)
                  value: root.runEditTaskId
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(val) { root.runEditTaskId = val }
                }

                MultiSelect {
                  id: runEditTagsMulti
                  width: parent.width
                  showLabel: false
                  placeholderText: "Filter tags"
                  noSelectionText: "No tags"
                  options: Model.tagOptions(clockify.tags)
                  values: root.runEditTagIds
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(vals) { root.runEditTagIds = vals }
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    text: "Start:"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  TextField {
                    id: runEditStartField
                    Layout.preferredWidth: Style.space(76)
                    placeholderText: "HH:MM"
                    foreground: root.foreground
                    font.family: root.fontFamily
                    Keys.onEscapePressed: focus = false
                  }

                  Button {
                    text: "-5m"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.runEditAdjustMin -= 5
                  }

                  Button {
                    text: "+5m"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.runEditAdjustMin += 5
                  }

                  Text {
                    visible: root.runEditAdjustMin !== 0
                    textFormat: Text.PlainText
                    text: (root.runEditAdjustMin > 0 ? "+" : "") + root.runEditAdjustMin + "m"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item { Layout.fillWidth: true }
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Button {
                    text: "Billable"
                    iconText: "󰄬"
                    bordered: true
                    selected: root.runEditBillable
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.runEditBillable = !root.runEditBillable
                  }

                  Item { Layout.fillWidth: true }

                  Button {
                    text: "Cancel"
                    bordered: true
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    onClicked: root.editRunningOpen = false
                  }

                  Button {
                    text: "Save Live"
                    iconText: "󰄳"
                    bordered: true
                    enabled: !clockify.actionBusy
                    foreground: root.accent
                    fontFamily: root.fontFamily
                    onClicked: root.saveRunningEdits()
                  }
                }
              }
            }
          }

          // Status / Error Banner
          Text {
            visible: root.statusText !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.statusText
            color: root.statusIsError ? root.urgent : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // ---------------------------------------------------------- login (when unconfigured)
          Column {
            visible: !clockify.configured
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "CONNECT CLOCKIFY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Sign in to the Clockify Desktop app (auto-detected) or paste a personal API key from Clockify Preferences → Advanced → API."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: keyField
                Layout.fillWidth: true
                password: true
                placeholderText: "Paste Clockify API key"
                foreground: root.foreground
                font.family: root.fontFamily
                enabled: !clockify.actionBusy
                onAccepted: root.commitKey()
                Keys.onEscapePressed: focus = false
              }

              Button {
                text: "Connect"
                iconText: "󰌆"
                bordered: true
                enabled: !clockify.actionBusy && keyField.text !== ""
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.commitKey()
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "Open Clockify App"
                iconText: "󰀻"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.launchDesktopApp()
              }

              Button {
                text: "Re-scan Desktop Session"
                iconText: "󰑐"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.refresh(true)
              }
            }
          }

          // ---------------------------------------------------------- main tabs
          ButtonGroup {
            visible: clockify.configured
            value: root.activeTab
            foreground: root.foreground
            background: Color.popups.background
            accent: root.accent
            fontFamily: root.fontFamily
            options: [
              { value: "tracker", label: "Tracker", icon: "󱎫" },
              { value: "history", label: "Dashboard", icon: "󰋚" },
              { value: "manage", label: "Manage", icon: "󰉋" },
              { value: "settings", label: "Settings", icon: "󰒓" }
            ]
            onChanged: function(val) {
              root.activeTab = val
              if (val === "history" || val === "manage") {
                clockify.refresh(val === "manage")
              }
            }
          }

          PanelSeparator {
            visible: clockify.configured
            foreground: root.foreground
          }

          // ========================================================== TAB 1: TRACKER
          Column {
            visible: clockify.configured && root.activeTab === "tracker"
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              ButtonGroup {
                value: root.trackerMode
                foreground: root.foreground
                background: Color.popups.background
                accent: root.accent
                fontFamily: root.fontFamily
                options: [
                  { value: "timer", label: "Timer", icon: "󰐊" },
                  { value: "manual", label: "Manual Entry", icon: "󰃭" }
                ]
                onChanged: function(val) { root.trackerMode = val }
              }

              Item { Layout.fillWidth: true }
            }

            // Quick Resume recent presets
            Flow {
              visible: clockify.recentEntries.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: Model.recentQuickPresets(clockify.recentEntries, 5)
                delegate: Button {
                  required property var modelData
                  text: modelData.label
                  iconText: "󰐊"
                  bordered: true
                  tooltipText: Model.neutralizeMarkup(
                    (modelData.description || "No description") +
                    (modelData.projectName ? " · " + modelData.projectName : "") +
                    (modelData.taskName ? " / " + modelData.taskName : "")
                  )
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: {
                    root.draftDescription = modelData.description
                    descriptionField.text = modelData.description
                    root.draftProjectId = modelData.projectId
                    root.draftTaskId = modelData.taskId
                    root.draftTagIds = Array.isArray(modelData.tagIds) ? modelData.tagIds.slice() : []
                    root.draftBillable = modelData.billable
                  }
                }
              }
            }

            TextField {
              id: descriptionField
              width: parent.width
              placeholderText: root.trackerMode === "manual"
                ? "What did you work on?"
                : (clockify.timing ? "Describe the next task (Enter switches)" : "What are you working on?")
              foreground: root.foreground
              font.family: root.fontFamily
              enabled: !clockify.actionBusy
              onTextChanged: root.draftDescription = text
              onAccepted: {
                focus = false
                if (root.trackerMode === "timer") {
                  clockify.start(root.draftDescription, root.draftProjectId, root.draftTaskId, root.draftTagIds, root.draftBillable)
                  root.clearDraftDescription()
                }
              }
              Keys.onEscapePressed: focus = false
            }

            SearchableDropdown {
              id: projectDropdown
              width: parent.width
              showLabel: false
              placeholderText: "Filter projects"
              emptyText: clockify.fullLoaded ? "No matching project" : "Loading projects…"
              triggerLabel: "No project"
              options: Model.projectOptions(clockify.projects, root.draftProjectId)
              value: root.draftProjectId
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) {
                root.draftProjectId = value
                root.draftTaskId = ""
                clockify.rememberProject(value)
              }
            }

            SearchableDropdown {
              id: taskDropdown
              width: parent.width
              visible: root.draftProjectId !== ""
              showLabel: false
              placeholderText: "Filter tasks"
              emptyText: "No tasks in this project"
              triggerLabel: "No task"
              options: Model.taskOptions(clockify.projects, root.draftProjectId, root.draftTaskId)
              value: root.draftTaskId
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) {
                root.draftTaskId = value
                clockify.saveConfig({ task: value })
              }
            }

            MultiSelect {
              id: tagsMulti
              width: parent.width
              showLabel: false
              placeholderText: "Filter tags"
              emptyText: "No workspace tags"
              noSelectionText: "No tags selected"
              options: Model.tagOptions(clockify.tags)
              values: root.draftTagIds
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(vals) {
                root.draftTagIds = vals
                clockify.saveConfig({ tags: vals })
              }
            }

            // Manual Date & Time Inputs
            RowLayout {
              visible: root.trackerMode === "manual"
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: manualDateField
                Layout.fillWidth: true
                text: root.manualDate
                placeholderText: "today / YYYY-MM-DD"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.manualDate = text
                Keys.onEscapePressed: focus = false
              }

              TextField {
                id: manualStartField
                Layout.preferredWidth: Style.space(76)
                text: root.manualStart
                placeholderText: "Start 09:00"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.manualStart = text
                Keys.onEscapePressed: focus = false
              }

              Text {
                textFormat: Text.PlainText
                text: "→"
                color: root.dim
                font.family: root.fontFamily
              }

              TextField {
                id: manualEndField
                Layout.preferredWidth: Style.space(76)
                text: root.manualEnd
                placeholderText: "End 10:30"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.manualEnd = text
                Keys.onEscapePressed: focus = false
              }
            }

            // Billable & Primary Action Row
            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: root.draftBillable ? "Billable" : "Non-billable"
                iconText: "󰄬"
                bordered: true
                selected: root.draftBillable
                foreground: root.draftBillable ? root.accent : root.dim
                fontFamily: root.fontFamily
                onClicked: {
                  root.draftBillable = !root.draftBillable
                  clockify.saveConfig({ billable: root.draftBillable })
                }
              }

              Item { Layout.fillWidth: true }

              Button {
                visible: root.trackerMode === "timer"
                text: clockify.timing ? "Switch Timer" : "Start Timer"
                iconText: "󰐊"
                bordered: true
                enabled: !clockify.actionBusy
                foreground: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  clockify.start(root.draftDescription, root.draftProjectId, root.draftTaskId, root.draftTagIds, root.draftBillable)
                  root.clearDraftDescription()
                }
              }

              Button {
                visible: root.trackerMode === "manual"
                text: "Add Manual Entry"
                iconText: "󰐕"
                bordered: true
                enabled: !clockify.actionBusy && root.manualStart.trim() !== "" && root.manualEnd.trim() !== ""
                foreground: root.accent
                fontFamily: root.fontFamily
                onClicked: root.submitManualEntry()
              }
            }

            PanelSeparator {
              foreground: root.foreground
            }

            // Summary totals
            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              Total {
                label: "TODAY"
                value: Model.formatDuration(root.todaySeconds)
                sub: root.todayBillableSeconds > 0 ? (Model.formatDuration(root.todayBillableSeconds) + " billable") : ""
                Layout.fillWidth: true
              }

              Total {
                label: clockify.weekStart === "sunday" ? "THIS WEEK (SUN)" : "THIS WEEK"
                value: Model.formatDuration(root.weekSeconds)
                sub: root.weekBillableSeconds > 0 ? (Model.formatDuration(root.weekBillableSeconds) + " billable") : ""
                Layout.fillWidth: true
              }

              Total {
                label: "THIS MONTH"
                value: Model.formatDuration(root.monthSeconds)
                sub: root.monthBillableSeconds > 0 ? (Model.formatDuration(root.monthBillableSeconds) + " billable") : ""
                Layout.fillWidth: true
              }
            }
          }

          // ========================================================== TAB 2: DASHBOARD & HISTORY
          Column {
            visible: clockify.configured && root.activeTab === "history"
            width: parent.width
            spacing: Style.space(8)

            // Period Selector Pills
            ButtonGroup {
              value: root.periodMode
              foreground: root.foreground
              background: Color.popups.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              options: [
                { value: "day", label: "Day" },
                { value: "week", label: "Week" },
                { value: "month", label: "Month" },
                { value: "year", label: "Year" },
                { value: "all", label: "All" },
                { value: "custom", label: "Custom" }
              ]
              onChanged: function(val) {
                root.periodMode = val
                root.periodOffset = 0
                if (val === "all" && clockify.loadedStartDate > "2020-01-01") {
                  clockify.fetchRange("2018-01-01", Model.toLocalDateIso(new Date()))
                }
              }
            }

            // Period Navigator + CSV Export
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelActionButton {
                visible: root.periodMode !== "all" && root.periodMode !== "custom"
                iconText: "󰅁"
                tooltipText: "Previous period"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.stepPeriod(-1)
              }

              Column {
                Layout.fillWidth: true
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.periodBounds.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.periodBounds.subtitle
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Button {
                visible: root.periodOffset !== 0 && root.periodMode !== "all" && root.periodMode !== "custom"
                text: "Today"
                bordered: true
                foreground: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.periodOffset = 0
              }

              PanelActionButton {
                visible: root.periodMode !== "all" && root.periodMode !== "custom"
                iconText: "󰅂"
                tooltipText: "Next period"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.periodOffset < 0
                onClicked: root.stepPeriod(1)
              }

              PanelActionButton {
                iconText: "󰈛"
                tooltipText: "Export filtered report to CSV"
                foreground: root.accent
                fontFamily: root.fontFamily
                enabled: !clockify.actionBusy
                onClicked: clockify.exportCsv(
                  root.periodBounds.startIso,
                  root.periodBounds.endIso,
                  root.filterProjectId,
                  root.filterTaskId,
                  root.filterTagId,
                  root.filterBillable,
                  root.historyQuery
                )
              }
            }

            // Custom Date Range Picker
            RowLayout {
              visible: root.periodMode === "custom"
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: customFromField
                Layout.fillWidth: true
                text: root.customFrom
                placeholderText: "From YYYY-MM-DD"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.customFrom = text
                Keys.onEscapePressed: focus = false
              }

              Text {
                textFormat: Text.PlainText
                text: "→"
                color: root.dim
                font.family: root.fontFamily
              }

              TextField {
                id: customToField
                Layout.fillWidth: true
                text: root.customTo
                placeholderText: "To YYYY-MM-DD"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.customTo = text
                Keys.onEscapePressed: focus = false
              }

              Button {
                text: "Fetch"
                iconText: "󰑐"
                bordered: true
                enabled: !clockify.actionBusy
                foreground: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: clockify.fetchRange(root.customFrom, root.customTo)
              }
            }

            // Search & Multi-Filter Controls
            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              TextField {
                id: historyFilterField
                Layout.fillWidth: true
                placeholderText: "Search entries, projects, tasks, tags…"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.historyQuery = text
                Keys.onEscapePressed: focus = false
              }

              Button {
                text: root.activeFilterCount > 0 ? ("Filters (" + root.activeFilterCount + ")") : "Filters"
                iconText: "󰈲"
                bordered: true
                selected: root.filtersExpanded || root.activeFilterCount > 0
                foreground: root.activeFilterCount > 0 ? root.accent : root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.filtersExpanded = !root.filtersExpanded
              }

              PanelActionButton {
                visible: root.activeFilterCount > 0 || root.historyQuery !== ""
                iconText: "󰅖"
                tooltipText: "Clear all filters"
                foreground: root.urgent
                fontFamily: root.fontFamily
                onClicked: root.clearDashboardFilters()
              }
            }

            // Collapsible Multi-Filter Drawer
            BorderSurface {
              visible: root.filtersExpanded
              width: parent.width
              implicitHeight: filterDrawerCol.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Column {
                id: filterDrawerCol
                anchors.fill: parent
                anchors.margins: Style.space(7)
                spacing: Style.space(6)

                SearchableDropdown {
                  id: filterProjectDropdown
                  width: parent.width
                  showLabel: false
                  placeholderText: "Filter by project"
                  triggerLabel: "All projects"
                  options: Model.projectOptions(clockify.projects, root.filterProjectId, "All projects")
                  value: root.filterProjectId
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(val) {
                    root.filterProjectId = val
                    root.filterTaskId = ""
                  }
                }

                SearchableDropdown {
                  id: filterTaskDropdown
                  width: parent.width
                  showLabel: false
                  placeholderText: "Filter by task"
                  triggerLabel: "All tasks"
                  options: Model.taskOptions(clockify.projects, root.filterProjectId, root.filterTaskId, "All tasks")
                  value: root.filterTaskId
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(val) { root.filterTaskId = val }
                }

                Dropdown {
                  id: filterTagDropdown
                  width: parent.width
                  showLabel: false
                  options: Model.tagFilterOptions(clockify.tags)
                  value: root.filterTagId
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(val) { root.filterTagId = val }
                }

                ButtonGroup {
                  value: root.filterBillable
                  foreground: root.foreground
                  background: Color.popups.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  options: [
                    { value: "all", label: "All" },
                    { value: "billable", label: "Billable $" },
                    { value: "non-billable", label: "Non-billable" }
                  ]
                  onChanged: function(val) { root.filterBillable = val }
                }
              }
            }

            // 4 KPI Summary Cards
            GridLayout {
              width: parent.width
              columns: 4
              columnSpacing: Style.space(6)
              rowSpacing: Style.space(6)

              KpiCard {
                Layout.fillWidth: true
                label: "TOTAL"
                value: Model.formatDuration(root.dashboardData.totalSeconds)
                sub: Model.formatClock(root.dashboardData.totalSeconds)
                highlight: root.accent
              }

              KpiCard {
                Layout.fillWidth: true
                label: "BILLABLE"
                value: Model.formatDuration(root.dashboardData.billableSeconds)
                sub: root.dashboardData.billablePercent + "% of total"
                highlight: root.foreground
              }

              KpiCard {
                Layout.fillWidth: true
                label: "DAILY AVG"
                value: Model.formatDuration(root.dashboardData.dailyAvgSeconds)
                sub: root.dashboardData.activeDays + "d · " + root.dashboardData.entryCount + " items"
                highlight: root.foreground
              }

              KpiCard {
                Layout.fillWidth: true
                label: "TOP PROJECT"
                value: root.dashboardData.topProject ? root.dashboardData.topProject.name : "—"
                sub: root.dashboardData.topProject ? (Model.formatDuration(root.dashboardData.topProject.seconds) + " (" + root.dashboardData.topProject.percent + "%)") : "No entries"
                highlight: root.dashboardData.topProject ? root.dashboardData.topProject.color : root.dim
              }
            }

            // Interactive Activity Bar Chart
            BorderSurface {
              visible: root.dashboardData.chartBars.length > 0
              width: parent.width
              implicitHeight: chartCardCol.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Column {
                id: chartCardCol
                anchors.fill: parent
                anchors.margins: Style.space(7)
                spacing: Style.space(6)

                RowLayout {
                  width: parent.width

                  PanelSectionHeader {
                    text: root.periodMode === "day" ? "HOURLY ACTIVITY" : (root.periodMode === "year" ? "MONTHLY ACTIVITY" : "DAILY ACTIVITY")
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    visible: root.periodMode === "week" || root.periodMode === "month" || root.periodMode === "all" || root.periodMode === "custom"
                    textFormat: Text.PlainText
                    text: "Click a bar for day view"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Item {
                  id: chartPlot
                  width: parent.width
                  height: Style.space(96)

                  Row {
                    id: chartRow
                    anchors.fill: parent
                    spacing: root.dashboardData.chartBars.length > 20 ? Style.space(2) : Style.space(5)

                    Repeater {
                      model: root.dashboardData.chartBars

                      delegate: Item {
                        id: barCol
                        required property var modelData
                        readonly property int barCount: Math.max(1, root.dashboardData.chartBars.length)
                        readonly property real usableBarMaxH: Style.space(62)
                        readonly property real barTotalH: modelData.seconds > 0 ? Math.max(Style.space(4), modelData.ratio * usableBarMaxH) : Style.space(2)
                        readonly property real billH: modelData.seconds > 0 ? (barTotalH * modelData.billableRatio) : 0
                        readonly property bool clickableDay: modelData.dayOffsetFromToday !== null && modelData.dayOffsetFromToday !== undefined

                        width: Math.max(3, (chartRow.width - chartRow.spacing * (barCount - 1)) / barCount)
                        height: chartRow.height

                        Text {
                          visible: barCol.barCount <= 14 && modelData.valueLabel !== ""
                          anchors.bottom: barStack.top
                          anchors.bottomMargin: Style.space(2)
                          anchors.horizontalCenter: parent.horizontalCenter
                          textFormat: Text.PlainText
                          text: modelData.valueLabel
                          color: modelData.isToday ? root.accent : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Math.max(8, Style.font.caption - 1)
                        }

                        Item {
                          id: barStack
                          anchors.bottom: barLabelTxt.top
                          anchors.bottomMargin: Style.space(4)
                          anchors.horizontalCenter: parent.horizontalCenter
                          width: Math.min(Style.space(26), Math.max(4, parent.width - 2))
                          height: barCol.barTotalH

                          Rectangle {
                            anchors.fill: parent
                            radius: Math.min(3, width / 2)
                            color: modelData.seconds > 0
                              ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                            border.width: modelData.isToday ? 1 : 0
                            border.color: root.accent
                          }

                          Rectangle {
                            visible: barCol.billH > 0
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: Math.max(2, barCol.billH)
                            radius: Math.min(3, width / 2)
                            color: barMouse.containsMouse ? Qt.lighter(root.accent, 1.2) : root.accent
                          }
                        }

                        Text {
                          id: barLabelTxt
                          anchors.bottom: parent.bottom
                          anchors.horizontalCenter: parent.horizontalCenter
                          textFormat: Text.PlainText
                          text: modelData.shortLabel
                          color: modelData.isToday ? root.accent : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Math.max(8, Style.font.caption - 1)
                          font.bold: modelData.isToday === true
                        }

                        MouseArea {
                          id: barMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: barCol.clickableDay ? Qt.PointingHandCursor : Qt.ArrowCursor
                          onClicked: {
                            if (barCol.clickableDay) {
                              root.periodMode = "day"
                              root.periodOffset = Number(modelData.dayOffsetFromToday)
                            }
                          }
                        }

                        PanelToolTip {
                          visible: barMouse.containsMouse
                          text: modelData.tooltip
                          fontFamily: root.fontFamily
                        }
                      }
                    }
                  }
                }
              }
            }

            // Stacked Distribution Bar & Switchable Breakdown
            BorderSurface {
              visible: root.dashboardData.totalSeconds > 0
              width: parent.width
              implicitHeight: breakdownCol.implicitHeight + Style.space(14)
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

              Column {
                id: breakdownCol
                anchors.fill: parent
                anchors.margins: Style.space(7)
                spacing: Style.space(8)

                ButtonGroup {
                  value: root.breakdownMode
                  foreground: root.foreground
                  background: Color.popups.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  options: [
                    { value: "projects", label: "By Project" },
                    { value: "tasks", label: "By Task" },
                    { value: "tags", label: "By Tag" },
                    { value: "days", label: "By Day" }
                  ]
                  onChanged: function(val) { root.breakdownMode = val }
                }

                // Multi-segment horizontal distribution bar
                Rectangle {
                  width: parent.width
                  height: Style.space(8)
                  radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                  clip: true

                  Row {
                    id: stackedRow
                    anchors.fill: parent
                    spacing: 1

                    Repeater {
                      model: root.activeBreakdownList
                      delegate: Rectangle {
                        required property var modelData
                        height: parent.height
                        width: Math.max(2, (stackedRow.width - Math.max(0, root.activeBreakdownList.length - 1)) * (modelData.seconds / Math.max(1, root.dashboardData.totalSeconds)))
                        color: modelData.color || root.accent
                      }
                    }
                  }
                }

                // Breakdown Rows (click to filter)
                Repeater {
                  model: root.activeBreakdownList.slice(0, 8)
                  delegate: BorderSurface {
                    id: bdRow
                    required property var modelData
                    readonly property bool isActiveFilter: (
                      (root.breakdownMode === "projects" && root.filterProjectId === modelData.id && modelData.id !== "") ||
                      (root.breakdownMode === "tasks" && root.filterTaskId === modelData.id && modelData.id !== "") ||
                      (root.breakdownMode === "tags" && root.filterTagId === modelData.id && modelData.id !== "")
                    )
                    width: parent.width
                    implicitHeight: bdRowContent.implicitHeight + Style.space(8)
                    radius: Style.cornerRadius
                    color: bdMouse.containsMouse || isActiveFilter
                      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                      : "transparent"
                    borderSpec: isActiveFilter
                      ? Border.controlSpec("focus", root.foreground, root.accent)
                      : Border.none()

                    Column {
                      id: bdRowContent
                      anchors.fill: parent
                      anchors.margins: Style.space(4)
                      spacing: Style.space(3)

                      RowLayout {
                        width: parent.width
                        spacing: Style.space(6)

                        Rectangle {
                          width: Style.space(8)
                          height: Style.space(8)
                          radius: width / 2
                          color: modelData.color || root.accent
                        }

                        Text {
                          Layout.fillWidth: true
                          textFormat: Text.PlainText
                          text: modelData.name + (modelData.clientName ? " · " + modelData.clientName : "")
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: bdRow.isActiveFilter
                          elide: Text.ElideRight
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: modelData.count + "×"
                          color: root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: Model.formatDuration(modelData.seconds) + " (" + modelData.percent + "%)"
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: true
                        }
                      }

                      Rectangle {
                        width: parent.width
                        height: Style.space(3)
                        radius: 2
                        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

                        Rectangle {
                          height: parent.height
                          width: Math.max(3, parent.width * modelData.ratio)
                          radius: 2
                          color: modelData.color || root.accent
                        }
                      }
                    }

                    MouseArea {
                      id: bdMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleBreakdownFilter(modelData)
                    }
                  }
                }
              }
            }

            Text {
              visible: root.dashboardData.groupedByDate.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: clockify.recentEntries.length === 0
                ? "No time entries loaded yet."
                : "No entries match this period and filter."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            // Date-Grouped Detailed Time Entries
            Repeater {
              model: root.dashboardData.groupedByDate

              delegate: Column {
                id: dayGroup
                required property var modelData
                width: parent.width
                spacing: Style.space(6)

                RowLayout {
                  width: parent.width

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: modelData.dateLabel + "  ·  " + modelData.dateIso
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.formatDuration(modelData.totalSeconds)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Repeater {
                  model: dayGroup.modelData.entries

                  delegate: BorderSurface {
                    id: entryRow
                    required property var modelData
                    readonly property bool isEditing: root.editingEntryId === String(modelData.id || "")
                    width: parent.width
                    implicitHeight: entryCol.implicitHeight + Style.space(14)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, isEditing ? 0.06 : 0.03)
                    borderSpec: Border.controlSpec(isEditing ? "focus" : "normal", root.foreground, root.accent)

                    Column {
                      id: entryCol
                      anchors.fill: parent
                      anchors.margins: Style.space(7)
                      spacing: Style.space(6)

                      RowLayout {
                        width: parent.width
                        spacing: Style.space(6)

                        Rectangle {
                          width: Style.space(8)
                          height: Style.space(8)
                          radius: width / 2
                          color: entryRow.modelData.projectColor ? entryRow.modelData.projectColor : root.dim
                          Layout.alignment: Qt.AlignVCenter
                        }

                        Column {
                          Layout.fillWidth: true
                          spacing: Style.space(2)

                          Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: Model.describeEntry(entryRow.modelData)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                            font.bold: true
                            elide: Text.ElideRight
                          }

                          Text {
                            width: parent.width
                            textFormat: Text.PlainText
                            text: [
                              (entryRow.modelData.startLocal && entryRow.modelData.endLocal) ? (entryRow.modelData.startLocal + "–" + entryRow.modelData.endLocal) : "",
                              Model.projectLabel(entryRow.modelData),
                              Model.taskLabel(entryRow.modelData),
                              Model.tagsLabel(entryRow.modelData),
                              entryRow.modelData.billable ? "$" : ""
                            ].filter(function(x) { return x !== "" }).join(" · ")
                            color: root.dim
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            elide: Text.ElideRight
                          }
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: Model.formatClock(entryRow.modelData.seconds)
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }

                        PanelActionButton {
                          iconText: "󰐊"
                          tooltipText: "Continue timer"
                          foreground: root.accent
                          fontFamily: root.fontFamily
                          enabled: !clockify.actionBusy
                          onClicked: clockify.continueEntry(entryRow.modelData.id)
                        }

                        PanelActionButton {
                          iconText: "󰏫"
                          tooltipText: entryRow.isEditing ? "Close editor" : "Edit entry"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          enabled: !clockify.actionBusy && !entryRow.modelData.isLocked
                          onClicked: {
                            if (entryRow.isEditing) root.editingEntryId = ""
                            else root.openEntryEditor(entryRow.modelData)
                          }
                        }

                        PanelActionButton {
                          iconText: "󰆏"
                          tooltipText: "Duplicate entry"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          enabled: !clockify.actionBusy
                          onClicked: clockify.duplicateEntry(entryRow.modelData.id)
                        }

                        PanelActionButton {
                          iconText: root.confirmDeleteId === String(entryRow.modelData.id) ? "󰄬" : "󰆴"
                          tooltipText: root.confirmDeleteId === String(entryRow.modelData.id) ? "Click again to confirm delete" : "Delete entry"
                          foreground: root.confirmDeleteId === String(entryRow.modelData.id) ? root.urgent : root.dim
                          hoverColor: root.urgent
                          fontFamily: root.fontFamily
                          enabled: !clockify.actionBusy && !entryRow.modelData.isLocked
                          onClicked: {
                            var eid = String(entryRow.modelData.id)
                            if (root.confirmDeleteId !== eid) {
                              root.confirmDeleteId = eid
                            } else {
                              root.confirmDeleteId = ""
                              clockify.deleteEntry(eid)
                            }
                          }
                        }
                      }

                      // Inline past-entry editor
                      Column {
                        visible: entryRow.isEditing
                        width: parent.width
                        spacing: Style.space(6)

                        TextField {
                          width: parent.width
                          text: root.entryEditDesc
                          placeholderText: "Description"
                          foreground: root.foreground
                          font.family: root.fontFamily
                          onTextChanged: if (entryRow.isEditing) root.entryEditDesc = text
                          Keys.onEscapePressed: root.editingEntryId = ""
                        }

                        SearchableDropdown {
                          width: parent.width
                          showLabel: false
                          placeholderText: "Filter projects"
                          triggerLabel: "No project"
                          options: Model.projectOptions(clockify.projects, root.entryEditProjectId)
                          value: root.entryEditProjectId
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onChanged: function(val) {
                            root.entryEditProjectId = val
                            root.entryEditTaskId = ""
                          }
                        }

                        SearchableDropdown {
                          width: parent.width
                          visible: root.entryEditProjectId !== ""
                          showLabel: false
                          placeholderText: "Filter tasks"
                          triggerLabel: "No task"
                          options: Model.taskOptions(clockify.projects, root.entryEditProjectId, root.entryEditTaskId)
                          value: root.entryEditTaskId
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onChanged: function(val) { root.entryEditTaskId = val }
                        }

                        MultiSelect {
                          width: parent.width
                          showLabel: false
                          placeholderText: "Filter tags"
                          noSelectionText: "No tags"
                          options: Model.tagOptions(clockify.tags)
                          values: root.entryEditTagIds
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onChanged: function(vals) { root.entryEditTagIds = vals }
                        }

                        RowLayout {
                          width: parent.width
                          spacing: Style.space(6)

                          TextField {
                            Layout.fillWidth: true
                            text: root.entryEditDate
                            placeholderText: "YYYY-MM-DD"
                            foreground: root.foreground
                            font.family: root.fontFamily
                            onTextChanged: if (entryRow.isEditing) root.entryEditDate = text
                          }

                          TextField {
                            Layout.preferredWidth: Style.space(68)
                            text: root.entryEditStart
                            placeholderText: "HH:MM"
                            foreground: root.foreground
                            font.family: root.fontFamily
                            onTextChanged: if (entryRow.isEditing) root.entryEditStart = text
                          }

                          Text {
                            textFormat: Text.PlainText
                            text: "→"
                            color: root.dim
                            font.family: root.fontFamily
                          }

                          TextField {
                            Layout.preferredWidth: Style.space(68)
                            text: root.entryEditEnd
                            placeholderText: "HH:MM"
                            foreground: root.foreground
                            font.family: root.fontFamily
                            onTextChanged: if (entryRow.isEditing) root.entryEditEnd = text
                          }
                        }

                        RowLayout {
                          width: parent.width
                          spacing: Style.space(6)

                          Button {
                            text: "Billable"
                            iconText: "󰄬"
                            bordered: true
                            selected: root.entryEditBillable
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            onClicked: root.entryEditBillable = !root.entryEditBillable
                          }

                          Item { Layout.fillWidth: true }

                          Button {
                            text: "Cancel"
                            bordered: true
                            foreground: root.dim
                            fontFamily: root.fontFamily
                            onClicked: root.editingEntryId = ""
                          }

                          Button {
                            text: "Save"
                            iconText: "󰄳"
                            bordered: true
                            enabled: !clockify.actionBusy
                            foreground: root.accent
                            fontFamily: root.fontFamily
                            onClicked: {
                              clockify.updateEntry(
                                entryRow.modelData.id,
                                root.entryEditDesc,
                                root.entryEditProjectId,
                                root.entryEditTaskId,
                                root.entryEditTagIds,
                                root.entryEditBillable,
                                root.entryEditDate,
                                root.entryEditStart,
                                root.entryEditEnd
                              )
                              root.editingEntryId = ""
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ========================================================== TAB 3: MANAGE
          Column {
            visible: clockify.configured && root.activeTab === "manage"
            width: parent.width
            spacing: Style.space(10)

            ButtonGroup {
              value: root.manageTab
              foreground: root.foreground
              background: Color.popups.background
              accent: root.accent
              fontFamily: root.fontFamily
              options: [
                { value: "project", label: "Projects (" + clockify.projects.length + ")" },
                { value: "task", label: "Tasks" },
                { value: "tag", label: "Tags (" + clockify.tags.length + ")" },
                { value: "client", label: "Clients (" + clockify.clients.length + ")" }
              ]
              onChanged: function(val) { root.manageTab = val }
            }

            // --- Create Project ---
            Column {
              visible: root.manageTab === "project"
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: newProjectNameField
                width: parent.width
                placeholderText: "New project name"
                foreground: root.foreground
                font.family: root.fontFamily
                onTextChanged: root.newProjectName = text
                Keys.onEscapePressed: focus = false
              }

              Dropdown {
                id: newProjectClientDropdown
                width: parent.width
                showLabel: false
                options: Model.clientOptions(clockify.clients, root.newProjectClientId)
                value: root.newProjectClientId
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(val) { root.newProjectClientId = val }
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: root.projectColorPalette
                  delegate: Rectangle {
                    required property string modelData
                    width: Style.space(22)
                    height: Style.space(22)
                    radius: width / 2
                    color: modelData
                    border.width: root.newProjectColor === modelData ? 2 : 0
                    border.color: root.foreground
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.newProjectColor = modelData
                    }
                  }
                }
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                Button {
                  text: "Billable"
                  bordered: true
                  selected: root.newProjectBillable
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.newProjectBillable = !root.newProjectBillable
                }

                Button {
                  text: root.newProjectPublic ? "Public" : "Private"
                  bordered: true
                  selected: root.newProjectPublic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.newProjectPublic = !root.newProjectPublic
                }

                Item { Layout.fillWidth: true }

                Button {
                  text: "Create Project"
                  iconText: "󰐕"
                  bordered: true
                  enabled: !clockify.actionBusy && root.newProjectName.trim() !== ""
                  foreground: root.accent
                  fontFamily: root.fontFamily
                  onClicked: {
                    clockify.createProject(root.newProjectName, root.newProjectClientId, root.newProjectColor, root.newProjectBillable, root.newProjectPublic)
                    newProjectNameField.text = ""
                    root.newProjectName = ""
                  }
                }
              }

              PanelSeparator { foreground: root.foreground }

              Repeater {
                model: clockify.projects
                delegate: RowLayout {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(8)
                  Rectangle {
                    width: Style.space(8)
                    height: Style.space(8)
                    radius: width / 2
                    color: modelData.color || root.dim
                  }
                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: modelData.name + (modelData.clientName ? " · " + modelData.clientName : "")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: (Array.isArray(modelData.tasks) ? modelData.tasks.length : 0) + " tasks"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // --- Create Task ---
            Column {
              visible: root.manageTab === "task"
              width: parent.width
              spacing: Style.space(8)

              SearchableDropdown {
                id: newTaskProjectDropdown
                width: parent.width
                showLabel: false
                placeholderText: "Select project for task"
                triggerLabel: "Choose project"
                options: Model.projectOptions(clockify.projects, root.newTaskProjectId)
                value: root.newTaskProjectId
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(val) { root.newTaskProjectId = val }
              }

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: newTaskNameField
                  Layout.fillWidth: true
                  placeholderText: "New task name"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onTextChanged: root.newTaskName = text
                  Keys.onEscapePressed: focus = false
                }

                Button {
                  text: "Add Task"
                  iconText: "󰐕"
                  bordered: true
                  enabled: !clockify.actionBusy && root.newTaskProjectId !== "" && root.newTaskName.trim() !== ""
                  foreground: root.accent
                  fontFamily: root.fontFamily
                  onClicked: {
                    clockify.createTask(root.newTaskProjectId, root.newTaskName)
                    newTaskNameField.text = ""
                    root.newTaskName = ""
                  }
                }
              }

              PanelSeparator { foreground: root.foreground }

              Repeater {
                model: Model.taskOptions(clockify.projects, root.newTaskProjectId, "").slice(1)
                delegate: Text {
                  required property var modelData
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "• " + modelData.label
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }

            // --- Create Tag ---
            Column {
              visible: root.manageTab === "tag"
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: newTagNameField
                  Layout.fillWidth: true
                  placeholderText: "New tag name"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onTextChanged: root.newTagName = text
                  Keys.onEscapePressed: focus = false
                }

                Button {
                  text: "Add Tag"
                  iconText: "󰐕"
                  bordered: true
                  enabled: !clockify.actionBusy && root.newTagName.trim() !== ""
                  foreground: root.accent
                  fontFamily: root.fontFamily
                  onClicked: {
                    clockify.createTag(root.newTagName)
                    newTagNameField.text = ""
                    root.newTagName = ""
                  }
                }
              }

              Flow {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: clockify.tags
                  delegate: BorderSurface {
                    required property var modelData
                    implicitWidth: tagTxt.implicitWidth + Style.space(12)
                    implicitHeight: tagTxt.implicitHeight + Style.space(6)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
                    Text {
                      id: tagTxt
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            // --- Create Client ---
            Column {
              visible: root.manageTab === "client"
              width: parent.width
              spacing: Style.space(8)

              RowLayout {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: newClientNameField
                  Layout.fillWidth: true
                  placeholderText: "New client name"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onTextChanged: root.newClientName = text
                  Keys.onEscapePressed: focus = false
                }

                Button {
                  text: "Add Client"
                  iconText: "󰐕"
                  bordered: true
                  enabled: !clockify.actionBusy && root.newClientName.trim() !== ""
                  foreground: root.accent
                  fontFamily: root.fontFamily
                  onClicked: {
                    clockify.createClient(root.newClientName)
                    newClientNameField.text = ""
                    root.newClientName = ""
                  }
                }
              }

              Text {
                visible: clockify.clients.length === 0
                textFormat: Text.PlainText
                text: "No clients yet."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: clockify.clients
                delegate: Text {
                  required property var modelData
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "• " + modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }
          }

          // ========================================================== TAB 4: SETTINGS
          Column {
            visible: clockify.configured && root.activeTab === "settings"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "WORKSPACE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: workspaceDropdown
              width: parent.width
              showLabel: false
              options: Model.workspaceOptions(clockify.workspaces)
              value: clockify.workspaceId
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(val) {
                if (val && val !== clockify.workspaceId) {
                  root.draftProjectId = ""
                  root.draftTaskId = ""
                  root.draftTagIds = []
                  clockify.switchWorkspace(val)
                }
              }
            }

            PanelSectionHeader {
              text: "POMODORO TIMER"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              NumberField {
                label: "Work (min)"
                value: clockify.pomodoroWorkMin
                from: 1
                to: 180
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.pomodoroWorkMin = val
                  clockify.saveConfig({ pomodoroWork: val })
                }
              }

              NumberField {
                label: "Break (min)"
                value: clockify.pomodoroBreakMin
                from: 1
                to: 60
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.pomodoroBreakMin = val
                  clockify.saveConfig({ pomodoroBreak: val })
                }
              }

              Item { Layout.fillWidth: true }

              Button {
                text: clockify.pomodoroRunning ? "Stop Pomodoro" : "Start Pomodoro"
                iconText: clockify.pomodoroRunning ? "󰓛" : "󰔟"
                bordered: true
                foreground: clockify.pomodoroRunning ? root.urgent : root.accent
                fontFamily: root.fontFamily
                Layout.alignment: Qt.AlignBottom
                onClicked: {
                  if (clockify.pomodoroRunning) clockify.stopPomodoro()
                  else clockify.startPomodoro()
                }
              }
            }

            PanelSectionHeader {
              text: "IDLE & REMINDERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Idle reminder notifications"
              description: "Notify every " + clockify.idleRemindMin + " min when no timer is running"
              checked: clockify.remindWhenIdle
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                clockify.remindWhenIdle = !clockify.remindWhenIdle
                clockify.saveConfig({ remindWhenIdle: clockify.remindWhenIdle })
              }
            }

            Toggle {
              width: parent.width
              label: "Auto-stop forgotten timers"
              description: "Stop timer automatically after " + clockify.idleStopMin + " min"
              checked: clockify.stopOnIdle
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                clockify.stopOnIdle = !clockify.stopOnIdle
                clockify.saveConfig({ stopOnIdle: clockify.stopOnIdle })
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              NumberField {
                label: "Remind every (min)"
                value: clockify.idleRemindMin
                from: 5
                to: 480
                stepSize: 5
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.idleRemindMin = val
                  clockify.saveConfig({ idleRemindMin: val })
                }
              }

              NumberField {
                label: "Auto-stop after (min)"
                value: clockify.idleStopMin
                from: 15
                to: 1440
                stepSize: 15
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.idleStopMin = val
                  clockify.saveConfig({ idleStopMin: val })
                }
              }
            }

            PanelSectionHeader {
              text: "WEEK & ACCOUNT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              value: clockify.weekStart
              foreground: root.foreground
              background: Color.popups.background
              accent: root.accent
              fontFamily: root.fontFamily
              options: [
                { value: "monday", label: "Week starts Monday" },
                { value: "sunday", label: "Week starts Sunday" }
              ]
              onChanged: function(val) {
                clockify.weekStart = val
                clockify.saveConfig({ weekStart: val })
                clockify.refresh(false)
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Auth source: " + (clockify.authSource === "desktop-app" ? "Clockify Desktop App session (auto)" : clockify.authSource)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "Open Clockify Desktop"
                iconText: "󰀻"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.launchDesktopApp()
              }

              Button {
                text: "Open Web Dashboard"
                iconText: "󰖟"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.openWebApp()
              }

              Button {
                visible: clockify.authSource === "api-key"
                text: "Forget API Key"
                iconText: "󰌆"
                bordered: true
                foreground: root.urgent
                fontFamily: root.fontFamily
                onClicked: clockify.clearKey()
              }
            }
          }

          PanelSeparator {
            visible: clockify.configured
            foreground: root.foreground
          }

          // -------------------------------------------------------- footer
          RowLayout {
            visible: clockify.configured
            width: parent.width
            spacing: Style.space(6)

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "󰀄  " + clockify.userName + (clockify.workspaceName === "" ? "" : "  ·  " + clockify.workspaceName)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh all Clockify data"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !clockify.refreshing
              onClicked: clockify.refresh(true)
            }

            PanelActionButton {
              iconText: "󰀻"
              tooltipText: "Open Clockify Desktop"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: clockify.launchDesktopApp()
            }

            PanelActionButton {
              iconText: "󰒓"
              tooltipText: "Settings & Workspace"
              foreground: root.activeTab === "settings" ? root.accent : root.foreground
              fontFamily: root.fontFamily
              onClicked: root.activeTab = root.activeTab === "settings" ? "tracker" : "settings"
            }
          }
        }
      }
    }
  }

  component Total: Column {
    id: total
    property string label: ""
    property string value: ""
    property string sub: ""

    spacing: Style.space(2)

    Text {
      textFormat: Text.PlainText
      text: total.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }

    Text {
      textFormat: Text.PlainText
      text: total.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }

    Text {
      visible: total.sub !== ""
      textFormat: Text.PlainText
      text: total.sub
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component KpiCard: BorderSurface {
    id: kpi
    property string label: ""
    property string value: ""
    property string sub: ""
    property color highlight: root.foreground

    implicitHeight: kpiCol.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

    Column {
      id: kpiCol
      anchors.fill: parent
      anchors.margins: Style.space(5)
      spacing: Style.space(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: kpi.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 1)
        font.bold: true
        font.letterSpacing: 0.8
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: kpi.value
        color: kpi.highlight
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: kpi.sub
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 1)
        elide: Text.ElideRight
      }
    }
  }
}
