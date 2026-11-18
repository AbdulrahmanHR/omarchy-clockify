#!/usr/bin/env python3
"""Clockify Control backend bridge for the io.github.abdulrahmanhr.clockify Omarchy plugin.

Every subcommand prints exactly one JSON object on stdout and exits 0 so the
QML layer has a single structured shape to parse. Credentials are never passed
via argv; they are read from ~/.config/omarchy/clockify.json (mode 0600),
$CLOCKIFY_API_KEY, stdin (for set-key), or read-only from Clockify Desktop's
active access session only after explicit user opt-in via connect-desktop.
"""

from __future__ import annotations

import argparse
import base64
import csv
import glob
import http.client
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path
from time import monotonic

HOST = "api.clockify.me"
API_PATH = "/api/v1"
USER_AGENT = "omarchy-clockify/1.0"
TIMEOUT = 6
DEADLINE = 26
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
PAGE_SIZE = 200
PAGE_LIMIT = 5
MAX_ENTRY_DAYS = 365
MAX_RECENT_ENTRIES = 500
MAX_TASK_PROJECTS = 40


class ApiError(Exception):
    """A Clockify call that failed in a way worth showing the user."""

    def __init__(self, message, code=None):
        super().__init__(message)
        self.code = code


class Identity:
    """Authenticated user and active workspace."""

    def __init__(self, user_id, workspace_id, user_name, user_email=""):
        self.user_id = user_id
        self.workspace_id = workspace_id
        self.user_name = user_name
        self.user_email = user_email


# ----------------------------------------------------------------- config

def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "omarchy" / "clockify.json"


def clockify_desktop_leveldb_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "Clockify" / "Local Storage" / "leveldb"


