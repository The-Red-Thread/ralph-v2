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
#   ./loop.sh audit --backpressure         # Analyze testing gaps and feedback loops
#   ./loop.sh done                         # Archive working files after feature complete
#
# Monitoring & Safety:
#   ./loop.sh --monitor 20                 # Build with live tmux dashboard
#   ./loop.sh plan --monitor               # Plan with live monitoring
#   ./loop.sh --no-circuit-breaker 50      # Disable circuit breaker
#
# Circuit Breaker: Stops after 3 iterations with no commits (configurable)
# Rate Limiting: Tracks iterations per hour, warns at thresholds
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

RALPH_DIR="${RALPH_DIR:-$HOME/.ralph-v2}"
CONFIG_FILE="${CONFIG_FILE:-$HOME/.config/ralph/config}"
LOG_FILE="ralph.log"
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

# Circuit breaker settings (can be overridden in config)
CIRCUIT_BREAKER_ENABLED=${CIRCUIT_BREAKER_ENABLED:-true}
CIRCUIT_BREAKER_THRESHOLD=${CIRCUIT_BREAKER_THRESHOLD:-3}  # Stop after N iterations with no progress
CIRCUIT_BREAKER_ERROR_THRESHOLD=${CIRCUIT_BREAKER_ERROR_THRESHOLD:-5}  # Stop after N consecutive errors

# Progress tracking
LAST_COMMIT_HASH=""
CONSECUTIVE_NO_PROGRESS=0
CONSECUTIVE_ERRORS=0
TOTAL_COMMITS=0

# Monitoring settings
MONITOR_MODE=${MONITOR_MODE:-false}
MONITOR_SESSION_NAME="ralph-monitor"

# Rate tracking
ITERATIONS_THIS_HOUR=0
HOUR_START=$(date +%s)
RATE_WARNING_THRESHOLD=${RATE_WARNING_THRESHOLD:-50}  # Warn when approaching this many iterations/hour

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
# PROGRESS DETECTION & CIRCUIT BREAKER
# =============================================================================

init_progress_tracking() {
    LAST_COMMIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "")
    CONSECUTIVE_NO_PROGRESS=0
    CONSECUTIVE_ERRORS=0
    TOTAL_COMMITS=0
    log "Progress tracking initialized (last commit: ${LAST_COMMIT_HASH:0:7})"
}

check_progress() {
    local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "")

    if [ -z "$current_commit" ]; then
        warn "Could not get current commit hash"
        return 0
    fi

    if [ "$current_commit" = "$LAST_COMMIT_HASH" ]; then
        CONSECUTIVE_NO_PROGRESS=$((CONSECUTIVE_NO_PROGRESS + 1))
        warn "No new commits this iteration ($CONSECUTIVE_NO_PROGRESS/$CIRCUIT_BREAKER_THRESHOLD)"
        write_status_file
        return 1  # No progress
    else
        if [ $CONSECUTIVE_NO_PROGRESS -gt 0 ]; then
            success "Progress resumed after $CONSECUTIVE_NO_PROGRESS stalled iterations"
        fi
        CONSECUTIVE_NO_PROGRESS=0
        TOTAL_COMMITS=$((TOTAL_COMMITS + 1))
        LAST_COMMIT_HASH="$current_commit"
        log "New commit detected: ${current_commit:0:7} (total this session: $TOTAL_COMMITS)"
        write_status_file
        return 0  # Progress made
    fi
}

check_circuit_breaker() {
    if [ "$CIRCUIT_BREAKER_ENABLED" != "true" ]; then
        return 0  # Circuit breaker disabled
    fi

    # Check for no progress
    if [ $CONSECUTIVE_NO_PROGRESS -ge $CIRCUIT_BREAKER_THRESHOLD ]; then
        echo ""
        error "╔═══════════════════════════════════════════════════════════════╗"
        error "║              CIRCUIT BREAKER TRIGGERED                        ║"
        error "╠═══════════════════════════════════════════════════════════════╣"
        error "║  No commits in $CIRCUIT_BREAKER_THRESHOLD consecutive iterations.                         ║"
        error "║  Ralph may be stuck in a loop.                                ║"
        error "║                                                               ║"
        error "║  Suggestions:                                                 ║"
        error "║  • Check IMPLEMENTATION_PLAN.md for issues                    ║"
        error "║  • Run 'ralph plan' to regenerate the plan                    ║"
        error "║  • Review the log file: $LOG_FILE                             ║"
        error "║                                                               ║"
        error "║  To disable: --no-circuit-breaker or set                      ║"
        error "║  CIRCUIT_BREAKER_ENABLED=false in config                      ║"
        error "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        return 1  # Trip the breaker
    fi

    # Check for consecutive errors
    if [ $CONSECUTIVE_ERRORS -ge $CIRCUIT_BREAKER_ERROR_THRESHOLD ]; then
        echo ""
        error "╔═══════════════════════════════════════════════════════════════╗"
        error "║         CIRCUIT BREAKER TRIGGERED (ERRORS)                    ║"
        error "╠═══════════════════════════════════════════════════════════════╣"
        error "║  $CONSECUTIVE_ERRORS consecutive iteration errors detected.                      ║"
        error "║                                                               ║"
        error "║  Check the log file for details: $LOG_FILE                    ║"
        error "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        return 1  # Trip the breaker
    fi

    return 0  # All good
}

