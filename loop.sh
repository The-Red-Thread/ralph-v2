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
#   ./loop.sh audit                        # Audit mode (--full by default)
#   ./loop.sh audit --docs-only            # Only verify documentation accuracy
#   ./loop.sh audit --patterns             # Include pattern analysis
#   ./loop.sh audit --full                 # Complete analysis
#   ./loop.sh audit --quick                # Lightweight audit (fewer subagents, lower cost)
#   ./loop.sh audit --full --apply         # Apply safe updates automatically
#   ./loop.sh audit --apply-docs           # Apply documentation fixes only
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

RALPH_DIR="${RALPH_DIR:-$HOME/.ralph-v2}"
CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/ralph/config}"
ITERATION=0
SESSION_START=$(date +%s)
AUDIT_SCOPE="full"
AUDIT_APPLY="false"
AUDIT_QUICK="false"

# Load config if exists (for SLACK_WEBHOOK_URL, etc.)
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Default notification settings
NOTIFY_PER_ITERATION=${NOTIFY_PER_ITERATION:-false}
DESKTOP_NOTIFICATION=${DESKTOP_NOTIFICATION:-true}
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

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
# NOTIFICATION FUNCTIONS
# =============================================================================

get_session_duration() {
    local now=$(date +%s)
    local elapsed=$((now - SESSION_START))
    local hours=$((elapsed / 3600))
    local minutes=$(((elapsed % 3600) / 60))

    if [ "$hours" -gt 0 ]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

get_project_name() {
    basename "$(git rev-parse --show-toplevel 2>/dev/null)" || basename "$(pwd)"
}

send_slack_notification() {
    local status="$1"      # "complete", "stopped", or "error"
    local iterations="$2"
    local message="${3:-}"

    # Skip if no webhook configured
    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        return 0
    fi

    local emoji="✅"
    local color="#36a64f"
    local title="Ralph v2 completed session"

    if [ "$status" = "stopped" ]; then
        emoji="⏹️"
        color="#ff9800"
        title="Ralph v2 reached max iterations"
    elif [ "$status" = "error" ]; then
        emoji="❌"
        color="#f44336"
        title="Ralph v2 encountered an error"
    fi

    local project_name=$(get_project_name)
    local branch=$(get_current_branch)
    local duration=$(get_session_duration)
    local commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    local payload=$(cat <<EOF
{
    "username": "Ralph v2",
    "icon_url": "https://raw.githubusercontent.com/snarktank/ralph/main/ralph.webp",
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "$emoji $title",
                "emoji": true
            }
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*Project:*\n\`$project_name\`"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Branch:*\n\`$branch\`"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Mode:*\n\`$MODE\`"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Duration:*\n$duration"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Iterations:*\n$iterations"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Commit:*\n\`$commit\`"
                }
            ]
        }
    ],
    "attachments": [
        {
            "color": "$color"
        }
    ]
}
EOF
)

    # Send to Slack (silently fail if it doesn't work)
    curl -s -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true

    log "Slack notification sent"
}

send_iteration_notification() {
    local iteration="$1"
    local status="$2"  # "started" or "completed"

    # Skip if disabled or no webhook
    if [ "$NOTIFY_PER_ITERATION" != "true" ] || [ -z "$SLACK_WEBHOOK_URL" ]; then
        return 0
    fi

    local emoji="🔄"
    local color="#2196f3"

    if [ "$status" = "completed" ]; then
        emoji="✓"
        color="#36a64f"
    fi

    local project_name=$(get_project_name)
    local branch=$(get_current_branch)

    local payload=$(cat <<EOF
{
    "username": "Ralph v2",
    "icon_url": "https://raw.githubusercontent.com/snarktank/ralph/main/ralph.webp",
    "attachments": [
        {
            "color": "$color",
            "blocks": [
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": "$emoji *Iteration $iteration $status* | \`$project_name\` on \`$branch\` | Mode: \`$MODE\`"
                    }
                }
            ]
        }
    ]
}
EOF
)

    curl -s -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" > /dev/null 2>&1 || true
}

send_desktop_notification() {
    local title="$1"
    local message="$2"

    # Skip if disabled
    if [ "$DESKTOP_NOTIFICATION" != "true" ]; then
        return 0
    fi

    # macOS notification
    if command -v osascript &> /dev/null; then
        osascript -e "display notification \"$message\" with title \"$title\" sound name \"Glass\"" 2>/dev/null || true
    fi
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
        audit)
            MODE="audit"
            PROMPT_FILE="$RALPH_DIR/PROMPT_audit.md"
            MAX_ITERATIONS=1  # Audit runs once
            AUDIT_SCOPE="full"  # Default scope
            shift  # Remove 'audit' from arguments
            # Parse audit flags
            while [ $# -gt 0 ]; do
                case "$1" in
                    --docs-only)
                        AUDIT_SCOPE="docs-only"
                        ;;
                    --patterns)
                        AUDIT_SCOPE="patterns"
                        ;;
                    --full)
                        AUDIT_SCOPE="full"
                        ;;
                    --apply|--apply-docs)
                        AUDIT_APPLY="true"
                        ;;
                    --quick)
                        AUDIT_QUICK="true"
                        ;;
                    *)
                        error "Unknown audit flag: $1"
                        error "Usage: ./loop.sh audit [--docs-only|--patterns|--full] [--quick] [--apply|--apply-docs]"
                        exit 1
                        ;;
                esac
                shift
            done
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
    local elapsed=$(get_session_duration)
    local timestamp=$(date '+%H:%M:%S')
    local branch=$(get_current_branch)
    local max_info=""

    if [ "$MAX_ITERATIONS" -gt 0 ]; then
        max_info=" of $MAX_ITERATIONS"
    fi

    local iter_display="▶ ITERATION ${ITERATION}${max_info}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC}  ${GREEN}%-60s${NC} ${CYAN}║${NC}\n" "$iter_display"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${NC}  Mode:    ${YELLOW}%-51s${NC} ${CYAN}║${NC}\n" "$mode"
    printf "${CYAN}║${NC}  Branch:  ${BLUE}%-51s${NC} ${CYAN}║${NC}\n" "$branch"
    printf "${CYAN}║${NC}  Started: %-18s  Elapsed: %-19s ${CYAN}║${NC}\n" "$timestamp" "$elapsed"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ "$mode" = "plan-work" ]; then
        log "Work scope: $WORK_SCOPE"
        export WORK_SCOPE
        envsubst '${WORK_SCOPE}' < "$prompt_file" | claude -p \
            --dangerously-skip-permissions \
            --output-format=stream-json \
            --model opus \
            --verbose
    elif [ "$mode" = "audit" ]; then
        log "Audit scope: $AUDIT_SCOPE (quick: $AUDIT_QUICK, apply: $AUDIT_APPLY)"
        export AUDIT_SCOPE AUDIT_APPLY AUDIT_QUICK
        envsubst '${AUDIT_SCOPE} ${AUDIT_APPLY} ${AUDIT_QUICK}' < "$prompt_file" | claude -p \
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
    local project_name=$(get_project_name)
    local branch=$(get_current_branch)
    local max_iter_display="${MAX_ITERATIONS:-unlimited}"
    if [ "$MAX_ITERATIONS" -eq 0 ] 2>/dev/null; then
        max_iter_display="unlimited"
    fi

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    RALPH v2 - Starting                        ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC}  Project:        ${CYAN}%-44s${NC} ${GREEN}║${NC}\n" "$project_name"
    printf "${GREEN}║${NC}  Branch:         ${BLUE}%-44s${NC} ${GREEN}║${NC}\n" "$branch"
    printf "${GREEN}║${NC}  Mode:           ${YELLOW}%-44s${NC} ${GREEN}║${NC}\n" "$MODE"
    printf "${GREEN}║${NC}  Max iterations: %-44s ${GREEN}║${NC}\n" "$max_iter_display"
    if [ -n "$WORK_SCOPE" ]; then
        printf "${GREEN}║${NC}  Work scope:     %-44s ${GREEN}║${NC}\n" "${WORK_SCOPE:0:44}"
    fi
    if [ "$MODE" = "audit" ]; then
        printf "${GREEN}║${NC}  Audit scope:    %-44s ${GREEN}║${NC}\n" "$AUDIT_SCOPE"
        printf "${GREEN}║${NC}  Quick mode:     %-44s ${GREEN}║${NC}\n" "$AUDIT_QUICK"
        printf "${GREEN}║${NC}  Auto-apply:     %-44s ${GREEN}║${NC}\n" "$AUDIT_APPLY"
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

    # Display notification config
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        log "Slack notifications: enabled"
    else
        log "Slack notifications: disabled (set SLACK_WEBHOOK_URL in $CONFIG_FILE)"
    fi

    # Trap for clean exit with notifications
    trap 'send_slack_notification "error" "$ITERATION"; send_desktop_notification "Ralph v2" "Session interrupted after $ITERATION iterations"' INT TERM

    # Main loop
    while true; do
        ITERATION=$((ITERATION + 1))

        # Check iteration limit
        if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -gt "$MAX_ITERATIONS" ]; then
            echo ""
            success "Reached maximum iterations ($MAX_ITERATIONS). Stopping."
            send_slack_notification "stopped" "$((ITERATION - 1))"
            send_desktop_notification "Ralph v2" "Reached max iterations ($MAX_ITERATIONS)"
            break
        fi

        # Notify iteration start (if enabled)
        send_iteration_notification "$ITERATION" "started"

        # Run Claude iteration
        if ! run_iteration "$PROMPT_FILE" "$MODE"; then
            error "Iteration $ITERATION failed"
            warn "Continuing to next iteration..."
            continue
        fi

        # Notify iteration complete (if enabled)
        send_iteration_notification "$ITERATION" "completed"

        # Push changes after each iteration
        push_changes "$branch" || {
            warn "Push failed, continuing anyway..."
        }

        # Small delay between iterations to avoid rate limits
        sleep 2
    done

    # Clear trap
    trap - INT TERM

    local project_name=$(get_project_name)
    local duration=$(get_session_duration)
    local branch=$(get_current_branch)
    local commit=$(git rev-parse --short HEAD 2>/dev/null || echo "none")

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║               RALPH v2 - Session Complete                     ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC}  Project:      ${CYAN}%-46s${NC} ${GREEN}║${NC}\n" "$project_name"
    printf "${GREEN}║${NC}  Branch:       ${BLUE}%-46s${NC} ${GREEN}║${NC}\n" "$branch"
    printf "${GREEN}║${NC}  Mode:         ${YELLOW}%-46s${NC} ${GREEN}║${NC}\n" "$MODE"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC}  Iterations:   %-46s ${GREEN}║${NC}\n" "$ITERATION"
    printf "${GREEN}║${NC}  Duration:     %-46s ${GREEN}║${NC}\n" "$duration"
    printf "${GREEN}║${NC}  Last commit:  %-46s ${GREEN}║${NC}\n" "$commit"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"

    # Send final notifications
    send_slack_notification "complete" "$ITERATION"
    send_desktop_notification "Ralph v2" "$project_name completed - $ITERATION iterations in $duration"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

main "$@"
