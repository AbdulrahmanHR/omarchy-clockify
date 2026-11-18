#!/usr/bin/env python3
"""Unit tests for io.github.abdulrahmanhr.clockify backend and Model.js."""

import base64
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

PLUGIN_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PLUGIN_DIR))

import clockify  # noqa: E402


class ClockifyHelperTests(unittest.TestCase):
    def test_parse_stamp_utc_and_offset(self):
        dt = clockify.parse_stamp("2026-11-17T14:10:53Z")
        self.assertIsNotNone(dt)
        self.assertEqual(dt.year, 2026)
        self.assertEqual(dt.hour, 14)
        self.assertEqual(dt.tzinfo, timezone.utc)

        dt_off = clockify.parse_stamp("2026-11-17T17:10:53+03:00")
        self.assertEqual(dt_off.astimezone(timezone.utc), dt)

    def test_parse_user_datetime_hhmm(self):
        utc_dt = clockify.parse_user_datetime("09:30", date_hint="2026-11-17")
        local_dt = utc_dt.astimezone()
        self.assertEqual(local_dt.strftime("%Y-%m-%d %H:%M"), "2026-11-17 09:30")

    def test_parse_user_datetime_rejects_bad(self):
        with self.assertRaises(clockify.ApiError):
            clockify.parse_user_datetime("25:99", date_hint="today")
        with self.assertRaises(clockify.ApiError):
            clockify.parse_user_datetime("10:00", date_hint="not-a-date")

    def test_parse_local_date(self):
        d = clockify._parse_local_date("2026-11-17")
        self.assertEqual((d.year, d.month, d.day), (2026, 11, 17))
        with self.assertRaises(clockify.ApiError):
            clockify._parse_local_date("2026-99-99")

    def test_snappy_decompress_literal(self):
        compressed = bytes([0x05, 0x10]) + b"hello"
        self.assertEqual(clockify._snappy_decompress(compressed), b"hello")

    def test_decode_jwt_claims(self):
        header = base64.urlsafe_b64encode(b'{"alg":"HS256"}').rstrip(b"=").decode()
        payload = base64.urlsafe_b64encode(
            json.dumps({"type": "access", "iat": 100, "exp": 200}).encode()
        ).rstrip(b"=").decode()
        claims = clockify._decode_jwt_claims(f"{header}.{payload}.sig")
        self.assertEqual(claims["type"], "access")
        self.assertEqual(claims["exp"], 200)

    def test_entry_view_extracts_project_task_tags(self):
        projects_by_id = {
            "p1": {
                "id": "p1",
                "name": "Dev",
                "color": "#039BE5",
                "clientName": "Acme",
                "tasks": [{"id": "t1", "name": "Build"}],
            }
        }
        raw = {
            "id": "e1",
            "description": "Write plugin",
            "projectId": "p1",
            "taskId": "t1",
            "tagIds": ["g1"],
            "tags": [{"id": "g1", "name": "Urgent"}],
            "billable": True,
            "timeInterval": {
                "start": "2026-11-17T10:00:00Z",
                "end": "2026-11-17T11:30:00Z",
            },
        }
        view = clockify.entry_view(raw, projects_by_id, today_date=datetime(2026, 11, 17).date())
        self.assertEqual(view["seconds"], 5400)
        self.assertEqual(view["projectName"], "Dev")
        self.assertEqual(view["taskName"], "Build")
        self.assertEqual(view["tagNames"], ["Urgent"])
        self.assertTrue(view["billable"])
        self.assertFalse(view["running"])

    def test_export_csv_filters_and_writes(self):
        fake_snap = {
            "loadedStartDate": "2026-11-01",
            "loadedEndDate": "2026-11-17",
            "recentEntries": [
                {
                    "id": "e1",
                    "dateIso": "2026-11-17",
                    "startLocal": "09:00",
                    "endLocal": "10:30",
                    "seconds": 5400,
                    "description": "Ship dashboard",
                    "projectId": "p1",
                    "projectName": "Omarchy",
                    "clientName": "",
                    "taskId": "t1",
                    "taskName": "UI",
                    "tagIds": ["g1"],
                    "tagNames": ["Dev"],
                    "billable": True,
                    "dateLabel": "Today",
                },
                {
                    "id": "e2",
                    "dateIso": "2026-11-16",
                    "startLocal": "11:00",
                    "endLocal": "12:00",
                    "seconds": 3600,
                    "description": "Internal sync",
                    "projectId": "p2",
                    "projectName": "Ops",
                    "clientName": "",
                    "taskId": "",
                    "taskName": "",
                    "tagIds": [],
                    "tagNames": [],
                    "billable": False,
                    "dateLabel": "Yesterday",
                },
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            out_csv = Path(tmp) / "report.csv"
            args = clockify.build_parser().parse_args([
                "export-csv",
                "--start-date", "2026-11-01",
                "--end-date", "2026-11-17",
                "--billable", "billable",
                "--output", str(out_csv),
            ])
            ident = clockify.Identity("u1", "w1", "Tester")
            with mock.patch.object(clockify, "load_config", return_value={}), \
                 mock.patch.object(clockify, "open_client", return_value=(mock.MagicMock(), ident, "api-key")), \
                 mock.patch.object(clockify, "snapshot", return_value=fake_snap), \
                 mock.patch.object(clockify, "remember_host"):
                res = clockify.cmd_export_csv(args)

            self.assertTrue(res["ok"])
            self.assertIn("Exported 1 entries", res["note"])
            with open(out_csv, encoding="utf-8") as fh:
                rows = list(csv.reader(fh))
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[1][3], "1:30:00")
            self.assertEqual(rows[1][5], "Ship dashboard")
            self.assertEqual(rows[1][10], "Yes")

    def test_qml_plain_text_and_model_markup_safety(self):
        qml_text = (PLUGIN_DIR / "Panel.qml").read_text(encoding="utf-8")
        text_blocks = list(re.finditer(r"\bText\s*\{", qml_text))
        self.assertGreater(len(text_blocks), 15)
        for m in text_blocks:
            snippet = qml_text[m.start():m.start() + 500]
            self.assertIn("textFormat: Text.PlainText", snippet)

    def test_model_js_dashboard_analytics(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("node not installed")
        model_path = PLUGIN_DIR / "Model.js"
        script = f"""
        const fs = require('fs');
        const vm = require('vm');
        const ctx = {{}};
        vm.createContext(ctx);
        vm.runInContext(fs.readFileSync({json.dumps(str(model_path))}, 'utf8'), ctx);

        const now = new Date(2026, 10, 17, 15, 0, 0); // 2026-11-17
        const weekBounds = ctx.computePeriodBounds('week', 0, 'monday', '', '', now);
        if (weekBounds.startIso !== '2026-11-16' || weekBounds.endIso !== '2026-11-22') {{
          throw new Error('Bad week bounds: ' + JSON.stringify(weekBounds));
        }}
        const monthBounds = ctx.computePeriodBounds('month', 0, 'monday', '', '', now);
        if (monthBounds.startIso !== '2026-11-01' || monthBounds.endIso !== '2026-11-30') {{
          throw new Error('Bad month bounds: ' + JSON.stringify(monthBounds));
        }}

        const entries = [
          {{ id: '1', dateIso: '2026-11-17', dateLabel: 'Today', startLocal: '09:00', seconds: 3600, billable: true, projectId: 'p1', projectName: 'Alpha', projectColor: '#039BE5', taskId: 't1', taskName: 'Build', tagIds: ['g1'], tagNames: ['Code'], description: 'Work A' }},
          {{ id: '2', dateIso: '2026-11-16', dateLabel: 'Yesterday', startLocal: '14:00', seconds: 1800, billable: false, projectId: 'p2', projectName: 'Beta', projectColor: '#009688', taskId: '', taskName: '', tagIds: [], tagNames: [], description: 'Sync' }},
          {{ id: '3', dateIso: '2026-11-02', dateLabel: 'Mon, 02 Nov', startLocal: '10:00', seconds: 7200, billable: true, projectId: 'p1', projectName: 'Alpha', projectColor: '#039BE5', taskId: 't1', taskName: 'Build', tagIds: ['g1'], tagNames: ['Code'], description: 'Earlier' }}
        ];

        const filteredWeek = ctx.filterDashboardEntries(entries, weekBounds, {{ billableMode: 'all' }});
        if (filteredWeek.length !== 2) throw new Error('Expected 2 week entries, got ' + filteredWeek.length);

        const dashWeek = ctx.buildDashboard(filteredWeek, weekBounds, 'week', 'monday', now);
        if (dashWeek.totalSeconds !== 5400 || dashWeek.billableSeconds !== 3600 || dashWeek.billablePercent !== 67) {{
          throw new Error('Unexpected KPIs: ' + JSON.stringify(dashWeek));
        }}
        if (dashWeek.chartBars.length !== 7) throw new Error('Expected 7 week bars');
        if (dashWeek.groupedByDate.length !== 2) throw new Error('Expected 2 date groups');

        const dayBounds = ctx.computePeriodBounds('day', 0, 'monday', '', '', now);
        const dashDay = ctx.buildDashboard([entries[0]], dayBounds, 'day', 'monday', now);
        if (dashDay.chartBars.length !== 8 || dashDay.chartBars[3].seconds !== 3600) {{
          throw new Error('Expected 8 day bars with slot 3 = 3600');
        }}

        const safe = ctx.neutralizeMarkup('<img src="https://x.invalid/a">');
        if (safe.includes('<') || safe.includes('>')) throw new Error('Markup not neutralized');

        // Time/Date stepping, rounding, duration formatting, grouping & weekly timesheet
        if (ctx.stepTimeHhMm('09:00', 5, now) !== '09:05') throw new Error('step +5 failed');
        if (ctx.stepTimeHhMm('00:02', -5, now) !== '23:57') throw new Error('step wrap back failed');
        if (ctx.stepTimeHhMm('23:58', 10, now) !== '00:08') throw new Error('step wrap fwd failed');
        if (ctx.roundTimeHhMm('09:07', 5, now) !== '09:05') throw new Error('round down failed');
        if (ctx.roundTimeHhMm('09:08', 5, now) !== '09:10') throw new Error('round up failed');
        if (ctx.roundTimeHhMm('23:58', 15, now) !== '00:00') throw new Error('round midnight failed');
        if (ctx.stepDateIso('2026-11-18', 1, now) !== '2026-11-19') throw new Error('stepDateIso +1 failed');
        if (ctx.stepDateIso('today', -1, now) !== '2026-11-16') throw new Error('stepDateIso today -1 failed');
        if (ctx.formatDurationByMode(5400, 'compact') !== '1h 30m') throw new Error('compact fmt failed');
        if (ctx.formatDurationByMode(5400, 'full') !== '1:30:00') throw new Error('full fmt failed');
        if (ctx.formatDurationByMode(5400, 'decimal') !== '1.50h') throw new Error('decimal fmt failed');

        const dupEntries = [
          {{ id: 'a1', dateIso: '2026-11-17', dateLabel: 'Today', startLocal: '09:00', endLocal: '09:30', seconds: 1800, billable: true, projectId: 'p1', projectName: 'Alpha', taskId: '', taskName: '', tagIds: [], tagNames: [], description: 'API' }},
          {{ id: 'a2', dateIso: '2026-11-17', dateLabel: 'Today', startLocal: '11:00', endLocal: '12:00', seconds: 3600, billable: true, projectId: 'p1', projectName: 'Alpha', taskId: '', taskName: '', tagIds: [], tagNames: [], description: 'API' }}
        ];
        const grouped = ctx.groupSimilarDayEntries(dupEntries);
        if (grouped.length !== 1 || grouped[0].count !== 2 || grouped[0].totalSeconds !== 5400 || grouped[0].startLocal !== '09:00' || grouped[0].endLocal !== '12:00') {{
          throw new Error('groupSimilarDayEntries failed: ' + JSON.stringify(grouped));
        }}

        const ts = ctx.buildWeeklyTimesheet(entries, [{{ id: 'p1', name: 'Alpha', billable: true }}, {{ id: 'p2', name: 'Beta', billable: false }}], 'monday', 0, now);
        if (ts.days.length !== 7 || ts.grandTotalSeconds !== 5400 || ts.rows.length < 2) {{
          throw new Error('buildWeeklyTimesheet failed: ' + JSON.stringify(ts));
        }}

        // QML sequence-like tag arrays (where Array.isArray() is false) & workspace tag fallback
        const qmlSeq = {{ 0: 't1', 1: 't2', length: 2 }};
        const arr = ctx.toArray(qmlSeq);
        if (!Array.isArray(arr) || arr.length !== 2 || arr[0] !== 't1' || arr[1] !== 't2') {{
          throw new Error('toArray failed on array-like sequence: ' + JSON.stringify(arr));
        }}
        if (ctx.toArray('abc').length !== 0 || ctx.toArray(null).length !== 0) {{
          throw new Error('toArray should return [] for strings/null');
        }}
        const lbl = ctx.tagsLabel(
          {{ tagIds: {{ 0: 'g1', length: 1 }}, tagNames: [] }},
          [{{ id: 'g1', name: 'Translation' }}]
        );
        if (lbl !== 'Translation') {{
          throw new Error('tagsLabel fallback failed: ' + lbl);
        }}
        """
        proc = subprocess.run([node, "-e", script], capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)

    def test_csv_safe_escapes_formula_prefixes(self):
        self.assertEqual(clockify._csv_safe("=CMD()"), "'=CMD()")
        self.assertEqual(clockify._csv_safe("+1+1"), "'+1+1")
        self.assertEqual(clockify._csv_safe("-2+3"), "'-2+3")
        self.assertEqual(clockify._csv_safe("@SUM"), "'@SUM")
        self.assertEqual(clockify._csv_safe("Normal task"), "Normal task")

    def test_set_config_and_time_step_preferences(self):
        fallback_one = clockify.base_payload()
        clockify._apply_prefs_to_payload(fallback_one, {"timeStepMinutes": 1})
        self.assertEqual(fallback_one["timeStepMinutes"], 1)
        self.assertEqual(fallback_one["quickStepMinutes"], 5)

        fallback_fifteen = clockify.base_payload()
        clockify._apply_prefs_to_payload(fallback_fifteen, {"timeStepMinutes": 15})
        self.assertEqual(fallback_fifteen["timeStepMinutes"], 15)
        self.assertEqual(fallback_fifteen["quickStepMinutes"], 1)

        with tempfile.TemporaryDirectory() as tmp:
            xdg = Path(tmp)
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg), "CLOCKIFY_API_KEY": ""}, clear=False):
                args = clockify.build_parser().parse_args([
                    "set-config",
                    "--panel-width", "680",
                    "--panel-height", "820",
                    "--wrap-text", "false",
                    "--time-step-min", "15",
                    "--quick-step-min", "5",
                    "--duration-format", "decimal",
                    "--group-similar", "false",
                    "--pomodoro-auto-timer", "true",
                    "--daily-target-hours", "6.5",
                    "--weekly-target-hours", "32",
                ])
                res = clockify.cmd_set_config(args)
                self.assertTrue(res["ok"])
                self.assertEqual(res["panelWidth"], 680)
                self.assertEqual(res["panelHeight"], 820)
                self.assertFalse(res["wrapText"])
                self.assertEqual(res["timeStepMinutes"], 15)
                self.assertEqual(res["quickStepMinutes"], 5)
                self.assertEqual(res["durationFormat"], "decimal")
                self.assertFalse(res["groupSimilarEntries"])
                self.assertTrue(res["pomodoroAutoTimer"])
                self.assertEqual(res["dailyTargetHours"], 6.5)
                self.assertEqual(res["weeklyTargetHours"], 32.0)

                saved = json.loads((xdg / "omarchy" / "clockify.json").read_text(encoding="utf-8"))
                self.assertEqual(saved["panelWidth"], 680)
                self.assertEqual(saved["panelHeight"], 820)
                self.assertFalse(saved["wrapText"])
                self.assertEqual(saved["timeStepMinutes"], 15)
                self.assertEqual(saved["quickStepMinutes"], 5)
                self.assertEqual(saved["durationFormat"], "decimal")

    def test_split_running_stops_and_starts_continuation(self):
        ident = clockify.Identity("u1", "w1", "Tester")
        running_entry = {
            "id": "run1",
            "description": "Build timesheet",
            "projectId": "p1",
            "taskId": "t1",
            "tagIds": ["g1"],
            "billable": True,
            "timeInterval": {"start": "2026-11-17T08:00:00Z"},
        }
        api = mock.MagicMock()
        api.call.return_value = {"id": "run2", "timeInterval": {"start": "2026-11-17T09:00:00Z"}}
        stopped = {"id": "run1", "timeInterval": {"start": "2026-11-17T08:00:00Z", "end": "2026-11-17T09:00:00Z"}}
        with mock.patch.object(clockify, "load_config", return_value={}), \
             mock.patch.object(clockify, "open_client", return_value=(api, ident, "api-key")), \
             mock.patch.object(clockify, "time_entries", return_value=[running_entry]), \
             mock.patch.object(clockify, "stop_running", return_value=stopped) as mock_stop, \
             mock.patch.object(clockify, "fast_mutation_snapshot", return_value={"ok": True, "configured": True}) as mock_fast, \
             mock.patch.object(clockify, "remember_host"):
            args = clockify.build_parser().parse_args(["split-running", "--minutes-ago", "10"])
            res = clockify.cmd_split_running(args)
        self.assertTrue(res["ok"])
        self.assertEqual(res["note"], "Timer split into new entry")
        mock_stop.assert_called_once()
        api.call.assert_called_once()
        mock_fast.assert_called_once()

    def test_cache_save_and_from_cache_contains_no_secrets(self):
        with tempfile.TemporaryDirectory() as tmp:
            xdg = Path(tmp)
            cfg_file = xdg / "omarchy" / "clockify.json"
            cfg_file.parent.mkdir(parents=True)
            cfg_file.write_text(json.dumps({"apiKey": "super-secret-key", "workspaceId": "w1"}), encoding="utf-8")
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg), "CLOCKIFY_API_KEY": ""}, clear=False):
                clockify.save_cache({
                    "configured": True,
                    "userId": "u1",
                    "userName": "Tester",
                    "workspaceId": "w1",
                    "workspaceName": "Main",
                    "projects": [{"id": "p1", "name": "Alpha", "tasks": []}],
                    "tags": [],
                    "clients": [],
                    "workspaces": [{"id": "w1", "name": "Main"}],
                    "recentEntries": [],
                    "loadedStartDate": "2026-01-01",
                    "loadedEndDate": "2026-11-17",
                    "fullLoaded": True,
                })
                cfile = xdg / "omarchy" / "clockify-cache.json"
                self.assertTrue(cfile.exists())
                self.assertEqual(cfile.stat().st_mode & 0o777, 0o600)
                raw = cfile.read_text(encoding="utf-8")
                self.assertNotIn("super-secret-key", raw)
                self.assertNotIn("apiKey", raw)

                res = clockify.cmd_status(clockify.build_parser().parse_args(["status", "--from-cache"]))
                self.assertTrue(res["ok"])
                self.assertTrue(res["configured"])
                self.assertEqual(res["projects"][0]["name"], "Alpha")