record_iteration_error() {
    CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    warn "Iteration error recorded ($CONSECUTIVE_ERRORS/$CIRCUIT_BREAKER_ERROR_THRESHOLD)"
    write_status_file
}

clear_iteration_error() {
    if [ $CONSECUTIVE_ERRORS -gt 0 ]; then
        log "Error streak cleared after $CONSECUTIVE_ERRORS errors"
    fi
    CONSECUTIVE_ERRORS=0
}

# =============================================================================
# RATE TRACKING
# =============================================================================

check_rate_limit() {
    local now=$(date +%s)
    local hour_elapsed=$((now - HOUR_START))

    # Reset counter every hour
    if [ $hour_elapsed -ge 3600 ]; then
        log "Hourly rate reset: $ITERATIONS_THIS_HOUR iterations in the last hour"
        ITERATIONS_THIS_HOUR=0
        HOUR_START=$now
    fi

    ITERATIONS_THIS_HOUR=$((ITERATIONS_THIS_HOUR + 1))

    # Warn if approaching threshold
    if [ $ITERATIONS_THIS_HOUR -eq $RATE_WARNING_THRESHOLD ]; then
        warn "Rate warning: $ITERATIONS_THIS_HOUR iterations this hour"
        warn "Consider monitoring API usage if running with many parallel projects"
    fi

    write_status_file
}

get_rate_info() {
    local now=$(date +%s)
    local hour_elapsed=$((now - HOUR_START))
    local minutes_remaining=$(( (3600 - hour_elapsed) / 60 ))
    echo "$ITERATIONS_THIS_HOUR iter/hr (resets in ${minutes_remaining}m)"
}

# =============================================================================
# STATUS FILE (for monitoring)
# =============================================================================

write_status_file() {
    local status_file=".ralph-status.json"
    local now=$(date +%s)
    local elapsed=$((now - SESSION_START))
    local current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "none")

    cat > "$status_file" << EOF
{
    "timestamp": $now,
    "iteration": $ITERATION,
    "max_iterations": $MAX_ITERATIONS,
    "mode": "$MODE",
    "branch": "$(get_current_branch)",
    "project": "$(get_project_name)",
    "elapsed_seconds": $elapsed,
    "total_commits": $TOTAL_COMMITS,
    "consecutive_no_progress": $CONSECUTIVE_NO_PROGRESS,
    "consecutive_errors": $CONSECUTIVE_ERRORS,
    "circuit_breaker_threshold": $CIRCUIT_BREAKER_THRESHOLD,
    "circuit_breaker_enabled": $CIRCUIT_BREAKER_ENABLED,
    "iterations_this_hour": $ITERATIONS_THIS_HOUR,
    "last_commit": "$current_commit",
    "status": "running"
}
EOF
}

cleanup_status_file() {
    local status_file=".ralph-status.json"
    if [ -f "$status_file" ]; then
        # Update status to stopped before removing
        local now=$(date +%s)
        local elapsed=$((now - SESSION_START))
        cat > "$status_file" << EOF
{
    "timestamp": $now,
    "iteration": $ITERATION,
    "mode": "$MODE",
    "elapsed_seconds": $elapsed,
    "total_commits": $TOTAL_COMMITS,
    "status": "stopped"
}
EOF
    fi
}

# =============================================================================
# LIVE MONITORING (tmux)
# =============================================================================

check_tmux_available() {
    if ! command -v tmux &> /dev/null; then
        error "tmux is required for --monitor mode"
        error "Install with: brew install tmux (macOS) or apt install tmux (Linux)"
        exit 1
    fi
}

