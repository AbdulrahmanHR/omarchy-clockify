// Pure formatting, option-building, filtering, analytics, and text-safety
// helpers for io.github.abdulrahmanhr.clockify.

var MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var MONTHS_FULL = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var DAYS_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var FALLBACK_COLORS = ["#039BE5", "#009688", "#4CAF50", "#FF9800", "#E91E63", "#9C27B0", "#673AB7", "#607D8B"]

function neutralizeMarkup(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/</g, "\u2039")
    .replace(/>/g, "\u203a")
}

function parsePayload(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, error: "The Clockify helper returned nothing" }
  try {
    var payload = JSON.parse(text)
    if (!payload || typeof payload !== "object") throw new Error("not an object")
    return payload
  } catch (e) {
    return { ok: false, error: "Could not read the Clockify helper output" }
  }
}

function pad2(value) {
  return value < 10 ? "0" + value : String(value)
}

function formatClock(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  return hours + ":" + pad2(minutes) + ":" + pad2(total % 60)
}

function formatDuration(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  if (hours > 0) return hours + "h " + pad2(minutes) + "m"
  return minutes + "m"
}

function formatCompactDuration(seconds) {
  var total = Math.max(0, Math.floor(Number(seconds) || 0))
  if (total <= 0) return ""
  if (total < 60) return total + "s"
  if (total < 3600) return Math.round(total / 60) + "m"
  var hrs = total / 3600
  return (hrs >= 10 ? Math.round(hrs) : hrs.toFixed(1).replace(/\.0$/, "")) + "h"
}

function formatDurationByMode(seconds, durationFormat) {
  var mode = String(durationFormat || "compact").toLowerCase()
  if (mode === "full") return formatClock(seconds)
  if (mode === "decimal") {
    var hrs = Math.max(0, Number(seconds) || 0) / 3600
    return hrs.toFixed(2) + "h"
  }
  return formatDuration(seconds)
}

function _parseHhMmTotalMinutes(value, fallbackDate) {
  var m = /^\s*(\d{1,2}):(\d{2})/.exec(String(value || ""))
  if (m) {
    var h = parseInt(m[1], 10)
    var min = parseInt(m[2], 10)
    if (isFinite(h) && isFinite(min) && h >= 0 && h <= 23 && min >= 0 && min <= 59) {
      return h * 60 + min
    }
  }
  var ref = (fallbackDate && typeof fallbackDate.getHours === "function") ? fallbackDate : new Date()
  return ref.getHours() * 60 + ref.getMinutes()
}

function stepTimeHhMm(value, deltaMinutes, fallbackDate) {
  var total = _parseHhMmTotalMinutes(value, fallbackDate)
  var delta = parseInt(deltaMinutes || 0, 10)
  if (!isFinite(delta)) delta = 0
  var wrapped = ((total + delta) % 1440 + 1440) % 1440
  return pad2(Math.floor(wrapped / 60)) + ":" + pad2(wrapped % 60)
}

function roundTimeHhMm(value, stepMinutes, fallbackDate) {
  var total = _parseHhMmTotalMinutes(value, fallbackDate)
  var step = Math.max(1, Math.min(60, parseInt(stepMinutes || 5, 10) || 5))
  var rounded = Math.round(total / step) * step
  var wrapped = ((rounded % 1440) + 1440) % 1440
  return pad2(Math.floor(wrapped / 60)) + ":" + pad2(wrapped % 60)
}

function stepDateIso(value, deltaDays, fallbackDate) {
  var now = (fallbackDate && typeof fallbackDate.getFullYear === "function") ? fallbackDate : new Date()
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0)
  var raw = String(value || "").trim().toLowerCase()
  var base = today
  if (raw === "yesterday") {
    base = addDays(today, -1)
  } else if (raw !== "" && raw !== "today") {
    base = parseLocalDateIso(raw) || today
  }
  var delta = parseInt(deltaDays || 0, 10)
  if (!isFinite(delta)) delta = 0
  return toLocalDateIso(addDays(base, delta))
}

function parseStamp(value) {
  var text = String(value || "").trim()
  if (text === "") return null
  var millis = Date.parse(text)
  return isNaN(millis) ? null : new Date(millis)
}

