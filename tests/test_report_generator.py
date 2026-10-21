"""
Tests for report_generator module
"""

import pytest
import json
import os
from pathlib import Path
from datetime import datetime
from utils.report_generator import ReportGenerator


def test_report_generator_initialization(mock_config):
    """Test ReportGenerator initialization"""
    generator = ReportGenerator(mock_config)
    
    assert generator.config == mock_config['reporting']
    assert generator.output_dir == Path(mock_config['reporting']['output_dir'])


def test_generate_json_report(mock_config, tmp_path):
    """Test JSON report generation"""
    # Update config to use tmp_path
    mock_config['reporting']['output_dir'] = str(tmp_path)
    generator = ReportGenerator(mock_config)
    
    # Mock results
    results = {
        'secrets': {'gitleaks': {'findings': [], 'status': 'completed'}},
        'sast': {'semgrep': {'findings': [], 'status': 'completed'}}
    }
    
    metadata = {
        'repo_path': '/test/repo',
        'start_time': datetime.now(),
        'end_time': datetime.now(),
        'duration': 10.5
    }
    
    generator.generate(results, metadata, 'json')
    
    # Check that JSON file was created
    json_files = list(tmp_path.glob('laria_report_*.json'))
    assert len(json_files) == 1
    
    # Verify JSON content
    with open(json_files[0]) as f:
        report = json.load(f)
    
    assert 'metadata' in report
    assert 'summary' in report
    assert 'results' in report
    assert report['metadata']['repository'] == '/test/repo'


def test_generate_markdown_report(mock_config, tmp_path):
    """Test Markdown report generation"""
    mock_config['reporting']['output_dir'] = str(tmp_path)
    generator = ReportGenerator(mock_config)
    
    results = {'secrets': {'gitleaks': {'findings': []}}}
    metadata = {
        'repo_path': '/test/repo',
        'start_time': datetime.now(),
        'end_time': datetime.now(),
        'duration': 10.5
    }
    
    generator.generate(results, metadata, 'markdown')
    
    # Check that Markdown file was created
    md_files = list(tmp_path.glob('laria_report_*.md'))
    assert len(md_files) == 1
    
    # Verify Markdown content
    content = md_files[0].read_text()
    assert '# Laria Security Scan Report' in content
    assert '/test/repo' in content


def test_generate_html_report(mock_config, tmp_path):
    """Test HTML report generation"""
    mock_config['reporting']['output_dir'] = str(tmp_path)
    generator = ReportGenerator(mock_config)
    
    results = {'secrets': {'gitleaks': {'findings': []}}}
    metadata = {
        'repo_path': '/test/repo',
        'start_time': datetime.now(),
        'end_time': datetime.now(),
        'duration': 10.5
    }
    
    generator.generate(results, metadata, 'html')
    
    # Check that HTML file was created
    html_files = list(tmp_path.glob('laria_report_*.html'))
    assert len(html_files) == 1
    
    # Verify HTML content
    content = html_files[0].read_text()
    assert '<!DOCTYPE html>' in content
    assert 'Laria Security Scan Report' in content
    assert '/test/repo' in content


def test_generate_summary(mock_config):
    """Test summary generation"""
    generator = ReportGenerator(mock_config)
    
    results = {
        'secrets': {'findings': [1, 2, 3]},
        'sast': {'findings': [1, 2]}
    }
    
    summary = generator._generate_summary(results)
    
    assert 'secrets' in summary
    assert 'sast' in summary
    assert all(key in summary['secrets'] for key in ['critical', 'high', 'medium', 'low', 'info'])


def test_summary_marks_a_failed_scan(mock_config):
    """#1: a failed scanner's zero counts must not read as a clean result."""
    generator = ReportGenerator(mock_config)
    results = {
        'dependencies': {'trivy': {'status': 'failed', 'error': 'HTTP 429'}},
    }
    summary = generator._generate_summary(results)
    assert summary['dependencies']['status'] == 'failed'
    assert 'status' not in summary['secrets']  # nothing claimed about scans that did not run


def test_markdown_executive_summary_names_the_failed_scan(mock_config, tmp_path):
    """#1: the executive summary distinguishes a failed scan from a clean one."""
    mock_config['reporting']['output_dir'] = str(tmp_path)
    generator = ReportGenerator(mock_config)
    results = {
        'dependencies': {'trivy': {'status': 'failed', 'error': 'Maven repository returned HTTP 429'}},
        'secrets': {'gitleaks': {'findings': [], 'status': 'completed'}},
    }
    metadata = {
        'repo_path': '/test/repo',
        'start_time': datetime.now(),
        'end_time': datetime.now(),
        'duration': 10.5,
    }
    generator.generate(results, metadata, 'markdown')
    content = list(tmp_path.glob('laria_report_*.md'))[0].read_text()
    assert "Scans that did not complete" in content
    assert "results are unavailable, not because nothing was found" in content
    assert "| **Dependencies** | scanner | `failed` |" in content


def test_html_executive_summary_names_the_failed_scan(mock_config, tmp_path):
    """#1: the HTML executive summary distinguishes a failed scan from a clean one."""
    mock_config['reporting']['output_dir'] = str(tmp_path)
    generator = ReportGenerator(mock_config)
    results = {
        'dependencies': {'trivy': {'status': 'failed', 'error': 'Maven repository returned HTTP 429'}},
        'secrets': {'gitleaks': {'findings': [], 'status': 'completed'}},
    }
    metadata = {
        'repo_path': '/test/repo',
        'start_time': datetime.now(),
        'end_time': datetime.now(),
        'duration': 10.5,
    }
    generator.generate(results, metadata, 'html')
    content = list(tmp_path.glob('laria_report_*.html'))[0].read_text()
    assert "Scans that did not complete" in content
    assert "results are unavailable" in content
    assert "dependencies failed scan" not in content  # human words, not a code identifier


def test_a_report_with_both_successful_and_failed_scanners(mock_config, tmp_path):
    """#1: a clean scanner keeps its findings while a failed one is marked."""
    mock_config['reporting']['output_dir'] = str(tmp_path)
    generator = ReportGenerator(mock_config)
    # gitleaks as the raw findings list the summary counts
    results = {
        'dependencies': {'trivy': {'status': 'failed', 'error': 'HTTP 429'}},
        'secrets': {'gitleaks': [{'file': 'a.py', 'line': 1}]},
    }
    metadata = {
        'repo_path': '/test/repo',
        'start_time': datetime.now(),
        'end_time': datetime.now(),
        'duration': 10.5,
    }
    generator.generate(results, metadata, 'json')
    import glob as glob_mod
    report_path = sorted(glob_mod.glob(str(tmp_path / 'laria_report_*.json')))[0]
    report = json.loads(open(report_path).read())
    assert report['summary']['secrets']['high'] == 1
    assert report['summary']['dependencies']['status'] == 'failed'
