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

  readonly property string iconGlyph: "󱎫"
  readonly property bool active: clockify.timing || root.opened
  readonly property string barTooltip: button.tooltipText

  readonly property string helperPath: String(Qt.resolvedUrl("clockify.py")).replace(/^file:\/\//, "")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool hideWhenIdle: setting("hideWhenIdle", false) === true
  readonly property bool showTimerInBar: setting("showTimerInBar", true) === true
  readonly property bool showTaskInBar: setting("showTaskInBar", false) === true
  readonly property int textWrapMode: clockify.wrapText ? Text.Wrap : Text.NoWrap
  readonly property int textElideMode: clockify.wrapText ? Text.ElideNone : Text.ElideRight
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
  property string trackerMode: "timer"     // "timer" | "manual" | "timesheet"
  property string manageTab: "project"     // "project" | "task" | "tag" | "client"
  property int timesheetOffset: 0

  // Midnight-keyed date so dashboard/timesheet analytics do NOT re-evaluate every second.
  readonly property string todayDateIso: Qt.formatDate(clock.date, "yyyy-MM-dd")
  readonly property var todayMidnightDate: Model.parseLocalDateIso(root.todayDateIso)
  readonly property var tagOptionList: Model.tagOptions(clockify.tags)

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
  property int historyDayLimit: 14
  property string expandedGroupKey: ""

  readonly property var periodBounds: Model.computePeriodBounds(
    root.periodMode, root.periodOffset, clockify.weekStart, root.customFrom, root.customTo, root.todayMidnightDate
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
    root.filteredHistoryEntries, root.periodBounds, root.periodMode, clockify.weekStart, root.todayMidnightDate, clockify.groupSimilarEntries
  )
  readonly property var weeklyTimesheet: Model.buildWeeklyTimesheet(
    clockify.recentEntries, clockify.projects, clockify.weekStart, root.timesheetOffset, root.todayMidnightDate
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
  property bool runEditStartManual: false
  property bool _updatingRunEditStartFromAdjust: false
  readonly property int livePrimaryStepMin: Math.min(Math.max(1, clockify.timeStepMinutes), Math.max(1, clockify.quickStepMinutes))
  readonly property int liveSecondaryStepMin: Math.max(Math.max(1, clockify.timeStepMinutes), Math.max(1, clockify.quickStepMinutes))
  property bool confirmDiscard: false

  // History filter & inline entry editor state
  property string historyQuery: ""

  function invalidatePendingExportOverwrite() {
    if (typeof clockify === "undefined" || !clockify) return
    if (clockify.pendingExportOverwritePath !== "" || clockify.pendingExportRequest !== null) {
      clockify.clearPendingExportOverwrite()
      if (clockify.lastError.indexOf("already exists. Confirm replace to overwrite.") !== -1) {
        clockify.lastError = ""
      }
    }
  }

  onPeriodModeChanged: invalidatePendingExportOverwrite()
  onPeriodOffsetChanged: invalidatePendingExportOverwrite()
  onCustomFromChanged: invalidatePendingExportOverwrite()
  onCustomToChanged: invalidatePendingExportOverwrite()
  onPeriodBoundsChanged: invalidatePendingExportOverwrite()
  onFilterProjectIdChanged: invalidatePendingExportOverwrite()
  onFilterTaskIdChanged: invalidatePendingExportOverwrite()
  onFilterTagIdChanged: invalidatePendingExportOverwrite()
  onFilterBillableChanged: invalidatePendingExportOverwrite()
  onHistoryQueryChanged: invalidatePendingExportOverwrite()
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

  // Manage tab creation & filter state
  property string manageSearch: ""
  property string confirmManageActionKey: ""
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
    settingsKeyField.activeFocus ||
    descriptionField.activeFocus ||
    manualDateField.inputFocused ||
    manualStartField.inputFocused ||
    manualEndField.inputFocused ||
    runEditDescField.activeFocus ||
    runEditStartField.inputFocused ||
    historyFilterField.activeFocus ||
    manageSearchField.activeFocus ||
    customFromField.inputFocused ||
    customToField.inputFocused ||
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

  function openTimesheetCellLog(row, day) {
    if (!day) return
    draftProjectId = String((row && row.projectId) || "")
    draftTaskId = String((row && row.taskId) || "")
    if (row) draftBillable = row.billable === true
    manualDateField.text = String(day.dateIso || "today")
    manualStartField.text = "09:00"
    manualEndField.text = Model.stepTimeHhMm("09:00", Math.max(clockify.timeStepMinutes, 60))
    trackerMode = "manual"
    Qt.callLater(function() { descriptionField.forceActiveFocus() })
  }

  function manageMatches(name, extra) {
    var q = String(manageSearch || "").trim().toLowerCase()
    if (q === "") return true
    var hay = (String(name || "") + " " + String(extra || "")).toLowerCase()
    return hay.indexOf(q) !== -1
  }

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
    var currentDraftTags = Model.toArray(draftTagIds)
    var defTags = Model.toArray(clockify.defaultTagIds)
    if (currentDraftTags.length === 0 && defTags.length > 0) {
      draftTagIds = defTags
      if (tagsMulti) tagsMulti.values = defTags.slice()
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
    runEditTagIds = Model.toArray(r.tagIds)
    if (runEditTagsMulti) runEditTagsMulti.values = runEditTagIds.slice()
    runEditBillable = r.billable === true
    runEditStart = String(r.startLocal || "")
    runEditStartManual = false
    runEditAdjustMin = 0
    _updatingRunEditStartFromAdjust = true
    runEditStartField.text = runEditStart
    _updatingRunEditStartFromAdjust = false
    editRunningOpen = true
  }

  function adjustRunningMinutes(delta) {
    runEditAdjustMin += delta
    _updatingRunEditStartFromAdjust = true
    runEditStartField.text = Model.stepTimeHhMm(runEditStart, -runEditAdjustMin, clock.date)
    _updatingRunEditStartFromAdjust = false
  }

  function resetRunningAdjust() {
    runEditAdjustMin = 0
    _updatingRunEditStartFromAdjust = true
    runEditStartField.text = runEditStart
    _updatingRunEditStartFromAdjust = false
  }

  function saveRunningEdits() {
    var origStart = String((clockify.running && clockify.running.startLocal) || "")
    var explicitStart = (runEditStartManual && runEditStart !== origStart) ? runEditStart : ""
    clockify.updateRunning(
      runEditDescField.text,
      runEditProjectId,
      runEditTaskId,
      runEditTagIds,
      runEditBillable,
      runEditAdjustMin,
      explicitStart
    )
    editRunningOpen = false
  }

  function openEntryEditor(entry) {
    if (!entry) return
    editingEntryId = String(entry.id || "")
    entryEditDesc = String(entry.description || "")
    entryEditProjectId = String(entry.projectId || "")
    entryEditTaskId = String(entry.taskId || "")
    entryEditTagIds = Model.toArray(entry.tagIds)
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

  function commitSettingsKey() {
    var key = settingsKeyField.text
    if (String(key).trim() === "") return
    settingsKeyField.text = ""
    settingsKeyField.focus = false
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
      confirmManageActionKey = ""
      clockify.clearPendingExportOverwrite()
      historyDayLimit = 14
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
      clockify.refreshIfStale(false, 1800000)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      editRunningOpen = false
      editingEntryId = ""
      confirmDiscard = false
      confirmDeleteId = ""
      confirmManageActionKey = ""
      clockify.clearPendingExportOverwrite()
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
    function onDefaultTaskIdChanged() { root.syncDraftDefaults() }
    function onDefaultTagIdsChanged() { root.syncDraftDefaults() }
    function onDefaultBillableChanged() { root.syncDraftDefaults() }
    function onProjectsChanged() { root.syncDraftDefaults() }
    function onRunningChanged() {
      if (!clockify.timing) {
        root.editRunningOpen = false
        root.confirmDiscard = false
      } else if (!root.editRunningOpen && clockify.running) {
        var rTags = Model.toArray(clockify.running.tagIds)
        if (rTags.length > 0 && Model.toArray(root.draftTagIds).length === 0) {
          root.draftTagIds = rTags
          if (tagsMulti) tagsMulti.values = rTags.slice()
        }
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
    function setTab(tab: string): string {
      var next = String(tab || "").trim()
      if (next !== "tracker" && next !== "history" && next !== "manage" && next !== "settings") {
        return "invalid tab"
      }
      root.activeTab = next
      return "ok"
    }
    function refresh(): string { clockify.refresh(true); return "ok" }
    function startTimer(description: string, projectId: string): string {
      clockify.start(description, projectId, "", clockify.defaultTagIds, clockify.defaultBillable)
      return "ok"
    }
    function stopTimer(): string { clockify.stop(); return "ok" }
    function toggleTimer(): string { root.toggleTimer(); return "ok" }
    function discardTimer(): string { clockify.discard(); return "ok" }
    function status(): string {
      if (!clockify.configured) return clockify.desktopSessionExpired ? "desktop session expired" : "not configured"
      if (!clockify.timing) return "idle, today " + Model.formatDuration(root.todaySeconds)
      return Model.describeEntry(clockify.running) + " " + Model.formatClock(root.elapsedSeconds)
    }
    function debug(): string {
      var window = root.QsWindow ? root.QsWindow.window : null
      return JSON.stringify({
        screen: window && window.screen ? String(window.screen.name) : "unknown",
        configured: clockify.configured,
        desktopSessionExpired: clockify.desktopSessionExpired,
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
    contentWidth: panel.fittedContentWidth(Style.space(clockify.panelWidth))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(clockify.panelHeight))

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
              : (clockify.configured ? "Today " + Model.formatDurationByMode(root.todaySeconds, clockify.durationFormat) + "  ·  Week " + Model.formatDurationByMode(root.weekSeconds, clockify.durationFormat) : (clockify.desktopSessionExpired ? "Desktop session expired  ·  Open Clockify or add API key" : "Not connected"))
            detail: clockify.pomodoroRunning
              ? (clockify.pomodoroPhase === "work" ? "Focus " : "Break ") + Model.formatClock(clockify.pomodoroSecondsLeft)
              : (clockify.timing ? "Today " + Model.formatDurationByMode(root.todaySeconds, clockify.durationFormat) : "")
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
              visible: Model.tagsLabel(clockify.running, clockify.tags) !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: "Tags: " + Model.tagsLabel(clockify.running, clockify.tags)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: root.textWrapMode
              elide: root.textElideMode
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
                text: root.editRunningOpen ? "Close" : "Edit Live"
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
                text: "Split"
                iconText: "󰤘"
                bordered: true
                enabled: !clockify.actionBusy
                tooltipText: "Split running timer now into a continued entry"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.splitRunning(0, "")
              }

              Button {
                text: root.confirmDiscard ? "Confirm" : "Discard"
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

              PanelActionButton {
                visible: clockify.pomodoroRunning
                iconText: "󰒭"
                tooltipText: "Skip Pomodoro phase"
                foreground: root.accent
                fontFamily: root.fontFamily
                onClicked: clockify.skipPomodoroPhase()
              }
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
                  options: root.tagOptionList
                  values: root.runEditTagIds
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(vals) {
                    var clean = Model.toArray(vals)
                    root.runEditTagIds = clean
                    root.draftTagIds = clean
                    if (tagsMulti) tagsMulti.values = clean.slice()
                    clockify.saveConfig({ tags: clean })
                  }
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    textFormat: Text.PlainText
                    text: "Start:"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  TimeSpinField {
                    id: runEditStartField
                    Layout.preferredWidth: Style.space(98)
                    stepMinutes: clockify.timeStepMinutes
                    placeholderText: "HH:MM"
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    onTextChanged: {
                      if (!root._updatingRunEditStartFromAdjust && root.editRunningOpen) {
                        root.runEditStart = text
                        root.runEditStartManual = true
                        root.runEditAdjustMin = 0
                      }
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Elapsed:"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Button {
                    visible: root.liveSecondaryStepMin !== root.livePrimaryStepMin
                    text: "-" + root.liveSecondaryStepMin + "m"
                    bordered: true
                    tooltipText: "Subtract " + root.liveSecondaryStepMin + " min from elapsed session (shifts start later)"
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.adjustRunningMinutes(-root.liveSecondaryStepMin)
                  }

                  Button {
                    text: "-" + root.livePrimaryStepMin + "m"
                    bordered: true
                    tooltipText: "Subtract " + root.livePrimaryStepMin + " min from elapsed session (shifts start later)"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.adjustRunningMinutes(-root.livePrimaryStepMin)
                  }

                  Button {
                    text: "+" + root.livePrimaryStepMin + "m"
                    bordered: true
                    tooltipText: "Add " + root.livePrimaryStepMin + " min to elapsed session (shifts start earlier)"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.adjustRunningMinutes(root.livePrimaryStepMin)
                  }

                  Button {
                    visible: root.liveSecondaryStepMin !== root.livePrimaryStepMin
                    text: "+" + root.liveSecondaryStepMin + "m"
                    bordered: true
                    tooltipText: "Add " + root.liveSecondaryStepMin + " min to elapsed session (shifts start earlier)"
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.adjustRunningMinutes(root.liveSecondaryStepMin)
                  }

                  Button {
                    visible: root.runEditAdjustMin !== 0
                    text: (root.runEditAdjustMin > 0 ? "+" : "") + root.runEditAdjustMin + "m ✕"
                    bordered: true
                    tooltipText: "Elapsed duration offset (click to reset to 0m)"
                    foreground: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.resetRunningAdjust()
                  }

                  Item { Layout.fillWidth: true }
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)

                  Button {
                    text: "Billable"
                    iconText: "󰄬"
                    bordered: true
                    selected: root.runEditBillable
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.runEditBillable = !root.runEditBillable
                  }

                  Button {
                    text: "Stop -" + clockify.timeStepMinutes + "m"
                    iconText: "󰓛"
                    bordered: true
                    enabled: !clockify.actionBusy
                    tooltipText: "Stop timer " + clockify.timeStepMinutes + " minutes ago"
                    foreground: root.urgent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: {
                      root.editRunningOpen = false
                      clockify.stopAt(clockify.timeStepMinutes, "")
                    }
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

          // Pending Offline / Rate-Limited Queue Banner
          Rectangle {
            visible: clockify.configured && clockify.pendingCount > 0
            width: parent.width
            implicitHeight: pendingSyncRow.implicitHeight + Style.space(10)
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)

            RowLayout {
              id: pendingSyncRow
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(6)

              Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: "󰅠  " + clockify.pendingCount + (clockify.pendingCount === 1 ? " change saved locally" : " changes saved locally") + " — will auto-sync when quota resets"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Button {
                text: "Sync Now"
                iconText: "󰑐"
                bordered: true
                enabled: !clockify.actionBusy && !clockify.refreshing
                foreground: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: clockify.syncPending()
              }
            }
          }

          // ---------------------------------------------------------- login (when unconfigured)
          Column {
            visible: !clockify.configured
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: clockify.desktopSessionExpired ? "DESKTOP SESSION EXPIRED" : "CONNECT CLOCKIFY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: clockify.desktopSessionExpired
                ? "Clockify Desktop's 60-minute access token expired while it ran in the background (it only refreshes when its window is opened). Paste a Personal API Key below for always-on background sync and full edit access, or open Clockify Desktop to refresh read-only mode."
                : "Recommended: paste a Personal API Key (Clockify → Preferences → Advanced → API) for always-on background sync (no need to open Clockify Desktop) and full start/stop/edit control. The Clockify Desktop session is read-only and expires after 60 min in the background."
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
                foreground: root.accent
                fontFamily: root.fontFamily
                onClicked: root.commitKey()
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                visible: !clockify.desktopSessionExpired
                text: "Desktop Session (Read-Only)"
                iconText: "󰌆"
                bordered: true
                enabled: !clockify.actionBusy
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.connectDesktop()
              }

              Button {
                text: "Get API Key"
                iconText: "󰖟"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.openApiKeyPage()
              }

              Button {
                text: "Open Clockify App"
                iconText: "󰀻"
                bordered: true
                foreground: clockify.desktopSessionExpired ? root.accent : root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.launchDesktopApp()
              }

              Button {
                visible: clockify.desktopSessionExpired
                text: "Retry"
                iconText: "󰑐"
                bordered: true
                enabled: !clockify.actionBusy && !clockify.refreshing
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.refresh(true)
              }

              Button {
                visible: clockify.desktopSessionExpired
                text: "Disconnect"
                iconText: "󰌆"
                bordered: true
                foreground: root.urgent
                fontFamily: root.fontFamily
                onClicked: clockify.clearKey()
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
              if (val === "history") {
                clockify.refreshIfStale(false, 1800000)
              } else if (val === "manage") {
                clockify.refreshIfStale(true, 1800000)
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
                  { value: "manual", label: "Manual Entry", icon: "󰃭" },
                  { value: "timesheet", label: "Timesheet", icon: "󰕮" }
                ]
                onChanged: function(val) { root.trackerMode = val }
              }

              Item { Layout.fillWidth: true }
            }

            // Timer & Manual Entry form
            Column {
              visible: root.trackerMode !== "timesheet"
              width: parent.width
              spacing: Style.space(8)

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
                options: root.tagOptionList
                values: root.draftTagIds
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(vals) {
                  var clean = Model.toArray(vals)
                  root.draftTagIds = clean
                  clockify.saveConfig({ tags: clean })
                  if (
                    clockify.timing &&
                    clockify.running &&
                    root.trackerMode === "timer" &&
                    root.draftDescription === "" &&
                    String(clockify.running.projectId || "") === root.draftProjectId &&
                    String(clockify.running.taskId || "") === root.draftTaskId
                  ) {
                    root.runEditTagIds = clean
                    if (runEditTagsMulti) runEditTagsMulti.values = clean.slice()
                    clockify.updateRunning(
                      String(clockify.running.description || ""),
                      String(clockify.running.projectId || ""),
                      String(clockify.running.taskId || ""),
                      clean,
                      clockify.running.billable === true,
                      0,
                      ""
                    )
                  }
                }
              }

              // Manual Date & Time Inputs with Up/Down Steppers & Round
              RowLayout {
                visible: root.trackerMode === "manual"
                width: parent.width
                spacing: Style.space(5)

                DateSpinField {
                  id: manualDateField
                  Layout.fillWidth: true
                  text: root.manualDate
                  placeholderText: "today / YYYY-MM-DD"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onTextChanged: root.manualDate = text
                }

                TimeSpinField {
                  id: manualStartField
                  Layout.preferredWidth: Style.space(98)
                  stepMinutes: clockify.timeStepMinutes
                  text: root.manualStart
                  placeholderText: "09:00"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onTextChanged: root.manualStart = text
                }

                Text {
                  textFormat: Text.PlainText
                  text: "→"
                  color: root.dim
                  font.family: root.fontFamily
                }

                TimeSpinField {
                  id: manualEndField
                  Layout.preferredWidth: Style.space(98)
                  stepMinutes: clockify.timeStepMinutes
                  text: root.manualEnd
                  placeholderText: "10:30"
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onTextChanged: root.manualEnd = text
                }

                PanelActionButton {
                  iconText: "󰑎"
                  tooltipText: "Round start/end to nearest " + clockify.timeStepMinutes + " min"
                  foreground: root.accent
                  fontFamily: root.fontFamily
                  onClicked: {
                    manualStartField.text = Model.roundTimeHhMm(manualStartField.text, clockify.timeStepMinutes, clock.date)
                    manualEndField.text = Model.roundTimeHhMm(manualEndField.text, clockify.timeStepMinutes, clock.date)
                  }
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
            }

            // Weekly Timesheet Grid (Tracker -> Timesheet mode)
            Column {
              visible: root.trackerMode === "timesheet"
              width: parent.width
              spacing: Style.space(6)

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                PanelActionButton {
                  iconText: "󰅁"
                  tooltipText: "Previous week"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: {
                    root.timesheetOffset -= 1
                    var b = root.weeklyTimesheet.bounds
                    if (b.startIso && clockify.loadedStartDate && b.startIso < clockify.loadedStartDate) {
                      clockify.fetchRange(b.startIso, b.endIso)
                    }
                  }
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: root.weeklyTimesheet.bounds.title + " · " + root.weeklyTimesheet.bounds.subtitle
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  wrapMode: root.textWrapMode
                  elide: root.textElideMode
                }

                Button {
                  visible: root.timesheetOffset !== 0
                  text: "This Week"
                  bordered: true
                  foreground: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.timesheetOffset = 0
                }

                PanelActionButton {
                  iconText: "󰅂"
                  tooltipText: "Next week"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: root.timesheetOffset < 0
                  onClicked: root.timesheetOffset += 1
                }

                Text {
                  textFormat: Text.PlainText
                  text: Model.formatDurationByMode(root.weeklyTimesheet.grandTotalSeconds, clockify.durationFormat)
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              // Day Column Headers
              RowLayout {
                width: parent.width
                spacing: Style.space(3)

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: "PROJECT"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Math.max(8, Style.font.caption - 1)
                  font.bold: true
                }

                Repeater {
                  model: root.weeklyTimesheet.days
                  delegate: Text {
                    required property var modelData
                    Layout.preferredWidth: Style.space(34)
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: modelData.shortLabel
                    color: modelData.isToday ? root.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(8, Style.font.caption - 1)
                    font.bold: modelData.isToday
                  }
                }

                Text {
                  Layout.preferredWidth: Style.space(42)
                  horizontalAlignment: Text.AlignRight
                  textFormat: Text.PlainText
                  text: "SUM"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Math.max(8, Style.font.caption - 1)
                  font.bold: true
                }
              }

              // Timesheet Rows
              Repeater {
                model: root.weeklyTimesheet.rows
                delegate: BorderSurface {
                  id: tsRow
                  required property var modelData
                  width: parent.width
                  implicitHeight: tsRowLayout.implicitHeight + Style.space(6)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
                  borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                  RowLayout {
                    id: tsRowLayout
                    anchors.fill: parent
                    anchors.margins: Style.space(3)
                    spacing: Style.space(3)

                    Rectangle {
                      width: Style.space(6)
                      height: Style.space(6)
                      radius: width / 2
                      color: tsRow.modelData.projectColor || root.dim
                    }

                    Text {
                      Layout.fillWidth: true
                      textFormat: Text.PlainText
                      text: Model.neutralizeMarkup(tsRow.modelData.projectName + (tsRow.modelData.taskName ? " / " + tsRow.modelData.taskName : ""))
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(9, Style.font.caption)
                      wrapMode: root.textWrapMode
                      elide: root.textElideMode
                    }

                    Repeater {
                      model: root.weeklyTimesheet.days
                      delegate: BorderSurface {
                        id: tsCell
                        required property var modelData
                        required property int index
                        readonly property int cellSec: tsRow.modelData.daySeconds[index] || 0
                        Layout.preferredWidth: Style.space(34)
                        implicitHeight: Style.space(22)
                        radius: 4
                        color: tsCellMouse.containsMouse
                          ? Style.hoverFillFor(root.accent, root.accent)
                          : (cellSec > 0 ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04))
                        borderSpec: tsCell.modelData.isToday ? Border.controlSpec("focus", root.foreground, root.accent) : Border.none()

                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          text: tsCell.cellSec > 0 ? Model.formatCompactDuration(tsCell.cellSec) : "+"
                          color: tsCell.cellSec > 0 ? root.foreground : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Math.max(8, Style.font.caption - 1)
                          font.bold: tsCell.cellSec > 0
                        }

                        MouseArea {
                          id: tsCellMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.openTimesheetCellLog(tsRow.modelData, tsCell.modelData)
                        }

                        PanelToolTip {
                          visible: tsCellMouse.containsMouse
                          text: Model.neutralizeMarkup(tsRow.modelData.projectName + " · " + tsCell.modelData.shortLabel + " " + tsCell.modelData.dayNum + " (click to log)")
                          fontFamily: root.fontFamily
                        }
                      }
                    }

                    Text {
                      Layout.preferredWidth: Style.space(42)
                      horizontalAlignment: Text.AlignRight
                      textFormat: Text.PlainText
                      text: tsRow.modelData.totalSeconds > 0 ? Model.formatCompactDuration(tsRow.modelData.totalSeconds) : "0m"
                      color: tsRow.modelData.totalSeconds > 0 ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(9, Style.font.caption)
                      font.bold: tsRow.modelData.totalSeconds > 0
                    }
                  }
                }
              }

              // Per-Day Totals Footer Row
              RowLayout {
                width: parent.width
                spacing: Style.space(3)

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: "DAILY TOTAL"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Math.max(8, Style.font.caption - 1)
                  font.bold: true
                }

                Repeater {
                  model: root.weeklyTimesheet.days
                  delegate: Text {
                    required property var modelData
                    Layout.preferredWidth: Style.space(34)
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    text: modelData.totalSeconds > 0 ? Model.formatCompactDuration(modelData.totalSeconds) : "—"
                    color: modelData.isToday ? root.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Math.max(8, Style.font.caption - 1)
                    font.bold: modelData.totalSeconds > 0
                  }
                }

                Item { Layout.preferredWidth: Style.space(42) }
              }
            }

            PanelSeparator {
              foreground: root.foreground
            }

            // Summary totals with optional daily/weekly target progress bars
            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              Total {
                label: "TODAY"
                value: Model.formatDurationByMode(root.todaySeconds, clockify.durationFormat)
                sub: root.todayBillableSeconds > 0 ? (Model.formatDurationByMode(root.todayBillableSeconds, clockify.durationFormat) + " billable") : ""
                valueSeconds: root.todaySeconds
                targetSeconds: clockify.dailyTargetHours > 0 ? clockify.dailyTargetHours * 3600 : 0
                Layout.fillWidth: true
                Layout.preferredWidth: 0
              }

              Total {
                label: clockify.weekStart === "sunday" ? "THIS WEEK (SUN)" : "THIS WEEK"
                value: Model.formatDurationByMode(root.weekSeconds, clockify.durationFormat)
                sub: root.weekBillableSeconds > 0 ? (Model.formatDurationByMode(root.weekBillableSeconds, clockify.durationFormat) + " billable") : ""
                valueSeconds: root.weekSeconds
                targetSeconds: clockify.weeklyTargetHours > 0 ? clockify.weeklyTargetHours * 3600 : 0
                Layout.fillWidth: true
                Layout.preferredWidth: 0
              }

              Total {
                label: "THIS MONTH"
                value: Model.formatDurationByMode(root.monthSeconds, clockify.durationFormat)
                sub: root.monthBillableSeconds > 0 ? (Model.formatDurationByMode(root.monthBillableSeconds, clockify.durationFormat) + " billable") : ""
                Layout.fillWidth: true
                Layout.preferredWidth: 0
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
                root.historyDayLimit = 14
                root.expandedGroupKey = ""
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
                  wrapMode: root.textWrapMode
                  elide: root.textElideMode
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.periodBounds.subtitle
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: root.textWrapMode
                  elide: root.textElideMode
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
                  root.historyQuery,
                  false
                )
              }
            }

            // Export overwrite confirmation banner
            Rectangle {
              visible: clockify.pendingExportOverwritePath !== ""
              width: parent.width
              implicitHeight: exportConfirmRow.implicitHeight + Style.space(12)
              radius: Style.radius("sm")
              color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12)
              border.width: 1
              border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.45)

              RowLayout {
                id: exportConfirmRow
                anchors.fill: parent
                anchors.margins: Style.space(6)
                spacing: Style.space(6)

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: "Replace existing " + (clockify.pendingExportOverwritePath.split("/").pop() || "report.csv") + "?"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }

                Button {
                  text: "Cancel"
                  bordered: true
                  foreground: root.dim
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: {
                    clockify.clearPendingExportOverwrite()
                    clockify.lastError = ""
                  }
                }

                Button {
                  text: "Replace"
                  bordered: true
                  foreground: root.urgent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  enabled: !clockify.actionBusy
                  onClicked: clockify.confirmPendingExportOverwrite()
                }
              }
            }

            // Custom Date Range Picker
            RowLayout {
              visible: root.periodMode === "custom"
              width: parent.width
              spacing: Style.space(6)

              DateSpinField {
                id: customFromField
                Layout.fillWidth: true
                text: root.customFrom
                placeholderText: "From YYYY-MM-DD"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onTextChanged: root.customFrom = text
              }

              Text {
                textFormat: Text.PlainText
                text: "→"
                color: root.dim
                font.family: root.fontFamily
              }

              DateSpinField {
                id: customToField
                Layout.fillWidth: true
                text: root.customTo
                placeholderText: "To YYYY-MM-DD"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onTextChanged: root.customTo = text
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

            // Search, Group & Multi-Filter Controls
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
                text: "Group"
                iconText: "󰒺"
                bordered: true
                selected: clockify.groupSimilarEntries
                tooltipText: "Group identical same-day entries"
                foreground: clockify.groupSimilarEntries ? root.accent : root.dim
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: {
                  clockify.groupSimilarEntries = !clockify.groupSimilarEntries
                  root.expandedGroupKey = ""
                  clockify.saveConfig({ groupSimilarEntries: clockify.groupSimilarEntries })
                }
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
                value: Model.formatDurationByMode(root.dashboardData.totalSeconds, clockify.durationFormat)
                sub: Model.formatClock(root.dashboardData.totalSeconds)
                highlight: root.accent
              }

              KpiCard {
                Layout.fillWidth: true
                label: "BILLABLE"
                value: Model.formatDurationByMode(root.dashboardData.billableSeconds, clockify.durationFormat)
                sub: root.dashboardData.billablePercent + "% of total"
                highlight: root.foreground
              }

              KpiCard {
                Layout.fillWidth: true
                label: "DAILY AVG"
                value: Model.formatDurationByMode(root.dashboardData.dailyAvgSeconds, clockify.durationFormat)
                sub: root.dashboardData.activeDays + "d · " + root.dashboardData.entryCount + " items"
                highlight: root.foreground
              }

              KpiCard {
                Layout.fillWidth: true
                label: "TOP PROJECT"
                value: root.dashboardData.topProject ? root.dashboardData.topProject.name : "—"
                sub: root.dashboardData.topProject ? (Model.formatDurationByMode(root.dashboardData.topProject.seconds, clockify.durationFormat) + " (" + root.dashboardData.topProject.percent + "%)") : "No entries"
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
                          wrapMode: root.textWrapMode
                          elide: root.textElideMode
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
                          text: Model.formatDurationByMode(modelData.seconds, clockify.durationFormat) + " (" + modelData.percent + "%)"
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

            // Date-Grouped Detailed Time Entries (paginated + optional similar-entry grouping)
            Repeater {
              model: root.dashboardData.groupedByDate.slice(0, root.historyDayLimit)

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
                    text: Model.formatDurationByMode(modelData.totalSeconds, clockify.durationFormat)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Repeater {
                  model: clockify.groupSimilarEntries ? dayGroup.modelData.groupedEntries : dayGroup.modelData.entries

                  delegate: BorderSurface {
                    id: entryRow
                    required property var modelData
                    readonly property int groupCount: modelData.count ? Number(modelData.count) : 1
                    readonly property bool isGroupRow: groupCount > 1
                    readonly property var targetEntry: modelData.latestEntry ? modelData.latestEntry : modelData
                    readonly property int rowSeconds: modelData.totalSeconds !== undefined ? Number(modelData.totalSeconds) : Number(modelData.seconds || 0)
                    readonly property string fullGroupKey: dayGroup.modelData.dateIso + "|" + String(modelData.groupKey || "")
                    readonly property bool isExpandedGroup: isGroupRow && root.expandedGroupKey === fullGroupKey
                    readonly property bool isEditing: !isGroupRow && root.editingEntryId === String(targetEntry.id || "")

                    width: parent.width
                    implicitHeight: entryCol.implicitHeight + Style.space(14)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, (isEditing || isExpandedGroup) ? 0.06 : 0.03)
                    borderSpec: Border.controlSpec((isEditing || isExpandedGroup) ? "focus" : "normal", root.foreground, root.accent)

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

                        BorderSurface {
                          visible: entryRow.isGroupRow
                          implicitWidth: grpBadgeTxt.implicitWidth + Style.space(8)
                          implicitHeight: grpBadgeTxt.implicitHeight + Style.space(2)
                          radius: 4
                          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                          borderSpec: Border.controlSpec("normal", root.accent, root.accent)

                          Text {
                            id: grpBadgeTxt
                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: entryRow.groupCount + "×"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Math.max(8, Style.font.caption - 1)
                            font.bold: true
                          }
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
                            wrapMode: root.textWrapMode
                            elide: root.textElideMode
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
                            wrapMode: root.textWrapMode
                            elide: root.textElideMode
                          }
                        }

                        Text {
                          textFormat: Text.PlainText
                          text: clockify.durationFormat === "compact" ? Model.formatClock(entryRow.rowSeconds) : Model.formatDurationByMode(entryRow.rowSeconds, clockify.durationFormat)
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
                          onClicked: clockify.continueEntry(entryRow.targetEntry.id)
                        }

                        PanelActionButton {
                          visible: entryRow.isGroupRow
                          iconText: entryRow.isExpandedGroup ? "󰅃" : "󰅀"
                          tooltipText: entryRow.isExpandedGroup ? "Collapse group" : "Expand " + entryRow.groupCount + " entries"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          onClicked: root.expandedGroupKey = entryRow.isExpandedGroup ? "" : entryRow.fullGroupKey
                        }

                        PanelActionButton {
                          visible: !entryRow.isGroupRow
                          iconText: "󰏫"
                          tooltipText: entryRow.isEditing ? "Close editor" : "Edit entry"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          enabled: !clockify.actionBusy && !entryRow.targetEntry.isLocked
                          onClicked: {
                            if (entryRow.isEditing) root.editingEntryId = ""
                            else root.openEntryEditor(entryRow.targetEntry)
                          }
                        }

                        PanelActionButton {
                          visible: !entryRow.isGroupRow
                          iconText: "󰆏"
                          tooltipText: "Duplicate entry"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          enabled: !clockify.actionBusy
                          onClicked: clockify.duplicateEntry(entryRow.targetEntry.id)
                        }

                        PanelActionButton {
                          visible: !entryRow.isGroupRow
                          iconText: root.confirmDeleteId === String(entryRow.targetEntry.id) ? "󰄬" : "󰆴"
                          tooltipText: root.confirmDeleteId === String(entryRow.targetEntry.id) ? "Click again to confirm delete" : "Delete entry"
                          foreground: root.confirmDeleteId === String(entryRow.targetEntry.id) ? root.urgent : root.dim
                          hoverColor: root.urgent
                          fontFamily: root.fontFamily
                          enabled: !clockify.actionBusy && !entryRow.targetEntry.isLocked
                          onClicked: {
                            var eid = String(entryRow.targetEntry.id)
                            if (root.confirmDeleteId !== eid) {
                              root.confirmDeleteId = eid
                            } else {
                              root.confirmDeleteId = ""
                              clockify.deleteEntry(eid)
                            }
                          }
                        }
                      }

                      // Expanded individual entries inside a grouped card
                      Column {
                        visible: entryRow.isExpandedGroup
                        width: parent.width
                        spacing: Style.space(5)

                        Repeater {
                          model: entryRow.isExpandedGroup ? (entryRow.modelData.entries || []) : []
                          delegate: BorderSurface {
                            id: childRow
                            required property var modelData
                            readonly property bool childEditing: root.editingEntryId === String(childRow.modelData.id || "")
                            width: parent.width
                            implicitHeight: childCol.implicitHeight + Style.space(10)
                            radius: Style.cornerRadius
                            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                            borderSpec: Border.controlSpec(childEditing ? "focus" : "normal", root.foreground, root.accent)

                            Column {
                              id: childCol
                              anchors.fill: parent
                              anchors.margins: Style.space(5)
                              spacing: Style.space(5)

                              RowLayout {
                                width: parent.width
                                spacing: Style.space(6)

                                Text {
                                  Layout.fillWidth: true
                                  textFormat: Text.PlainText
                                  text: (childRow.modelData.startLocal && childRow.modelData.endLocal)
                                    ? (childRow.modelData.startLocal + "–" + childRow.modelData.endLocal)
                                    : Model.describeEntry(childRow.modelData)
                                  color: root.dim
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                  wrapMode: root.textWrapMode
                                  elide: root.textElideMode
                                }

                                Text {
                                  textFormat: Text.PlainText
                                  text: clockify.durationFormat === "compact" ? Model.formatClock(childRow.modelData.seconds) : Model.formatDurationByMode(childRow.modelData.seconds, clockify.durationFormat)
                                  color: root.foreground
                                  font.family: root.fontFamily
                                  font.pixelSize: Style.font.caption
                                  font.bold: true
                                }

                                PanelActionButton {
                                  iconText: "󰏫"
                                  tooltipText: childRow.childEditing ? "Close editor" : "Edit entry"
                                  foreground: root.foreground
                                  fontFamily: root.fontFamily
                                  enabled: !clockify.actionBusy && !childRow.modelData.isLocked
                                  onClicked: {
                                    if (childRow.childEditing) root.editingEntryId = ""
                                    else root.openEntryEditor(childRow.modelData)
                                  }
                                }

                                PanelActionButton {
                                  iconText: "󰆏"
                                  tooltipText: "Duplicate entry"
                                  foreground: root.foreground
                                  fontFamily: root.fontFamily
                                  enabled: !clockify.actionBusy
                                  onClicked: clockify.duplicateEntry(childRow.modelData.id)
                                }

                                PanelActionButton {
                                  iconText: root.confirmDeleteId === String(childRow.modelData.id) ? "󰄬" : "󰆴"
                                  tooltipText: root.confirmDeleteId === String(childRow.modelData.id) ? "Click again to confirm delete" : "Delete entry"
                                  foreground: root.confirmDeleteId === String(childRow.modelData.id) ? root.urgent : root.dim
                                  hoverColor: root.urgent
                                  fontFamily: root.fontFamily
                                  enabled: !clockify.actionBusy && !childRow.modelData.isLocked
                                  onClicked: {
                                    var ceid = String(childRow.modelData.id)
                                    if (root.confirmDeleteId !== ceid) {
                                      root.confirmDeleteId = ceid
                                    } else {
                                      root.confirmDeleteId = ""
                                      clockify.deleteEntry(ceid)
                                    }
                                  }
                                }
                              }

                              Loader {
                                active: childRow.childEditing
                                visible: active
                                width: parent.width
                                sourceComponent: active ? entryEditorComponent : null
                              }
                            }
                          }
                        }
                      }

                      // Lazy-instantiated inline past-entry editor (0 overhead when closed)
                      Loader {
                        active: entryRow.isEditing
                        visible: active
                        width: parent.width
                        sourceComponent: active ? entryEditorComponent : null
                      }
                    }
                  }
                }
              }
            }

            Button {
              visible: root.dashboardData.groupedByDate.length > root.historyDayLimit
              width: parent.width
              text: "Show More Days (" + (root.dashboardData.groupedByDate.length - root.historyDayLimit) + " remaining)"
              iconText: "󰅀"
              bordered: true
              foreground: root.accent
              fontFamily: root.fontFamily
              onClicked: root.historyDayLimit += 14
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
              onChanged: function(val) {
                root.manageTab = val
                root.confirmManageActionKey = ""
              }
            }

            TextField {
              id: manageSearchField
              width: parent.width
              placeholderText: "Filter " + root.manageTab + "s…"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.manageSearch = text
              Keys.onEscapePressed: focus = false
            }

            // --- Create & Manage Projects ---
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
                  visible: root.manageMatches(modelData.name, modelData.clientName)
                  width: parent.width
                  spacing: Style.space(6)
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
                    wrapMode: root.textWrapMode
                    elide: root.textElideMode
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: (Array.isArray(modelData.tasks) ? modelData.tasks.length : 0) + "t"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  PanelActionButton {
                    iconText: "󰐊"
                    tooltipText: "Start timer on this project"
                    foreground: root.accent
                    fontFamily: root.fontFamily
                    enabled: !clockify.actionBusy
                    onClicked: {
                      root.draftProjectId = modelData.id
                      root.draftTaskId = ""
                      clockify.start("", modelData.id, "", root.draftTagIds, modelData.billable)
                    }
                  }
                  PanelActionButton {
                    iconText: clockify.defaultProjectId === modelData.id ? "󰓎" : "󰓒"
                    tooltipText: "Set as default project"
                    foreground: clockify.defaultProjectId === modelData.id ? root.accent : root.dim
                    fontFamily: root.fontFamily
                    onClicked: {
                      root.draftProjectId = modelData.id
                      root.draftTaskId = ""
                      clockify.rememberProject(modelData.id)
                    }
                  }
                  PanelActionButton {
                    property string archKey: "arch_proj_" + modelData.id
                    iconText: root.confirmManageActionKey === archKey ? "󰄬" : "󰀼"
                    tooltipText: root.confirmManageActionKey === archKey ? "Click again to archive project" : "Archive project"
                    foreground: root.confirmManageActionKey === archKey ? root.accent : root.dim
                    fontFamily: root.fontFamily
                    enabled: !clockify.actionBusy
                    onClicked: {
                      if (root.confirmManageActionKey !== archKey) {
                        root.confirmManageActionKey = archKey
                      } else {
                        root.confirmManageActionKey = ""
                        clockify.archiveProject(modelData.id, true)
                      }
                    }
                  }
                  PanelActionButton {
                    property string delKey: "del_proj_" + modelData.id
                    iconText: root.confirmManageActionKey === delKey ? "󰄬" : "󰆴"
                    tooltipText: root.confirmManageActionKey === delKey ? "Click again to delete project" : "Delete project"
                    foreground: root.confirmManageActionKey === delKey ? root.urgent : root.dim
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    enabled: !clockify.actionBusy
                    onClicked: {
                      if (root.confirmManageActionKey !== delKey) {
                        root.confirmManageActionKey = delKey
                      } else {
                        root.confirmManageActionKey = ""
                        clockify.deleteProject(modelData.id)
                      }
                    }
                  }
                }
              }
            }

            // --- Create & Manage Tasks ---
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
                delegate: RowLayout {
                  required property var modelData
                  visible: root.manageMatches(modelData.label, modelData.description)
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: "• " + modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: root.textWrapMode
                    elide: root.textElideMode
                  }

                  PanelActionButton {
                    visible: root.newTaskProjectId !== ""
                    iconText: "󰐊"
                    tooltipText: "Start timer on this task"
                    foreground: root.accent
                    fontFamily: root.fontFamily
                    enabled: !clockify.actionBusy
                    onClicked: clockify.start("", root.newTaskProjectId, modelData.value, root.draftTagIds, root.draftBillable)
                  }

                  PanelActionButton {
                    visible: root.newTaskProjectId !== ""
                    iconText: "󰄬"
                    tooltipText: "Mark task Done"
                    foreground: root.dim
                    hoverColor: root.accent
                    fontFamily: root.fontFamily
                    enabled: !clockify.actionBusy
                    onClicked: clockify.updateTaskStatus(root.newTaskProjectId, modelData.value, "DONE")
                  }

                  PanelActionButton {
                    visible: root.newTaskProjectId !== ""
                    property string delKey: "del_task_" + modelData.value
                    iconText: root.confirmManageActionKey === delKey ? "󰄬" : "󰆴"
                    tooltipText: root.confirmManageActionKey === delKey ? "Click again to delete task" : "Delete task"
                    foreground: root.confirmManageActionKey === delKey ? root.urgent : root.dim
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    enabled: !clockify.actionBusy
                    onClicked: {
                      if (root.confirmManageActionKey !== delKey) {
                        root.confirmManageActionKey = delKey
                      } else {
                        root.confirmManageActionKey = ""
                        clockify.deleteTask(root.newTaskProjectId, modelData.value)
                      }
                    }
                  }
                }
              }
            }

            // --- Create & Manage Tags ---
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
                    property string delKey: "del_tag_" + modelData.id
                    visible: root.manageMatches(modelData.name, "")
                    implicitWidth: tagChipRow.implicitWidth + Style.space(10)
                    implicitHeight: tagChipRow.implicitHeight + Style.space(6)
                    radius: Style.cornerRadius
                    color: root.confirmManageActionKey === delKey ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.14) : "transparent"
                    borderSpec: Border.controlSpec("normal", root.confirmManageActionKey === delKey ? root.urgent : root.foreground, root.accent)

                    RowLayout {
                      id: tagChipRow
                      anchors.centerIn: parent
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        text: modelData.name
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      PanelActionButton {
                        size: Style.space(16)
                        fontSize: Math.max(9, Style.font.caption)
                        iconText: root.confirmManageActionKey === delKey ? "󰄬" : "󰅖"
                        tooltipText: root.confirmManageActionKey === delKey ? "Click again to delete tag" : "Delete tag"
                        foreground: root.confirmManageActionKey === delKey ? root.urgent : root.dim
                        hoverColor: root.urgent
                        fontFamily: root.fontFamily
                        enabled: !clockify.actionBusy
                        onClicked: {
                          if (root.confirmManageActionKey !== delKey) {
                            root.confirmManageActionKey = delKey
                          } else {
                            root.confirmManageActionKey = ""
                            clockify.deleteTag(modelData.id)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // --- Create & Manage Clients ---
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
                delegate: RowLayout {
                  required property var modelData
                  visible: root.manageMatches(modelData.name, "")
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: "• " + modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: root.textWrapMode
                    elide: root.textElideMode
                  }

                  PanelActionButton {
                    property string delKey: "del_client_" + modelData.id
                    iconText: root.confirmManageActionKey === delKey ? "󰄬" : "󰆴"
                    tooltipText: root.confirmManageActionKey === delKey ? "Click again to delete client" : "Delete client"
                    foreground: root.confirmManageActionKey === delKey ? root.urgent : root.dim
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    enabled: !clockify.actionBusy
                    onClicked: {
                      if (root.confirmManageActionKey !== delKey) {
                        root.confirmManageActionKey = delKey
                      } else {
                        root.confirmManageActionKey = ""
                        clockify.deleteClient(modelData.id)
                      }
                    }
                  }
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
                  if (tagsMulti) tagsMulti.values = []
                  clockify.switchWorkspace(val)
                }
              }
            }

            PanelSectionHeader {
              text: "DISPLAY & WINDOW"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ButtonGroup {
              value: clockify.panelWidth + "x" + clockify.panelHeight
              foreground: root.foreground
              background: Color.popups.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              options: [
                { value: "460x640", label: "Compact" },
                { value: "560x740", label: "Default" },
                { value: "680x820", label: "Wide" },
                { value: "800x900", label: "Large" }
              ]
              onChanged: function(val) {
                var parts = String(val).split("x")
                if (parts.length === 2) {
                  var w = parseInt(parts[0], 10)
                  var h = parseInt(parts[1], 10)
                  clockify.panelWidth = w
                  clockify.panelHeight = h
                  clockify.saveConfig({ panelWidth: w, panelHeight: h })
                }
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              NumberField {
                label: "Width (px)"
                value: clockify.panelWidth
                from: 380
                to: 1000
                stepSize: 20
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.panelWidth = val
                  clockify.saveConfig({ panelWidth: val })
                }
              }

              NumberField {
                label: "Max height (px)"
                value: clockify.panelHeight
                from: 420
                to: 1200
                stepSize: 20
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.panelHeight = val
                  clockify.saveConfig({ panelHeight: val })
                }
              }
            }

            Toggle {
              width: parent.width
              label: "Wrap long text lines"
              description: clockify.wrapText
                ? "Wrap long titles, targets, and metadata onto multiple lines"
                : "Keep rows compact on one line with ellipsis"
              checked: clockify.wrapText
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                clockify.wrapText = !clockify.wrapText
                clockify.saveConfig({ wrapText: clockify.wrapText })
              }
            }

            PanelSectionHeader {
              text: "TIME & TRACKER CONTROLS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              NumberField {
                label: "Arrow time step (min)"
                value: clockify.timeStepMinutes
                from: 1
                to: 60
                stepSize: 1
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.timeStepMinutes = val
                  clockify.saveConfig({ timeStepMinutes: val })
                }
              }

              Column {
                Layout.fillWidth: true
                spacing: Style.spacing.md

                Text {
                  textFormat: Text.PlainText
                  text: "Quick step presets"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                ButtonGroup {
                  value: String(clockify.timeStepMinutes)
                  foreground: root.foreground
                  background: Color.popups.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  options: [
                    { value: "1", label: "1m" },
                    { value: "5", label: "5m" },
                    { value: "10", label: "10m" },
                    { value: "15", label: "15m" },
                    { value: "30", label: "30m" }
                  ]
                  onChanged: function(val) {
                    var parsed = parseInt(val, 10)
                    clockify.timeStepMinutes = parsed
                    clockify.saveConfig({ timeStepMinutes: parsed })
                  }
                }
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              NumberField {
                label: "Second adjust step (min)"
                value: clockify.quickStepMinutes
                from: 1
                to: 60
                stepSize: 1
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.quickStepMinutes = val
                  clockify.saveConfig({ quickStepMinutes: val })
                }
              }

              Column {
                Layout.fillWidth: true
                spacing: Style.spacing.md

                Text {
                  textFormat: Text.PlainText
                  text: "Second step presets"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                ButtonGroup {
                  value: String(clockify.quickStepMinutes)
                  foreground: root.foreground
                  background: Color.popups.background
                  accent: root.accent
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  options: [
                    { value: "1", label: "1m" },
                    { value: "5", label: "5m" },
                    { value: "10", label: "10m" },
                    { value: "15", label: "15m" },
                    { value: "30", label: "30m" }
                  ]
                  onChanged: function(val) {
                    var parsed = parseInt(val, 10)
                    clockify.quickStepMinutes = parsed
                    clockify.saveConfig({ quickStepMinutes: parsed })
                  }
                }
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Up/Down arrows & wheel step HH:MM fields by " + clockify.timeStepMinutes + "m (Shift ±1m, Ctrl ±1h). Edit Live buttons nudge elapsed duration by ±" + root.livePrimaryStepMin + "m" + (root.liveSecondaryStepMin !== root.livePrimaryStepMin ? " and ±" + root.liveSecondaryStepMin + "m." : ".")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            ButtonGroup {
              value: clockify.durationFormat
              foreground: root.foreground
              background: Color.popups.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              options: [
                { value: "compact", label: "Compact (1h 30m)" },
                { value: "full", label: "Full (1:30:00)" },
                { value: "decimal", label: "Decimal (1.50h)" }
              ]
              onChanged: function(val) {
                clockify.durationFormat = val
                clockify.saveConfig({ durationFormat: val })
              }
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(10)

              NumberField {
                label: "Daily target (hrs)"
                value: Math.round(clockify.dailyTargetHours)
                from: 0
                to: 24
                stepSize: 1
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.dailyTargetHours = val
                  clockify.saveConfig({ dailyTargetHours: val })
                }
              }

              NumberField {
                label: "Weekly target (hrs)"
                value: Math.round(clockify.weeklyTargetHours)
                from: 0
                to: 168
                stepSize: 2
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onModified: function(val) {
                  clockify.weeklyTargetHours = val
                  clockify.saveConfig({ weeklyTargetHours: val })
                }
              }
            }

            Toggle {
              width: parent.width
              label: "Group similar entries in Dashboard"
              description: "Collapse identical same-day entries with expandable rows"
              checked: clockify.groupSimilarEntries
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                clockify.groupSimilarEntries = !clockify.groupSimilarEntries
                root.expandedGroupKey = ""
                clockify.saveConfig({ groupSimilarEntries: clockify.groupSimilarEntries })
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

              Button {
                visible: clockify.pomodoroRunning
                text: "Skip"
                iconText: "󰒭"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.alignment: Qt.AlignBottom
                onClicked: clockify.skipPomodoroPhase()
              }
            }

            Toggle {
              width: parent.width
              label: "Auto-sync timer with Pomodoro"
              description: "Start your default timer on focus start and stop it on break"
              checked: clockify.pomodoroAutoTimer
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: {
                clockify.pomodoroAutoTimer = !clockify.pomodoroAutoTimer
                clockify.saveConfig({ pomodoroAutoTimer: clockify.pomodoroAutoTimer })
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
              text: "ACCOUNT & API"
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
              text: "Auth source: " + (clockify.authSource === "desktop-app" ? "Clockify Desktop session (read-only, expires after 60m in background)" : (clockify.authSource === "api-key" ? "Personal API Key (always-on, full access)" : clockify.authSource))
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            RowLayout {
              visible: clockify.configured && clockify.authSource === "desktop-app"
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: settingsKeyField
                Layout.fillWidth: true
                password: true
                placeholderText: "Switch to Personal API Key (always-on + full edit)"
                foreground: root.foreground
                font.family: root.fontFamily
                enabled: !clockify.actionBusy
                onAccepted: root.commitSettingsKey()
                Keys.onEscapePressed: focus = false
              }

              Button {
                text: "Get Key"
                iconText: "󰖟"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: clockify.openApiKeyPage()
              }

              Button {
                text: "Use API Key"
                iconText: "󰌆"
                bordered: true
                enabled: !clockify.actionBusy && settingsKeyField.text !== ""
                foreground: root.accent
                fontFamily: root.fontFamily
                onClicked: root.commitSettingsKey()
              }
            }

            Column {
              visible: clockify.configured && clockify.authSource === "api-key"
              width: parent.width
              spacing: Style.space(6)

              RowLayout {
                width: parent.width
                spacing: Style.space(10)

                NumberField {
                  label: "Auto-refresh / hr"
                  value: clockify.refreshRequestsPerHour
                  from: 0
                  to: 60
                  stepSize: 1
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onModified: function(val) {
                    clockify.refreshRequestsPerHour = val
                    clockify.saveConfig({ refreshRequestsPerHour: val })
                  }
                }

                NumberField {
                  label: "Hourly API limit"
                  value: clockify.hourlyRequestLimit
                  from: 0
                  to: 500
                  stepSize: 5
                  foreground: root.foreground
                  accent: root.accent
                  fontFamily: root.fontFamily
                  onModified: function(val) {
                    clockify.hourlyRequestLimit = val
                    clockify.saveConfig({ hourlyRequestLimit: val })
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: (clockify.refreshRequestsPerHour > 0
                  ? (clockify.refreshRequestsPerHour + " req/hr · every " + Math.max(1, Math.round(clockify.refreshIntervalSec / 60)) + " min")
                  : "Manual refresh only")
                  + "  ·  "
                  + (clockify.quotaLimit > 0
                    ? (clockify.quotaRemaining + "/" + clockify.quotaLimit + " requests left (" + clockify.quotaUsed + " used in last hour)"
                      + (clockify.quotaResetSec > 0 ? " · next slot in " + Math.max(1, Math.ceil(clockify.quotaResetSec / 60)) + "m" : ""))
                    : ("Unlimited quota (" + clockify.quotaUsed + " used in last hour)"))
                color: (clockify.quotaLimit > 0 && (clockify.quotaExhausted || clockify.quotaRemaining <= 3)) ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Toggle {
                width: parent.width
                label: "Show API quota counter in footer"
                description: "Display remaining hourly requests (X/30 req) in the panel footer"
                checked: clockify.showQuotaInFooter
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                onClicked: {
                  clockify.showQuotaInFooter = !clockify.showQuotaInFooter
                  clockify.saveConfig({ showQuotaInFooter: clockify.showQuotaInFooter })
                }
              }
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
                visible: clockify.configured
                text: clockify.authSource === "desktop-app" ? "Disconnect Desktop Session" : "Forget API Key"
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
              wrapMode: root.textWrapMode
              elide: root.textElideMode
            }

            Text {
              visible: clockify.authSource === "api-key" && clockify.showQuotaInFooter && clockify.quotaLimit > 0
              textFormat: Text.PlainText
              text: clockify.quotaRemaining + "/" + clockify.quotaLimit + " req"
              color: (clockify.quotaExhausted || clockify.quotaRemaining <= 3)
                ? root.urgent
                : (clockify.quotaRemaining <= 8 ? root.accent : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
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

  Component {
    id: entryEditorComponent

    Column {
      width: parent ? parent.width : Style.space(420)
      spacing: Style.space(6)

      TextField {
        width: parent.width
        text: root.entryEditDesc
        placeholderText: "Description"
        foreground: root.foreground
        font.family: root.fontFamily
        onTextChanged: root.entryEditDesc = text
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
        options: root.tagOptionList
        values: root.entryEditTagIds
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(vals) { root.entryEditTagIds = Model.toArray(vals) }
      }

      RowLayout {
        width: parent.width
        spacing: Style.space(5)

        DateSpinField {
          id: entryDateField
          Layout.fillWidth: true
          text: root.entryEditDate
          placeholderText: "YYYY-MM-DD"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onTextChanged: root.entryEditDate = text
        }

        TimeSpinField {
          id: entryStartField
          Layout.preferredWidth: Style.space(96)
          stepMinutes: clockify.timeStepMinutes
          text: root.entryEditStart
          placeholderText: "HH:MM"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onTextChanged: root.entryEditStart = text
        }

        Text {
          textFormat: Text.PlainText
          text: "→"
          color: root.dim
          font.family: root.fontFamily
        }

        TimeSpinField {
          id: entryEndField
          Layout.preferredWidth: Style.space(96)
          stepMinutes: clockify.timeStepMinutes
          text: root.entryEditEnd
          placeholderText: "HH:MM"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onTextChanged: root.entryEditEnd = text
        }

        PanelActionButton {
          iconText: "󰑎"
          tooltipText: "Round times to nearest " + clockify.timeStepMinutes + " min"
          foreground: root.accent
          fontFamily: root.fontFamily
          onClicked: {
            entryStartField.text = Model.roundTimeHhMm(entryStartField.text, clockify.timeStepMinutes, clock.date)
            entryEndField.text = Model.roundTimeHhMm(entryEndField.text, clockify.timeStepMinutes, clock.date)
          }
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
            var eid = root.editingEntryId
            root.editingEntryId = ""
            clockify.updateEntry(
              eid,
              root.entryEditDesc,
              root.entryEditProjectId,
              root.entryEditTaskId,
              root.entryEditTagIds,
              root.entryEditBillable,
              root.entryEditDate,
              root.entryEditStart,
              root.entryEditEnd
            )
          }
        }
      }
    }
  }

  component TimeSpinField: RowLayout {
    id: tsf
    property alias text: timeInput.text
    property alias placeholderText: timeInput.placeholderText
    property int stepMinutes: 5
    property color foreground: root.foreground
    property color accent: root.accent
    property string fontFamily: root.fontFamily
    readonly property bool inputFocused: timeInput.activeFocus

    spacing: Style.space(2)

    function step(delta) {
      var next = Model.stepTimeHhMm(timeInput.text, delta, clock.date)
      if (timeInput.text !== next) timeInput.text = next
    }

    TextField {
      id: timeInput
      Layout.fillWidth: true
      foreground: tsf.foreground
      accent: tsf.accent
      font.family: tsf.fontFamily
      Keys.onUpPressed: function(event) {
        var mult = (event.modifiers & Qt.ControlModifier) ? 60 : ((event.modifiers & Qt.ShiftModifier) ? 1 : tsf.stepMinutes)
        tsf.step(mult)
        event.accepted = true
      }
      Keys.onDownPressed: function(event) {
        var mult = (event.modifiers & Qt.ControlModifier) ? 60 : ((event.modifiers & Qt.ShiftModifier) ? 1 : tsf.stepMinutes)
        tsf.step(-mult)
        event.accepted = true
      }
      Keys.onEscapePressed: focus = false

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
          var mult = (event.modifiers & Qt.ControlModifier) ? 60 : ((event.modifiers & Qt.ShiftModifier) ? 1 : tsf.stepMinutes)
          tsf.step(event.angleDelta.y >= 0 ? mult : -mult)
        }
      }
    }

    Column {
      Layout.alignment: Qt.AlignVCenter
      spacing: 1

      PanelActionButton {
        size: Style.space(15)
        fontSize: Math.max(8, Style.font.caption - 1)
        bordered: true
        iconText: "󰅃"
        tooltipText: "+" + tsf.stepMinutes + "m (Shift +1m, Ctrl +1h)"
        foreground: tsf.foreground
        fontFamily: tsf.fontFamily
        onClicked: tsf.step(tsf.stepMinutes)
      }

      PanelActionButton {
        size: Style.space(15)
        fontSize: Math.max(8, Style.font.caption - 1)
        bordered: true
        iconText: "󰅀"
        tooltipText: "-" + tsf.stepMinutes + "m (Shift -1m, Ctrl -1h)"
        foreground: tsf.foreground
        fontFamily: tsf.fontFamily
        onClicked: tsf.step(-tsf.stepMinutes)
      }
    }
  }

  component DateSpinField: RowLayout {
    id: dsf
    property alias text: dateInput.text
    property alias placeholderText: dateInput.placeholderText
    property color foreground: root.foreground
    property color accent: root.accent
    property string fontFamily: root.fontFamily
    readonly property bool inputFocused: dateInput.activeFocus

    spacing: Style.space(2)

    function step(deltaDays) {
      var next = Model.stepDateIso(dateInput.text, deltaDays, clock.date)
      if (dateInput.text !== next) dateInput.text = next
    }

    PanelActionButton {
      size: Style.space(20)
      fontSize: Style.font.caption
      bordered: true
      iconText: "󰅁"
      tooltipText: "Previous day"
      foreground: dsf.foreground
      fontFamily: dsf.fontFamily
      onClicked: dsf.step(-1)
    }

    TextField {
      id: dateInput
      Layout.fillWidth: true
      foreground: dsf.foreground
      accent: dsf.accent
      font.family: dsf.fontFamily
      Keys.onUpPressed: function(event) {
        dsf.step(1)
        event.accepted = true
      }
      Keys.onDownPressed: function(event) {
        dsf.step(-1)
        event.accepted = true
      }
      Keys.onEscapePressed: focus = false
    }

    PanelActionButton {
      size: Style.space(20)
      fontSize: Style.font.caption
      bordered: true
      iconText: "󰅂"
      tooltipText: "Next day"
      foreground: dsf.foreground
      fontFamily: dsf.fontFamily
      onClicked: dsf.step(1)
    }
  }

  component Total: Column {
    id: total
    property string label: ""
    property string value: ""
    property string sub: ""
    property int valueSeconds: 0
    property int targetSeconds: 0

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
      width: parent.width
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      wrapMode: root.textWrapMode
      elide: root.textElideMode
    }

    Rectangle {
      visible: total.targetSeconds > 0
      width: parent.width
      height: Style.space(3)
      radius: 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

      Rectangle {
        height: parent.height
        width: Math.min(parent.width, parent.width * (total.valueSeconds / Math.max(1, total.targetSeconds)))
        radius: 2
        color: total.valueSeconds >= total.targetSeconds ? root.accent : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
      }
    }

    Text {
      visible: total.sub !== "" || total.targetSeconds > 0
      textFormat: Text.PlainText
      text: {
        var parts = []
        if (total.sub !== "") parts.push(total.sub)
        if (total.targetSeconds > 0) {
          var pct = Math.round((total.valueSeconds / total.targetSeconds) * 100)
          var hrs = Math.round((total.targetSeconds / 3600) * 10) / 10
          parts.push(pct + "% of " + hrs + "h")
        }
        return parts.join(" · ")
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: root.textWrapMode
      elide: root.textElideMode
      width: parent.width
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
        wrapMode: root.textWrapMode
        elide: root.textElideMode
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: kpi.value
        color: kpi.highlight
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        wrapMode: root.textWrapMode
        elide: root.textElideMode
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: kpi.sub
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 1)
        wrapMode: root.textWrapMode
        elide: root.textElideMode
      }
    }
  }
}
