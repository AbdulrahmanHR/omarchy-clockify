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

  property bool pomodoroEnabled: false
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

  // Idle reminder tracking
  property double lastIdleNoticeMs: 0
  property string lastAutoStoppedId: ""

  property string lastError: ""
  property string note: ""
  property string fetchedAt: ""

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

  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "Clockify", String(title || "Clockify"), String(body || "")])
  }

  // ------------------------------------------------------------- commands

  function refresh(full) {
    if (!ready || statusProcess.running) return
    var command = [helperPath, "status"]
    if (full === true || (!fullLoaded && configured)) command.push("--full")
    statusProcess.command = pythonCommand(command)
    statusProcess.running = true
  }

  function fetchRange(startDateIso, endDateIso) {
    if (!ready) return
    var cmd = [helperPath, "status"]
    if (startDateIso) cmd.push("--start-date", String(startDateIso))
    if (endDateIso) cmd.push("--end-date", String(endDateIso))
    runAction(cmd, true, false, false)
  }

  function exportCsv(startDateIso, endDateIso, projectId, taskId, tagId, billableMode, query) {
    if (!ready) return
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
    runAction(cmd, true, false, false)
  }

  function start(description, projectId, taskId, tagIds, billable) {
    var cmd = [
      helperPath, "start",
      "--description", String(description || ""),
      "--project", String(projectId === undefined || projectId === null ? "" : projectId),
      "--task", String(taskId === undefined || taskId === null ? "" : taskId),
      "--tags", Array.isArray(tagIds) ? tagIds.join(",") : "",
      billable ? "--billable" : "--no-billable"
    ]
    runAction(cmd, true)
  }

  function stop() {
    runAction([helperPath, "stop"], true)
  }

  function discard() {
    runAction([helperPath, "discard"], true)
  }

  function updateRunning(description, projectId, taskId, tagIds, billable, adjustMinutes, startTime) {
    var cmd = [
      helperPath, "update-running",
      "--description", String(description || ""),
      "--project", String(projectId === undefined || projectId === null ? "" : projectId),
      "--task", String(taskId === undefined || taskId === null ? "" : taskId),
      "--tags", Array.isArray(tagIds) ? tagIds.join(",") : "",
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
      "--tags", Array.isArray(tagIds) ? tagIds.join(",") : "",
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
      "--tags", Array.isArray(tagIds) ? tagIds.join(",") : "",
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

  function createTask(projectId, name) {
    runAction([
      helperPath, "create-task",
      "--project", String(projectId || ""),
      "--name", String(name || "").trim()
    ], true)
  }

  function createTag(name) {
    runAction([helperPath, "create-tag", "--name", String(name || "").trim()], true)
  }

  function createClient(name) {
    runAction([helperPath, "create-client", "--name", String(name || "").trim()], true)
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
    if (!ready || actionProcess.running) return
    var cmd = [helperPath, "set-config"]
    if (opts.project !== undefined) cmd.push("--project", String(opts.project))
    if (opts.task !== undefined) cmd.push("--task", String(opts.task))
    if (opts.tags !== undefined) cmd.push("--tags", Array.isArray(opts.tags) ? opts.tags.join(",") : String(opts.tags))
    if (opts.billable !== undefined) cmd.push("--billable", opts.billable ? "true" : "false")
    if (opts.weekStart !== undefined) cmd.push("--week-start", String(opts.weekStart))
    if (opts.pomodoro !== undefined) cmd.push("--pomodoro", opts.pomodoro ? "true" : "false")
    if (opts.pomodoroWork !== undefined) cmd.push("--pomodoro-work", String(opts.pomodoroWork))
    if (opts.pomodoroBreak !== undefined) cmd.push("--pomodoro-break", String(opts.pomodoroBreak))
    if (opts.stopOnIdle !== undefined) cmd.push("--stop-on-idle", opts.stopOnIdle ? "true" : "false")
    if (opts.idleStopMin !== undefined) cmd.push("--idle-stop-min", String(opts.idleStopMin))
    if (opts.remindWhenIdle !== undefined) cmd.push("--remind-when-idle", opts.remindWhenIdle ? "true" : "false")
    if (opts.idleRemindMin !== undefined) cmd.push("--idle-remind-min", String(opts.idleRemindMin))
    runAction(cmd, false, true)
  }

  function saveKey(key) {
    var trimmed = String(key || "").trim()
    if (!ready || trimmed === "" || keyProcess.running) return
    note = "Validating API key…"
    keyProcess.secret = trimmed
    keyProcess.command = pythonCommand([helperPath, "set-key"])
    keyProcess.running = true
  }

  function clearKey() {
    runAction([helperPath, "clear-key"], true)
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
  }

  function stopPomodoro() {
    pomodoroRunning = false
    pomodoroPhase = "work"
    pomodoroSecondsLeft = 0
  }

  function runAction(command, expectsSnapshot, isConfigOnly, shouldSettle) {
    if (!ready || actionProcess.running) return
    actionProcess.expectsSnapshot = expectsSnapshot !== false
    actionProcess.isConfigOnly = isConfigOnly === true
    actionProcess.shouldSettle = shouldSettle !== false
    actionProcess.command = pythonCommand(command)
    actionProcess.running = true
  }

  function pythonCommand(parts) {
    return ["python3"].concat(parts)
  }

  // -------------------------------------------------------------- payloads

  function applyConfigPayload(payload) {
    if (!payload || payload.ok === false) return
    defaultProjectId = String(payload.defaultProjectId || "")
    defaultTaskId = String(payload.defaultTaskId || "")
    defaultTagIds = Array.isArray(payload.defaultTagIds) ? payload.defaultTagIds : []
    defaultBillable = payload.defaultBillable === true
    weekStart = String(payload.weekStart || "monday")
    pomodoroEnabled = payload.pomodoroEnabled === true
    pomodoroWorkMin = Number(payload.pomodoroWorkMin || 25)
    pomodoroBreakMin = Number(payload.pomodoroBreakMin || 5)
    stopOnIdle = payload.stopOnIdle === true
    idleStopMin = Number(payload.idleStopMin || 240)
    remindWhenIdle = payload.remindWhenIdle === true
    idleRemindMin = Number(payload.idleRemindMin || 30)
    if (payload.note) {
      note = String(payload.note)
      noteTimer.restart()
    }
  }

  function applyPayload(raw) {
    var payload = Model.parsePayload(raw)

    if (payload.ok === false) {
      lastError = String(payload.error || "Clockify request failed")
      note = ""
      if (payload.configured !== undefined) configured = payload.configured === true
      if (payload.authSource !== undefined) authSource = String(payload.authSource || "")
      return payload
    }

    lastError = String(payload.error || "")
    note = String(payload.note || "")
    configured = payload.configured === true
    authSource = String(payload.authSource || "")
    userId = String(payload.userId || "")
    userName = String(payload.userName || "")

    if (payload.rangeOnly === true) {
      if (payload.exportPath && String(payload.exportPath) !== "") {
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
      if (note !== "") noteTimer.restart()
      return payload
    }

    userEmail = String(payload.userEmail || "")
    workspaceId = String(payload.workspaceId || "")
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
    }

    if (!configured) {
      workspaces = []
      projects = []
      tags = []
      clients = []
      recentEntries = []
      fullLoaded = false
      workspaceName = ""
      userName = ""
      userEmail = ""
      userId = ""
    }
    if (note !== "") noteTimer.restart()
    return payload
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.ready
    onTriggered: root.refresh(false)
  }

  Timer {
    id: firstRefresh
    interval: 250 + Math.floor(Math.random() * 2500)
    repeat: false
    running: root.ready
    onTriggered: root.refresh(true)
  }

  Timer {
    id: settleTimer
    interval: 2200
    repeat: false
    onTriggered: root.refresh(false)
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
        if (root.timing) root.stop()
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
    running: false
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.helperFailure(statusErr.text, exitCode)
        return
      }
      root.applyPayload(statusOut.text)
    }
  }

  Process {
    id: actionProcess
    property bool expectsSnapshot: true
    property bool isConfigOnly: false
    property bool shouldSettle: true
    running: false
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.lastError = root.helperFailure(actionErr.text, exitCode)
        return
      }
      if (isConfigOnly) {
        root.applyConfigPayload(Model.parsePayload(actionOut.text))
        return
      }
      if (!expectsSnapshot) return
      var parsed = root.applyPayload(actionOut.text)
      if (shouldSettle && (!parsed || parsed.rangeOnly !== true)) {
        settleTimer.restart()
      }
    }
  }

  Process {
    id: keyProcess
    property string secret: ""
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
