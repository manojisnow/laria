#!/bin/bash
set -e

# Laria Uninstallation Script
# Removes ~/.laria directory

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

LARIA_HOME="$HOME/.laria"

log() { echo -e "${BLUE}[LARIA]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

main() {
    echo -e "${RED}!!! Laria Uninstaller !!!${NC}"
    echo "This will remove Laria and all its isolated dependencies from $LARIA_HOME."
    
    read -p "Are you sure? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            ;;
        *)
            echo "Aborted."
            exit 0
            ;;
    esac
    
    if [ -d "$LARIA_HOME" ]; then
        log "Removing $LARIA_HOME..."
        rm -rf "$LARIA_HOME"
        success "Uninstallation complete."
    else
        log "Laria directory not found."
    fi
    
    echo "Note: You may need to remove $LARIA_HOME/bin from your PATH in .bashrc/.zshrc"
}

main
