#!/bin/bash
# =============================================================================
# Ralph v2 - Installation Script
# =============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash
#    or: ./install.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[ralph]${NC} $1"; }
success() { echo -e "${GREEN}[ralph]${NC} $1"; }
warn() { echo -e "${YELLOW}[ralph]${NC} $1"; }
error() { echo -e "${RED}[ralph]${NC} $1" >&2; }

RALPH_DIR="${RALPH_DIR:-$HOME/.ralph-v2}"

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."

    local missing=()

    # Check for git
    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi

    # Check for Claude CLI
    if ! command -v claude &>/dev/null; then
        missing+=("claude (Claude Code CLI)")
    fi

    # Check for envsubst (part of gettext)
    if ! command -v envsubst &>/dev/null; then
        missing+=("envsubst (install gettext)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing required tools:"
        for tool in "${missing[@]}"; do
            echo "  - $tool"
        done
        echo ""
        echo "Installation instructions:"
        echo ""
        echo "  Claude CLI:"
        echo "    npm install -g @anthropic-ai/claude-code"
        echo "    # Then authenticate: claude auth"
        echo ""
        echo "  envsubst (macOS):"
        echo "    brew install gettext"
        echo ""
        echo "  envsubst (Linux):"
        echo "    apt-get install gettext"
        echo ""
        exit 1
    fi

    success "All prerequisites met"
}

# =============================================================================
# Installation
# =============================================================================

install_ralph() {
    log "Installing Ralph v2 to $RALPH_DIR..."

    # Create directory structure
    mkdir -p "$RALPH_DIR"/{templates,docs,examples/specs,examples/llm-review}

    success "Directory structure created"
    log "Making loop.sh executable..."
    chmod +x "$RALPH_DIR/loop.sh"

    # Create config directory and default config
    local config_dir="$HOME/.config/ralph"
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
        success "Created config directory: $config_dir"
    fi

    if [ ! -f "$config_dir/config" ]; then
        cat > "$config_dir/config" << 'EOF'
# =============================================================================
# Ralph v2 Configuration
# =============================================================================
# This file is sourced by loop.sh at startup.
# Location: ~/.config/ralph/config

# =============================================================================
# SLACK NOTIFICATIONS
# =============================================================================

# Slack webhook URL for notifications (required for Slack)
# Create one at: https://api.slack.com/messaging/webhooks
# SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx/yyy/zzz"

# Send notification for each iteration (default: false)
# Set to "true" for verbose per-iteration updates
NOTIFY_PER_ITERATION=false

# =============================================================================
# DESKTOP NOTIFICATIONS (macOS)
# =============================================================================

# Enable macOS desktop notifications (default: true)
DESKTOP_NOTIFICATION=true
EOF
        success "Created config file: $config_dir/config"
    else
        log "Config file already exists: $config_dir/config"
    fi

    success "Installation complete!"
}

# =============================================================================
# Post-Install Instructions
# =============================================================================

show_instructions() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Ralph v2 Installation Complete                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Quick Start:"
    echo ""
    echo "  1. Initialize a project:"
    echo "     cd your-project"
    echo "     cp $RALPH_DIR/templates/AGENTS.md ./AGENTS.md"
    echo "     mkdir specs"
    echo ""
    echo "  2. Create specifications in specs/*.md"
    echo ""
    echo "  3. Run planning loop:"
    echo "     $RALPH_DIR/loop.sh plan"
    echo ""
    echo "  4. Run build loop:"
    echo "     $RALPH_DIR/loop.sh 20"
    echo ""
    echo "Notifications:"
    echo ""
    echo "  Configure Slack webhook for notifications:"
    echo "  Edit: ~/.config/ralph/config"
    echo "  Set:  SLACK_WEBHOOK_URL=\"https://hooks.slack.com/services/xxx/yyy/zzz\""
    echo ""
    echo "Documentation: $RALPH_DIR/docs/README.md"
    echo ""
    echo "Optional: Add to PATH"
    echo "  echo 'export PATH=\"\$PATH:$RALPH_DIR\"' >> ~/.bashrc"
    echo ""
}

# =============================================================================
# Project Initialization
# =============================================================================

init_project() {
    local project_dir="${1:-.}"

    log "Initializing Ralph project in $project_dir..."

    # Check if already initialized
    if [ -f "$project_dir/AGENTS.md" ]; then
        warn "AGENTS.md already exists. Skipping."
    else
        cp "$RALPH_DIR/templates/AGENTS.md" "$project_dir/AGENTS.md"
        success "Created AGENTS.md"
    fi

    if [ -f "$project_dir/IMPLEMENTATION_PLAN.md" ]; then
        warn "IMPLEMENTATION_PLAN.md already exists. Skipping."
    else
        cp "$RALPH_DIR/templates/IMPLEMENTATION_PLAN.md" "$project_dir/IMPLEMENTATION_PLAN.md"
        success "Created IMPLEMENTATION_PLAN.md"
    fi

    # Create specs directory
    mkdir -p "$project_dir/specs"
    success "Created specs/ directory"

    # Copy library patterns to src/lib
    mkdir -p "$project_dir/src/lib"
    if [ ! -f "$project_dir/src/lib/llm-review.ts" ]; then
        cp "$RALPH_DIR/examples/llm-review/llm-review.ts" "$project_dir/src/lib/llm-review.ts"
        success "Created src/lib/llm-review.ts"
    else
        log "src/lib/llm-review.ts already exists. Skipping."
    fi
    if [ ! -f "$project_dir/src/lib/visual-testing.ts" ]; then
        cp "$RALPH_DIR/examples/visual-testing/visual-testing.ts" "$project_dir/src/lib/visual-testing.ts"
        success "Created src/lib/visual-testing.ts"
    else
        log "src/lib/visual-testing.ts already exists. Skipping."
    fi

    # Create .gitignore additions if not present
    if [ -f "$project_dir/.gitignore" ]; then
        if ! grep -q "# Ralph v2" "$project_dir/.gitignore"; then
            cat >> "$project_dir/.gitignore" << 'EOF'

# Ralph v2
tmp/
*.tmp
.ralph-session/
EOF
            success "Updated .gitignore"
        fi
    else
        cat > "$project_dir/.gitignore" << 'EOF'
# Ralph v2
tmp/
*.tmp
.ralph-session/

# Dependencies
node_modules/

# Build outputs
dist/
build/

# Environment
.env
.env.local
*.pem

# IDE
.idea/
.vscode/
*.swp
EOF
        success "Created .gitignore"
    fi

    # Optionally copy AUDIENCE_JTBD.md
    if [ ! -f "$project_dir/AUDIENCE_JTBD.md" ]; then
        read -p "Create AUDIENCE_JTBD.md for user journey mapping? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp "$RALPH_DIR/templates/AUDIENCE_JTBD.md" "$project_dir/AUDIENCE_JTBD.md"
            success "Created AUDIENCE_JTBD.md"
        fi
    fi

    echo ""
    success "Project initialized!"
    echo ""
    echo "Next steps:"
    echo "  1. Edit AGENTS.md with your build/test commands"
    echo "  2. Create specifications in specs/*.md"
    echo "  3. Run: $RALPH_DIR/loop.sh plan"
}

# =============================================================================
# Main
# =============================================================================

main() {
    case "${1:-}" in
        init)
            shift
            init_project "${1:-.}"
            ;;
        check)
            check_prerequisites
            ;;
        *)
            check_prerequisites
            install_ralph
            show_instructions
            ;;
    esac
}

main "$@"