start_monitor_session() {
    check_tmux_available

    local project_name=$(get_project_name)

    # Kill existing session if any
    tmux kill-session -t "$MONITOR_SESSION_NAME" 2>/dev/null || true

    # Create new tmux session with monitoring layout
    tmux new-session -d -s "$MONITOR_SESSION_NAME" -x 180 -y 50

    # Main pane: tail the log file
    tmux send-keys -t "$MONITOR_SESSION_NAME" "echo 'Ralph v2 Monitor - $project_name'; echo '═══════════════════════════════════════════════════════'; tail -f $LOG_FILE 2>/dev/null || echo 'Waiting for log file...'; while [ ! -f $LOG_FILE ]; do sleep 1; done; tail -f $LOG_FILE" C-m

    # Split horizontally for status
    tmux split-window -t "$MONITOR_SESSION_NAME" -h -p 35

    # Right pane: watch status and git log
    tmux send-keys -t "$MONITOR_SESSION_NAME" "watch -n 2 -c 'echo \"═══ RALPH STATUS ═══\"; if [ -f .ralph-status.json ]; then cat .ralph-status.json | python3 -m json.tool 2>/dev/null || cat .ralph-status.json; else echo \"Waiting for status...\"; fi; echo \"\"; echo \"═══ RECENT COMMITS ═══\"; git log --oneline --color=always -8 2>/dev/null || echo \"No commits yet\"; echo \"\"; echo \"═══ PLAN (first 20 lines) ═══\"; head -20 IMPLEMENTATION_PLAN.md 2>/dev/null || echo \"No plan file\"'" C-m

    # Split the right pane vertically for a mini dashboard
    tmux split-window -t "$MONITOR_SESSION_NAME" -v -p 30

    # Bottom right: simple progress indicator
    tmux send-keys -t "$MONITOR_SESSION_NAME" "watch -n 1 'if [ -f .ralph-status.json ]; then iter=\$(grep -o \"\\\"iteration\\\": [0-9]*\" .ralph-status.json | grep -o \"[0-9]*\"); max=\$(grep -o \"\\\"max_iterations\\\": [0-9]*\" .ralph-status.json | grep -o \"[0-9]*\"); commits=\$(grep -o \"\\\"total_commits\\\": [0-9]*\" .ralph-status.json | grep -o \"[0-9]*\"); noprog=\$(grep -o \"\\\"consecutive_no_progress\\\": [0-9]*\" .ralph-status.json | grep -o \"[0-9]*\"); echo \"┌─────────────────────────┐\"; echo \"│   ITERATION: \$iter / \$max    │\"; echo \"│   COMMITS: \$commits            │\"; echo \"│   STALLED: \$noprog / $CIRCUIT_BREAKER_THRESHOLD          │\"; echo \"└─────────────────────────┘\"; fi'" C-m

    log "Monitor session started: $MONITOR_SESSION_NAME"
    log "Attach with: tmux attach -t $MONITOR_SESSION_NAME"
}

attach_monitor_session() {
    if tmux has-session -t "$MONITOR_SESSION_NAME" 2>/dev/null; then
        exec tmux attach -t "$MONITOR_SESSION_NAME"
    else
        error "No monitor session found. Start ralph with --monitor first."
        exit 1
    fi
}

stop_monitor_session() {
    tmux kill-session -t "$MONITOR_SESSION_NAME" 2>/dev/null || true
}

# =============================================================================
# LOGGING TO FILE
# =============================================================================

init_log_file() {
    local project_name=$(get_project_name)
    local branch=$(get_current_branch)

    # Create or append to log file
    {
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "RALPH v2 SESSION STARTED"
        echo "═══════════════════════════════════════════════════════════════════"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Project:   $project_name"
        echo "Branch:    $branch"
        echo "Mode:      $MODE"
        echo "Max iter:  ${MAX_ITERATIONS:-unlimited}"
        echo "Circuit breaker: $CIRCUIT_BREAKER_ENABLED (threshold: $CIRCUIT_BREAKER_THRESHOLD)"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
    } >> "$LOG_FILE"
}

log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
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
# ARCHIVE FUNCTION
# =============================================================================

