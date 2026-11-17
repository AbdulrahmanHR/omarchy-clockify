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
        """
        proc = subprocess.run([node, "-e", script], capture_output=True, text=True, check=False)
        self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)


if __name__ == "__main__":
    unittest.main()
