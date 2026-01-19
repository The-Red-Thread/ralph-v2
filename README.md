# Ralph v2

An autonomous AI coding agent based on [Geoffrey Huntley's Ralph Wiggum Technique](https://ghuntley.com/ralph/).

Ralph transforms feature specifications into implemented code through structured planning and building loops. It's "a bash loop that feeds prompts to Claude CLI" — simple orchestration, smart execution.

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Outer Loop (loop.sh)                                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  while true; do                                       │  │
│  │    cat PROMPT.md | claude -p --dangerously-skip...    │  │
│  │    git push                                           │  │
│  │  done                                                 │  │
│  └───────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼                                 │
│  Inner Loop (Claude session)                                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Read specs → Implement → Test → Commit → Exit        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

Each iteration = one task = fresh context. The LLM manages its own work via self-updating markdown files.

## Installation

```bash
# Clone to ~/.ralph-v2
git clone https://github.com/The-Red-Thread/ralph-v2.git ~/.ralph-v2

# Check prerequisites
~/.ralph-v2/install.sh check

# Add aliases to your shell (add to ~/.zshrc or ~/.bashrc)
alias ralph='~/.ralph-v2/loop.sh'
alias ralph-init='~/.ralph-v2/install.sh init'
alias ralph-check='~/.ralph-v2/install.sh check'

# Reload shell
source ~/.zshrc  # or ~/.bashrc
```

## Quick Start

```bash
# 1. Initialize your project
cd /path/to/your-project
ralph-init

# 2. Edit AGENTS.md with your build/test commands

# 3. Create specs in specs/*.md

# 4. Plan
ralph plan

# 5. Build (20 iterations)
ralph 20
```

## Documentation

| Document | Description |
|----------|-------------|
| [docs/README.md](docs/README.md) | Full usage guide |
| [docs/philosophy.md](docs/philosophy.md) | Core principles and patterns |
| [docs/sandbox-environments.md](docs/sandbox-environments.md) | Security and sandboxing |

## Directory Structure

```
~/.ralph-v2/
├── loop.sh                 # Main orchestration script
├── PROMPT_plan.md          # Planning mode prompt
├── PROMPT_build.md         # Building mode prompt
├── PROMPT_plan_work.md     # Scoped planning (feature branches)
├── install.sh              # Installation and project init
├── templates/              # Files copied to new projects
│   ├── AGENTS.md           # Operational guide template
│   ├── IMPLEMENTATION_PLAN.md
│   └── AUDIENCE_JTBD.md    # Optional JTBD workflow
├── docs/                   # Documentation
└── examples/               # Example specs and libraries
    ├── specs/              # Example specification format
    └── llm-review/         # LLM-as-Judge library template
```

## Commands

```bash
ralph                        # Build mode, unlimited iterations
ralph 20                     # Build mode, max 20 iterations
ralph plan                   # Planning mode
ralph plan 5                 # Planning mode, max 5 iterations
ralph plan-work "desc"       # Scoped planning for feature branch
ralph-init                   # Initialize current directory as Ralph project
ralph-check                  # Check prerequisites are installed
```

## Key Concepts

- **Specs** (`specs/*.md`) - Requirements written as acceptance criteria
- **AGENTS.md** - Operational guide (build commands, patterns) — updated by Ralph
- **IMPLEMENTATION_PLAN.md** - Task list — managed entirely by Ralph
- **Backpressure** - Tests, types, and lint that catch errors automatically
- **Subagent fan-out** - Parallel LLM calls for reading, single for writing

## Prerequisites

- bash 4.0+
- git
- [Claude CLI](https://github.com/anthropics/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- envsubst (optional, for `plan-work` mode)

## Contributing

1. Read [CLAUDE.md](CLAUDE.md) for project conventions
2. Test changes with `bash -n loop.sh` (syntax check)
3. Test in a real project before submitting

### Key Files to Understand

- `loop.sh` - The bash orchestration loop
- `PROMPT_*.md` - Prompts fed to Claude CLI
- `templates/` - Files copied to projects during init

### The 9s Pattern

Guardrails in prompts use escalating numbers (99999, 999999, etc.). Higher = more critical. This is part of the original Ralph pattern.

## References

- [Geoffrey Huntley's Ralph post](https://ghuntley.com/ralph/)
- [ralph-playbook](https://github.com/ClaytonFarr/ralph-playbook) - Community playbook
- [Vercel's ralph-loop-agent](https://github.com/vercel-labs/ralph-loop-agent) - Vercel's implementation

## License

MIT