archive_working_files() {
    local branch=$(get_current_branch)
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local archive_dir=".ralph-v2/archive/${branch}_${timestamp}"
    local archived_count=0

    log "Archiving working files for branch: $branch"

    # Create archive directory
    mkdir -p "$archive_dir"

    # Archive IMPLEMENTATION_PLAN.md if exists
    if [ -f "IMPLEMENTATION_PLAN.md" ]; then
        mv "IMPLEMENTATION_PLAN.md" "$archive_dir/"
        success "Archived IMPLEMENTATION_PLAN.md"
        archived_count=$((archived_count + 1))
    fi

    # Archive AUDIT_REPORT.md if exists
    if [ -f "AUDIT_REPORT.md" ]; then
        mv "AUDIT_REPORT.md" "$archive_dir/"
        success "Archived AUDIT_REPORT.md"
        archived_count=$((archived_count + 1))
    fi

    if [ "$archived_count" -eq 0 ]; then
        warn "No working files to archive"
        rmdir "$archive_dir" 2>/dev/null || true
        rmdir ".ralph-v2/archive" 2>/dev/null || true
        return 0
    fi

    # Create a summary file
    cat > "$archive_dir/ARCHIVE_INFO.md" << EOF
# Archive Info

- **Branch:** $branch
- **Archived:** $(date '+%Y-%m-%d %H:%M:%S')
- **Files:** $archived_count

## Contents
$(ls -1 "$archive_dir" | grep -v ARCHIVE_INFO.md | sed 's/^/- /')
EOF

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 RALPH v2 - Archive Complete                   ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC}  Branch:    ${BLUE}%-50s${NC} ${GREEN}║${NC}\n" "$branch"
    printf "${GREEN}║${NC}  Files:     %-50s ${GREEN}║${NC}\n" "$archived_count archived"
    printf "${GREEN}║${NC}  Location:  %-50s ${GREEN}║${NC}\n" "$archive_dir"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log "Working files archived to: $archive_dir"
    log "Ready for next feature. Run 'ralph plan' or 'ralph plan-work' to start."
}

# =============================================================================
# MODE PARSING
# =============================================================================

parse_arguments() {
    MODE="build"
    PROMPT_FILE="$RALPH_DIR/PROMPT_build.md"
    MAX_ITERATIONS=0  # 0 = unlimited
    WORK_SCOPE=""

    # First pass: extract global flags
    local args=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --monitor)
                MONITOR_MODE=true
                ;;
            --no-circuit-breaker)
                CIRCUIT_BREAKER_ENABLED=false
                ;;
            --circuit-breaker-threshold)
                shift
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    CIRCUIT_BREAKER_THRESHOLD="$1"
                else
                    error "--circuit-breaker-threshold requires a number"
                    exit 1
                fi
                ;;
            *)
                args+=("$1")
                ;;
        esac
        shift
    done

    # Reset positional parameters to non-flag arguments
    set -- "${args[@]}"

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
                    --backpressure)
                        AUDIT_SCOPE="backpressure"
                        PROMPT_FILE="$RALPH_DIR/PROMPT_audit_backpressure.md"
                        ;;
                    *)
                        error "Unknown audit flag: $1"
                        error "Usage: ./loop.sh audit [--docs-only|--patterns|--full|--backpressure] [--quick] [--apply|--apply-docs]"
                        exit 1
                        ;;
                esac
                shift
            done
            ;;
        done)
            MODE="done"
            ;;
        monitor)
            # Standalone monitor command to attach to existing session
            attach_monitor_session
            exit 0
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                # Number argument = build mode with iteration limit
                MAX_ITERATIONS="$1"
            else
                error "Unknown argument: $1"
                error "Usage: ./loop.sh [plan|plan-work \"desc\"|audit|done|monitor|N] [--monitor] [--no-circuit-breaker]"
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

    # Handle 'done' mode separately (no loop needed)
    if [ "$MODE" = "done" ]; then
        validate_git_repo
        archive_working_files
        exit 0
    fi

    # Display startup banner
    local project_name=$(get_project_name)
    local branch=$(get_current_branch)
    local max_iter_display="${MAX_ITERATIONS:-unlimited}"
    if [ "$MAX_ITERATIONS" -eq 0 ] 2>/dev/null; then
        max_iter_display="unlimited"
    fi

    local circuit_breaker_display="enabled (threshold: $CIRCUIT_BREAKER_THRESHOLD)"
    if [ "$CIRCUIT_BREAKER_ENABLED" != "true" ]; then
        circuit_breaker_display="disabled"
    fi

    local monitor_display="disabled"
    if [ "$MONITOR_MODE" = "true" ]; then
        monitor_display="enabled (tmux)"
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
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC}  Circuit breaker: %-43s ${GREEN}║${NC}\n" "$circuit_breaker_display"
    printf "${GREEN}║${NC}  Live monitor:    %-43s ${GREEN}║${NC}\n" "$monitor_display"
    printf "${GREEN}║${NC}  Log file:        %-43s ${GREEN}║${NC}\n" "$LOG_FILE"
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

    # Initialize logging and tracking
    init_log_file
    init_progress_tracking
    write_status_file

    # Start monitor session if requested
    if [ "$MONITOR_MODE" = "true" ]; then
        start_monitor_session
        log "Monitor session started. Attach with: tmux attach -t $MONITOR_SESSION_NAME"
    fi

    # Display notification config
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        log "Slack notifications: enabled"
    else
        log "Slack notifications: disabled (set SLACK_WEBHOOK_URL in $CONFIG_FILE)"
    fi

    # Trap for clean exit with notifications
    trap 'cleanup_on_exit "interrupted"' INT TERM

    # Main loop
    while true; do
        ITERATION=$((ITERATION + 1))
        log_to_file "Starting iteration $ITERATION"

        # Check iteration limit
        if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -gt "$MAX_ITERATIONS" ]; then
            echo ""
            success "Reached maximum iterations ($MAX_ITERATIONS). Stopping."
            log_to_file "Reached maximum iterations ($MAX_ITERATIONS)"
            cleanup_on_exit "max_iterations"
            break
        fi

        # Track rate
        check_rate_limit

        # Notify iteration start (if enabled)
        send_iteration_notification "$ITERATION" "started"

        # Run Claude iteration
        if ! run_iteration "$PROMPT_FILE" "$MODE"; then
            error "Iteration $ITERATION failed"
            log_to_file "Iteration $ITERATION failed"
            record_iteration_error

            # Check circuit breaker for errors
            if ! check_circuit_breaker; then
                log_to_file "Circuit breaker triggered (errors)"
                cleanup_on_exit "circuit_breaker_errors"
                break
            fi

            warn "Continuing to next iteration..."
            continue
        fi

        # Clear error streak on successful iteration
        clear_iteration_error

        # Check for progress (new commits)
        check_progress

        # Check circuit breaker for no progress
        if ! check_circuit_breaker; then
            log_to_file "Circuit breaker triggered (no progress)"
            cleanup_on_exit "circuit_breaker_no_progress"
            break
        fi

        # Notify iteration complete (if enabled)
        send_iteration_notification "$ITERATION" "completed"
        log_to_file "Iteration $ITERATION completed (commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'none'))"

        # Push changes after each iteration
        push_changes "$branch" || {
            warn "Push failed, continuing anyway..."
            log_to_file "Push failed for iteration $ITERATION"
        }

        # Small delay between iterations to avoid rate limits
        sleep 2
    done

    # Normal completion
    cleanup_on_exit "complete"
}

