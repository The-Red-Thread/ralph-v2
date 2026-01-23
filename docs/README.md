# Ralph v2 - Usage Guide

Ralph v2 is an autonomous AI coding agent that transforms specifications into implemented code through structured planning and building loops.

## Prerequisites

**Required:**
- **bash** 4.0+ (macOS/Linux)
- **git** - Version control
- **Claude CLI** - The AI backbone

**Installing Claude CLI:**
```bash
npm install -g @anthropic-ai/claude-code
claude auth  # Authenticate with your API key
```

**Optional:**
- **envsubst** - For `plan-work` mode (from gettext package)
  ```bash
  # macOS
  brew install gettext

  # Linux
  apt-get install gettext
  ```

## Installation

```bash
# Clone Ralph v2
git clone https://github.com/The-Red-Thread/ralph-v2.git ~/.ralph-v2

# Check prerequisites
~/.ralph-v2/install.sh check

# Add aliases to your shell (~/.zshrc or ~/.bashrc)
alias ralph='~/.ralph-v2/loop.sh'
alias ralph-init='~/.ralph-v2/install.sh init'
alias ralph-check='~/.ralph-v2/install.sh check'

# Reload shell
source ~/.zshrc
```

## Quick Start

```bash
# 1. Initialize a project
cd /path/to/your-project
ralph-init

# 2. Edit AGENTS.md with your build/test commands

# 3. Create your first spec
# Discuss requirements with Claude, then save to specs/feature-name.md

# 4. Generate implementation plan
ralph plan

# 5. Build
ralph 20  # Run 20 iterations
```

## Workflow Overview

### Phase 1: Define Requirements (Human + LLM)

Work with Claude to define specifications in `specs/*.md`. Each spec should cover one "topic of concern" or user activity.

**Using AskUserQuestion (Enhancement):**
```
Interview me using AskUserQuestion to understand the user authentication requirements
```

Claude will iteratively ask clarifying questions until requirements stabilize.

### Phase 2: Plan (Ralph Loop)

```bash
ralph plan      # Full project planning
ralph plan 5    # Plan with max 5 iterations
```

Ralph reads specs, compares against existing code, and generates `IMPLEMENTATION_PLAN.md`.

### Phase 3: Build (Ralph Loop)

```bash
ralph           # Build unlimited
ralph 20        # Build max 20 iterations
```

Ralph implements one task per iteration, runs tests, commits, and pushes.

## Feature Branches (Enhancement)

For scoped work on branches:

```bash
# 1. Create work branch
git checkout -b ralph/user-auth

# 2. Scoped planning (creates plan for ONLY this work)
ralph plan-work "user authentication with OAuth"

# 3. Build from scoped plan
ralph 10

# 4. Create PR when complete

# 5. Archive working files (optional but recommended)
ralph done
```

The `ralph done` command archives `IMPLEMENTATION_PLAN.md` and `AUDIT_REPORT.md` to `.ralph-v2/archive/` so you start fresh on the next feature.

## Codebase Audit

Ralph can audit your codebase to verify documentation accuracy and identify patterns:

```bash
# Full audit (documentation + patterns + code quality)
ralph audit

# Only verify documentation accuracy
ralph audit --docs-only

# Include pattern analysis
ralph audit --patterns

# Lightweight audit (fewer subagents, lower cost)
ralph audit --quick

# Full analysis with auto-apply safe fixes
ralph audit --full --apply

# Apply documentation fixes (alias for --apply)
ralph audit --apply-docs

# Analyze testing gaps and feedback loops
ralph audit --backpressure
```

**Audit scopes:**
- `--docs-only`: Verifies AGENTS.md, CLAUDE.md, README.md match actual code
- `--patterns`: Adds pattern analysis (good patterns, inconsistencies, anti-patterns)
- `--full`: Complete analysis including code quality concerns (default)
- `--backpressure`: Analyzes testing infrastructure and recommends task-specific validation

**Cost optimization:**
- `--quick`: Uses ~10 subagents instead of ~100, prioritizes high-impact checks
- `--docs-only --quick`: Minimal cost, just verifies documentation accuracy
- Full audit on large codebases can cost $10-50+ depending on size

**Output:**
- `AUDIT_REPORT.md` - Detailed findings with evidence (file:line citations)
- If `--apply` or `--apply-docs`:
  - Safe documentation fixes applied automatically via Edit tool
  - A commit is created with the applied changes
  - Summary printed showing what was fixed vs. what needs human review

