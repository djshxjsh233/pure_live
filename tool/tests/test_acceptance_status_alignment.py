import re
import unittest
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MATRIX = ROOT / "docs" / "ACCEPTANCE_MATRIX_3_1_0.md"
STATUS = ROOT / "docs" / "ACCEPTANCE_STATUS_3_2_0.md"
SITES = ROOT / "lib" / "core" / "sites.dart"


class AcceptanceStatusAlignmentTests(unittest.TestCase):
    def test_numbered_rows_stay_compact(self):
        rows = [
            line
            for line in MATRIX.read_text(encoding="utf-8").splitlines()
            if re.match(r"^\| (?:A|W)\d-\d{2} \|", line)
        ]

        self.assertEqual(len(rows), 62)
        for row in rows:
            row_id = row.split("|", 2)[1].strip()
            with self.subTest(row_id=row_id):
                self.assertLessEqual(
                    len(row),
                    1000,
                    f"{row_id} contains batch history; keep current evidence and remaining closure only",
                )

    def test_status_counts_match_the_numbered_matrix(self):
        matrix = MATRIX.read_text(encoding="utf-8")
        status = STATUS.read_text(encoding="utf-8")
        rows = re.findall(r"^\| ((?:A|W)\d-\d{2}) \| (PASS|RUN|NR) \|", matrix, re.MULTILINE)

        self.assertEqual(len(rows), 62)
        self.assertEqual(len({row_id for row_id, _ in rows}), len(rows))
        for prefix, label in (("A", "Android"), ("W", "Windows"), (None, "合计")):
            selected = [state for row_id, state in rows if prefix is None or row_id.startswith(prefix)]
            counts = Counter(selected)
            expected_row = (
                f"| {label} | {len(selected)} | {counts['PASS']} | "
                f"{counts['RUN']} | {counts['NR']} |"
            )
            self.assertTrue(expected_row in status, f"Missing current matrix row: {expected_row}")

        all_counts = Counter(state for _, state in rows)
        current_sentence = (
            f"当前账本已有 {all_counts['PASS']} 项 PASS、{all_counts['RUN']} 项 RUN、"
            f"{all_counts['NR']} 项 NR"
        )
        self.assertTrue(current_sentence in status, f"Missing current matrix sentence: {current_sentence}")
        current_summary = (
            f"历史大组 {all_counts['PASS']} PASS / {all_counts['RUN']} RUN / {all_counts['NR']} NR"
        )
        self.assertTrue(current_summary in status, f"Missing current state summary: {current_summary}")

    def test_current_platform_totals_follow_the_registry_and_status_head(self):
        sites = SITES.read_text(encoding="utf-8")
        status = STATUS.read_text(encoding="utf-8")
        block_match = re.search(
            r"static const Set<String> supportedSiteIds = \{(?P<body>.*?)\};",
            sites,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(block_match)
        registered = re.findall(r"(\w+Site)", block_match.group("body"))
        self.assertEqual(
            registered,
            ["bilibiliSite", "douyuSite", "huyaSite", "douyinSite", "kuaishouSite"],
        )
        self.assertEqual(len(registered), len(set(registered)))

        expected_summary = f"当前 **{len(registered)} 个直播站点，共 {len(registered)} 个适配器**"
        self.assertTrue(expected_summary in status, f"Missing current platform summary: {expected_summary}")


if __name__ == "__main__":
    unittest.main()
