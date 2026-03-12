#!/bin/bash
set -e

# Load versions
source "$(dirname "$0")/versions.env"

docker build \
  --build-arg PYTHON_BASE="$PYTHON_BASE" \
  --build-arg TRIVY_VERSION="$TRIVY_VERSION" \
  --build-arg GRYPE_VERSION="$GRYPE_VERSION" \
  --build-arg SYFT_VERSION="$SYFT_VERSION" \
  --build-arg GITLEAKS_VERSION="$GITLEAKS_VERSION" \
  --build-arg SEMGREP_VERSION="$SEMGREP_VERSION" \
  --build-arg HADOLINT_VERSION="$HADOLINT_VERSION" \
  --build-arg CHECKOV_VERSION="$CHECKOV_VERSION" \
  --build-arg KUBESCAPE_VERSION="$KUBESCAPE_VERSION" \
  --build-arg KUBEAUDIT_VERSION="$KUBEAUDIT_VERSION" \
  --build-arg HELM_VERSION="$HELM_VERSION" \
  --build-arg DEPENDENCY_CHECK_VERSION="$DEPENDENCY_CHECK_VERSION" \
  --build-arg SPOTBUGS_VERSION="$SPOTBUGS_VERSION" \
  -t laria:local .