**Key principles:**
- Every finding must cite specific `file:line` with quoted code
- Conservative: better to miss something than report false positives
- Good patterns are documented for AGENTS.md
- Bad patterns are flagged for IMPLEMENTATION_PLAN.md

**When to run:**
- After major refactoring to sync documentation
- Before onboarding new team members
- Periodically to catch documentation drift
- When Ralph seems to be going in circles (stale docs often the cause)

## Backpressure Audit

Analyze your testing infrastructure and identify gaps in feedback loops:

```bash
ralph audit --backpressure
```

**What it analyzes:**
- **Code categories**: UI components, API routes, hooks, utilities, etc.
- **Existing tests**: Unit tests, integration tests, E2E, visual tests
- **CI configuration**: What validations run on push/PR
- **Feedback loop speed**: What runs on save vs commit vs push

**Output:** `BACKPRESSURE_REPORT.md` with:
- Coverage analysis by code category
- Gap identification (code without tests)
- Task-specific validation recommendations
- Ready-to-copy AGENTS.md additions
- Setup instructions for missing infrastructure

**Example output:**
```markdown
| Category | Files | Tests | Coverage | Grade |
|----------|------:|------:|---------:|-------|
| UI Components | 47 | 3 | 6% | D |
| API Routes | 12 | 0 | 0% | F |
| Hooks | 9 | 2 | 22% | D |
| Utilities | 8 | 5 | 62% | B |

## Recommendations
1. Set up visual testing for UI components
2. Add integration tests for API routes
3. Add unit tests for hooks
```

**When to run:**
- When setting up a new project
- When test coverage feels inadequate
- When Ralph keeps introducing regressions
- Before adding new team members to understand testing expectations

## Key Files

### In Your Project (Committed)

| File | Purpose |
|------|---------|
| `AGENTS.md` | Operational guide (build commands, validation, patterns) |
| `CLAUDE.md` | Project-specific instructions for Claude |
| `AUDIENCE_JTBD.md` | (Optional) User personas and jobs-to-be-done |
| `specs/*.md` | Requirement specifications (grow over time) |

### Working Files (Gitignored - Local Only)

| File | Purpose |
|------|---------|
| `IMPLEMENTATION_PLAN.md` | Task list for current work session |
| `AUDIT_REPORT.md` | Point-in-time audit findings |
| `.ralph-v2/archive/` | Archived working files from completed features |

Working files are **not committed** to avoid conflicts when multiple people use Ralph on the same project. Each person has their own local copy.

### In Ralph v2

| File | Purpose |
|------|---------|
| `loop.sh` | Main loop script |
| `PROMPT_plan.md` | Planning mode prompt |
| `PROMPT_build.md` | Building mode prompt |
| `PROMPT_plan_work.md` | Scoped planning prompt |

## Key Concepts

### Jobs to Be Done (JTBD)

Focus on user outcomes, not features:
- ❌ "Color picker component"
- ✅ "When uploading a photo, extract dominant colors so I can create a palette"

### Topics of Concern

One spec per topic. Topics map to user activities:
- `specs/photo-upload.md`
- `specs/color-extraction.md`
- `specs/palette-export.md`

### Backpressure

Quality gates that provide feedback:
- **Tests:** Must pass before commit
- **Types:** TypeScript/type checking
- **Lint:** Code style enforcement
- **LLM-as-Judge:** Perceptual quality tests for subjective criteria (tone, text quality)
- **Visual Testing:** UI verification for layout, responsive design, accessibility

### Acceptance-Driven Testing

Specs include acceptance criteria. Tests are derived from criteria:

```markdown
## Acceptance Criteria
- Extracts 5-10 dominant colors from images <5MB in <100ms
- Handles grayscale images gracefully

## Test Requirements
- [ ] Verify color count (5-10)
- [ ] Verify performance (<100ms)
- [ ] Test grayscale handling
```

### Subagent Fan-Out

Ralph uses parallel subagents for scalability:
- 250-500 Sonnet subagents for reading/searching
- 1 Sonnet subagent for building/testing (backpressure)
- Opus subagents for complex reasoning

## Troubleshooting

### "Ralph going in circles"

The plan may be incorrect. Regenerate:
```bash
rm IMPLEMENTATION_PLAN.md
ralph plan
```

### "Wrong patterns emerging"

Add utilities to `src/lib` to guide Ralph toward better patterns. Ralph discovers and follows patterns in the standard library.

### "Context overflow"

- Break tasks into smaller units
- Use more subagent fan-out
- Clean out completed items from IMPLEMENTATION_PLAN.md

### "Tests keep failing"