function elapsedSeconds(startStamp, now) {
  var start = parseStamp(startStamp)
  if (!start || !now) return 0
  return Math.max(0, Math.floor((now.getTime() - start.getTime()) / 1000))
}

function describeEntry(entry) {
  if (!entry) return ""
  var description = String(entry.description || "").trim()
  if (description !== "") return description
  var task = String(entry.taskName || "").trim()
  if (task !== "") return task
  var project = String(entry.projectName || "").trim()
  if (project !== "") return project
  return "No description"
}

function projectLabel(entry) {
  if (!entry) return ""
  var project = String(entry.projectName || "").trim()
  var client = String(entry.clientName || "").trim()
  if (project === "") return ""
  return client === "" ? project : project + " · " + client
}

function taskLabel(entry) {
  if (!entry) return ""
  return String(entry.taskName || "").trim()
}

function tagsLabel(entry) {
  if (!entry || !Array.isArray(entry.tagNames) || entry.tagNames.length === 0) return ""
  return entry.tagNames.join(", ")
}

function truncateText(text, maxLen) {
  var s = String(text || "").trim()
  if (s.length <= maxLen) return s
  return s.substring(0, Math.max(1, maxLen - 1)) + "…"
}

function barLabel(running, seconds, showTimerInBar, showTaskInBar) {
  var icon = "󱎫"
  if (!running) return icon
  var parts = [icon]
  if (showTaskInBar) {
    parts.push(truncateText(neutralizeMarkup(describeEntry(running)), 18))
  }
  if (showTimerInBar) {
    parts.push(formatClock(seconds))
  }
  return parts.join(" ")
}

function barTooltip(running, seconds, todaySeconds, weekSeconds) {
  var today = "Today: " + formatDuration(todaySeconds)
  var week = "Week: " + formatDuration(weekSeconds)
  if (!running) return "Clockify · idle · " + today + " · " + week
  var proj = projectLabel(running)
  var task = taskLabel(running)
  var meta = []
  if (proj !== "") meta.push(proj)
  if (task !== "") meta.push(task)
  var head = describeEntry(running) + (meta.length ? " (" + meta.join(" / ") + ")" : "")
  return neutralizeMarkup(head) + " · " + formatClock(seconds) + "\n" + today + " · " + week
}

function projectOptions(projects, selectedId, emptyLabel) {
  var options = [{ value: "", label: emptyLabel || "No project", description: "" }]
  var list = Array.isArray(projects) ? projects : []
  var selected = String(selectedId || "")
  var matched = selected === ""
  for (var i = 0; i < list.length; i++) {
    var project = list[i] || {}
    var id = String(project.id || "")
    if (id === selected) matched = true
    options.push({
      value: id,
      label: neutralizeMarkup(project.name || "Unnamed project"),
      description: neutralizeMarkup(project.clientName || "")
    })
  }
  if (!matched) options.push({ value: selected, label: "Selected project", description: "" })
  return options
}

function taskOptions(projects, projectId, selectedTaskId, emptyLabel) {
  var options = [{ value: "", label: emptyLabel || "No task", description: "" }]
  var pid = String(projectId || "")
  var sid = String(selectedTaskId || "")
  var list = Array.isArray(projects) ? projects : []
  var matched = sid === ""
  for (var i = 0; i < list.length; i++) {
    var p = list[i] || {}
    if (pid !== "" && String(p.id || "") !== pid) continue
    var tasks = Array.isArray(p.tasks) ? p.tasks : []
    for (var j = 0; j < tasks.length; j++) {
      var t = tasks[j] || {}
      var tid = String(t.id || "")
      if (tid === sid) matched = true
      options.push({
        value: tid,
        label: neutralizeMarkup(t.name || "Unnamed task"),
        description: pid === "" ? neutralizeMarkup(p.name || "") : ""
      })
    }
    if (pid !== "") break
  }
  if (!matched && sid !== "") {
    options.push({ value: sid, label: "Selected task", description: "" })
  }
  return options
}

function tagOptions(tags) {
  var options = []
  var list = Array.isArray(tags) ? tags : []
  for (var i = 0; i < list.length; i++) {
    var t = list[i] || {}
    var id = String(t.id || "")
    if (!id) continue
    options.push({
      value: id,
      label: neutralizeMarkup(t.name || "Unnamed tag"),
      description: ""
    })
  }
  return options
}

