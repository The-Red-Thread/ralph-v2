# CLAUDE.md - Ralph v2 Project

This file contains instructions for Claude Code when working on Ralph v2 itself.

## Project Overview

Ralph v2 is an autonomous AI coding agent that uses a simple bash loop to orchestrate Claude CLI sessions. Each iteration = one task = fresh context.

**Core Philosophy:** "Ralph is a Bash loop." Keep it simple. Let the LLM do the thinking.

## Directory Structure

```
~/.ralph-v2/
├── loop.sh                 # Main orchestration script
├── PROMPT_plan.md          # Planning mode prompt
├── PROMPT_build.md         # Building mode prompt
├── PROMPT_plan_work.md     # Scoped planning prompt
├── install.sh              # Installation script
├── templates/              # Project initialization templates
├── docs/                   # Documentation
└── examples/               # Example specs and libraries
```

## Key Files

### loop.sh

The main bash script. Conventions:
- Use `set -euo pipefail`
- Use logging functions: `log`, `success`, `warn`, `error`
- Keep functions small and focused
- Quote all variables: `"$var"` not `$var`

### PROMPT_*.md

Prompt templates fed to Claude CLI. Key patterns:
- Phase 0: Context gathering with parallel subagents
- Numbered instructions for main workflow
- Guardrails using escalating 9s (99999, 999999, etc.)
- "Ultrathink" keyword for deep analysis
- `@FILE` syntax for file references

### templates/

Templates copied to projects during init:
- Keep AGENTS.md brief (~60 lines max)
- IMPLEMENTATION_PLAN.md is minimal (LLM manages format)
- AUDIENCE_JTBD.md for optional JTBD workflow

## Conventions

### Source Directory

Prompts reference `src/*` as the convention for application source code. This is a convention, not enforced. Projects may use different structures.

### Subagent Guidance

Numbers like "250 parallel Sonnet subagents" are guidance for the LLM about parallelism level, not literal requirements. The LLM interprets these based on context.

### The 9s Pattern

Guardrails in PROMPT_build.md use escalating numbers:
- 99999 = important
- 999999 = more important
- 9999999999999999 = critical

Higher = more critical invariant.

## Testing Changes

1. Syntax check: `bash -n loop.sh`
2. Test argument parsing with mock functions
3. Test in a real git repo with specs
4. Verify all modes: `plan`, `build`, `plan-work`

## Making Changes

### Adding a New Mode

1. Add case in `parse_arguments()` in loop.sh
2. Create `PROMPT_<mode>.md`
3. Update docs/README.md
4. Test the new mode

### Modifying Prompts

1. Maintain the phase structure (0, 1, 2, ...)
2. Keep guardrails numbered with 9s pattern
3. Use `@FILE` for file references
4. Include "Ultrathink" for complex analysis steps
5. End with clear exit conditions

### Adding Templates

1. Create in `templates/`
2. Update `install.sh init_project()` to copy it
3. Document in docs/README.md

## Dependencies

- bash (4.0+)
- git
- claude CLI (`@anthropic-ai/claude-code`)
- envsubst (from gettext)

## No TypeScript/Node

Ralph v2 is pure bash orchestration. The only TypeScript is in `examples/llm-review/` which is a template for projects to copy, not part of Ralph itself.
