#!/bin/bash
# =============================================================================
# Ralph v2 - Autonomous AI Coding Agent Loop
# =============================================================================
# Usage:
#   ./loop.sh              # Build mode, unlimited iterations
#   ./loop.sh 20           # Build mode, max 20 iterations
#   ./loop.sh plan         # Planning mode, unlimited
#   ./loop.sh plan 5       # Planning mode, max 5 iterations
#   ./loop.sh plan-work "description"      # Scoped planning for work branch
#   ./loop.sh plan-work "description" 5    # Scoped planning, max 5 iterations
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

RALPH_DIR="${RALPH_DIR:-$HOME/.ralph-v2}"
ITERATION=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

validate_git_repo() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        error "Not inside a git repository. Initialize with 'git init' first."
        exit 1
    fi
}

validate_prompt_file() {
    local prompt_file="$1"
    if [ ! -f "$prompt_file" ]; then
        error "Prompt file not found: $prompt_file"
        error "Ensure Ralph v2 is properly installed at $RALPH_DIR"
        exit 1
    fi
}

validate_work_branch() {
    local branch
    branch=$(git branch --show-current)
    if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
        error "plan-work should run on a work branch, not '$branch'"
        error "Create a work branch first: git checkout -b ralph/feature-name"
        exit 1
    fi
}

# =============================================================================
# GIT FUNCTIONS
# =============================================================================

get_current_branch() {
    git branch --show-current
}

ensure_remote_branch() {
    local branch="$1"
    if ! git ls-remote --heads origin "$branch" | grep -q "$branch"; then
        log "Creating remote branch: $branch"
        git push -u origin "$branch" 2>/dev/null || {
            warn "Could not push to remote. Will retry after first commit."
        }
    fi
}

push_changes() {
    local branch="$1"
    log "Pushing changes to origin/$branch..."
    if ! git push origin "$branch" 2>/dev/null; then
        warn "Push failed. Attempting to set upstream..."
        git push -u origin "$branch" || {
            error "Failed to push changes"
            return 1
        }
    fi
    success "Changes pushed successfully"
}

# =============================================================================
# MODE PARSING
# =============================================================================

parse_arguments() {
    MODE="build"
    PROMPT_FILE="$RALPH_DIR/PROMPT_build.md"
    MAX_ITERATIONS=0  # 0 = unlimited
    WORK_SCOPE=""

    if [ $# -eq 0 ]; then
        # Default: build mode, unlimited
        return
    fi

    case "$1" in
        plan)
            MODE="plan"
            PROMPT_FILE="$RALPH_DIR/PROMPT_plan.md"
            if [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                MAX_ITERATIONS="$2"
            fi
            ;;
        plan-work)
            MODE="plan-work"
            PROMPT_FILE="$RALPH_DIR/PROMPT_plan_work.md"
            if [ $# -lt 2 ]; then
                error "plan-work requires a work description"
                error "Usage: ./loop.sh plan-work \"user auth with OAuth\""
                exit 1
            fi
            WORK_SCOPE="$2"
            if [ $# -ge 3 ] && [[ "$3" =~ ^[0-9]+$ ]]; then
                MAX_ITERATIONS="$3"
            else
                MAX_ITERATIONS=5  # Default for scoped planning
            fi
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                # Number argument = build mode with iteration limit
                MAX_ITERATIONS="$1"
            else
                error "Unknown argument: $1"
                error "Usage: ./loop.sh [plan|plan-work \"desc\"|N]"
                exit 1
            fi
            ;;
    esac
}

# =============================================================================
# MAIN LOOP
# =============================================================================

run_iteration() {
    local prompt_file="$1"
    local mode="$2"

    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ITERATION $ITERATION │ MODE: $mode │ BRANCH: $(get_current_branch)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [ "$mode" = "plan-work" ]; then
        log "Work scope: $WORK_SCOPE"
        export WORK_SCOPE
        envsubst '${WORK_SCOPE}' < "$prompt_file" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --model opus \
            --verbose
    else
        cat "$prompt_file" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --model opus \
            --verbose
    fi
}

main() {
    parse_arguments "$@"

    # Display startup banner
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    RALPH v2 - Starting                        ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Mode: $(printf '%-54s' "$MODE")║${NC}"
    echo -e "${GREEN}║  Max iterations: $(printf '%-43s' "${MAX_ITERATIONS:-unlimited}")║${NC}"
    if [ -n "$WORK_SCOPE" ]; then
        echo -e "${GREEN}║  Work scope: $(printf '%-47s' "${WORK_SCOPE:0:47}")║${NC}"
    fi
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Validate environment
    validate_git_repo
    validate_prompt_file "$PROMPT_FILE"

    if [ "$MODE" = "plan-work" ]; then
        validate_work_branch
    fi

    local branch
    branch=$(get_current_branch)
    log "Operating on branch: $branch"

    # Main loop
    while true; do
        ITERATION=$((ITERATION + 1))

        # Check iteration limit
        if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -gt "$MAX_ITERATIONS" ]; then
            echo ""
            success "Reached maximum iterations ($MAX_ITERATIONS). Stopping."
            break
        fi

        # Run Claude iteration
        if ! run_iteration "$PROMPT_FILE" "$MODE"; then
            error "Iteration $ITERATION failed"
            warn "Continuing to next iteration..."
            continue
        fi

        # Push changes after each iteration
        push_changes "$branch" || {
            warn "Push failed, continuing anyway..."
        }

        # Small delay between iterations to avoid rate limits
        sleep 2
    done

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 RALPH v2 - Session Complete                   ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Total iterations: $(printf '%-41s' "$ITERATION")║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

main "$@"