function tagFilterOptions(tags) {
  var options = [{ value: "", label: "All tags" }]
  var list = Array.isArray(tags) ? tags : []
  for (var i = 0; i < list.length; i++) {
    var t = list[i] || {}
    var id = String(t.id || "")
    if (!id) continue
    options.push({ value: id, label: neutralizeMarkup(t.name || "Unnamed tag") })
  }
  return options
}

function clientOptions(clients, selectedId) {
  var options = [{ value: "", label: "No client", description: "" }]
  var list = Array.isArray(clients) ? clients : []
  var selected = String(selectedId || "")
  var matched = selected === ""
  for (var i = 0; i < list.length; i++) {
    var c = list[i] || {}
    var id = String(c.id || "")
    if (id === selected) matched = true
    options.push({
      value: id,
      label: neutralizeMarkup(c.name || "Unnamed client"),
      description: ""
    })
  }
  if (!matched) options.push({ value: selected, label: "Selected client", description: "" })
  return options
}

function workspaceOptions(workspaces) {
  var options = []
  var list = Array.isArray(workspaces) ? workspaces : []
  for (var i = 0; i < list.length; i++) {
    var ws = list[i] || {}
    var id = String(ws.id || "")
    if (!id) continue
    options.push({ value: id, label: neutralizeMarkup(ws.name || "Workspace") })
  }
  return options
}

function filterEntries(entries, query) {
  var list = Array.isArray(entries) ? entries : []
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return list
  var out = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {}
    var hay = [
      e.description || "",
      e.projectName || "",
      e.clientName || "",
      e.taskName || "",
      Array.isArray(e.tagNames) ? e.tagNames.join(" ") : "",
      e.dateLabel || ""
    ].join(" ").toLowerCase()
    if (hay.indexOf(q) !== -1) out.push(e)
  }
  return out
}

function statusLine(error, note, configured) {
  if (String(error || "") !== "") return String(error)
  if (String(note || "") !== "") return String(note)
  if (!configured) return "Paste an API key or opt in to Clockify Desktop."
  return ""
}

// ------------------------------------------------ Dashboard & Reports

function toLocalDateIso(dt) {
  return dt.getFullYear() + "-" + pad2(dt.getMonth() + 1) + "-" + pad2(dt.getDate())
}

function parseLocalDateIso(iso) {
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || "").trim())
  if (!m) return null
  var d = new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10), 0, 0, 0, 0)
  return isNaN(d.getTime()) ? null : d
}

function addDays(dt, days) {
  return new Date(dt.getFullYear(), dt.getMonth(), dt.getDate() + days, 0, 0, 0, 0)
}

function fmtDayShort(dt) {
  return dt.getDate() + " " + MONTHS_SHORT[dt.getMonth()]
}

