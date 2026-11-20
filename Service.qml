import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Owns all Clockify state, background polling, Pomodoro/idle timers, and
// communication with clockify.py.
Item {
  id: root

  property var settings: ({})
  property string helperPath: ""
  property bool isPrimaryMonitor: true

  property bool configured: false
  property string authSource: ""
  property string userId: ""
  property string userName: ""
  property string userEmail: ""
  property string workspaceId: ""
  property string workspaceName: ""
  property var workspaces: []
  property var running: null
  property var recentEntries: []
  property int todaySeconds: 0
  property int weekSeconds: 0
  property int monthSeconds: 0
  property int todayBillableSeconds: 0
  property int weekBillableSeconds: 0
  property int monthBillableSeconds: 0
  property string loadedStartDate: ""
  property string loadedEndDate: ""
  property var projects: []
  property var tags: []
  property var clients: []
  property bool fullLoaded: false

  property string defaultProjectId: ""
  property string defaultTaskId: ""
  property var defaultTagIds: []
  property bool defaultBillable: false
  property string weekStart: "monday"
  property int panelWidth: 560
  property int panelHeight: 740
  property bool wrapText: true
  property int timeStepMinutes: 5
  property int quickStepMinutes: 1
  property string durationFormat: "compact"
  property bool groupSimilarEntries: true
  property real dailyTargetHours: 8
  property real weeklyTargetHours: 40

  property bool pomodoroEnabled: false
  property bool pomodoroAutoTimer: true
  property int pomodoroWorkMin: 25
  property int pomodoroBreakMin: 5
  property bool stopOnIdle: false
  property int idleStopMin: 240
  property bool remindWhenIdle: false
  property int idleRemindMin: 30

  // Local Pomodoro session state
  property bool pomodoroRunning: false
  property string pomodoroPhase: "work" // "work" | "break"
  property int pomodoroSecondsLeft: 0

  // Refresh & cache tracking
  property double lastFullRefreshMs: 0
  property double lastRefreshMs: 0
  property bool _bootCachePending: true
  property bool _nextIsCacheOnly: false
  property int _mutationSeq: 0
  property int _accountSeq: 0
  property var _actionQueue: []

  // Idle reminder tracking
  property double lastIdleNoticeMs: 0
  property string lastAutoStoppedId: ""

  property string lastError: ""
  property string note: ""
  property string fetchedAt: ""
  property string pendingExportOverwritePath: ""

  readonly property bool timing: running !== null
  readonly property bool refreshing: statusProcess.running
  readonly property bool actionBusy: actionProcess.running || keyProcess.running
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 45, 15, 3600)
  readonly property bool ready: helperPath !== ""

  signal keyRejected(string message)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var parsed = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(parsed)) parsed = fallback
    return Math.max(min, Math.min(max, parsed))
  }

  function tagCsv(tagIds) {
    return Model.toArray(tagIds).join(",")
  }

  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "Clockify", String(title || "Clockify"), String(body || "")])
  }

  // ------------------------------------------------------------- commands

  function refresh(full) {
    if (!ready || statusProcess.running || actionProcess.running) return
    _nextIsCacheOnly = false
    var command = [helperPath, "status"]
    if (full === true || (!fullLoaded && configured)) command.push("--full")
    lastRefreshMs = Date.now()
    statusProcess.seqAtStart = root._mutationSeq
    statusProcess.accountSeqAtStart = root._accountSeq
    statusProcess.command = pythonCommand(command)
    statusProcess.running = true
  }

  function refreshFromCache() {
    if (!ready || statusProcess.running || actionProcess.running) return
    _nextIsCacheOnly = true
    statusProcess.seqAtStart = root._mutationSeq
    statusProcess.accountSeqAtStart = root._accountSeq
    statusProcess.command = pythonCommand([helperPath, "status", "--from-cache"])
    statusProcess.running = true
  }

  function refreshIfStale(wantFull, fullMaxAgeMs) {
    if (!ready) return
    var nowMs = Date.now()
    if (!fullLoaded && configured) {
      refresh(true)
      return
    }
    var ageFull = nowMs - lastFullRefreshMs
    if (wantFull && ageFull > (fullMaxAgeMs || 300000)) {
      refresh(true)
      return
    }
    if ((nowMs - lastRefreshMs) > 15000) {
      refresh(false)
    }
  }

  function fetchRange(startDateIso, endDateIso) {
    if (!ready) return
    var cmd = [helperPath, "status"]
    if (startDateIso) cmd.push("--start-date", String(startDateIso))
    if (endDateIso) cmd.push("--end-date", String(endDateIso))
    runAction(cmd, true, false, false)
  }

  function clearPendingExportOverwrite() {
    pendingExportOverwritePath = ""
  }

  function exportCsv(startDateIso, endDateIso, projectId, taskId, tagId, billableMode, query, overwrite) {
    if (!ready) return
    pendingExportOverwritePath = ""
    var cmd = [
      helperPath, "export-csv",
      "--start-date", String(startDateIso || ""),
      "--end-date", String(endDateIso || ""),
      "--project", String(projectId || ""),
      "--task", String(taskId || ""),
      "--tag", String(tagId || ""),
      "--billable", String(billableMode || "all"),
      "--query", String(query || "")
    ]
    if (overwrite === true) cmd.push("--overwrite")
    runAction(cmd, true, false, false)
  }

  function start(description, projectId, taskId, tagIds, billable) {
    var cmd = [
      helperPath, "start",
      "--description", String(description || ""),
      "--project", String(projectId === undefined || projectId === null ? "" : projectId),
      "--task", String(taskId === undefined || taskId === null ? "" : taskId),
      "--tags", tagCsv(tagIds),
      billable ? "--billable" : "--no-billable"
    ]
    runAction(cmd, true)
  }

  function stop() {
    stopAt(0, "")
  }

  function stopAt(minutesAgo, atTime) {
    if (!ready || actionProcess.running) return
    var prev = running
    if (!minutesAgo && !atTime) {
      running = null
      note = "Stopping timer…"
    }
    var cmd = [helperPath, "stop"]
    if (minutesAgo && minutesAgo > 0) cmd.push("--minutes-ago", String(minutesAgo))
    if (atTime !== undefined && atTime !== null && String(atTime).trim() !== "") cmd.push("--at", String(atTime).trim())
    runAction(cmd, true, false, prev)
  }

  function discard() {
    if (!ready || actionProcess.running) return
    var prev = running
    running = null
    note = "Discarding timer…"
    runAction([helperPath, "discard"], true, false, prev)
  }

  function splitRunning(minutesAgo, atTime) {
    var cmd = [helperPath, "split-running"]
    if (minutesAgo && minutesAgo > 0) cmd.push("--minutes-ago", String(minutesAgo))
    if (atTime !== undefined && atTime !== null && String(atTime).trim() !== "") cmd.push("--at", String(atTime).trim())
    runAction(cmd, true)
  }

  function updateRunning(description, projectId, taskId, tagIds, billable, adjustMinutes, startTime) {
    var cleanTags = Model.toArray(tagIds)
    if (running && typeof running === "object") {
      var tagMap = {}
      for (var ti = 0; ti < tags.length; ti++) {
        if (tags[ti] && tags[ti].id) tagMap[String(tags[ti].id)] = String(tags[ti].name || "")
      }
      var nextNames = []
      for (var tj = 0; tj < cleanTags.length; tj++) {
        if (tagMap[cleanTags[tj]]) nextNames.push(tagMap[cleanTags[tj]])
      }
      running = Object.assign({}, running, {
        description: String(description || ""),
        projectId: String(projectId === undefined || projectId === null ? "" : projectId),
        taskId: String(taskId === undefined || taskId === null ? "" : taskId),
        tagIds: cleanTags,
        tagNames: nextNames,
        billable: billable === true
      })
    }
    var cmd = [
      helperPath, "update-running",
      "--description", String(description || ""),
      "--project", String(projectId === undefined || projectId === null ? "" : projectId),
      "--task", String(taskId === undefined || taskId === null ? "" : taskId),
      "--tags", cleanTags.join(","),
      billable ? "--billable" : "--no-billable"
    ]
    if (adjustMinutes && adjustMinutes !== 0) {
      cmd.push("--adjust-minutes", String(adjustMinutes))
    }
    if (startTime !== undefined && startTime !== null && String(startTime).trim() !== "") {
      cmd.push("--start", String(startTime).trim())
    }
    runAction(cmd, true)
  }

  function addManual(description, projectId, taskId, tagIds, billable, dateStr, startTime, endTime) {
    var cmd = [
      helperPath, "add-manual",
      "--description", String(description || ""),
      "--project", String(projectId === undefined || projectId === null ? "" : projectId),
      "--task", String(taskId === undefined || taskId === null ? "" : taskId),
      "--tags", tagCsv(tagIds),
      billable ? "--billable" : "--no-billable",
      "--date", String(dateStr || "today"),
      "--start", String(startTime || ""),
      "--end", String(endTime || "")
    ]
    runAction(cmd, true)
  }

  function continueEntry(entryId) {
    if (!entryId) return
    runAction([helperPath, "continue-entry", "--id", String(entryId)], true)
  }

  function duplicateEntry(entryId) {
    if (!entryId) return
    runAction([helperPath, "duplicate-entry", "--id", String(entryId)], true)
  }

  function updateEntry(entryId, description, projectId, taskId, tagIds, billable, dateStr, startTime, endTime) {
    if (!entryId) return
    var cmd = [
      helperPath, "update-entry",
      "--id", String(entryId),
      "--description", String(description || ""),
      "--project", String(projectId === undefined || projectId === null ? "" : projectId),
      "--task", String(taskId === undefined || taskId === null ? "" : taskId),
      "--tags", tagCsv(tagIds),
      billable ? "--billable" : "--no-billable"
    ]
    if (dateStr !== undefined && String(dateStr).trim() !== "") {
      cmd.push("--date", String(dateStr).trim())
    }
    if (startTime !== undefined && String(startTime).trim() !== "") {
      cmd.push("--start", String(startTime).trim())
    }
    if (endTime !== undefined && String(endTime).trim() !== "") {
      cmd.push("--end", String(endTime).trim())
    }
    runAction(cmd, true)
  }

  function deleteEntry(entryId) {
    if (!entryId) return
    runAction([helperPath, "delete-entry", "--id", String(entryId)], true)
  }

  function createProject(name, clientId, color, billable, isPublic) {
    var cmd = [
      helperPath, "create-project",
      "--name", String(name || "").trim(),
      "--client", String(clientId || ""),
      "--color", String(color || "#039BE5"),
      billable ? "--billable" : "--no-billable",
      isPublic ? "--public" : "--private"
    ]
    runAction(cmd, true)
  }

  function archiveProject(projectId, archived) {
    if (!projectId) return
    runAction([
      helperPath, "archive-project",
      "--id", String(projectId),
      "--archived", archived !== false ? "true" : "false"
    ], true)
  }

  function deleteProject(projectId) {
    if (!projectId) return
    runAction([helperPath, "delete-project", "--id", String(projectId)], true)
  }

  function createTask(projectId, name) {
    runAction([
      helperPath, "create-task",
      "--project", String(projectId || ""),
      "--name", String(name || "").trim()
    ], true)
  }

  function updateTaskStatus(projectId, taskId, status) {
    if (!projectId || !taskId) return
    runAction([
      helperPath, "update-task-status",
      "--project", String(projectId),
      "--id", String(taskId),
      "--status", String(status || "DONE")
    ], true)
  }

  function deleteTask(projectId, taskId) {
    if (!projectId || !taskId) return
    runAction([
      helperPath, "delete-task",
      "--project", String(projectId),
      "--id", String(taskId)
    ], true)
  }

  function createTag(name) {
    runAction([helperPath, "create-tag", "--name", String(name || "").trim()], true)
  }

  function deleteTag(tagId) {
    if (!tagId) return
    runAction([helperPath, "delete-tag", "--id", String(tagId)], true)
  }

  function createClient(name) {
    runAction([helperPath, "create-client", "--name", String(name || "").trim()], true)
  }

  function deleteClient(clientId) {
    if (!clientId) return
    runAction([helperPath, "delete-client", "--id", String(clientId)], true)
  }

  function switchWorkspace(workspaceId) {
    if (!workspaceId) return
    runAction([helperPath, "switch-workspace", "--workspace", String(workspaceId)], true)
  }

  function rememberProject(projectId) {
    defaultProjectId = String(projectId || "")
    defaultTaskId = ""
    saveConfig({ project: defaultProjectId, task: "" })
  }

  function saveConfig(opts) {
    if (!ready) return
    var cmd = [helperPath, "set-config"]
    if (opts.project !== undefined) cmd.push("--project", String(opts.project))
    if (opts.task !== undefined) cmd.push("--task", String(opts.task))
    if (opts.tags !== undefined) cmd.push("--tags", typeof opts.tags === "string" ? opts.tags : tagCsv(opts.tags))
    if (opts.billable !== undefined) cmd.push("--billable", opts.billable ? "true" : "false")
    if (opts.weekStart !== undefined) cmd.push("--week-start", String(opts.weekStart))
    if (opts.panelWidth !== undefined) cmd.push("--panel-width", String(opts.panelWidth))
    if (opts.panelHeight !== undefined) cmd.push("--panel-height", String(opts.panelHeight))
    if (opts.wrapText !== undefined) cmd.push("--wrap-text", opts.wrapText ? "true" : "false")
    if (opts.timeStepMinutes !== undefined) cmd.push("--time-step-min", String(opts.timeStepMinutes))
    if (opts.quickStepMinutes !== undefined) cmd.push("--quick-step-min", String(opts.quickStepMinutes))
    if (opts.durationFormat !== undefined) cmd.push("--duration-format", String(opts.durationFormat))
    if (opts.groupSimilarEntries !== undefined) cmd.push("--group-similar", opts.groupSimilarEntries ? "true" : "false")
    if (opts.pomodoro !== undefined) cmd.push("--pomodoro", opts.pomodoro ? "true" : "false")
    if (opts.pomodoroAutoTimer !== undefined) cmd.push("--pomodoro-auto-timer", opts.pomodoroAutoTimer ? "true" : "false")
    if (opts.pomodoroWork !== undefined) cmd.push("--pomodoro-work", String(opts.pomodoroWork))
    if (opts.pomodoroBreak !== undefined) cmd.push("--pomodoro-break", String(opts.pomodoroBreak))
    if (opts.dailyTargetHours !== undefined) cmd.push("--daily-target-hours", String(opts.dailyTargetHours))
    if (opts.weeklyTargetHours !== undefined) cmd.push("--weekly-target-hours", String(opts.weeklyTargetHours))
    if (opts.stopOnIdle !== undefined) cmd.push("--stop-on-idle", opts.stopOnIdle ? "true" : "false")
    if (opts.idleStopMin !== undefined) cmd.push("--idle-stop-min", String(opts.idleStopMin))
    if (opts.remindWhenIdle !== undefined) cmd.push("--remind-when-idle", opts.remindWhenIdle ? "true" : "false")
    if (opts.idleRemindMin !== undefined) cmd.push("--idle-remind-min", String(opts.idleRemindMin))
    runAction(cmd, false, true)
  }

  function saveKey(key) {
    var trimmed = String(key || "").trim()
    if (!ready || trimmed === "" || keyProcess.running) return
    _mutationSeq += 1
    _accountSeq += 1
    _actionQueue = []
    if (statusProcess.running) statusProcess.running = false
    note = "Validating API key…"
    keyProcess.accountSeqAtStart = root._accountSeq
    keyProcess.secret = trimmed
    keyProcess.command = pythonCommand([helperPath, "set-key"])
    keyProcess.running = true
  }

  function connectDesktop() {
    if (!ready) return
    _accountSeq += 1
    _actionQueue = []
    runAction([helperPath, "connect-desktop"], true, false, false, root._accountSeq)
  }

  function clearKey() {
    if (!ready) return
    _accountSeq += 1
    _actionQueue = []
    note = "Disconnecting…"
    runAction([helperPath, "clear-key"], true, false, false, root._accountSeq)
  }

  function launchDesktopApp() {
    Quickshell.execDetached(["clockify"])
  }

  function openWebApp() {
    Qt.openUrlExternally("https://app.clockify.me/tracker")
  }

  function startPomodoro() {
    pomodoroPhase = "work"
    pomodoroSecondsLeft = Math.max(60, pomodoroWorkMin * 60)
    pomodoroRunning = true
    notify("Pomodoro started", "Focus session: " + pomodoroWorkMin + " min")
    if (pomodoroAutoTimer && configured && !timing && !actionBusy) {
      start("", defaultProjectId, defaultTaskId, defaultTagIds, defaultBillable)
    }
  }

  function stopPomodoro() {
    pomodoroRunning = false
    pomodoroPhase = "work"
    pomodoroSecondsLeft = 0
  }

  function skipPomodoroPhase() {
    if (!pomodoroRunning) return
    if (pomodoroPhase === "work") {
      pomodoroPhase = "break"
      pomodoroSecondsLeft = Math.max(60, pomodoroBreakMin * 60)
      notify("Pomodoro: Break time", "Take a " + pomodoroBreakMin + " minute break!")
      if (pomodoroAutoTimer && timing) stop()
    } else {
      pomodoroPhase = "work"
      pomodoroSecondsLeft = Math.max(60, pomodoroWorkMin * 60)
      notify("Pomodoro: Focus session", "Starting " + pomodoroWorkMin + " min focus.")
      if (pomodoroAutoTimer && configured && !timing && !actionBusy) {
        start("", defaultProjectId, defaultTaskId, defaultTagIds, defaultBillable)
      }
    }
  }

  function _startActionItem(item) {
    actionProcess.expectsSnapshot = item.expectsSnapshot
    actionProcess.isConfigOnly = item.isConfigOnly
    actionProcess.preOptimisticRunning = item.rollbackRunning
    actionProcess.accountSeqAtStart = item.accountSeq
    actionProcess.command = pythonCommand(item.command)
    actionProcess.running = true
  }

  function _startNextAction() {
    if (actionProcess.running || _actionQueue.length === 0) return
    var q = _actionQueue.slice()
    var nextItem = q.shift()
    _actionQueue = q
    _startActionItem(nextItem)
  }

  function runAction(command, expectsSnapshot, isConfigOnly, rollbackRunning, accountSeqOverride) {
    if (!ready) return
    _mutationSeq += 1
    var expectSnap = expectsSnapshot !== false
    var cfgOnly = isConfigOnly === true
    var rollback = (rollbackRunning && typeof rollbackRunning === "object") ? rollbackRunning : null
    var acctSeq = (accountSeqOverride !== undefined) ? accountSeqOverride : root._accountSeq
    if (statusProcess.running && !cfgOnly) {
      statusProcess.running = false
    }
    var item = {
      command: command,
      expectsSnapshot: expectSnap,
      isConfigOnly: cfgOnly,
      rollbackRunning: rollback,
      accountSeq: acctSeq
    }
    if (actionProcess.running) {
      var q = _actionQueue.slice()
      q.push(item)
      _actionQueue = q
      return
    }
    _startActionItem(item)
  }

  function pythonCommand(parts) {
    return ["python3"].concat(parts)
  }

  // -------------------------------------------------------------- payloads

  function applyConfigPayload(payload) {
    if (!payload || payload.ok === false) return
    defaultProjectId = String(payload.defaultProjectId || "")
    defaultTaskId = String(payload.defaultTaskId || "")
    defaultTagIds = Model.toArray(payload.defaultTagIds)
    defaultBillable = payload.defaultBillable === true
    weekStart = String(payload.weekStart || "monday")
    panelWidth = Number(payload.panelWidth || 560)
    panelHeight = Number(payload.panelHeight || 740)
    wrapText = payload.wrapText !== false
    timeStepMinutes = Number(payload.timeStepMinutes || 5)
    var fallbackQuick = (timeStepMinutes === 1) ? 5 : 1
    quickStepMinutes = Number(payload.quickStepMinutes || fallbackQuick)
    durationFormat = String(payload.durationFormat || "compact")
    groupSimilarEntries = payload.groupSimilarEntries !== false
    pomodoroEnabled = payload.pomodoroEnabled === true
    pomodoroAutoTimer = payload.pomodoroAutoTimer !== false
    pomodoroWorkMin = Number(payload.pomodoroWorkMin || 25)
    pomodoroBreakMin = Number(payload.pomodoroBreakMin || 5)
    dailyTargetHours = Number(payload.dailyTargetHours !== undefined ? payload.dailyTargetHours : 8)
    weeklyTargetHours = Number(payload.weeklyTargetHours !== undefined ? payload.weeklyTargetHours : 40)
    stopOnIdle = payload.stopOnIdle === true
    idleStopMin = Number(payload.idleStopMin || 240)
    remindWhenIdle = payload.remindWhenIdle === true
    idleRemindMin = Number(payload.idleRemindMin || 30)
    if (payload.note) {
      note = String(payload.note)
      noteTimer.restart()
    }
  }

  function clearAccountData() {
    workspaces = []
    projects = []
    tags = []
    clients = []
    recentEntries = []
    running = null
    todaySeconds = 0
    weekSeconds = 0
    monthSeconds = 0
    todayBillableSeconds = 0
    weekBillableSeconds = 0
    monthBillableSeconds = 0
    loadedStartDate = ""
    loadedEndDate = ""
    fetchedAt = ""
    fullLoaded = false
    lastFullRefreshMs = 0
    workspaceName = ""
    workspaceId = ""
    userName = ""
    userEmail = ""
    userId = ""
    lastAutoStoppedId = ""
    pendingExportOverwritePath = ""
  }

  function _identityChanged(prevConfigured, prevAuthSource, prevUserId, prevWorkspaceId,
                            nextConfigured, nextAuthSource, nextUserId, nextWorkspaceId) {
    if (!prevConfigured || !nextConfigured) return false
    if (prevUserId !== "" && nextUserId !== "" && prevUserId !== nextUserId) return true
    if (prevWorkspaceId !== "" && nextWorkspaceId !== "" && prevWorkspaceId !== nextWorkspaceId) return true
    if (prevAuthSource !== "" && nextAuthSource !== "" && prevAuthSource !== nextAuthSource) return true
    return false
  }

  function applyPayload(raw) {
    var payload = Model.parsePayload(raw)

    if (payload.ok === false) {
      var prevAuthSource = authSource
      lastError = String(payload.error || "Clockify request failed")
      note = ""
      if (payload.configured !== undefined) configured = payload.configured === true
      if (payload.authSource !== undefined) authSource = String(payload.authSource || "")
      if (!configured || (prevAuthSource !== "" && authSource !== "" && prevAuthSource !== authSource)) {
        clearAccountData()
      }
      if (payload.exportExists === true) {
        pendingExportOverwritePath = String(payload.exportPath || "")
      }
      return payload
    }

    var prevConfigured = configured
    var prevAuthSource = authSource
    var prevUserId = userId
    var prevWorkspaceId = workspaceId

    var nextConfigured = payload.configured === true
    var nextAuthSource = String(payload.authSource || "")
    var nextUserId = String(payload.userId || "")
    var nextWorkspaceId = String(payload.workspaceId || "")
    var accountChanged = _identityChanged(
      prevConfigured, prevAuthSource, prevUserId, prevWorkspaceId,
      nextConfigured, nextAuthSource, nextUserId, nextWorkspaceId
    )

    lastError = String(payload.error || "")
    note = String(payload.note || "")
    configured = nextConfigured
    authSource = nextAuthSource
    userId = nextUserId
    userName = String(payload.userName || "")

    if (!configured) {
      clearAccountData()
      applyConfigPayload(payload)
      if (note !== "") noteTimer.restart()
      return payload
    }

    if (accountChanged) {
      clearAccountData()
      userId = nextUserId
      userName = String(payload.userName || "")
    }

    if (payload.rangeOnly === true) {
      if (payload.userEmail !== undefined) userEmail = String(payload.userEmail || "")
      if (nextWorkspaceId !== "") workspaceId = nextWorkspaceId
      applyConfigPayload(payload)
      if (payload.exportPath && String(payload.exportPath) !== "") {
        if (accountChanged) {
          Qt.callLater(function() {
            if (root.configured && !root.fullLoaded) root.refresh(true)
          })
        }
        if (note !== "") noteTimer.restart()
        return payload
      }
      var incoming = Array.isArray(payload.recentEntries) ? payload.recentEntries : []
      var byId = {}
      var merged = []
      var existing = Array.isArray(recentEntries) ? recentEntries : []
      for (var i = 0; i < incoming.length; i++) {
        var inc = incoming[i]
        if (inc && inc.id) {
          byId[String(inc.id)] = true
          merged.push(inc)
        }
      }
      for (var j = 0; j < existing.length; j++) {
        var ex = existing[j]
        if (ex && ex.id && !byId[String(ex.id)]) {
          byId[String(ex.id)] = true
          merged.push(ex)
        }
      }
      merged.sort(function(a, b) {
        return String(a.start || "") < String(b.start || "") ? 1 : -1
      })
      recentEntries = merged
      loadedStartDate = String(payload.loadedStartDate || loadedStartDate)
      loadedEndDate = String(payload.loadedEndDate || loadedEndDate)
      if (accountChanged) {
        Qt.callLater(function() {
          if (root.configured && !root.fullLoaded) root.refresh(true)
        })
      }
      if (note !== "") noteTimer.restart()
      return payload
    }

    userEmail = String(payload.userEmail || "")
    workspaceId = nextWorkspaceId
    running = payload.running || null
    recentEntries = Array.isArray(payload.recentEntries) ? payload.recentEntries : []
    todaySeconds = Number(payload.todaySeconds || 0)
    weekSeconds = Number(payload.weekSeconds || 0)
    monthSeconds = Number(payload.monthSeconds || 0)
    todayBillableSeconds = Number(payload.todayBillableSeconds || 0)
    weekBillableSeconds = Number(payload.weekBillableSeconds || 0)
    monthBillableSeconds = Number(payload.monthBillableSeconds || 0)
    loadedStartDate = String(payload.loadedStartDate || "")
    loadedEndDate = String(payload.loadedEndDate || "")
    fetchedAt = String(payload.fetchedAt || "")

    applyConfigPayload(payload)

    if (payload.fullLoaded === true) {
      workspaces = Array.isArray(payload.workspaces) ? payload.workspaces : []
      projects = Array.isArray(payload.projects) ? payload.projects : []
      tags = Array.isArray(payload.tags) ? payload.tags : []
      clients = Array.isArray(payload.clients) ? payload.clients : []
      workspaceName = String(payload.workspaceName || "")
      fullLoaded = true
      if (!root._nextIsCacheOnly) root.lastFullRefreshMs = Date.now()
    } else if (accountChanged) {
      Qt.callLater(function() {
        if (root.configured && !root.fullLoaded) root.refresh(true)
      })
    }

    if (note !== "") noteTimer.restart()
    return payload
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.ready && root.configured
    onTriggered: root.refresh(false)
  }

  Timer {
    id: firstRefresh
    interval: 60
    repeat: false
    running: root.ready
    onTriggered: root.refreshFromCache()
  }

  Timer {
    id: bootLiveTimer
    interval: 250 + Math.floor(Math.random() * 1200)
    repeat: false
    onTriggered: root.refresh(!root.fullLoaded)
  }

  Timer {
    id: noteTimer
    interval: 3200
    repeat: false
    onTriggered: root.note = ""
  }

  Timer {
    id: pomodoroTimer
    interval: 1000
    repeat: true
    running: root.pomodoroRunning
    onTriggered: {
      if (root.pomodoroSecondsLeft > 1) {
        root.pomodoroSecondsLeft -= 1
        return
      }
      if (root.pomodoroPhase === "work") {
        root.pomodoroPhase = "break"
        root.pomodoroSecondsLeft = Math.max(60, root.pomodoroBreakMin * 60)
        root.notify("Pomodoro: Break time", "Take a " + root.pomodoroBreakMin + " minute break!")
        if (root.pomodoroAutoTimer && root.timing) root.stop()
      } else {
        root.pomodoroPhase = "work"
        root.pomodoroSecondsLeft = Math.max(60, root.pomodoroWorkMin * 60)
        root.notify("Pomodoro: Back to focus", "Break ended — ready for " + root.pomodoroWorkMin + " min focus.")
      }
    }
  }

  Timer {
    id: automationTimer
    interval: 60000
    repeat: true
    running: root.ready && root.isPrimaryMonitor && root.configured
    onTriggered: {
      var nowMs = Date.now()
      if (!root.timing && root.remindWhenIdle) {
        if (root.lastIdleNoticeMs === 0) {
          root.lastIdleNoticeMs = nowMs
        } else if ((nowMs - root.lastIdleNoticeMs) >= root.idleRemindMin * 60000) {
          root.lastIdleNoticeMs = nowMs
          root.notify("Clockify Reminder", "No timer is currently running.")
        }
      } else {
        root.lastIdleNoticeMs = nowMs
      }

      if (root.timing && root.stopOnIdle && root.running && root.running.start) {
        var elapsed = Model.elapsedSeconds(root.running.start, new Date(nowMs))
        if (elapsed >= root.idleStopMin * 60 && root.lastAutoStoppedId !== String(root.running.id || "")) {
          root.lastAutoStoppedId = String(root.running.id || "")
          root.notify("Clockify Auto-Stop", "Stopped running timer after " + root.idleStopMin + " minutes.")
          root.stop()
        }
      }
    }
  }

  Process {
    id: statusProcess
    property int seqAtStart: 0
    property int accountSeqAtStart: 0
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      var wasCacheBoot = root._bootCachePending
      root._bootCachePending = false
      var stale = (seqAtStart !== root._mutationSeq) || (accountSeqAtStart !== root._accountSeq) || actionProcess.running
      if (!stale) {
        if (exitCode === 0) {
          root.applyPayload(statusOut.text)
        } else if (!wasCacheBoot) {
          root.lastError = root.helperFailure(statusErr.text, exitCode)
        }
      }
      root._nextIsCacheOnly = false
      if (wasCacheBoot) {
        bootLiveTimer.restart()
      }
    }
  }

  Process {
    id: actionProcess
    property bool expectsSnapshot: true
    property bool isConfigOnly: false
    property var preOptimisticRunning: null
    property int accountSeqAtStart: 0
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var rollback = preOptimisticRunning
      preOptimisticRunning = null
      if (accountSeqAtStart !== root._accountSeq) {
        root._startNextAction()
        return
      }
      if (exitCode !== 0) {
        if (rollback !== null && root.running === null) root.running = rollback
        root.lastError = root.helperFailure(actionErr.text, exitCode)
        root._startNextAction()
        return
      }
      if (isConfigOnly) {
        root.applyConfigPayload(Model.parsePayload(actionOut.text))
        root._startNextAction()
        return
      }
      if (!expectsSnapshot) {
        root._startNextAction()
        return
      }
      var parsed = root.applyPayload(actionOut.text)
      if (parsed && parsed.ok === false && rollback !== null && root.running === null) {
        root.running = rollback
      }
      root._startNextAction()
    }
  }

  Process {
    id: keyProcess
    property string secret: ""
    property int accountSeqAtStart: 0
    running: false
    command: []
    stdinEnabled: true
    stdout: StdioCollector { id: keyOut; waitForEnd: true }
    stderr: StdioCollector { id: keyErr; waitForEnd: true }
    onStarted: {
      write(secret + "\n")
      secret = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (accountSeqAtStart !== root._accountSeq) return
      if (exitCode !== 0) {
        root.lastError = root.helperFailure(keyErr.text, exitCode)
        root.keyRejected(root.lastError)
        return
      }
      var payload = root.applyPayload(keyOut.text)
      if (payload.ok === false || payload.configured !== true) {
        root.keyRejected(String(payload.error || "Clockify rejected the API key"))
      }
    }
  }

  function helperFailure(stderrText, exitCode) {
    var text = String(stderrText || "").replace(/\s+/g, " ").trim()
    if (text === "") return "clockify.py exited with code " + exitCode
    return text.length > 160 ? text.substring(0, 157) + "…" : text
  }
}
