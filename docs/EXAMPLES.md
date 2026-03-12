# Laria Quick Start Examples

## Example 1: Scan a Local Java Project

```bash
# Navigate to your Laria directory
cd /path/to/laria

# Build the Docker image
docker build -t laria:latest .

# Scan a local Java project (repository mounted to same path)
docker run --rm \
  --tmpfs /tmp:rw,exec,size=4g \
  -v /path/to/java-project:/path/to/java-project:ro \
  -v $(pwd)/reports:/laria/reports \
  laria:latest /path/to/java-project

# View the HTML report
open reports/laria_report_*.html
```

## Example 2: Using the Scan Script

The easiest way to scan a repository:

```bash
# Make the script executable
chmod +x scan-repo.sh

# Scan a repository
./scan-repo.sh /path/to/your/repository

# Reports will be in ./reports directory
```

## Example 3: Scan a Remote Repository

```bash
# Scan a GitHub repository
docker run --rm \
  -v $(pwd)/reports:/laria/reports \
  laria:latest https://github.com/OWASP/WebGoat --url

# Reports will be in ./reports directory
```

## Example 4: Custom Configuration

Create a custom config file `my-config.yaml`:

```yaml
build:
  enabled: true
  tool: maven

scanners:
  secrets:
    enabled: true
    tools:
      - gitleaks
  
  sast:
    enabled: true
    tools:
      - semgrep
      - spotbugs
  
  dependencies:
    enabled: true
    tools:
      - trivy
  
  iac:
    enabled: true
    tools:
      - trivy
      - checkov

severity:
  fail_on: CRITICAL
  report_threshold: LOW

reporting:
  formats:
    - json
    - html
    - markdown
```

Run with custom config:

```bash
docker run --rm \
  --tmpfs /tmp:rw,exec,size=4g \
  -v /path/to/project:/path/to/project:ro \
  -v $(pwd)/reports:/laria/reports \
  -v $(pwd)/my-config.yaml:/laria/config.yaml:ro \
  laria:latest /path/to/project --config /laria/config.yaml
```

## Example 5: CI/CD Integration (GitHub Actions)

Create `.github/workflows/laria-scan.yml`:

```yaml
name: Laria Security Scan

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Build Laria
        run: docker build -t laria:latest .
        working-directory: ./laria
      
      - name: Run Security Scan
        run: |
          docker run --rm \
            --tmpfs /tmp:rw,exec,size=4g \
            -v ${{ github.workspace }}:${{ github.workspace }}:ro \
            -v ${{ github.workspace }}/reports:/laria/reports \
            laria:latest ${{ github.workspace }}
      
      - name: Upload Reports
        uses: actions/upload-artifact@v4
        with:
          name: security-reports
          path: reports/
```

## Performance Tips

1. **Cache Volumes**: Mount cache directories for faster subsequent scans
   ```bash
   -v ~/.laria/cache/trivy:/home/laria/.cache/trivy \
   -v ~/.laria/cache/semgrep:/home/laria/.cache/semgrep
   ```

2. **Tmpfs for /tmp**: Use tmpfs for better performance
   ```bash
   --tmpfs /tmp:rw,exec,size=4g
   ```

3. **Parallel Scanning**: Laria runs scanners in parallel automatically

## Report Formats

Laria generates three report formats:

- **JSON** (`laria_report_*.json`) - Machine-readable, complete data
- **HTML** (`laria_report_*.html`) - Beautiful formatted tables, color-coded severity
- **Markdown** (`laria_report_*.md`) - GitHub-compatible, readable tables

## Next Steps

1. Review the generated reports
2. Prioritize critical and high severity findings
3. Create tickets for remediation
4. Integrate into your CI/CD pipeline
5. Run regularly (weekly or on every PR)

For more information, see:
- [README.md](../README.md)
- [TOOLS.md](TOOLS.md)
- [TEST_RESULTS.md](TEST_RESULTS.md)