function computePeriodBounds(periodMode, offset, weekStart, customFrom, customTo, nowDate) {
  var mode = String(periodMode || "week")
  var off = parseInt(offset || 0, 10)
  if (!isFinite(off)) off = 0
  var now = nowDate ? new Date(nowDate.getTime()) : new Date()
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0)
  var todayIso = toLocalDateIso(today)

  if (mode === "day") {
    var target = addDays(today, off)
    var tIso = toLocalDateIso(target)
    var title = off === 0 ? "Today" : (off === -1 ? "Yesterday" : (DAYS_SHORT[target.getDay()] + ", " + fmtDayShort(target)))
    return {
      mode: "day",
      startDate: target,
      endDate: target,
      startIso: tIso,
      endIso: tIso,
      todayIso: todayIso,
      title: title,
      subtitle: tIso
    }
  }

  if (mode === "week") {
    var dow = today.getDay()
    var shift = String(weekStart || "monday").toLowerCase() === "sunday" ? dow : ((dow + 6) % 7)
    var start = addDays(today, -shift + off * 7)
    var end = addDays(start, 6)
    var wTitle = off === 0 ? "This Week" : (off === -1 ? "Last Week" : (fmtDayShort(start) + " – " + fmtDayShort(end)))
    return {
      mode: "week",
      startDate: start,
      endDate: end,
      startIso: toLocalDateIso(start),
      endIso: toLocalDateIso(end),
      todayIso: todayIso,
      title: wTitle,
      subtitle: fmtDayShort(start) + " – " + fmtDayShort(end) + " " + end.getFullYear()
    }
  }

  if (mode === "month") {
    var mStart = new Date(today.getFullYear(), today.getMonth() + off, 1, 0, 0, 0, 0)
    var mEnd = new Date(mStart.getFullYear(), mStart.getMonth() + 1, 0, 0, 0, 0, 0)
    var mTitle = off === 0 ? "This Month" : (off === -1 ? "Last Month" : (MONTHS_FULL[mStart.getMonth()] + " " + mStart.getFullYear()))
    return {
      mode: "month",
      startDate: mStart,
      endDate: mEnd,
      startIso: toLocalDateIso(mStart),
      endIso: toLocalDateIso(mEnd),
      todayIso: todayIso,
      title: mTitle,
      subtitle: "1 " + MONTHS_SHORT[mStart.getMonth()] + " – " + mEnd.getDate() + " " + MONTHS_SHORT[mEnd.getMonth()] + " " + mEnd.getFullYear()
    }
  }

  if (mode === "year") {
    var yr = today.getFullYear() + off
    var yStart = new Date(yr, 0, 1, 0, 0, 0, 0)
    var yEnd = new Date(yr, 11, 31, 0, 0, 0, 0)
    return {
      mode: "year",
      startDate: yStart,
      endDate: yEnd,
      startIso: toLocalDateIso(yStart),
      endIso: toLocalDateIso(yEnd),
      todayIso: todayIso,
      title: off === 0 ? ("This Year (" + yr + ")") : String(yr),
      subtitle: yr + "-01-01 – " + yr + "-12-31"
    }
  }

  if (mode === "custom") {
    var cf = parseLocalDateIso(customFrom) || addDays(today, -6)
    var ct = parseLocalDateIso(customTo) || today
    if (cf.getTime() > ct.getTime()) {
      var tmp = cf; cf = ct; ct = tmp
    }
    var cfIso = toLocalDateIso(cf)
    var ctIso = toLocalDateIso(ct)
    return {
      mode: "custom",
      startDate: cf,
      endDate: ct,
      startIso: cfIso,
      endIso: ctIso,
      todayIso: todayIso,
      title: fmtDayShort(cf) + " – " + fmtDayShort(ct),
      subtitle: cfIso + " to " + ctIso
    }
  }

  return {
    mode: "all",
    startDate: null,
    endDate: null,
    startIso: "",
    endIso: "",
    todayIso: todayIso,
    title: "All Loaded History",
    subtitle: "Past 365 days"
  }
}

function filterDashboardEntries(entries, bounds, filters) {
  var list = Array.isArray(entries) ? entries : []
  var f = filters || {}
  var projId = String(f.projectId || "")
  var taskId = String(f.taskId || "")
  var tagId = String(f.tagId || "")
  var billMode = String(f.billableMode || "all")
  var q = String(f.query || "").trim().toLowerCase()
  var sIso = bounds && bounds.startIso ? String(bounds.startIso) : ""
  var eIso = bounds && bounds.endIso ? String(bounds.endIso) : ""

  var out = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {}
    var dIso = String(e.dateIso || "")
    if (sIso !== "" && dIso < sIso) continue
    if (eIso !== "" && dIso > eIso) continue
    if (projId !== "" && String(e.projectId || "") !== projId) continue
    if (taskId !== "" && String(e.taskId || "") !== taskId) continue
    if (tagId !== "") {
      var tids = Array.isArray(e.tagIds) ? e.tagIds : []
      if (tids.indexOf(tagId) === -1) continue
    }
    if (billMode === "billable" && !e.billable) continue
    if (billMode === "non-billable" && e.billable) continue
    if (q !== "") {
      var hay = [
        e.description || "",
        e.projectName || "",
        e.clientName || "",
        e.taskName || "",
        Array.isArray(e.tagNames) ? e.tagNames.join(" ") : "",
        e.dateLabel || "",
        dIso
      ].join(" ").toLowerCase()
      if (hay.indexOf(q) === -1) continue
    }
    out.push(e)
  }
  return out
}

