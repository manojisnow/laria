"""
Tests for report_formatter module — scan status vs clean results (#1)
"""

from utils.report_formatter import ReportFormatter


class TestTrivyScanStatus:
    """A failed scan must never be presented as a clean result (#1)."""

    def test_failed_scan_markdown_says_so(self):
        failed = {"status": "failed", "error": "Maven repository returned HTTP 429"}
        md = ReportFormatter.format_trivy_results_markdown(failed)
        assert "Scan did not complete" in md
        assert "results unavailable" in md
        assert "No vulnerabilities found" not in md
        assert "429" in md  # the error summary is shown

    def test_failed_scan_html_says_so(self):
        failed = {"status": "failed", "error": "Maven repository returned HTTP 429"}
        html = ReportFormatter.format_trivy_results_html(failed)
        assert "Scan did not complete" in html
        assert "results unavailable" in html
        assert "No vulnerabilities found" not in html
        assert "429" in html

    def test_timeout_and_not_installed_are_not_clean_either(self):
        for status in ("timeout", "not_installed", "error", "skipped"):
            for formatter, phrase in (
                (ReportFormatter.format_trivy_results_markdown, "results unavailable"),
                (ReportFormatter.format_trivy_results_html, "results unavailable"),
            ):
                out = formatter({"status": status, "error": "boom"})
                assert phrase in out, status
                assert "No vulnerabilities found" not in out, status

    def test_invalid_results_markdown_is_not_clean(self):
        # No Results and no status: not a scan result, so not "no findings".
        for bad in (None, [], "junk", {}):
            md = ReportFormatter.format_trivy_results_markdown(bad)
            assert "unavailable" in md, bad
            assert "No vulnerabilities found" not in md, bad

    def test_invalid_results_html_is_not_clean(self):
        for bad in (None, [], "junk", {}):
            html = ReportFormatter.format_trivy_results_html(bad)
            assert "unavailable" in html, bad
            assert "No vulnerabilities found" not in html, bad

    def test_successful_clean_scan_still_reads_as_clean(self):
        for clean in (
            {"Results": []},
            {"findings": [], "status": "completed"},
        ):
            md = ReportFormatter.format_trivy_results_markdown(clean)
            html = ReportFormatter.format_trivy_results_html(clean)
            assert "No vulnerabilities found" in md, clean
            assert "No vulnerabilities found" in html, clean

    def test_successful_scan_with_findings_is_unchanged(self):
        data = {"Results": [{"Target": "pom.xml", "Vulnerabilities": [
            {"VulnerabilityID": "CVE-2026-0001", "Severity": "HIGH",
             "PkgName": "log4j", "InstalledVersion": "2.0",
             "FixedVersion": "2.17", "Title": "RCE"},
        ]}]}
        md = ReportFormatter.format_trivy_results_markdown(data)
        html = ReportFormatter.format_trivy_results_html(data)
        assert "CVE-2026-0001" in md and "CVE-2026-0001" in html
        assert "No vulnerabilities found" not in md