- Check AGENTS.md has correct validation commands
- Ensure acceptance criteria are realistic
- Review test requirements in the plan

### "AGENTS.md getting bloated"

Move status updates to IMPLEMENTATION_PLAN.md. AGENTS.md should only contain operational information.

## Commands Reference

```bash
# Basic commands
ralph                        # Build mode, unlimited
ralph 20                     # Build mode, max 20 iterations
ralph plan                   # Planning mode, unlimited
ralph plan 5                 # Planning mode, max 5 iterations
ralph plan-work "desc"       # Scoped planning for branch
ralph plan-work "desc" 3     # Scoped planning, max 3 iterations
ralph done                   # Archive working files after feature complete

# Audit commands
ralph audit                  # Full codebase audit
ralph audit --docs-only      # Documentation accuracy only
ralph audit --patterns       # Include pattern analysis
ralph audit --quick          # Lightweight audit (lower cost)
ralph audit --full --apply   # Full audit with auto-apply fixes
ralph audit --apply-docs     # Apply documentation fixes only
ralph audit --backpressure   # Analyze testing gaps and feedback loops

# Monitoring & safety flags (can combine with any mode)
ralph --monitor 20           # Build with live tmux dashboard
ralph plan --monitor         # Plan with live monitoring
ralph --no-circuit-breaker   # Disable circuit breaker
ralph --circuit-breaker-threshold 5  # Custom threshold (default: 3)
ralph monitor                # Attach to existing monitor session

# Setup commands
ralph-init                   # Initialize current directory as Ralph project
ralph-check                  # Check prerequisites are installed
```

## Circuit Breaker

Ralph v2 includes a circuit breaker that automatically stops execution when it detects the loop is stuck. This prevents runaway API costs and wasted iterations.

### How It Works

The circuit breaker monitors two conditions:

1. **No Progress:** Stops after N consecutive iterations with no new commits (default: 3)
2. **Consecutive Errors:** Stops after N consecutive iteration failures (default: 5)

### Configuration

```bash
# In ~/.config/ralph/config
CIRCUIT_BREAKER_ENABLED=true          # Enable/disable (default: true)
CIRCUIT_BREAKER_THRESHOLD=3           # No-progress threshold (default: 3)
CIRCUIT_BREAKER_ERROR_THRESHOLD=5     # Error threshold (default: 5)
```

### Command Line Options

```bash
ralph --no-circuit-breaker 50         # Disable for this session
ralph --circuit-breaker-threshold 5   # Custom threshold for this session
```

### When It Triggers

When the circuit breaker trips, Ralph displays diagnostic information:

```
╔═══════════════════════════════════════════════════════════════╗
║              CIRCUIT BREAKER TRIGGERED                        ║
╠═══════════════════════════════════════════════════════════════╣
║  No commits in 3 consecutive iterations.                      ║
║  Ralph may be stuck in a loop.                                ║
║                                                               ║
║  Suggestions:                                                 ║
║  • Check IMPLEMENTATION_PLAN.md for issues                    ║
║  • Run 'ralph plan' to regenerate the plan                    ║
║  • Review the log file: ralph.log                             ║
╚═══════════════════════════════════════════════════════════════╝
```

## Live Monitoring

Ralph v2 supports live monitoring via tmux for real-time visibility into long-running sessions.

### Prerequisites

```bash
# macOS
brew install tmux

# Linux
apt install tmux
```

### Usage

```bash
# Start Ralph with monitoring
ralph --monitor 20

# In another terminal, attach to the monitor
ralph monitor
# or
tmux attach -t ralph-monitor
```

### Monitor Layout

The tmux session has three panes:

1. **Left (main):** Live log file stream
2. **Top right:** Status JSON + recent commits + plan preview
3. **Bottom right:** Simple progress indicator (iteration, commits, stall count)

### Status File

Ralph writes a `.ralph-status.json` file that the monitor reads:

```json
{
    "timestamp": 1705847123,
    "iteration": 5,
    "max_iterations": 20,
    "mode": "build",
    "branch": "ralph/feature-x",
    "total_commits": 3,
    "consecutive_no_progress": 0,
    "circuit_breaker_threshold": 3,
    "iterations_this_hour": 5,
    "status": "running"
}
```

## Rate Tracking

Ralph tracks iteration rate and warns when approaching high usage:

- Tracks iterations per hour
- Warns at 50 iterations/hour (configurable via `RATE_WARNING_THRESHOLD`)
- Displays rate info in session summary