function _buildBreakdownList(map, totalSeconds) {
  var rows = []
  for (var k in map) {
    if (!Object.prototype.hasOwnProperty.call(map, k)) continue
    rows.push(map[k])
  }
  rows.sort(function(a, b) { return b.seconds - a.seconds })
  var maxSec = rows.length > 0 ? Math.max(1, rows[0].seconds) : 1
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (!r.color) r.color = FALLBACK_COLORS[i % FALLBACK_COLORS.length]
    r.percent = totalSeconds > 0 ? Math.round((r.seconds / totalSeconds) * 100) : 0
    r.ratio = r.seconds / maxSec
  }
  return rows
}

function buildDashboard(entries, bounds, periodMode, weekStart, nowDate) {
  var list = Array.isArray(entries) ? entries : []
  var now = nowDate ? new Date(nowDate.getTime()) : new Date()
  var today = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0)
  var todayIso = toLocalDateIso(today)
  var mode = String(periodMode || (bounds ? bounds.mode : "week"))

  var totalSeconds = 0
  var billableSeconds = 0
  var dayTotals = {}
  var projMap = {}
  var taskMap = {}
  var tagMap = {}
  var dateGroupsMap = {}

  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {}
    var sec = Math.max(0, Number(e.seconds || 0))
    var bill = e.billable === true
    var dIso = String(e.dateIso || "")
    totalSeconds += sec
    if (bill) billableSeconds += sec

    if (dIso !== "") {
      if (!dayTotals[dIso]) {
        dayTotals[dIso] = {
          id: dIso,
          name: String(e.dateLabel || dIso),
          clientName: dIso,
          color: "",
          seconds: 0,
          billableSeconds: 0,
          count: 0
        }
      }
      dayTotals[dIso].seconds += sec
      if (bill) dayTotals[dIso].billableSeconds += sec
      dayTotals[dIso].count += 1

      if (!dateGroupsMap[dIso]) {
        dateGroupsMap[dIso] = {
          dateIso: dIso,
          dateLabel: String(e.dateLabel || dIso),
          totalSeconds: 0,
          billableSeconds: 0,
          entries: []
        }
      }
      dateGroupsMap[dIso].totalSeconds += sec
      if (bill) dateGroupsMap[dIso].billableSeconds += sec
      dateGroupsMap[dIso].entries.push(e)
    }

    var pKey = String(e.projectId || "__none__")
    if (!projMap[pKey]) {
      projMap[pKey] = {
        id: String(e.projectId || ""),
        name: String(e.projectName || "No project"),
        clientName: String(e.clientName || ""),
        color: String(e.projectColor || ""),
        seconds: 0,
        billableSeconds: 0,
        count: 0
      }
    }
    projMap[pKey].seconds += sec
    if (bill) projMap[pKey].billableSeconds += sec
    projMap[pKey].count += 1

    var tKey = String(e.taskId || "__none__")
    if (!taskMap[tKey]) {
      taskMap[tKey] = {
        id: String(e.taskId || ""),
        name: String(e.taskName || "No task"),
        clientName: String(e.projectName || ""),
        color: String(e.projectColor || ""),
        seconds: 0,
        billableSeconds: 0,
        count: 0
      }
    }
    taskMap[tKey].seconds += sec
    if (bill) taskMap[tKey].billableSeconds += sec
    taskMap[tKey].count += 1

    var tids = Array.isArray(e.tagIds) ? e.tagIds : []
    var tnames = Array.isArray(e.tagNames) ? e.tagNames : []
    if (tids.length === 0) {
      if (!tagMap["__untagged__"]) {
        tagMap["__untagged__"] = {
          id: "",
          name: "Untagged",
          clientName: "",
          color: "#607D8B",
          seconds: 0,
          billableSeconds: 0,
          count: 0
        }
      }
      tagMap["__untagged__"].seconds += sec
      if (bill) tagMap["__untagged__"].billableSeconds += sec
      tagMap["__untagged__"].count += 1
    } else {
      for (var ti = 0; ti < tids.length; ti++) {
        var gId = String(tids[ti] || "")
        if (!gId) continue
        var gName = String(tnames[ti] || gId)
        if (!tagMap[gId]) {
          tagMap[gId] = {
            id: gId,
            name: gName,
            clientName: "",
            color: "",
            seconds: 0,
            billableSeconds: 0,
            count: 0
          }
        }
        tagMap[gId].seconds += sec
        if (bill) tagMap[gId].billableSeconds += sec
        tagMap[gId].count += 1
      }
    }
  }

  var projectBreakdown = _buildBreakdownList(projMap, totalSeconds)
  var taskBreakdown = _buildBreakdownList(taskMap, totalSeconds)
  var tagBreakdown = _buildBreakdownList(tagMap, totalSeconds)
  var dayBreakdown = _buildBreakdownList(dayTotals, totalSeconds)
  dayBreakdown.sort(function(a, b) { return a.id < b.id ? 1 : -1 })

  var groupedByDate = []
  for (var gk in dateGroupsMap) {
    if (!Object.prototype.hasOwnProperty.call(dateGroupsMap, gk)) continue
    var grp = dateGroupsMap[gk]
    grp.groupedEntries = groupSimilarDayEntries(grp.entries)
    groupedByDate.push(grp)
  }
  groupedByDate.sort(function(a, b) { return a.dateIso < b.dateIso ? 1 : -1 })

  var activeDays = Object.keys(dayTotals).length
  var dailyAvgSeconds = activeDays > 0 ? Math.round(totalSeconds / activeDays) : 0
  var billablePercent = totalSeconds > 0 ? Math.round((billableSeconds / totalSeconds) * 100) : 0
  var topProject = projectBreakdown.length > 0 ? projectBreakdown[0] : null

  // Build chart bars depending on mode
  var chartBars = []
  var bStart = bounds && bounds.startDate ? bounds.startDate : null
  var bEnd = bounds && bounds.endDate ? bounds.endDate : null

  if (mode === "day") {
    var buckets = []
    for (var h = 0; h < 24; h += 3) {
      buckets.push({
        label: pad2(h) + "h",
        shortLabel: pad2(h),
        dateIso: bounds ? bounds.startIso : todayIso,
        dayOffsetFromToday: null,
        seconds: 0,
        billableSeconds: 0
      })
    }
    for (var bi = 0; bi < list.length; bi++) {
      var be = list[bi]
      var hm = /^(\d{2}):(\d{2})/.exec(String(be.startLocal || ""))
      var slot = hm ? Math.min(7, Math.floor(parseInt(hm[1], 10) / 3)) : 0
      var bsec = Math.max(0, Number(be.seconds || 0))
      buckets[slot].seconds += bsec
      if (be.billable) buckets[slot].billableSeconds += bsec
    }
    chartBars = buckets
  } else if (mode === "week" && bStart) {
    for (var wd = 0; wd < 7; wd++) {
      var cur = addDays(bStart, wd)
      var cIso = toLocalDateIso(cur)
      var dtInfo = dayTotals[cIso]
      var diffDays = Math.round((cur.getTime() - today.getTime()) / 86400000)
      chartBars.push({
        label: DAYS_SHORT[cur.getDay()] + " " + cur.getDate(),
        shortLabel: DAYS_SHORT[cur.getDay()],
        dateIso: cIso,
        dayOffsetFromToday: diffDays,
        seconds: dtInfo ? dtInfo.seconds : 0,
        billableSeconds: dtInfo ? dtInfo.billableSeconds : 0,
        isToday: cIso === todayIso
      })
    }
  } else if (mode === "month" && bStart && bEnd) {
    var totalDays = bEnd.getDate()
    for (var md = 1; md <= totalDays; md++) {
      var mCur = new Date(bStart.getFullYear(), bStart.getMonth(), md, 0, 0, 0, 0)
      var mIso = toLocalDateIso(mCur)
      var mInfo = dayTotals[mIso]
      var mDiff = Math.round((mCur.getTime() - today.getTime()) / 86400000)
      chartBars.push({
        label: md + " " + MONTHS_SHORT[mCur.getMonth()],
        shortLabel: (md === 1 || md % 5 === 0 || md === totalDays) ? String(md) : "",
        dateIso: mIso,
        dayOffsetFromToday: mDiff,
        seconds: mInfo ? mInfo.seconds : 0,
        billableSeconds: mInfo ? mInfo.billableSeconds : 0,
        isToday: mIso === todayIso
      })
    }
  } else if (mode === "year" && bStart) {
    var yr = bStart.getFullYear()
    var yBuckets = []
    for (var mo = 0; mo < 12; mo++) {
      yBuckets.push({
        label: MONTHS_SHORT[mo] + " " + yr,
        shortLabel: MONTHS_SHORT[mo],
        monthPrefix: yr + "-" + pad2(mo + 1),
        dateIso: "",
        dayOffsetFromToday: null,
        seconds: 0,
        billableSeconds: 0,
        isToday: (yr === today.getFullYear() && mo === today.getMonth())
      })
    }
    for (var yi = 0; yi < list.length; yi++) {
      var ye = list[yi]
      var ym = /^\d{4}-(\d{2})-/.exec(String(ye.dateIso || ""))
      if (!ym) continue
      var mIdx = parseInt(ym[1], 10) - 1
      if (mIdx >= 0 && mIdx < 12) {
        var ysec = Math.max(0, Number(ye.seconds || 0))
        yBuckets[mIdx].seconds += ysec
        if (ye.billable) yBuckets[mIdx].billableSeconds += ysec
      }
    }
    chartBars = yBuckets
  } else {
    var datesAsc = Object.keys(dayTotals).sort()
    var sliceDates = datesAsc.slice(Math.max(0, datesAsc.length - 14))
    for (var ai = 0; ai < sliceDates.length; ai++) {
      var dKey = sliceDates[ai]
      var info = dayTotals[dKey]
      var parsedD = parseLocalDateIso(dKey)
      var dDiff = parsedD ? Math.round((parsedD.getTime() - today.getTime()) / 86400000) : null
      chartBars.push({
        label: info.name + " (" + dKey + ")",
        shortLabel: dKey.substring(5),
        dateIso: dKey,
        dayOffsetFromToday: dDiff,
        seconds: info.seconds,
        billableSeconds: info.billableSeconds,
        isToday: dKey === todayIso
      })
    }
  }

  var maxBarSec = 1
  for (var cb = 0; cb < chartBars.length; cb++) {
    if (chartBars[cb].seconds > maxBarSec) maxBarSec = chartBars[cb].seconds
  }
  for (var cb2 = 0; cb2 < chartBars.length; cb2++) {
    var bar = chartBars[cb2]
    bar.nonBillableSeconds = Math.max(0, bar.seconds - bar.billableSeconds)
    bar.ratio = bar.seconds > 0 ? Math.max(0.06, bar.seconds / maxBarSec) : 0
    bar.billableRatio = bar.seconds > 0 ? (bar.billableSeconds / bar.seconds) : 0
    bar.valueLabel = formatCompactDuration(bar.seconds)
    bar.tooltip = neutralizeMarkup(bar.label + ": " + formatDuration(bar.seconds) + (bar.billableSeconds > 0 ? " (" + formatDuration(bar.billableSeconds) + " billable)" : ""))
  }

  return {
    totalSeconds: totalSeconds,
    billableSeconds: billableSeconds,
    nonBillableSeconds: Math.max(0, totalSeconds - billableSeconds),
    billablePercent: billablePercent,
    entryCount: list.length,
    activeDays: activeDays,
    dailyAvgSeconds: dailyAvgSeconds,
    topProject: topProject,
    chartBars: chartBars,
    projectBreakdown: projectBreakdown,
    taskBreakdown: taskBreakdown,
    tagBreakdown: tagBreakdown,
    dayBreakdown: dayBreakdown,
    groupedByDate: groupedByDate
  }
}

