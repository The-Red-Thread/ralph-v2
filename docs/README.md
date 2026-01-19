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
# Clone or download Ralph v2 to ~/.ralph-v2
# Then run the install script:
~/.ralph-v2/install.sh

# Or initialize a project directly:
~/.ralph-v2/install.sh init /path/to/project
```

## Quick Start

```bash
# 1. Initialize a project
cp ~/.ralph-v2/templates/AGENTS.md ./AGENTS.md
cp ~/.ralph-v2/templates/AUDIENCE_JTBD.md ./AUDIENCE_JTBD.md  # Optional
mkdir specs

# 2. Create your first spec
# Discuss requirements with Claude, then save to specs/feature-name.md
# Or use AskUserQuestion: "Interview me using AskUserQuestion to understand [JTBD/topic]"

# 3. Generate implementation plan
~/.ralph-v2/loop.sh plan

# 4. Build
~/.ralph-v2/loop.sh 20  # Run 20 iterations
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
~/.ralph-v2/loop.sh plan      # Full project planning
~/.ralph-v2/loop.sh plan 5    # Plan with max 5 iterations
```

Ralph reads specs, compares against existing code, and generates `IMPLEMENTATION_PLAN.md`.

### Phase 3: Build (Ralph Loop)

```bash
~/.ralph-v2/loop.sh           # Build unlimited
~/.ralph-v2/loop.sh 20        # Build max 20 iterations
```

Ralph implements one task per iteration, runs tests, commits, and pushes.

## Feature Branches (Enhancement)

For scoped work on branches:

```bash
# 1. Create work branch
git checkout -b ralph/user-auth

# 2. Scoped planning (creates plan for ONLY this work)
~/.ralph-v2/loop.sh plan-work "user authentication with OAuth"

# 3. Build from scoped plan
~/.ralph-v2/loop.sh 10

# 4. Create PR when complete
```

## Key Files

### In Your Project

| File | Purpose |
|------|---------|
| `AGENTS.md` | Operational guide (build commands, validation, patterns) |
| `IMPLEMENTATION_PLAN.md` | Task list managed by Ralph |
| `AUDIENCE_JTBD.md` | (Optional) User personas and jobs-to-be-done |
| `specs/*.md` | Requirement specifications |

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
- **LLM-as-Judge:** Perceptual quality tests for subjective criteria

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
~/.ralph-v2/loop.sh plan
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
~/.ralph-v2/loop.sh                           # Build mode, unlimited
~/.ralph-v2/loop.sh 20                        # Build mode, max 20 iterations
~/.ralph-v2/loop.sh plan                      # Planning mode, unlimited
~/.ralph-v2/loop.sh plan 5                    # Planning mode, max 5 iterations
~/.ralph-v2/loop.sh plan-work "description"   # Scoped planning for branch
~/.ralph-v2/loop.sh plan-work "desc" 3        # Scoped planning, max 3 iterations
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RALPH_DIR` | `~/.ralph-v2` | Ralph installation directory |

## Conventions

### Source Directory

Prompts reference `src/*` as the application source code location. This is a convention, not enforced. If your project uses a different structure (e.g., `lib/`, `app/`), update the prompts accordingly.

### Standard Library

Place shared utilities in `src/lib/`. Ralph discovers patterns there and reuses them rather than creating ad-hoc implementations.

### Git Tagging

PROMPT_build.md instructs Ralph to create semantic version tags (starting at 0.0.0) when tests pass. Tags are incremented automatically.

### Subagent Numbers

Numbers like "250 parallel Sonnet subagents" are guidance for parallelism, not literal requirements. The LLM interprets these contextually.

## See Also

- [Philosophy](./philosophy.md) - Core principles behind Ralph
- [Sandbox Environments](./sandbox-environments.md) - Secure execution options