class AuthIsolationTests(unittest.TestCase):
    @staticmethod
    def _make_jwt(typ, exp_offset=3600):
        import time as _time

        header = base64.urlsafe_b64encode(b'{"alg":"HS256"}').rstrip(b"=").decode()
        payload = base64.urlsafe_b64encode(
            json.dumps({
                "type": typ,
                "iat": int(_time.time()),
                "exp": int(_time.time()) + exp_offset,
            }).encode()
        ).rstrip(b"=").decode()
        return f"{header}.{payload}.sig"

    def test_status_does_not_read_desktop_leveldb_without_explicit_opt_in(self):
        with tempfile.TemporaryDirectory() as tmp:
            xdg = Path(tmp)
            ldb_dir = xdg / "Clockify" / "Local Storage" / "leveldb"
            ldb_dir.mkdir(parents=True)
            access_jwt = self._make_jwt("access")
            (ldb_dir / "000001.log").write_text(f'_file://\x00\x01token"{access_jwt}"', encoding="utf-8")

            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg), "CLOCKIFY_API_KEY": ""}, clear=False):
                self.assertEqual(clockify.resolve_auth({}), ("", "", ""))
                res = clockify.cmd_status(clockify.build_parser().parse_args(["status"]))
                self.assertTrue(res["ok"])
                self.assertFalse(res["configured"])
                self.assertEqual(res["authSource"], "")
                # Once explicitly opted in, the active Desktop access token is read in memory.
                cred, hdr, src = clockify.resolve_auth({"useDesktopSession": True})
                self.assertEqual(cred, access_jwt)
                self.assertEqual(hdr, "X-Auth-Token")
                self.assertEqual(src, "desktop-app")

    def test_connect_desktop_opts_in_without_storing_tokens(self):
        with tempfile.TemporaryDirectory() as tmp:
            xdg = Path(tmp)
            ldb_dir = xdg / "Clockify" / "Local Storage" / "leveldb"
            ldb_dir.mkdir(parents=True)
            access_jwt = self._make_jwt("access")
            refresh_jwt = self._make_jwt("refresh", exp_offset=86400)
            (ldb_dir / "000001.log").write_text(
                f'token="{access_jwt}" refreshToken="{refresh_jwt}"',
                encoding="utf-8",
            )
            cfg_file = xdg / "omarchy" / "clockify.json"
            cfg_file.parent.mkdir(parents=True)
            cfg_file.write_text(
                json.dumps({"desktopAccessToken": "legacy", "desktopRefreshToken": "legacy"}),
                encoding="utf-8",
            )

            ident = clockify.Identity("u1", "w1", "Tester")
            fake_snap = {"ok": True, "configured": True, "authSource": "desktop-app"}
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg), "CLOCKIFY_API_KEY": ""}, clear=False), \
                 mock.patch.object(clockify, "Api") as mock_api, \
                 mock.patch.object(clockify, "identity", return_value=ident), \
                 mock.patch.object(clockify, "snapshot", return_value=fake_snap):
                mock_api.return_value.good_host = "1.2.3.4"
                res = clockify.cmd_connect_desktop(clockify.build_parser().parse_args(["connect-desktop"]))

            self.assertTrue(res["configured"])
            saved = json.loads(cfg_file.read_text(encoding="utf-8"))
            self.assertTrue(saved.get("useDesktopSession"))
            self.assertNotIn("desktopAccessToken", saved)
            self.assertNotIn("desktopRefreshToken", saved)
            self.assertNotIn("token", saved)
            self.assertNotIn("apiKey", saved)

    def test_clear_key_disconnects_both_api_key_and_desktop_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            xdg = Path(tmp)
            cfg_file = xdg / "omarchy" / "clockify.json"
            cfg_file.parent.mkdir(parents=True)
            cfg_file.write_text(
                json.dumps({
                    "apiKey": "secret",
                    "useDesktopSession": True,
                    "desktopAccessToken": "legacy",
                    "desktopRefreshToken": "legacy",
                    "weekStart": "monday",
                }),
                encoding="utf-8",
            )
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg), "CLOCKIFY_API_KEY": ""}, clear=False):
                res = clockify.cmd_clear_key(clockify.build_parser().parse_args(["clear-key"]))

            self.assertTrue(res["ok"])
            self.assertFalse(res["configured"])
            saved = json.loads(cfg_file.read_text(encoding="utf-8"))
            self.assertNotIn("apiKey", saved)
            self.assertNotIn("useDesktopSession", saved)
            self.assertNotIn("desktopAccessToken", saved)
            self.assertNotIn("desktopRefreshToken", saved)
            self.assertEqual(saved.get("weekStart"), "monday")

    def test_in_flight_status_cannot_undo_disconnect(self):
        with tempfile.TemporaryDirectory() as tmp:
            xdg = Path(tmp)
            cfg_file = xdg / "omarchy" / "clockify.json"
            cfg_file.parent.mkdir(parents=True)
            cfg_file.write_text(
                json.dumps({"apiKey": "key-user-1", "workspaceId": "w1", "authEpoch": "e1"}),
                encoding="utf-8",
            )
            cache_file = xdg / "omarchy" / "clockify-cache.json"
            ident = clockify.Identity("u1", "w1", "Tester", week_start="sunday")
            api = mock.MagicMock()
            api.credential = "key-user-1"
            api.auth_source = "api-key"
            api.good_host = "1.2.3.4"

            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg), "CLOCKIFY_API_KEY": ""}, clear=False):
                stale_cfg = clockify.load_config()

                def disconnect_mid_flight(*_args, **_kwargs):
                    clockify.cmd_clear_key(clockify.build_parser().parse_args(["clear-key"]))
                    return []

                with mock.patch.object(clockify, "time_entries", side_effect=disconnect_mid_flight):
                    clockify.snapshot(stale_cfg, api, ident, full=False, auth_source="api-key")
                clockify.remember_host(stale_cfg, api)

            saved = json.loads(cfg_file.read_text(encoding="utf-8"))
            self.assertNotIn("apiKey", saved)
            self.assertNotIn("useDesktopSession", saved)
            self.assertNotIn("apiHost", saved)
            self.assertFalse(cache_file.exists())

            # Also verify weekStart / config update is rejected if disconnect happened before snapshot().
            self.assertFalse(
                clockify.update_config_guarded(clockify._auth_signature(stale_cfg), {"weekStart": "monday"})
            )
            saved_after = json.loads(cfg_file.read_text(encoding="utf-8"))
            self.assertEqual(saved_after.get("weekStart"), "sunday")

    def test_cached_history_is_isolated_across_external_credential_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            xdg = Path(tmp)
            cfg_file = xdg / "omarchy" / "clockify.json"
            cfg_file.parent.mkdir(parents=True)
            cfg_file.write_text(json.dumps({"apiKey": "key-user-a", "workspaceId": "w1"}), encoding="utf-8")

            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg), "CLOCKIFY_API_KEY": ""}, clear=False):
                clockify.save_cache({
                    "configured": True,
                    "userId": "user-a",
                    "userName": "User A",
                    "workspaceId": "w1",
                    "workspaceName": "Shared WS",
                    "recentEntries": [{
                        "id": "e-a1",
                        "description": "User A secret work",
                        "start": "2026-11-17T08:00:00Z",
                        "end": "2026-11-17T09:00:00Z",
                        "seconds": 3600,
                        "dateIso": "2026-11-17",
                    }],
                    "loadedStartDate": "2026-11-01",
                    "loadedEndDate": "2026-11-17",
                    "fullLoaded": True,
                })

                # Externally switch credential to User B in the same workspace w1.
                cfg_file.write_text(json.dumps({"apiKey": "key-user-b", "workspaceId": "w1"}), encoding="utf-8")

                # 1. Startup cache path must not serve User A's cache.
                self.assertIsNone(clockify._payload_from_cache(clockify.load_config(), "api-key"))

                # 2. fast_identity must not reuse User A's userId.
                api_b = mock.MagicMock()
                api_b.credential = "key-user-b"
                api_b.auth_source = "api-key"
                ident_b = clockify.Identity("user-b", "w1", "User B")
                with mock.patch.object(clockify, "identity", return_value=ident_b) as mock_id:
                    resolved = clockify.fast_identity(clockify.load_config(), api_b, force_network=False)
                mock_id.assert_called_once()
                self.assertEqual(resolved.user_id, "user-b")

                # 3. snapshot (and export-csv) must not merge User A's cached entries.
                with mock.patch.object(clockify, "time_entries", return_value=[]):
                    snap_b = clockify.snapshot(clockify.load_config(), api_b, ident_b, full=False, auth_source="api-key")
                self.assertEqual(snap_b["recentEntries"], [])

    def test_desktop_session_enforces_read_only_at_api_boundary(self):
        api_ro = clockify.Api("jwt-tok", "X-Auth-Token", auth_source="desktop-app", addresses=[])
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            with self.assertRaises(clockify.ApiError) as ctx:
                api_ro.call(method, "/workspaces/w1/time-entries", body={"start": "2026-11-17T08:00:00Z"})
            self.assertIn("read-only", str(ctx.exception).lower())

    def test_service_qml_clears_prior_account_on_external_account_change(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("node not installed")
        service_path = PLUGIN_DIR / "Service.qml"
        model_path = PLUGIN_DIR / "Model.js"
        script = f"""
        const fs = require('fs');
        const vm = require('vm');
        const qml = fs.readFileSync({json.dumps(str(service_path))}, 'utf8');

        function extractFn(name) {{
          const start = qml.indexOf('function ' + name + '(');
          if (start === -1) throw new Error('Missing function ' + name);
          let depth = 0;
          let inBody = false;
          for (let i = start; i < qml.length; i++) {{
            const ch = qml[i];
            if (ch === '{{') {{ depth++; inBody = true; }}
            else if (ch === '}}') {{
              depth--;
              if (inBody && depth === 0) return qml.slice(start, i + 1);
            }}
          }}
          throw new Error('Unclosed function ' + name);
        }}

        const Model = {{}};
        vm.createContext(Model);
        vm.runInContext(fs.readFileSync({json.dumps(str(model_path))}, 'utf8'), Model);

        const refreshCalls = [];
        const ctx = {{
          Model,
          noteTimer: {{ restart() {{}} }},
          Qt: {{ callLater(fn) {{ fn(); }} }},
          configured: false, authSource: '', userId: '', userName: '', userEmail: '',
          workspaceId: '', workspaceName: '', workspaces: [], projects: [], tags: [], clients: [],
          running: null, recentEntries: [], todaySeconds: 0, weekSeconds: 0, monthSeconds: 0,
          todayBillableSeconds: 0, weekBillableSeconds: 0, monthBillableSeconds: 0,
          loadedStartDate: '', loadedEndDate: '', fetchedAt: '',
          fullLoaded: false, lastFullRefreshMs: 0, _nextIsCacheOnly: false,
          lastError: '', note: '', lastAutoStoppedId: '',
          defaultProjectId: '', defaultTaskId: '', defaultTagIds: [], defaultBillable: false,
          weekStart: 'monday', panelWidth: 560, panelHeight: 740, wrapText: true,
          timeStepMinutes: 5, quickStepMinutes: 1, durationFormat: 'compact',
          groupSimilarEntries: true, pomodoroEnabled: false, pomodoroAutoTimer: true,
          pomodoroWorkMin: 25, pomodoroBreakMin: 5, dailyTargetHours: 8, weeklyTargetHours: 40,
          stopOnIdle: false, idleStopMin: 240, remindWhenIdle: false, idleRemindMin: 30,
          refresh(full) {{ refreshCalls.push(Boolean(full)); }},
        }};
        ctx.root = ctx;
        vm.createContext(ctx);
        vm.runInContext(
          [
            extractFn('applyConfigPayload'),
            extractFn('clearAccountData'),
            extractFn('_identityChanged'),
            extractFn('applyPayload'),
          ].join('\\n'),
          ctx
        );

        const accountA = {{
          ok: true, configured: true, authSource: 'desktop-app',
          userId: 'user-a', userName: 'Alice', userEmail: 'a@example.com',
          workspaceId: 'ws-a', workspaceName: 'Alice WS',
          workspaces: [{{ id: 'ws-a', name: 'Alice WS' }}],
          projects: [{{ id: 'p-a', name: 'Secret A' }}],
          tags: [{{ id: 't-a', name: 'Tag A' }}],
          clients: [{{ id: 'c-a', name: 'Client A' }}],
          recentEntries: [{{ id: 'e-a1', description: 'Alice work', start: '2026-11-18T09:00:00Z' }}],
          fullLoaded: true,
        }};

        // 1. Account A -> external switch to Account B via rangeOnly payload
        ctx.applyPayload(JSON.stringify(accountA));
        ctx.applyPayload(JSON.stringify({{
          ok: true, configured: true, authSource: 'desktop-app',
          userId: 'user-b', userName: 'Bob', userEmail: 'b@example.com',
          workspaceId: 'ws-b', rangeOnly: true, fullLoaded: false,
          recentEntries: [{{ id: 'e-b1', description: 'Bob work', start: '2026-11-18T10:00:00Z' }}],
          loadedStartDate: '2026-11-01', loadedEndDate: '2026-11-18',
        }}));
        if (ctx.recentEntries.length !== 1 || ctx.recentEntries[0].id !== 'e-b1') {{
          throw new Error('rangeOnly leaked prior entries: ' + JSON.stringify(ctx.recentEntries));
        }}
        if (ctx.projects.length || ctx.tags.length || ctx.clients.length || ctx.workspaces.length) {{
          throw new Error('rangeOnly leaked prior metadata');
        }}
        if (ctx.fullLoaded !== false || refreshCalls.pop() !== true) {{
          throw new Error('rangeOnly did not trigger full refresh after account change');
        }}

        // 2. Account A -> external switch to Account B via non-full status refresh
        ctx.applyPayload(JSON.stringify(accountA));
        ctx.applyPayload(JSON.stringify({{
          ok: true, configured: true, authSource: 'desktop-app',
          userId: 'user-b', userName: 'Bob', userEmail: 'b@example.com',
          workspaceId: 'ws-b', rangeOnly: false, fullLoaded: false,
          recentEntries: [{{ id: 'e-b2', description: 'Bob status', start: '2026-11-18T11:00:00Z' }}],
        }}));
        if (ctx.projects.length || ctx.tags.length || ctx.clients.length || ctx.workspaces.length || ctx.workspaceName !== '') {{
          throw new Error('non-full status kept prior metadata');
        }}
        if (ctx.fullLoaded !== false || refreshCalls.pop() !== true) {{
          throw new Error('non-full status did not trigger full refresh after account change');
        }}
        """
        proc = subprocess.run([node, "-e", script], capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)


if __name__ == "__main__":
    unittest.main()
