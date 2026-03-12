# Production Dockerfile for Laria Security Scanner
# Includes all security scanning tools

# Global ARG — used in the FROM instruction
ARG PYTHON_BASE=3.11-slim-bookworm

FROM python:${PYTHON_BASE} AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Tool version ARGs with defaults matching versions.env
ARG SYFT_VERSION=1.9.0

# Install system dependencies
# hadolint ignore=DL3008
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    git \
    curl \
    gnupg \
    ca-certificates \
    default-jdk \
    maven \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Syft (arch-aware direct download)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -sSfL "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_${ARCH}.tar.gz" -o syft.tar.gz && \
    tar -xzf syft.tar.gz syft && \
    mv syft /usr/local/bin/ && \
    rm syft.tar.gz

WORKDIR /laria

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install security tools stage
FROM base AS tools

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Re-declare ARGs for use in this stage
ARG TRIVY_VERSION=0.58.0
ARG GRYPE_VERSION=0.80.0
ARG GITLEAKS_VERSION=8.18.1
ARG SEMGREP_VERSION=1.59.0
ARG HADOLINT_VERSION=2.12.0
ARG CHECKOV_VERSION=3.2.495
ARG KUBESCAPE_VERSION=3.0.3
ARG KUBEAUDIT_VERSION=0.22.1
ARG HELM_VERSION=3.16.0
ARG DEPENDENCY_CHECK_VERSION=9.0.7
ARG SPOTBUGS_VERSION=4.8.3

# Install Trivy (arch-aware direct download — Trivy uses different arch naming)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  TRIVY_ARCH="Linux-64bit" ;; \
      aarch64) TRIVY_ARCH="Linux-ARM64" ;; \
    esac && \
    curl -sfL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_${TRIVY_ARCH}.tar.gz" -o trivy.tar.gz && \
    tar -xzf trivy.tar.gz trivy && \
    mv trivy /usr/local/bin/ && \
    rm trivy.tar.gz

# Install Grype (arch-aware direct download)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -sSfL "https://github.com/anchore/grype/releases/download/v${GRYPE_VERSION}/grype_${GRYPE_VERSION}_linux_${ARCH}.tar.gz" -o grype.tar.gz && \
    tar -xzf grype.tar.gz grype && \
    mv grype /usr/local/bin/ && \
    rm grype.tar.gz

# Install Gitleaks (arch-aware direct download)
RUN ARCH=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/') && \
    curl -sSfL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${ARCH}.tar.gz" -o gitleaks.tar.gz && \
    tar -xzf gitleaks.tar.gz gitleaks && \
    mv gitleaks /usr/local/bin/ && \
    rm gitleaks.tar.gz

# Install Semgrep
RUN pip install --no-cache-dir "semgrep==${SEMGREP_VERSION}"

# Install Hadolint (arch-aware direct download)
RUN ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/aarch64/arm64/') && \
    curl -sSfL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${ARCH}" -o /usr/local/bin/hadolint && \
    chmod +x /usr/local/bin/hadolint

# Install Checkov
RUN pip install --no-cache-dir "checkov==${CHECKOV_VERSION}"

# Install Kubescape (arch-aware direct download)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  KS_ARCH="kubescape-ubuntu-latest" ;; \
      aarch64) KS_ARCH="kubescape-arm64-ubuntu-latest" ;; \
    esac && \
    curl -sSfL "https://github.com/kubescape/kubescape/releases/download/v${KUBESCAPE_VERSION}/${KS_ARCH}" -o /usr/local/bin/kubescape && \
    chmod +x /usr/local/bin/kubescape

# Install Kubeaudit (arch-aware direct download)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -sSfL "https://github.com/Shopify/kubeaudit/releases/download/v${KUBEAUDIT_VERSION}/kubeaudit_${KUBEAUDIT_VERSION}_linux_${ARCH}.tar.gz" -o kubeaudit.tar.gz && \
    tar -xzf kubeaudit.tar.gz kubeaudit && \
    mv kubeaudit /usr/local/bin/ && \
    rm kubeaudit.tar.gz

# Install Helm (arch-aware direct download)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -sSfL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" -o helm.tar.gz && \
    tar -xzf helm.tar.gz "linux-${ARCH}/helm" && \
    mv "linux-${ARCH}/helm" /usr/local/bin/helm && \
    rm -rf helm.tar.gz "linux-${ARCH}"

# Install OWASP Dependency-Check (Java — architecture-independent)
RUN curl -sSfL "https://github.com/jeremylong/DependencyCheck/releases/download/v${DEPENDENCY_CHECK_VERSION}/dependency-check-${DEPENDENCY_CHECK_VERSION}-release.zip" -o dependency-check.zip && \
    unzip dependency-check.zip && \
    mv dependency-check /opt/ && \
    ln -s /opt/dependency-check/bin/dependency-check.sh /usr/local/bin/dependency-check && \
    rm dependency-check.zip

# Install SpotBugs (Java — architecture-independent)
RUN curl -sSfL "https://github.com/spotbugs/spotbugs/releases/download/${SPOTBUGS_VERSION}/spotbugs-${SPOTBUGS_VERSION}.tgz" -o spotbugs.tgz && \
    tar -xzf spotbugs.tgz && \
    mv "spotbugs-${SPOTBUGS_VERSION}" /opt/spotbugs && \
    chmod +x /opt/spotbugs/bin/spotbugs && \
    ln -s /opt/spotbugs/bin/spotbugs /usr/local/bin/spotbugs && \
    rm spotbugs.tgz

# Final stage
FROM tools

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy Laria application
COPY . /laria/

# Create reports directory
RUN mkdir -p /laria/reports

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PATH="/laria:${PATH}"

# Make laria.py executable
RUN chmod +x /laria/laria.py

# Create non-root user for security
RUN useradd -m -u 1000 laria && \
    chown -R laria:laria /laria

USER laria

# Set entrypoint
ENTRYPOINT ["python3", "/laria/laria.py"]

# Default command (show help)
CMD ["--help"]

# Add Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python3 /laria/laria.py --version || exit 1