```bash
# In ~/.config/ralph/config
RATE_WARNING_THRESHOLD=50   # Warn at this many iterations/hour
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_DIR` | `~/.ralph-v2` | Ralph installation directory |
| `CONFIG_FILE` | `~/.config/ralph/config` | Configuration file path |
| `CIRCUIT_BREAKER_ENABLED` | `true` | Enable/disable circuit breaker |
| `CIRCUIT_BREAKER_THRESHOLD` | `3` | Iterations without commits before stopping |
| `CIRCUIT_BREAKER_ERROR_THRESHOLD` | `5` | Consecutive errors before stopping |
| `RATE_WARNING_THRESHOLD` | `50` | Warn at this many iterations/hour |

## Notifications

Ralph v2 supports Slack and desktop notifications to keep you informed when running unattended.

### Configuration

Edit `~/.config/ralph/config`:

```bash
# =============================================================================
# Notifications
# =============================================================================

# Slack webhook URL (required for Slack notifications)
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/xxx/yyy/zzz"

# Notify per iteration (default: false)
NOTIFY_PER_ITERATION=true

# Desktop notifications on macOS (default: true)
DESKTOP_NOTIFICATION=true

# =============================================================================
# Circuit Breaker
# =============================================================================

# Enable/disable circuit breaker (default: true)
CIRCUIT_BREAKER_ENABLED=true

# Stop after N iterations with no commits (default: 3)
CIRCUIT_BREAKER_THRESHOLD=3

# Stop after N consecutive errors (default: 5)
CIRCUIT_BREAKER_ERROR_THRESHOLD=5

# =============================================================================
# Rate Tracking
# =============================================================================

# Warn at this many iterations per hour (default: 50)
RATE_WARNING_THRESHOLD=50
```

### Setting Up Slack

1. Go to [Slack API](https://api.slack.com/messaging/webhooks)
2. Create a new app or use an existing one
3. Enable "Incoming Webhooks"
4. Add a new webhook to your workspace
5. Copy the webhook URL to your config file

### Notification Events

| Event | Slack | Desktop |
|-------|-------|---------|
| Session complete | ✅ | ✅ |
| Max iterations reached | ✅ | ✅ |
| Session interrupted (Ctrl+C) | ✅ | ✅ |
| Circuit breaker triggered | ✅ | ✅ |
| Each iteration (if enabled) | ✅ | ❌ |

### Slack Message Content

Notifications include:
- Project name and branch
- Mode (plan/build/plan-work)
- Session duration
- Iteration count
- Total commits this session
- Latest commit hash
- Exit reason

## Conventions

### Source Directory

Prompts reference `src/*` as the application source code location. This is a convention, not enforced. If your project uses a different structure (e.g., `lib/`, `app/`), update the prompts accordingly.

### Standard Library

Place shared utilities in `src/lib/`. Ralph discovers patterns there and reuses them rather than creating ad-hoc implementations.

### Visual Testing

Visual testing provides automated UI verification using `agent-browser` and LLM-as-Judge:

**Prerequisites:**
```bash
npm install -g agent-browser  # Browser automation
# Ensure ANTHROPIC_API_KEY is set
```

**Usage:**
```typescript
import { createVisualTestSession, VIEWPORTS } from './visual-testing';

// Session-based testing
const session = await createVisualTestSession({ baseUrl: 'http://localhost:3000' });
await session.navigate('/dashboard');
await session.assertLayout('Clear visual hierarchy');
await session.assertResponsive('Content readable on all devices');
await session.assertAccessibility('WCAG AA compliance');
await session.close();

// One-off checks
await assertPageVisual('http://localhost:3000', 'Professional design');
await assertPageAccessibility('http://localhost:3000');
```

**Assertion types:**
- `assertLayout(criteria)` - Visual hierarchy and structure
- `assertResponsive(criteria, viewports[])` - Multi-viewport testing
- `assertAccessibility(criteria)` - A11y checks with contrast verification
- `assertInteractiveState({target, state, criteria})` - Hover/focus/active states
- `assertBaseline(name, criteria)` - Visual regression against baselines

**Running visual tests:**
```bash
# Ensure app is running first
npm run test:visual

# Update baselines after design approval
npm run update-baselines
```

### Git Tagging

PROMPT_build.md instructs Ralph to create semantic version tags (starting at 0.0.0) when tests pass. Tags are incremented automatically.

### Subagent Numbers

Numbers like "250 parallel Sonnet subagents" are guidance for parallelism, not literal requirements. The LLM interprets these contextually.

## See Also

- [Philosophy](./philosophy.md) - Core principles behind Ralph
- [Sandbox Environments](./sandbox-environments.md) - Secure execution options