def load_config():
    try:
        with open(config_path(), encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def save_config(config):
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(temporary, path)
    os.chmod(path, 0o600)


# ----------------------------------------------------- leveldb / jwt auth

def _snappy_decompress(data):
    """Pure-Python Snappy block decompressor for LevelDB SSTable blocks."""
    pos = 0
    shift = 0
    while pos < len(data):
        b = data[pos]
        pos += 1
        if not (b & 0x80):
            break
        shift += 7
    out = bytearray()
    while pos < len(data):
        tag = data[pos]
        pos += 1
        kind = tag & 0x03
        if kind == 0:
            length = (tag >> 2) + 1
            if length > 60:
                extra = length - 60
                length = int.from_bytes(data[pos:pos + extra], "little") + 1
                pos += extra
            out.extend(data[pos:pos + length])
            pos += length
        else:
            if kind == 1:
                length = ((tag >> 2) & 0x07) + 4
                offset = ((tag & 0xE0) << 3) | data[pos]
                pos += 1
            elif kind == 2:
                length = (tag >> 2) + 1
                offset = int.from_bytes(data[pos:pos + 2], "little")
                pos += 2
            else:
                length = (tag >> 2) + 1
                offset = int.from_bytes(data[pos:pos + 4], "little")
                pos += 4
            if offset <= 0 or offset > len(out):
                raise ValueError("invalid snappy offset")
            for _ in range(length):
                out.append(out[-offset])
    return bytes(out)


def _read_varint(buf, pos):
    res = 0
    shift = 0
    while pos < len(buf):
        b = buf[pos]
        pos += 1
        res |= (b & 0x7F) << shift
        if not (b & 0x80):
            return res, pos
        shift += 7
    return res, pos


def _read_ldb_blocks(raw):
    """Extract and decompress data blocks from a LevelDB .ldb SSTable."""
    if len(raw) < 48:
        return raw
    footer = raw[-48:]
    try:
        _, p = _read_varint(footer, 0)
        _, p = _read_varint(footer, p)
        idx_off, p = _read_varint(footer, p)
        idx_sz, p = _read_varint(footer, p)
        if idx_off + idx_sz >= len(raw):
            return raw
        idx_block = raw[idx_off:idx_off + idx_sz]
        if raw[idx_off + idx_sz] == 1:
            idx_block = _snappy_decompress(idx_block)
        num_restarts = int.from_bytes(idx_block[-4:], "little")
        entries_end = len(idx_block) - 4 * (1 + num_restarts)
        p = 0
        out = bytearray()
        while p < entries_end:
            _, p = _read_varint(idx_block, p)
            non_shared, p = _read_varint(idx_block, p)
            val_len, p = _read_varint(idx_block, p)
            p += non_shared
            val = idx_block[p:p + val_len]
            p += val_len
            boff, vp = _read_varint(val, 0)
            bsz, vp = _read_varint(val, vp)
            if boff + bsz >= len(raw):
                continue
            bdata = raw[boff:boff + bsz]
            btype = raw[boff + bsz]
            out.extend(_snappy_decompress(bdata) if btype == 1 else bdata)
        return bytes(out)
    except Exception:
        return raw


def _decode_jwt_claims(token):
    try:
        parts = str(token).split(".")
        if len(parts) != 3:
            return None
        b64 = parts[1] + ("=" * (-len(parts[1]) % 4))
        claims = json.loads(base64.urlsafe_b64decode(b64).decode("utf-8"))
        return claims if isinstance(claims, dict) else None
    except Exception:
        return None


def _discover_desktop_access_token():
    """Find newest active access JWT in Clockify Desktop storage (read-only, in memory)."""
    access_candidates = []
    now_ts = time.time()

    ldb_dir = clockify_desktop_leveldb_dir()
    if not ldb_dir.is_dir():
        return ""

    jwt_re = re.compile(rb"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")
    for fn in sorted(glob.glob(str(ldb_dir / "*"))):
        if not (fn.endswith(".ldb") or fn.endswith(".log")):
            continue
        try:
            raw = Path(fn).read_bytes()
        except OSError:
            continue
        blobs = [raw]
        if fn.endswith(".ldb"):
            blobs.append(_read_ldb_blocks(raw))
        for blob in blobs:
            for m in jwt_re.finditer(blob):
                tok = m.group(0).decode("ascii", "ignore")
                claims = _decode_jwt_claims(tok)
                if not claims or str(claims.get("type") or "") != "access":
                    continue
                iat = int(claims.get("iat") or 0)
                exp = int(claims.get("exp") or 0)
                if exp > now_ts + 30:
                    access_candidates.append((iat, exp, tok))

    if not access_candidates:
        return ""
    access_candidates.sort(key=lambda item: item[0])
    return access_candidates[-1][2]


def resolve_auth(config):
    """Return (credential, header_name, auth_source) or ('', '', '')."""
    key = str(config.get("apiKey") or os.environ.get("CLOCKIFY_API_KEY") or "").strip()
    if key:
        return key, "X-Api-Key", "api-key"

    if config.get("useDesktopSession") is True:
        tok = _discover_desktop_access_token()
        if tok:
            return tok, "X-Auth-Token", "desktop-app"

    return "", "", ""


# -------------------------------------------------------------------- http

class Api:
    """Resilient HTTP/1.1 client with CloudFront IP failover for api.clockify.me."""

    def __init__(self, credential, header_name="X-Api-Key", preferred="", auth_source="", config=None):
        self.credential = credential
        self.header_name = header_name
        self.auth_source = auth_source
        self.config = config if config is not None else {}
        self.addresses = self._resolve()
        self.connection = None
        self.address = None
        self.preferred = str(preferred or "")
        self.good_host = ""

    @staticmethod
    def _resolve():
        try:
            infos = socket.getaddrinfo(HOST, 443, socket.AF_UNSPEC, socket.SOCK_STREAM)
        except OSError as error:
            raise ApiError("Could not resolve %s: %s" % (HOST, error)) from error
        ordered = []
        for info in infos:
            address = (info[0], info[4])
            if address not in ordered:
                ordered.append(address)
        if not ordered:
            raise ApiError("Could not resolve %s" % HOST)
        return ordered

    def _open(self, family, sockaddr):
        raw = socket.socket(family, socket.SOCK_STREAM)
        raw.settimeout(TIMEOUT)
        raw.connect(sockaddr)
        context = ssl.create_default_context()
        secure = context.wrap_socket(raw, server_hostname=HOST)
        connection = http.client.HTTPSConnection(HOST, 443, timeout=TIMEOUT)
        connection.sock = secure
        return connection

    def _close(self):
        if self.connection is not None:
            try:
                self.connection.close()
            except OSError:
                pass
        self.connection = None

    def call(self, method, path, body=None, params=None):
        target = API_PATH + path
        if params:
            target += "?" + urllib.parse.urlencode(params)
        payload = json.dumps(body).encode("utf-8") if body is not None else None
        headers = {
            self.header_name: self.credential,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        }

        candidates = []
        if self.address is not None:
            candidates.append(self.address)
        candidates.extend(a for a in self.addresses if a != self.address and a[1][0] == self.preferred)
        candidates.extend(a for a in self.addresses if a != self.address and a[1][0] != self.preferred)

        failure = None
        expiry = monotonic() + DEADLINE
        while candidates and monotonic() < expiry:
            candidate = candidates.pop(0)
            reused = self.connection is not None and self.address == candidate
            try:
                if not reused:
                    self._close()
                    self.connection = self._open(*candidate)
                    self.address = candidate
                self.connection.request(method, target, payload, headers)
                response = self.connection.getresponse()
                raw_bytes = response.read(MAX_RESPONSE_BYTES + 1)
                if len(raw_bytes) > MAX_RESPONSE_BYTES:
                    self._close()
                    raise ApiError("Clockify response exceeded size limit")
                raw = raw_bytes.decode("utf-8", "replace")
            except (OSError, http.client.HTTPException) as error:
                self._close()
                failure = error
                if reused and not is_timeout(error):
                    candidates.insert(0, candidate)
                continue
            self.good_host = candidate[1][0]
            return self._decode(response.status, raw)

        raise ApiError("Clockify did not answer (%s)" % (describe(failure),))

    @staticmethod
    def _decode(status, raw):
        if status >= 400:
            raise ApiError(status_message(status, raw), status)
        if not raw.strip():
            return None
        try:
            return json.loads(raw)
        except ValueError as error:
            raise ApiError("Could not parse the Clockify response") from error


def is_timeout(error):
    return isinstance(error, (TimeoutError, socket.timeout))


def describe(error):
    if error is None:
        return "no route answered"
    if is_timeout(error):
        return "timed out after %ds" % TIMEOUT
    return str(error) or error.__class__.__name__


def status_message(status, raw):
    detail = ""
    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            detail = str(parsed.get("message") or "").strip()
    except ValueError:
        detail = ""
    if status == 401:
        return detail or "Clockify rejected credentials"
    if status == 403:
        return detail or "Clockify denied the request"
    if status == 404:
        return detail or "Clockify resource not found"
    if status == 429:
        return "Clockify rate limit reached, try again in a moment"
    return detail or ("Clockify returned HTTP %d" % status)


# --------------------------------------------------------------------- time

def now_utc():
    return datetime.now(timezone.utc)


def utc_stamp(moment):
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_stamp(value):
    text = str(value or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        moment = datetime.fromisoformat(text)
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)


def local_midnight(moment):
    return moment.astimezone().replace(hour=0, minute=0, second=0, microsecond=0)


def week_start(moment, first_day):
    today = local_midnight(moment)
    weekday = today.weekday()
    offset = (weekday + 1) % 7 if str(first_day).lower() == "sunday" else weekday
    return today - timedelta(days=offset)


def parse_user_datetime(value, date_hint="", fallback_dt=None):
    """Parse ISO-8601 or HH:MM[:SS] (with optional date_hint) into UTC datetime."""
    text = str(value or "").strip()
    if not text:
        raise ApiError("Time value cannot be empty")
    if "T" in text or len(text) > 8:
        parsed = parse_stamp(text)
        if parsed is None:
            raise ApiError("Invalid date/time format: %s" % text)
        return parsed.astimezone(timezone.utc)

    m = re.fullmatch(r"(\d{1,2}):(\d{2})(?::(\d{2}))?", text)
    if not m:
        raise ApiError("Time must be HH:MM (24h), got: %s" % text)
    hh, mm, ss = int(m.group(1)), int(m.group(2)), int(m.group(3) or 0)
    if not (0 <= hh <= 23 and 0 <= mm <= 59 and 0 <= ss <= 59):
        raise ApiError("Invalid clock time: %s" % text)

    local_now = datetime.now().astimezone()
    hint = str(date_hint or "").strip().lower()
    if not hint or hint == "today":
        base_date = fallback_dt.astimezone().date() if fallback_dt else local_now.date()
    elif hint == "yesterday":
        base_date = local_now.date() - timedelta(days=1)
    else:
        try:
            base_date = datetime.strptime(hint, "%Y-%m-%d").date()
        except ValueError as exc:
            raise ApiError("Date must be today, yesterday, or YYYY-MM-DD") from exc

    local_dt = datetime(base_date.year, base_date.month, base_date.day, hh, mm, ss, tzinfo=local_now.tzinfo)
    return local_dt.astimezone(timezone.utc)


def friendly_date_label(local_dt, today_date):
    d = local_dt.date()
    if d == today_date:
        return "Today"
    if d == today_date - timedelta(days=1):
        return "Yesterday"
    return local_dt.strftime("%a, %d %b")


# ------------------------------------------------------------------ reading

def identity(config, api):
    user = api.call("GET", "/user") or {}
    user_id = str(user.get("id") or "")
    workspace_id = str(
        config.get("workspaceId")
        or user.get("activeWorkspace")
        or user.get("defaultWorkspace")
        or ""
    )
    if not user_id or not workspace_id:
        raise ApiError("Clockify did not return a user and workspace")
    return Identity(
        user_id,
        workspace_id,
        str(user.get("name") or user.get("email") or ""),
        str(user.get("email") or ""),
    )


def fetch_workspaces(api):
    out = []
    for ws in api.call("GET", "/workspaces") or []:
        ws_id = str(ws.get("id") or "")
        if ws_id:
            out.append({"id": ws_id, "name": str(ws.get("name") or "Workspace")})
    return out


def fetch_projects_with_tasks(workspace_id, api):
    projects = []
    for page in range(1, PAGE_LIMIT + 1):
        batch = api.call(
            "GET",
            "/workspaces/%s/projects" % workspace_id,
            params={"archived": "false", "page-size": PAGE_SIZE, "page": page},
        ) or []
        for project in batch:
            projects.append({
                "id": str(project.get("id") or ""),
                "name": str(project.get("name") or ""),
                "color": str(project.get("color") or ""),
                "clientId": str(project.get("clientId") or ""),
                "clientName": str(project.get("clientName") or ""),
                "billable": bool(project.get("billable")),
                "public": bool(project.get("public")),
                "tasks": [],
            })
        if len(batch) < PAGE_SIZE:
            break
    projects.sort(key=lambda p: p["name"].lower())

    for project in projects[:MAX_TASK_PROJECTS]:
        if not project["id"]:
            continue
        try:
            tasks_raw = api.call(
                "GET",
                "/workspaces/%s/projects/%s/tasks" % (workspace_id, project["id"]),
                params={"is-active": "true", "page-size": PAGE_SIZE},
            ) or []
            tasks = []
            for t in tasks_raw:
                tid = str(t.get("id") or "")
                if tid:
                    tasks.append({
                        "id": tid,
                        "name": str(t.get("name") or ""),
                        "status": str(t.get("status") or "ACTIVE"),
                        "billable": bool(t.get("billable")),
                    })
            tasks.sort(key=lambda t: t["name"].lower())
            project["tasks"] = tasks
        except ApiError:
            project["tasks"] = []
    return projects


def fetch_tags(workspace_id, api):
    tags = []
    try:
        batch = api.call(
            "GET",
            "/workspaces/%s/tags" % workspace_id,
            params={"archived": "false", "page-size": PAGE_SIZE},
        ) or []
        for tag in batch:
            tid = str(tag.get("id") or "")
            if tid:
                tags.append({"id": tid, "name": str(tag.get("name") or "")})
    except ApiError:
        pass
    tags.sort(key=lambda t: t["name"].lower())
    return tags


def fetch_clients(workspace_id, api):
    clients = []
    try:
        batch = api.call(
            "GET",
            "/workspaces/%s/clients" % workspace_id,
            params={"archived": "false", "page-size": PAGE_SIZE},
        ) or []
        for client in batch:
            cid = str(client.get("id") or "")
            if cid:
                clients.append({"id": cid, "name": str(client.get("name") or "")})
    except ApiError:
        pass
    clients.sort(key=lambda c: c["name"].lower())
    return clients


def time_entries(ident, api, params):
    query = {"hydrated": "true"}
    query.update(params)
    return api.call(
        "GET",
        "/workspaces/%s/user/%s/time-entries" % (ident.workspace_id, ident.user_id),
        params=query,
    ) or []


def entry_view(entry, projects_by_id, today_date=None):
    if today_date is None:
        today_date = datetime.now().astimezone().date()
    interval = entry.get("timeInterval") or {}
    start = parse_stamp(interval.get("start"))
    end = parse_stamp(interval.get("end"))
    project = entry.get("project") if isinstance(entry.get("project"), dict) else {}
    project_id = str(entry.get("projectId") or project.get("id") or "")
    known = projects_by_id.get(project_id) or {}

    task = entry.get("task") if isinstance(entry.get("task"), dict) else {}
    task_id = str(entry.get("taskId") or task.get("id") or "")
    task_name = str(task.get("name") or "")
    if not task_name and task_id and known.get("tasks"):
        for kt in known["tasks"]:
            if kt.get("id") == task_id:
                task_name = str(kt.get("name") or "")
                break

    tags_raw = entry.get("tags") if isinstance(entry.get("tags"), list) else []
    tag_ids = [str(tid) for tid in (entry.get("tagIds") or []) if tid]
    tag_names = [str(t.get("name") or "") for t in tags_raw if isinstance(t, dict) and t.get("name")]
    if not tag_ids and tags_raw:
        tag_ids = [str(t.get("id") or "") for t in tags_raw if isinstance(t, dict) and t.get("id")]

    start_local = ""
    end_local = ""
    date_iso = ""
    date_label = ""
    if start:
        ls = start.astimezone()
        start_local = ls.strftime("%H:%M")
        date_iso = ls.strftime("%Y-%m-%d")
        date_label = friendly_date_label(ls, today_date)
    if end:
        end_local = end.astimezone().strftime("%H:%M")

    return {
        "id": str(entry.get("id") or ""),
        "description": str(entry.get("description") or "").strip(),
        "projectId": project_id,
        "projectName": str(project.get("name") or known.get("name") or ""),
        "projectColor": str(project.get("color") or known.get("color") or ""),
        "clientName": str(project.get("clientName") or known.get("clientName") or ""),
        "taskId": task_id,
        "taskName": task_name,
        "tagIds": tag_ids,
        "tagNames": tag_names,
        "billable": bool(entry.get("billable")),
        "isLocked": bool(entry.get("isLocked")),
        "start": str(interval.get("start") or ""),
        "end": str(interval.get("end") or ""),
        "startLocal": start_local,
        "endLocal": end_local,
        "dateIso": date_iso,
        "dateLabel": date_label,
        "seconds": max(0, int((end - start).total_seconds())) if start and end else 0,
        "running": start is not None and end is None,
    }


def _bool_pref(config, key, default=False):
    val = config.get(key)
    return bool(default if val is None else val)


def _int_pref(config, key, default, lo, hi):
    try:
        val = int(config.get(key, default))
    except (TypeError, ValueError):
        val = default
    return max(lo, min(hi, val))


def base_payload():
    return {
        "ok": True,
        "configured": False,
        "authSource": "",
        "error": "",
        "note": "",
        "userId": "",
        "userName": "",
        "userEmail": "",
        "workspaceId": "",
        "workspaceName": "",
        "workspaces": [],
        "defaultProjectId": "",
        "defaultTaskId": "",
        "defaultTagIds": [],
        "defaultBillable": False,
        "weekStart": "monday",
        "pomodoroEnabled": False,
        "pomodoroWorkMin": 25,
        "pomodoroBreakMin": 5,
        "stopOnIdle": False,
        "idleStopMin": 240,
        "remindWhenIdle": False,
        "idleRemindMin": 30,
        "running": None,
        "recentEntries": [],
        "todaySeconds": 0,
        "weekSeconds": 0,
        "monthSeconds": 0,
        "todayBillableSeconds": 0,
        "weekBillableSeconds": 0,
        "monthBillableSeconds": 0,
        "loadedStartDate": "",
        "loadedEndDate": "",
        "rangeOnly": False,
        "exportPath": "",
        "projects": [],
        "tags": [],
        "clients": [],
        "fullLoaded": False,
        "fetchedAt": "",
    }


def _apply_prefs_to_payload(payload, config):
    payload.update({
        "defaultProjectId": str(config.get("defaultProjectId") or ""),
        "defaultTaskId": str(config.get("defaultTaskId") or ""),
        "defaultTagIds": [str(t) for t in (config.get("defaultTagIds") or []) if t],
        "defaultBillable": _bool_pref(config, "defaultBillable", False),
        "weekStart": str(config.get("weekStart") or "monday"),
        "pomodoroEnabled": _bool_pref(config, "pomodoroEnabled", False),
        "pomodoroWorkMin": _int_pref(config, "pomodoroWorkMin", 25, 1, 180),
        "pomodoroBreakMin": _int_pref(config, "pomodoroBreakMin", 5, 1, 60),
        "stopOnIdle": _bool_pref(config, "stopOnIdle", False),
        "idleStopMin": _int_pref(config, "idleStopMin", 240, 5, 1440),
        "remindWhenIdle": _bool_pref(config, "remindWhenIdle", False),
        "idleRemindMin": _int_pref(config, "idleRemindMin", 30, 5, 480),
    })


def _parse_local_date(date_str):
    text = str(date_str or "").strip()
    if not text:
        return None
    try:
        return datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError as exc:
        raise ApiError("Date must be YYYY-MM-DD, got: %s" % text) from exc


def _format_hms(seconds):
    total = max(0, int(seconds or 0))
    return "%d:%02d:%02d" % (total // 3600, (total % 3600) // 60, total % 60)


def snapshot(config, api, ident, full=False, auth_source="", start_date="", end_date=""):
    workspaces = fetch_workspaces(api) if full else []
    projects = fetch_projects_with_tasks(ident.workspace_id, api) if full else []
    tags = fetch_tags(ident.workspace_id, api) if full else []
    clients = fetch_clients(ident.workspace_id, api) if full else []
    projects_by_id = {p["id"]: p for p in projects}

    local_tz = datetime.now().astimezone().tzinfo
    today_date = datetime.now().astimezone().date()
    running_entries = time_entries(ident, api, {"in-progress": "true"})
    running = entry_view(running_entries[0], projects_by_id, today_date) if running_entries else None

    first_day = str(config.get("weekStart") or "monday")
    moment = now_utc()
    week_floor = week_start(moment, first_day)
    month_floor = local_midnight(moment).replace(day=1)

    req_start = _parse_local_date(start_date) if str(start_date or "").strip() else None
    req_end = _parse_local_date(end_date) if str(end_date or "").strip() else None
    is_custom_range = req_start is not None or req_end is not None

    if req_start is not None:
        history_floor = datetime(req_start.year, req_start.month, req_start.day, 0, 0, 0, tzinfo=local_tz).astimezone(timezone.utc)
    else:
        history_floor = min(week_floor, month_floor, local_midnight(moment) - timedelta(days=MAX_ENTRY_DAYS))

    if req_end is not None:
        end_local_dt = datetime(req_end.year, req_end.month, req_end.day, 23, 59, 59, tzinfo=local_tz).astimezone(timezone.utc)
        # Pad +2 days to work around Clockify's zoned end-filter quirk in UTC+ timezones.
        query_end = end_local_dt + timedelta(days=2)
    else:
        query_end = moment + timedelta(days=2)

    max_pages = 6 if is_custom_range else 4
    raw_window = []
    for page in range(1, max_pages):
        batch = time_entries(ident, api, {
            "start": utc_stamp(history_floor),
            "end": utc_stamp(query_end),
            "page-size": PAGE_SIZE,
            "page": page,
        })
        raw_window.extend(batch)
        if len(batch) < PAGE_SIZE:
            break

    entries = [entry_view(e, projects_by_id, today_date) for e in raw_window]
    finished = [e for e in entries if not e["running"]]

    if req_start is not None:
        s_iso = req_start.strftime("%Y-%m-%d")
        finished = [e for e in finished if e["dateIso"] >= s_iso]
    if req_end is not None:
        e_iso = req_end.strftime("%Y-%m-%d")
        finished = [e for e in finished if e["dateIso"] <= e_iso]

    today_floor_dt = local_midnight(moment).astimezone(timezone.utc)
    week_floor_dt = week_floor.astimezone(timezone.utc)
    month_floor_dt = month_floor.astimezone(timezone.utc)

    def _entry_after(entry, floor_dt):
        st = parse_stamp(entry.get("start"))
        return st is not None and st >= floor_dt

    today_entries = [e for e in finished if _entry_after(e, today_floor_dt)]
    week_entries = [e for e in finished if _entry_after(e, week_floor_dt)]
    month_entries = [e for e in finished if _entry_after(e, month_floor_dt)]

    workspace_name = ""
    for ws in workspaces:
        if ws["id"] == ident.workspace_id:
            workspace_name = ws["name"]
            break

    loaded_start = req_start.strftime("%Y-%m-%d") if req_start else history_floor.astimezone().strftime("%Y-%m-%d")
    loaded_end = req_end.strftime("%Y-%m-%d") if req_end else today_date.strftime("%Y-%m-%d")

    payload = base_payload()
    _apply_prefs_to_payload(payload, config)
    payload.update({
        "configured": True,
        "authSource": auth_source,
        "userId": ident.user_id,
        "userName": ident.user_name,
        "userEmail": ident.user_email,
        "workspaceId": ident.workspace_id,
        "workspaceName": workspace_name,
        "workspaces": workspaces,
        "running": running,
        "recentEntries": finished[:MAX_RECENT_ENTRIES],
        "todaySeconds": sum(e["seconds"] for e in today_entries),
        "weekSeconds": sum(e["seconds"] for e in week_entries),
        "monthSeconds": sum(e["seconds"] for e in month_entries),
        "todayBillableSeconds": sum(e["seconds"] for e in today_entries if e["billable"]),
        "weekBillableSeconds": sum(e["seconds"] for e in week_entries if e["billable"]),
        "monthBillableSeconds": sum(e["seconds"] for e in month_entries if e["billable"]),
        "loadedStartDate": loaded_start,
        "loadedEndDate": loaded_end,
        "rangeOnly": is_custom_range,
        "projects": projects,
        "tags": tags,
        "clients": clients,
        "fullLoaded": bool(full),
        "fetchedAt": utc_stamp(moment),
    })
    return payload


def stop_running(ident, api):
    try:
        api.call(
            "PATCH",
            "/workspaces/%s/user/%s/time-entries" % (ident.workspace_id, ident.user_id),
            body={"end": utc_stamp(now_utc())},
        )
    except ApiError as error:
        if error.code == 404:
            return False
        raise
    return True


def _parse_tag_csv(raw):
    if raw is None:
        return None
    text = str(raw).strip()
    if text == "":
        return []
    return [part.strip() for part in text.split(",") if part.strip()]


# ---------------------------------------------------------------- commands

def open_client(config):
    cred, header, source = resolve_auth(config)
    if not cred:
        return None, None, ""
    api = Api(cred, header, str(config.get("apiHost") or ""), auth_source=source, config=config)
    return api, identity(config, api), source


def remember_host(config, api):
    host = str(api.good_host or "")
    if host and host != str(config.get("apiHost") or ""):
        config["apiHost"] = host
        save_config(config)


def unconfigured(config, note=""):
    payload = base_payload()
    _apply_prefs_to_payload(payload, config)
    payload["note"] = note
    return payload


def cmd_status(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    payload = snapshot(
        config,
        api,
        ident,
        full=args.full,
        auth_source=source,
        start_date=getattr(args, "start_date", "") or "",
        end_date=getattr(args, "end_date", "") or "",
    )
    remember_host(config, api)
    return payload


def _csv_safe(value):
    text = str(value if value is not None else "")
    if text and text[0] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + text
    return text


def cmd_export_csv(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)

    start_date = str(getattr(args, "start_date", "") or "").strip()
    end_date = str(getattr(args, "end_date", "") or "").strip()
    snap = snapshot(config, api, ident, full=False, auth_source=source, start_date=start_date, end_date=end_date)
    entries = list(snap.get("recentEntries") or [])

    proj_filter = str(getattr(args, "project", "") or "").strip()
    task_filter = str(getattr(args, "task", "") or "").strip()
    tag_filter = str(getattr(args, "tag", "") or "").strip()
    bill_filter = str(getattr(args, "billable", "all") or "all").strip().lower()
    query_filter = str(getattr(args, "query", "") or "").strip().lower()

    filtered = []
    for e in entries:
        if proj_filter and e.get("projectId") != proj_filter:
            continue
        if task_filter and e.get("taskId") != task_filter:
            continue
        if tag_filter and tag_filter not in (e.get("tagIds") or []):
            continue
        if bill_filter == "billable" and not e.get("billable"):
            continue
        if bill_filter == "non-billable" and e.get("billable"):
            continue
        if query_filter:
            hay = " ".join([
                str(e.get("description") or ""),
                str(e.get("projectName") or ""),
                str(e.get("clientName") or ""),
                str(e.get("taskName") or ""),
                " ".join(e.get("tagNames") or []),
                str(e.get("dateLabel") or ""),
            ]).lower()
            if query_filter not in hay:
                continue
        filtered.append(e)

    s_lbl = re.sub(r"[^A-Za-z0-9._-]", "_", str(start_date or snap.get("loadedStartDate") or "start"))
    e_lbl = re.sub(r"[^A-Za-z0-9._-]", "_", str(end_date or snap.get("loadedEndDate") or "today"))
    out_raw = str(getattr(args, "output", "") or "").strip()
    if out_raw:
        out_path = Path(out_raw).expanduser()
    else:
        out_path = Path.home() / "Downloads" / ("clockify-report-%s_to_%s.csv" % (s_lbl, e_lbl))
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with open(out_path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["Date", "Start", "End", "Duration", "Seconds", "Description", "Project", "Client", "Task", "Tags", "Billable"])
        for e in filtered:
            writer.writerow([
                _csv_safe(e.get("dateIso", "")),
                _csv_safe(e.get("startLocal", "")),
                _csv_safe(e.get("endLocal", "")),
                _csv_safe(_format_hms(e.get("seconds", 0))),
                int(e.get("seconds", 0)),
                _csv_safe(e.get("description", "")),
                _csv_safe(e.get("projectName", "")),
                _csv_safe(e.get("clientName", "")),
                _csv_safe(e.get("taskName", "")),
                _csv_safe(", ".join(e.get("tagNames") or [])),
                "Yes" if e.get("billable") else "No",
            ])

    payload = base_payload()
    _apply_prefs_to_payload(payload, config)
    payload.update({
        "configured": True,
        "authSource": source,
        "userId": ident.user_id,
        "userName": ident.user_name,
        "workspaceId": ident.workspace_id,
        "rangeOnly": True,
        "exportPath": str(out_path),
        "note": "Exported %d entries to %s" % (len(filtered), out_path.name),
    })
    remember_host(config, api)
    return payload


def cmd_start(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    stop_running(ident, api)

    start_dt = parse_user_datetime(args.start) if args.start else now_utc()
    body = {"start": utc_stamp(start_dt)}
    description = str(args.description or "").strip()
    if description:
        body["description"] = description

    project_id = str(config.get("defaultProjectId") or "") if args.project is None else str(args.project).strip()
    if project_id:
        body["projectId"] = project_id
        task_id = str(config.get("defaultTaskId") or "") if args.task is None else str(args.task).strip()
        if task_id:
            body["taskId"] = task_id

    tag_ids = _parse_tag_csv(args.tags)
    if tag_ids is None:
        tag_ids = [str(t) for t in (config.get("defaultTagIds") or []) if t]
    if tag_ids:
        body["tagIds"] = tag_ids

    if args.billable is not None:
        body["billable"] = bool(args.billable)
    elif _bool_pref(config, "defaultBillable", False):
        body["billable"] = True

    api.call("POST", "/workspaces/%s/time-entries" % ident.workspace_id, body=body)

    changed = False
    if args.project is not None and project_id != str(config.get("defaultProjectId") or ""):
        config["defaultProjectId"] = project_id
        if not project_id:
            config["defaultTaskId"] = ""
        changed = True
    if args.task is not None:
        tid = str(args.task).strip() if project_id else ""
        if tid != str(config.get("defaultTaskId") or ""):
            config["defaultTaskId"] = tid
            changed = True
    if changed:
        save_config(config)

    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Timer started"
    remember_host(config, api)
    return payload


def cmd_stop(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    stopped = stop_running(ident, api)
    payload = snapshot(config, api, ident, auth_source=source)
    if stopped:
        payload["note"] = "Timer stopped"
    else:
        payload["error"] = "No timer is running"
    remember_host(config, api)
    return payload


def cmd_discard(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    running_entries = time_entries(ident, api, {"in-progress": "true"})
    if not running_entries:
        payload = snapshot(config, api, ident, auth_source=source)
        payload["error"] = "No timer is running"
        return payload
    entry_id = str(running_entries[0].get("id") or "")
    api.call("DELETE", "/workspaces/%s/time-entries/%s" % (ident.workspace_id, entry_id))
    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Running timer discarded"
    remember_host(config, api)
    return payload


def _build_entry_put_body(existing, args, keep_running=False):
    interval = existing.get("timeInterval") or {}
    orig_start = parse_stamp(interval.get("start"))
    orig_end = parse_stamp(interval.get("end"))

    if args.start is not None and str(args.start).strip() != "":
        date_hint = getattr(args, "date", "") or ""
        new_start = parse_user_datetime(args.start, date_hint=date_hint, fallback_dt=orig_start)
    else:
        new_start = orig_start

    adjust = getattr(args, "adjust_minutes", 0) or 0
    if adjust != 0 and new_start is not None:
        # Positive adjust adds elapsed minutes (moves start earlier).
        new_start = new_start - timedelta(minutes=adjust)
        now = now_utc()
        if keep_running and new_start >= now:
            new_start = now - timedelta(seconds=1)

    body = {
        "start": utc_stamp(new_start),
        "description": str(existing.get("description") or "") if args.description is None else str(args.description).strip(),
    }
    if args.billable is not None and bool(args.billable) != bool(existing.get("billable")):
        body["billable"] = bool(args.billable)

    if not keep_running:
        if getattr(args, "end", None):
            date_hint = getattr(args, "date", "") or ""
            new_end = parse_user_datetime(args.end, date_hint=date_hint, fallback_dt=orig_end or new_start)
            if new_end <= new_start and str(args.end).strip().startswith("00:"):
                new_end += timedelta(days=1)
        else:
            new_end = orig_end
        if new_end is not None:
            if new_end <= new_start:
                raise ApiError("End time must be after start time")
            body["end"] = utc_stamp(new_end)

    project_id = str(existing.get("projectId") or "") if args.project is None else str(args.project).strip()
    if project_id:
        body["projectId"] = project_id
        task_id = str(existing.get("taskId") or "") if args.task is None else str(args.task).strip()
        if task_id:
            body["taskId"] = task_id

    parsed_tags = _parse_tag_csv(args.tags)
    tag_ids = [str(t) for t in (existing.get("tagIds") or []) if t] if parsed_tags is None else parsed_tags
    body["tagIds"] = tag_ids
    return body


def cmd_update_running(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    running_entries = time_entries(ident, api, {"in-progress": "true"})
    if not running_entries:
        payload = snapshot(config, api, ident, auth_source=source)
        payload["error"] = "No timer is running"
        return payload
    existing = running_entries[0]
    entry_id = str(existing.get("id") or "")
    body = _build_entry_put_body(existing, args, keep_running=True)
    api.call("PUT", "/workspaces/%s/time-entries/%s" % (ident.workspace_id, entry_id), body=body)
    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Running timer updated"
    remember_host(config, api)
    return payload


def cmd_add_manual(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    start_dt = parse_user_datetime(args.start, date_hint=args.date)
    end_dt = parse_user_datetime(args.end, date_hint=args.date)
    if end_dt <= start_dt and str(args.end).strip().startswith("00:"):
        end_dt += timedelta(days=1)
    if end_dt <= start_dt:
        raise ApiError("End time must be after start time")

    body = {
        "start": utc_stamp(start_dt),
        "end": utc_stamp(end_dt),
        "description": str(args.description or "").strip(),
        "billable": bool(args.billable) if args.billable is not None else _bool_pref(config, "defaultBillable", False),
    }
    project_id = str(args.project or "").strip()
    if project_id:
        body["projectId"] = project_id
        task_id = str(args.task or "").strip()
        if task_id:
            body["taskId"] = task_id
    tag_ids = _parse_tag_csv(args.tags)
    if tag_ids:
        body["tagIds"] = tag_ids

    api.call("POST", "/workspaces/%s/time-entries" % ident.workspace_id, body=body)
    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Manual entry logged"
    remember_host(config, api)
    return payload


def cmd_continue_entry(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    existing = api.call("GET", "/workspaces/%s/time-entries/%s" % (ident.workspace_id, args.id)) or {}
    stop_running(ident, api)
    body = {
        "start": utc_stamp(now_utc()),
        "description": str(existing.get("description") or "").strip(),
        "billable": bool(existing.get("billable")),
    }
    project_id = str(existing.get("projectId") or "")
    if project_id:
        body["projectId"] = project_id
        task_id = str(existing.get("taskId") or "")
        if task_id:
            body["taskId"] = task_id
    tag_ids = [str(t) for t in (existing.get("tagIds") or []) if t]
    if tag_ids:
        body["tagIds"] = tag_ids

    api.call("POST", "/workspaces/%s/time-entries" % ident.workspace_id, body=body)
    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Continued time entry"
    remember_host(config, api)
    return payload


def cmd_duplicate_entry(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    try:
        api.call("POST", "/workspaces/%s/user/%s/time-entries/%s/duplicate" % (ident.workspace_id, ident.user_id, args.id))
    except ApiError as err:
        if err.code not in (404, 405):
            raise
        existing = api.call("GET", "/workspaces/%s/time-entries/%s" % (ident.workspace_id, args.id)) or {}
        interval = existing.get("timeInterval") or {}
        if not interval.get("start") or not interval.get("end"):
            raise ApiError("Cannot duplicate an entry without start and end times")
        body = {
            "start": interval["start"],
            "end": interval["end"],
            "description": str(existing.get("description") or ""),
            "billable": bool(existing.get("billable")),
        }
        if existing.get("projectId"):
            body["projectId"] = existing["projectId"]
            if existing.get("taskId"):
                body["taskId"] = existing["taskId"]
        if existing.get("tagIds"):
            body["tagIds"] = existing["tagIds"]
        api.call("POST", "/workspaces/%s/time-entries" % ident.workspace_id, body=body)

    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Entry duplicated"
    remember_host(config, api)
    return payload


def cmd_update_entry(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    existing = api.call("GET", "/workspaces/%s/time-entries/%s" % (ident.workspace_id, args.id)) or {}
    body = _build_entry_put_body(existing, args, keep_running=False)
    api.call("PUT", "/workspaces/%s/time-entries/%s" % (ident.workspace_id, args.id), body=body)
    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Entry updated"
    remember_host(config, api)
    return payload


def cmd_delete_entry(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    api.call("DELETE", "/workspaces/%s/time-entries/%s" % (ident.workspace_id, args.id))
    payload = snapshot(config, api, ident, auth_source=source)
    payload["note"] = "Entry deleted"
    remember_host(config, api)
    return payload


def cmd_create_project(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    name = str(args.name or "").strip()
    if not name:
        raise ApiError("Project name cannot be empty")
    body = {
        "name": name,
        "isPublic": bool(args.public),
        "billable": bool(args.billable),
    }
    if args.client:
        body["clientId"] = str(args.client).strip()
    if args.color:
        body["color"] = str(args.color).strip()
    created = api.call("POST", "/workspaces/%s/projects" % ident.workspace_id, body=body) or {}
    if created.get("id"):
        config["defaultProjectId"] = str(created["id"])
        config["defaultTaskId"] = ""
        save_config(config)
    payload = snapshot(config, api, ident, full=True, auth_source=source)
    payload["note"] = "Project created: %s" % name
    remember_host(config, api)
    return payload


def cmd_create_task(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    project_id = str(args.project or "").strip()
    name = str(args.name or "").strip()
    if not project_id:
        raise ApiError("Choose a project first")
    if not name:
        raise ApiError("Task name cannot be empty")
    created = api.call(
        "POST",
        "/workspaces/%s/projects/%s/tasks" % (ident.workspace_id, project_id),
        body={"name": name, "projectId": project_id},
    ) or {}
    if created.get("id"):
        config["defaultProjectId"] = project_id
        config["defaultTaskId"] = str(created["id"])
        save_config(config)
    payload = snapshot(config, api, ident, full=True, auth_source=source)
    payload["note"] = "Task created: %s" % name
    remember_host(config, api)
    return payload


def cmd_create_tag(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    name = str(args.name or "").strip()
    if not name:
        raise ApiError("Tag name cannot be empty")
    api.call("POST", "/workspaces/%s/tags" % ident.workspace_id, body={"name": name})
    payload = snapshot(config, api, ident, full=True, auth_source=source)
    payload["note"] = "Tag created: %s" % name
    remember_host(config, api)
    return payload


def cmd_create_client(args):
    config = load_config()
    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    name = str(args.name or "").strip()
    if not name:
        raise ApiError("Client name cannot be empty")
    api.call("POST", "/workspaces/%s/clients" % ident.workspace_id, body={"name": name})
    payload = snapshot(config, api, ident, full=True, auth_source=source)
    payload["note"] = "Client created: %s" % name
    remember_host(config, api)
    return payload


def cmd_switch_workspace(args):
    config = load_config()
    ws_id = str(args.workspace or "").strip()
    if not ws_id:
        raise ApiError("Workspace id cannot be empty")
    config["workspaceId"] = ws_id
    config["defaultProjectId"] = ""
    config["defaultTaskId"] = ""
    config["defaultTagIds"] = []
    save_config(config)

    api, ident, source = open_client(config)
    if not api:
        return unconfigured(config)
    payload = snapshot(config, api, ident, full=True, auth_source=source)
    payload["note"] = "Workspace switched"
    remember_host(config, api)
    return payload


def cmd_set_key(args):
    key = sys.stdin.readline().strip()
    if not key:
        payload = base_payload()
        payload["ok"] = False
        payload["error"] = "No API key received"
        return payload

    config = load_config()
    api = Api(key, "X-Api-Key", str(config.get("apiHost") or ""), auth_source="api-key", config=config)
    ident = identity({}, api)
    config["apiKey"] = key
    config.pop("useDesktopSession", None)
    config.pop("desktopAccessToken", None)
    config.pop("desktopRefreshToken", None)
    config["workspaceId"] = ident.workspace_id
    save_config(config)

    payload = snapshot(config, api, ident, full=True, auth_source="api-key")
    payload["note"] = "Connected via API key as %s" % (ident.user_name or "Clockify user")
    remember_host(config, api)
    return payload


def cmd_connect_desktop(args):
    tok = _discover_desktop_access_token()
    if not tok:
        raise ApiError("No active Clockify Desktop session found. Sign in to Clockify Desktop first or paste an API key.")

    config = load_config()
    api = Api(tok, "X-Auth-Token", str(config.get("apiHost") or ""), auth_source="desktop-app", config=config)
    ident = identity({}, api)
    config["useDesktopSession"] = True
    config.pop("apiKey", None)
    config.pop("desktopAccessToken", None)
    config.pop("desktopRefreshToken", None)
    config["workspaceId"] = ident.workspace_id
    save_config(config)

    payload = snapshot(config, api, ident, full=True, auth_source="desktop-app")
    payload["note"] = "Connected to Clockify Desktop session"
    remember_host(config, api)
    return payload


def cmd_clear_key(args):
    config = load_config()
    config.pop("apiKey", None)
    config.pop("useDesktopSession", None)
    config.pop("desktopAccessToken", None)
    config.pop("desktopRefreshToken", None)
    save_config(config)
    return unconfigured(config, note="Disconnected")


def _parse_bool_arg(val):
    if val is None:
        return None
    s = str(val).strip().lower()
    if s in ("true", "1", "yes", "on"):
        return True
    if s in ("false", "0", "no", "off"):
        return False
    raise ApiError("Expected boolean value, got: %s" % val)


def cmd_set_config(args):
    config = load_config()
    if args.project is not None:
        config["defaultProjectId"] = str(args.project).strip()
        if not config["defaultProjectId"]:
            config["defaultTaskId"] = ""
    if args.task is not None:
        config["defaultTaskId"] = str(args.task).strip()
    if args.tags is not None:
        config["defaultTagIds"] = _parse_tag_csv(args.tags) or []
    if args.billable is not None:
        config["defaultBillable"] = _parse_bool_arg(args.billable)
    if args.workspace is not None:
        config["workspaceId"] = str(args.workspace).strip()
    if args.week_start is not None:
        config["weekStart"] = str(args.week_start).strip().lower()
    if args.pomodoro is not None:
        config["pomodoroEnabled"] = _parse_bool_arg(args.pomodoro)
    if args.pomodoro_work is not None:
        config["pomodoroWorkMin"] = max(1, min(180, int(args.pomodoro_work)))
    if args.pomodoro_break is not None:
        config["pomodoroBreakMin"] = max(1, min(60, int(args.pomodoro_break)))
    if args.stop_on_idle is not None:
        config["stopOnIdle"] = _parse_bool_arg(args.stop_on_idle)
    if args.idle_stop_min is not None:
        config["idleStopMin"] = max(5, min(1440, int(args.idle_stop_min)))
    if args.remind_when_idle is not None:
        config["remindWhenIdle"] = _parse_bool_arg(args.remind_when_idle)
    if args.idle_remind_min is not None:
        config["idleRemindMin"] = max(5, min(480, int(args.idle_remind_min)))

    save_config(config)
    payload = base_payload()
    _apply_prefs_to_payload(payload, config)
    payload["note"] = "Preferences saved"
    payload["workspaceId"] = str(config.get("workspaceId") or "")
    cred, _, source = resolve_auth(config)
    payload["configured"] = bool(cred)
    payload["authSource"] = source
    return payload


def build_parser():
    parser = argparse.ArgumentParser(description="Clockify Control CLI & Omarchy shell bridge")
    commands = parser.add_subparsers(dest="command", required=True)

    status = commands.add_parser("status", help="current timer, totals, recent entries, and optional workspace metadata")
    status.add_argument("--full", "--projects", dest="full", action="store_true", help="include workspaces, projects, tasks, tags, clients")
    status.add_argument("--start-date", default="", help="optional YYYY-MM-DD start date")
    status.add_argument("--end-date", default="", help="optional YYYY-MM-DD end date")
    status.set_defaults(handler=cmd_status)

    exp = commands.add_parser("export-csv", help="export filtered time entries to CSV")
    exp.add_argument("--start-date", default="")
    exp.add_argument("--end-date", default="")
    exp.add_argument("--project", default="")
    exp.add_argument("--task", default="")
    exp.add_argument("--tag", default="")
    exp.add_argument("--billable", default="all", choices=["all", "billable", "non-billable"])
    exp.add_argument("--query", default="")
    exp.add_argument("--output", default="")
    exp.set_defaults(handler=cmd_export_csv)

    start = commands.add_parser("start", help="stop any running entry and start a new timer")
    start.add_argument("--description", default="")
    start.add_argument("--project", default=None)
    start.add_argument("--task", default=None)
    start.add_argument("--tags", default=None, help="comma-separated tag ids")
    start.add_argument("--start", default=None, help="optional ISO timestamp or HH:MM")
    start.add_argument("--billable", dest="billable", action="store_const", const=True, default=None)
    start.add_argument("--no-billable", dest="billable", action="store_const", const=False)
    start.set_defaults(handler=cmd_start)

    stop = commands.add_parser("stop", help="stop the running entry")
    stop.set_defaults(handler=cmd_stop)

    discard = commands.add_parser("discard", help="delete the currently running entry without saving")
    discard.set_defaults(handler=cmd_discard)

    up_run = commands.add_parser("update-running", help="live-edit the currently running entry")
    up_run.add_argument("--description", default=None)
    up_run.add_argument("--project", default=None)
    up_run.add_argument("--task", default=None)
    up_run.add_argument("--tags", default=None)
    up_run.add_argument("--start", default=None)
    up_run.add_argument("--adjust-minutes", type=int, default=0)
    up_run.add_argument("--billable", dest="billable", action="store_const", const=True, default=None)
    up_run.add_argument("--no-billable", dest="billable", action="store_const", const=False)
    up_run.set_defaults(handler=cmd_update_running)

    manual = commands.add_parser("add-manual", help="add a completed manual time entry")
    manual.add_argument("--start", required=True)
    manual.add_argument("--end", required=True)
    manual.add_argument("--date", default="today", help="today, yesterday, or YYYY-MM-DD")
    manual.add_argument("--description", default="")
    manual.add_argument("--project", default="")
    manual.add_argument("--task", default="")
    manual.add_argument("--tags", default="")
    manual.add_argument("--billable", dest="billable", action="store_const", const=True, default=None)
    manual.add_argument("--no-billable", dest="billable", action="store_const", const=False)
    manual.set_defaults(handler=cmd_add_manual)

    cont = commands.add_parser("continue-entry", help="start a new running timer from an existing entry")
    cont.add_argument("--id", required=True)
    cont.set_defaults(handler=cmd_continue_entry)

    dup = commands.add_parser("duplicate-entry", help="duplicate an existing time entry")
    dup.add_argument("--id", required=True)
    dup.set_defaults(handler=cmd_duplicate_entry)

    up_ent = commands.add_parser("update-entry", help="update an existing time entry")
    up_ent.add_argument("--id", required=True)
    up_ent.add_argument("--description", default=None)
    up_ent.add_argument("--project", default=None)
    up_ent.add_argument("--task", default=None)
    up_ent.add_argument("--tags", default=None)
    up_ent.add_argument("--date", default="")
    up_ent.add_argument("--start", default=None)
    up_ent.add_argument("--end", default=None)
    up_ent.add_argument("--billable", dest="billable", action="store_const", const=True, default=None)
    up_ent.add_argument("--no-billable", dest="billable", action="store_const", const=False)
    up_ent.set_defaults(handler=cmd_update_entry)

    del_ent = commands.add_parser("delete-entry", help="delete a time entry")
    del_ent.add_argument("--id", required=True)
    del_ent.set_defaults(handler=cmd_delete_entry)

    c_proj = commands.add_parser("create-project", help="create a project")
    c_proj.add_argument("--name", required=True)
    c_proj.add_argument("--client", default="")
    c_proj.add_argument("--color", default="#039BE5")
    c_proj.add_argument("--billable", dest="billable", action="store_true", default=True)
    c_proj.add_argument("--no-billable", dest="billable", action="store_false")
    c_proj.add_argument("--public", dest="public", action="store_true", default=True)
    c_proj.add_argument("--private", dest="public", action="store_false")
    c_proj.set_defaults(handler=cmd_create_project)

    c_task = commands.add_parser("create-task", help="create a task on a project")
    c_task.add_argument("--project", required=True)
    c_task.add_argument("--name", required=True)
    c_task.set_defaults(handler=cmd_create_task)

    c_tag = commands.add_parser("create-tag", help="create a workspace tag")
    c_tag.add_argument("--name", required=True)
    c_tag.set_defaults(handler=cmd_create_tag)

    c_client = commands.add_parser("create-client", help="create a workspace client")
    c_client.add_argument("--name", required=True)
    c_client.set_defaults(handler=cmd_create_client)

    sw_ws = commands.add_parser("switch-workspace", help="switch active workspace")
    sw_ws.add_argument("--workspace", required=True)
    sw_ws.set_defaults(handler=cmd_switch_workspace)

    set_key = commands.add_parser("set-key", help="read an API key from stdin and store it")
    set_key.set_defaults(handler=cmd_set_key)

    conn_desk = commands.add_parser("connect-desktop", help="explicitly opt in to read-only Clockify Desktop session")
    conn_desk.set_defaults(handler=cmd_connect_desktop)

    clear_key = commands.add_parser("clear-key", help="disconnect Clockify credentials")
    clear_key.set_defaults(handler=cmd_clear_key)

    set_cfg = commands.add_parser("set-config", help="update local preferences")
    set_cfg.add_argument("--project", default=None)
    set_cfg.add_argument("--task", default=None)
    set_cfg.add_argument("--tags", default=None)
    set_cfg.add_argument("--billable", default=None)
    set_cfg.add_argument("--workspace", default=None)
    set_cfg.add_argument("--week-start", default=None, choices=["monday", "sunday"])
    set_cfg.add_argument("--pomodoro", default=None)
    set_cfg.add_argument("--pomodoro-work", type=int, default=None)
    set_cfg.add_argument("--pomodoro-break", type=int, default=None)
    set_cfg.add_argument("--stop-on-idle", default=None)
    set_cfg.add_argument("--idle-stop-min", type=int, default=None)
    set_cfg.add_argument("--remind-when-idle", default=None)
    set_cfg.add_argument("--idle-remind-min", type=int, default=None)
    set_cfg.set_defaults(handler=cmd_set_config)

    return parser


def main(argv):
    args = build_parser().parse_args(argv)
    try:
        payload = args.handler(args)
    except ApiError as error:
        config = load_config()
        payload = base_payload()
        _apply_prefs_to_payload(payload, config)
        payload["ok"] = False
        payload["error"] = str(error)
        cred, _, source = resolve_auth(config)
        payload["configured"] = bool(cred)
        payload["authSource"] = source
    except Exception as error:
        config = load_config()
        payload = base_payload()
        _apply_prefs_to_payload(payload, config)
        payload["ok"] = False
        payload["error"] = "Clockify helper failed: %s" % (error,)
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