function groupSimilarDayEntries(dayEntries) {
  var list = Array.isArray(dayEntries) ? dayEntries : []
  var map = {}
  var ordered = []
  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {}
    var tids = Array.isArray(e.tagIds) ? e.tagIds.slice().sort().join(",") : ""
    var key = [
      String(e.description || "").trim(),
      String(e.projectId || ""),
      String(e.taskId || ""),
      e.billable ? "1" : "0",
      tids
    ].join("\n")
    if (!map[key]) {
      var group = {
        groupKey: key,
        id: String(e.id || key),
        count: 0,
        totalSeconds: 0,
        description: String(e.description || "").trim(),
        projectId: String(e.projectId || ""),
        projectName: String(e.projectName || ""),
        projectColor: String(e.projectColor || ""),
        clientName: String(e.clientName || ""),
        taskId: String(e.taskId || ""),
        taskName: String(e.taskName || ""),
        tagIds: Array.isArray(e.tagIds) ? e.tagIds : [],
        tagNames: Array.isArray(e.tagNames) ? e.tagNames : [],
        billable: e.billable === true,
        startLocal: String(e.startLocal || ""),
        endLocal: String(e.endLocal || ""),
        dateIso: String(e.dateIso || ""),
        dateLabel: String(e.dateLabel || ""),
        latestEntry: e,
        entries: []
      }
      map[key] = group
      ordered.push(group)
    }
    var g = map[key]
    g.count += 1
    g.totalSeconds += Math.max(0, Number(e.seconds || 0))
    if (e.startLocal && (!g.startLocal || String(e.startLocal) < g.startLocal)) {
      g.startLocal = String(e.startLocal)
    }
    if (e.endLocal && (!g.endLocal || String(e.endLocal) > g.endLocal)) {
      g.endLocal = String(e.endLocal)
    }
    g.entries.push(e)
  }
  return ordered
}

