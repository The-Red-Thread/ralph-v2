# Ralph v2 - Core Philosophy

The principles that make Ralph work.

## 1. Context Is Everything

LLM context windows have limits:
- 200K advertised ≈ 176K usable
- 40-60% utilization = "smart zone"
- Beyond ~70% quality degrades

**Ralph's Solution:**
- Main agent acts as scheduler
- Subagents act as workers (~156kb each)
- Subagents are garbage collected after use
- Massive parallelism for reads (250-500)
- Single subagent for writes (backpressure)

## 2. Steering Ralph

You guide Ralph through environmental signals, not just prompt text.

### Upstream: Discoverable Inputs

Plant "signs" Ralph will find:
- **Code patterns** in `src/lib` - Ralph discovers and follows
- **Utilities** - Ralph reuses rather than reinventing
- **Conventions** - Consistent naming, structure, organization
- **Specs** - Clear acceptance criteria

### Downstream: Backpressure

Quality gates that catch errors:
- **Tests** - Behavioral verification
- **Types** - Compile-time checks
- **Lint** - Style enforcement
- **LLM-as-Judge** - Perceptual quality (tone, aesthetics)

### The Feedback Loop

```
Upstream Signals → Ralph Implements → Backpressure Catches Errors → Ralph Corrects
```

## 3. Let Ralph Ralph

Trust the LLM to self-manage:

**Self-Identify:** Ralph finds what needs work by comparing specs to code.

**Self-Correct:** When tests fail, Ralph fixes issues without human intervention.

**Self-Improve:** Ralph updates IMPLEMENTATION_PLAN.md with learnings.

**Eventual Consistency:** Through iteration, Ralph converges on correct implementation.

## 4. The Plan Is Disposable

IMPLEMENTATION_PLAN.md is a living document:
- Regenerate when wrong
- Update continuously during work
- Clean out completed items
- Don't over-invest in plan perfection

```bash
# Plan gone wrong? Just regenerate
rm IMPLEMENTATION_PLAN.md
~/.ralph-v2/loop.sh plan
```

## 5. Move Outside the Loop

Your role as human operator:

**Observe:** Watch Ralph work, notice patterns.

**Course Correct:** Tune like a guitar—adjust reactively.

**Plant Signs:** Add utilities, patterns, specs as needed.

**Don't Over-Specify:** Start with minimal AGENTS.md, add only as needed.

## 6. Scoping Happens at Planning

For feature branches, scope at plan creation:

- ❌ **Wrong:** Full project plan → ask Ralph to filter at runtime (70-80% unreliable)
- ✅ **Right:** Create scoped plan upfront → deterministic, simple

```bash
git checkout -b ralph/feature-x
~/.ralph-v2/loop.sh plan-work "feature x description"
```

## 7. Use Protection

`--dangerously-skip-permissions` bypasses all security:

> "It's not if it gets popped, it's when. What's the blast radius?"

**Always run in sandboxed environments.** See [sandbox-environments.md](./sandbox-environments.md).

## 8. Complete Implementations Only

**No placeholders. No stubs. No TODOs.**

Each iteration should produce working, tested code. Incomplete work means:
- Future iterations redo the same work
- Wasted context on rediscovery
- Accumulated technical debt

## 9. Single Sources of Truth

**No migrations. No adapters. No compatibility layers.**

When something changes:
- Change it everywhere
- Fix all affected tests
- Don't leave old code paths

## 10. AGENTS.md Is Operational Only

AGENTS.md pollutes every loop's context. Keep it brief:

- ✅ Build commands
- ✅ Validation commands
- ✅ Key patterns
- ❌ Status updates (→ IMPLEMENTATION_PLAN.md)
- ❌ Progress notes (→ IMPLEMENTATION_PLAN.md)
- ❌ Changelogs (→ git history)

## The Two-Loop Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     RALPH V2 SYSTEM                          │
│                                                              │
│  Outer Loop (loop.sh)                                        │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  while true; do                                        │  │
│  │    cat PROMPT_{mode}.md | claude -p --dangerously...   │  │
│  │    git push                                            │  │
│  │  done                                                  │  │
│  └────────────────────────────────────────────────────────┘  │
│                            │                                 │
│                            ▼                                 │
│  Inner Loop (within Claude session)                          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Tool calls ↔ LLM reasoning ↔ Tool calls               │  │
│  │  Until task complete → commit → exit                   │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

**Outer Loop:** Bash script, dumb, persistent. Feeds prompts, pushes changes.

**Inner Loop:** Claude session, smart, ephemeral. Does the actual work.

## Summary

1. **Context is precious** - Use subagents wisely
2. **Steer with signals** - Upstream patterns, downstream backpressure
3. **Trust the process** - Let Ralph self-correct through iteration
4. **Plans are disposable** - Regenerate when wrong
5. **Stay outside** - Observe, tune, don't micromanage
6. **Scope at planning** - Deterministic > probabilistic
7. **Use sandboxes** - Assume breach, limit blast radius
8. **Complete work only** - No stubs, no placeholders
9. **Single truth** - No adapters, no migrations
10. **Brief AGENTS.md** - Operational only, not a changelog