cleanup_on_exit() {
    local exit_reason="${1:-unknown}"

    # Clear trap
    trap - INT TERM

    # Update status file
    cleanup_status_file

    # Stop monitor session if running
    if [ "$MONITOR_MODE" = "true" ]; then
        # Don't kill the session, let user review
        log "Monitor session still running. Kill with: tmux kill-session -t $MONITOR_SESSION_NAME"
    fi

    local project_name=$(get_project_name)
    local duration=$(get_session_duration)
    local branch=$(get_current_branch)
    local commit=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
    local rate_info=$(get_rate_info)

    # Log final state
    log_to_file "Session ended: $exit_reason"
    log_to_file "Final stats: $ITERATION iterations, $TOTAL_COMMITS commits, duration: $duration"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║               RALPH v2 - Session Complete                     ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC}  Project:      ${CYAN}%-46s${NC} ${GREEN}║${NC}\n" "$project_name"
    printf "${GREEN}║${NC}  Branch:       ${BLUE}%-46s${NC} ${GREEN}║${NC}\n" "$branch"
    printf "${GREEN}║${NC}  Mode:         ${YELLOW}%-46s${NC} ${GREEN}║${NC}\n" "$MODE"
    printf "${GREEN}║${NC}  Exit reason:  %-46s ${GREEN}║${NC}\n" "$exit_reason"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${NC}  Iterations:   %-46s ${GREEN}║${NC}\n" "$ITERATION"
    printf "${GREEN}║${NC}  Commits:      %-46s ${GREEN}║${NC}\n" "$TOTAL_COMMITS"
    printf "${GREEN}║${NC}  Duration:     %-46s ${GREEN}║${NC}\n" "$duration"
    printf "${GREEN}║${NC}  Rate:         %-46s ${GREEN}║${NC}\n" "$rate_info"
    printf "${GREEN}║${NC}  Last commit:  %-46s ${GREEN}║${NC}\n" "$commit"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"

    # Determine notification status
    local notify_status="complete"
    if [ "$exit_reason" = "interrupted" ]; then
        notify_status="error"
    elif [ "$exit_reason" = "max_iterations" ]; then
        notify_status="stopped"
    elif [[ "$exit_reason" == circuit_breaker* ]]; then
        notify_status="error"
    fi

    # Send final notifications
    send_slack_notification "$notify_status" "$ITERATION"
    send_desktop_notification "Ralph v2" "$project_name: $exit_reason after $ITERATION iterations ($TOTAL_COMMITS commits)"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

main "$@"