function buildWeeklyTimesheet(entries, projects, weekStart, offset, nowDate) {
  var bounds = computePeriodBounds("week", offset, weekStart, "", "", nowDate)
  var days = []
  var dayIndexByIso = {}
  for (var i = 0; i < 7; i++) {
    var d = addDays(bounds.startDate, i)
    var dIso = toLocalDateIso(d)
    days.push({
      dayIndex: i,
      dateIso: dIso,
      shortLabel: DAYS_SHORT[d.getDay()],
      dayNum: d.getDate() + " " + MONTHS_SHORT[d.getMonth()],
      isToday: dIso === bounds.todayIso,
      totalSeconds: 0
    })
    dayIndexByIso[dIso] = i
  }

  var rowMap = {}
  var rows = []
  var grandTotalSeconds = 0
  var list = Array.isArray(entries) ? entries : []

  for (var ei = 0; ei < list.length; ei++) {
    var e = list[ei] || {}
    var idx = dayIndexByIso[String(e.dateIso || "")]
    if (idx === undefined) continue
    var sec = Math.max(0, Number(e.seconds || 0))
    var pid = String(e.projectId || "")
    var tid = String(e.taskId || "")
    var rKey = pid + "|" + tid + "|" + (e.billable ? "1" : "0")
    if (!rowMap[rKey]) {
      rowMap[rKey] = {
        key: rKey,
        projectId: pid,
        projectName: String(e.projectName || "No project"),
        projectColor: String(e.projectColor || ""),
        clientName: String(e.clientName || ""),
        taskId: tid,
        taskName: String(e.taskName || ""),
        billable: e.billable === true,
        daySeconds: [0, 0, 0, 0, 0, 0, 0],
        totalSeconds: 0
      }
      rows.push(rowMap[rKey])
    }
    rowMap[rKey].daySeconds[idx] += sec
    rowMap[rKey].totalSeconds += sec
    days[idx].totalSeconds += sec
    grandTotalSeconds += sec
  }

  rows.sort(function(a, b) { return b.totalSeconds - a.totalSeconds })

  // Include active projects with 0h this week so any day cell can be clicked to log quickly.
  var seenProjects = {}
  for (var ri = 0; ri < rows.length; ri++) {
    if (rows[ri].projectId) seenProjects[rows[ri].projectId] = true
  }
  var projList = Array.isArray(projects) ? projects : []
  for (var pi = 0; pi < projList.length && rows.length < 10; pi++) {
    var p = projList[pi] || {}
    var pid2 = String(p.id || "")
    if (!pid2 || seenProjects[pid2]) continue
    seenProjects[pid2] = true
    rows.push({
      key: pid2 + "||" + (p.billable ? "1" : "0"),
      projectId: pid2,
      projectName: String(p.name || "Project"),
      projectColor: String(p.color || ""),
      clientName: String(p.clientName || ""),
      taskId: "",
      taskName: "",
      billable: p.billable === true,
      daySeconds: [0, 0, 0, 0, 0, 0, 0],
      totalSeconds: 0
    })
  }

  return {
    bounds: bounds,
    days: days,
    rows: rows,
    grandTotalSeconds: grandTotalSeconds
  }
}
