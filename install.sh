#!/bin/bash
set -e

# Laria Installation Script (Isolated)
# Installs Laria and all tools into ~/.laria

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

LARIA_HOME="$HOME/.laria"
INSTALL_DIR="$LARIA_HOME/bin"
VENV_DIR="$LARIA_HOME/venv"
SRC_DIR="$LARIA_HOME/src"

# Versions (matching Dockerfile)
TRIVY_VERSION="v0.48.0"
GRYPE_VERSION="v0.74.0"
GITLEAKS_VERSION="8.18.1"
HADOLINT_VERSION="v2.12.0"
KUBEAUDIT_VERSION="0.22.1"
SPOTBUGS_VERSION="4.8.3"

log() { echo -e "${BLUE}[LARIA]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Check prerequisites
check_prereqs() {
    log "Checking prerequisites..."
    command -v python3 >/dev/null || error "Python 3 required"
    command -v git >/dev/null || error "Git required"
    
    if ! command -v java >/dev/null; then
        log "Warning: Java not found. SpotBugs scanning will be disabled."
    fi
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    
    case "$OS" in
        Linux) OS_TYPE="linux" ;;
        Darwin) OS_TYPE="darwin" ;;
        *) error "Unsupported OS: $OS" ;;
    esac
    
    case "$ARCH" in
        x86_64) ARCH_TYPE="amd64"; GITLEAKS_ARCH="x64" ;;
        arm64|aarch64) ARCH_TYPE="arm64"; GITLEAKS_ARCH="arm64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac
    
    log "Detected platform: $OS_TYPE/$ARCH_TYPE"
}

setup_dirs() {
    log "Cleaning up old installation..."
    
    # Backup reports if they exist
    if [ -d "$LARIA_HOME/reports" ]; then
        log "Backing up reports..."
        mv "$LARIA_HOME/reports" "/tmp/laria_reports_backup_$$"
    fi

    # Wipe clean to ensure fresh install
    rm -rf "$LARIA_HOME"
    
    log "Creating directory structure in $LARIA_HOME..."
    mkdir -p "$INSTALL_DIR" "$SRC_DIR"

    # Restore reports
    if [ -d "/tmp/laria_reports_backup_$$" ]; then
        log "Restoring reports..."
        mv "/tmp/laria_reports_backup_$$" "$LARIA_HOME/reports"
    fi
}

setup_venv() {
    log "Setting up Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install --upgrade pip
    "$VENV_DIR/bin/pip" install -r requirements.txt
}

install_tools() {
    log "Installing tools to $INSTALL_DIR..."
    
    # Create temp dir
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    # Trivy
    log "Installing Trivy..."
    curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b "$INSTALL_DIR" "$TRIVY_VERSION"

    # Grype
    log "Installing Grype..."
    curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b "$INSTALL_DIR" "$GRYPE_VERSION"

    # Gitleaks
    log "Installing Gitleaks..."
    wget -q "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_${OS_TYPE}_${GITLEAKS_ARCH}.tar.gz"
    tar -xzf "gitleaks_${GITLEAKS_VERSION}_${OS_TYPE}_${GITLEAKS_ARCH}.tar.gz"
    mv gitleaks "$INSTALL_DIR/"

    # Hadolint
    log "Installing Hadolint..."
    if [ "$OS_TYPE" = "darwin" ]; then
        if command -v brew >/dev/null; then
            log "Using Homebrew to install Hadolint (avoids architecture issues)..."
            brew install hadolint
            # Symlink to our bin dir for consistency
            ln -sf "$(brew --prefix hadolint)/bin/hadolint" "$INSTALL_DIR/hadolint"
        else
            log "Homebrew not found. Falling back to binary download (may have issues on M1/M2)..."
            wget -q "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Darwin-x86_64" -O "$INSTALL_DIR/hadolint"
        fi
    else
        wget -q "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64" -O "$INSTALL_DIR/hadolint"
    fi

    # Kubescape
    log "Installing Kubescape..."
    # Kubescape install script tries to install to ~/.kubescape/bin
    curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash
    if [ -f "$HOME/.kubescape/bin/kubescape" ]; then
        ln -sf "$HOME/.kubescape/bin/kubescape" "$INSTALL_DIR/kubescape"
    fi

    # SpotBugs
    log "Installing SpotBugs..."
    # Ensure dir exists
    mkdir -p "$LARIA_HOME/spotbugs"
    wget -q "https://github.com/spotbugs/spotbugs/releases/download/${SPOTBUGS_VERSION}/spotbugs-${SPOTBUGS_VERSION}.tgz"
    tar -xzf "spotbugs-${SPOTBUGS_VERSION}.tgz" -C "$LARIA_HOME/spotbugs" --strip-components=1
    # Check if target exists before linking to avoid error
    if [ -f "$LARIA_HOME/spotbugs/bin/spotbugs" ]; then
        ln -sf "$LARIA_HOME/spotbugs/bin/spotbugs" "$INSTALL_DIR/spotbugs"
    fi
    
    # Syft
    log "Installing Syft..."
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b "$INSTALL_DIR" > /dev/null 2>&1

    # Cleanup downloads
    cd - > /dev/null
    rm -rf "$TMP_DIR"

    # Final Permission Check
    log "Setting permissions..."
    chmod +x "$INSTALL_DIR/trivy" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/grype" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/gitleaks" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/hadolint" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/kubescape" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/spotbugs" 2>/dev/null || true
    chmod +x "$LARIA_HOME/spotbugs/bin/spotbugs" 2>/dev/null || true
}

setup_laria() {
    log "Installing Laria Source..."
    # Copy source code (excluding .git and other artifacts)
    # We use a loop to copy specific files/dirs to avoid .git permission issues
    cp laria.py "$SRC_DIR/"
    cp config.yaml "$SRC_DIR/"
    cp -r scanners "$SRC_DIR/"
    cp -r utils "$SRC_DIR/"
    
    # Create wrapper
    cat > "$INSTALL_DIR/laria" <<EOF
#!/bin/bash
export PATH="$INSTALL_DIR:\$PATH"
source "$VENV_DIR/bin/activate"
export PYTHONPATH="$SRC_DIR"
python3 "$SRC_DIR/laria.py" "\$@"
EOF
    chmod +x "$INSTALL_DIR/laria"
}

main() {
    check_prereqs
    detect_platform
    # Step 1: Clean and Setup Dirs (Backup reports)
    setup_dirs
    # Step 2: Venv
    setup_venv
    # Step 3: Tools (Consolidated)
    install_tools
    # Step 4: Code
    setup_laria
    
    success "Laria installed to $LARIA_HOME"
    echo "✅ Tools installed successfully!"
    echo "Please add the following to your shell config (.bashrc/.zshrc):"
    echo "export PATH=\"$INSTALL_DIR:\$PATH\""
}

main
