# Ralph v2 - Sandbox Environments

Running Ralph with `--dangerously-skip-permissions` bypasses all security controls. **Always use sandboxed environments.**

> "It's not if it gets popped, it's when. What's the blast radius?"

## Environment Options

| Option | Cold Start | Best For | Cost |
|--------|------------|----------|------|
| Docker (local) | N/A | Development, free | Free |
| Sprites (Fly.io) | <1s | Long-running, persistent | ~$0.02/hr |
| E2B | ~150ms | Production loops | Usage-based |
| Modal | 2-5s | Python/ML workloads | Usage-based |
| Cloudflare | 1-5s | Edge, security-first | Usage-based |

## Docker (Recommended for Development)

### Setup

```bash
# Install Docker sandbox extension
docker extension install anthropic/claude-sandbox

# Or use Docker directly
docker pull anthropic/claude-sandbox:latest
```

### Usage

```bash
# Start a sandbox session
docker sandbox run claude

# Continue existing session
docker sandbox run -c

# With mounted project directory
docker sandbox run -v $(pwd):/workspace claude
```

### Dockerfile for Custom Environment

```dockerfile
FROM anthropic/claude-sandbox:latest

# Install project dependencies
RUN apt-get update && apt-get install -y \
    nodejs \
    npm \
    git

# Install global tools
RUN npm install -g pnpm typescript

WORKDIR /workspace
```

```bash
# Build and run
docker build -t my-ralph-sandbox .
docker run -it -v $(pwd):/workspace my-ralph-sandbox
```

## E2B (Production Recommendation)

E2B provides fast, isolated sandboxes optimized for AI agents.

### Setup

```bash
# Install E2B CLI
npm install -g @e2b/cli

# Authenticate
e2b auth login
```

### Usage with Ralph

```python
from e2b import Sandbox

# Create sandbox
sandbox = Sandbox(template="base")

# Run Ralph loop
sandbox.process.start(
    cmd="~/.ralph-v2/loop.sh 10",
    on_stdout=lambda msg: print(msg),
    on_stderr=lambda msg: print(msg, file=sys.stderr)
)
```

### Custom Template

```bash
# Create template
e2b template init

# Build and publish
e2b template build
e2b template publish
```

## Sprites (Fly.io)

Persistent sandboxes with sub-second cold starts.

### Setup

```bash
# Install Fly CLI
curl -L https://fly.io/install.sh | sh

# Authenticate
fly auth login
```

### Usage

```bash
# Launch sprite
fly launch --image anthropic/claude-sandbox

# Connect
fly ssh console
```

## Modal

Best for Python/ML workloads with GPU support.

### Setup

```python
import modal

app = modal.App("ralph-sandbox")

@app.function(
    image=modal.Image.debian_slim().pip_install("anthropic"),
    timeout=3600
)
def run_ralph(iterations: int):
    import subprocess
    subprocess.run(["~/.ralph-v2/loop.sh", str(iterations)])
```

### Usage

```bash
modal run ralph_sandbox.py
```

## Cloudflare Workers

Edge-first, security-focused sandboxes.

### Setup

```bash
# Install Wrangler
npm install -g wrangler

# Authenticate
wrangler login
```

### Worker Configuration

```toml
# wrangler.toml
name = "ralph-sandbox"
main = "src/index.ts"
compatibility_date = "2024-01-01"

[vars]
RALPH_DIR = "/workspace/.ralph-v2"
```

## Security Best Practices

### Network Isolation

```bash
# Docker: No network access
docker run --network none my-ralph-sandbox

# Docker: Limited network
docker run --network internal my-ralph-sandbox
```

### Resource Limits

```bash
# Docker: Memory and CPU limits
docker run \
    --memory=4g \
    --cpus=2 \
    --pids-limit=100 \
    my-ralph-sandbox
```

### Filesystem Restrictions

```bash
# Read-only root filesystem
docker run --read-only my-ralph-sandbox

# Specific writable directories
docker run \
    --read-only \
    --tmpfs /tmp \
    -v $(pwd):/workspace \
    my-ralph-sandbox
```

### Credentials Management

**Never** put credentials in:
- AGENTS.md
- specs/*.md
- IMPLEMENTATION_PLAN.md
- Any file Ralph can read

Use environment variables injected at runtime:
```bash
docker run \
    -e API_KEY="${API_KEY}" \
    -e DATABASE_URL="${DATABASE_URL}" \
    my-ralph-sandbox
```

## Monitoring

### Log Collection

```bash
# Docker: Follow logs
docker logs -f container_name

# Save to file
docker logs container_name > ralph-session.log 2>&1
```

### Resource Monitoring

```bash
# Docker stats
docker stats container_name

# Inside container
top -b -n 1
```

## Recovery

### Checkpoint and Restore

```bash
# Create checkpoint
docker checkpoint create container_name checkpoint1

# Restore from checkpoint
docker start --checkpoint checkpoint1 container_name
```

### Git as Recovery

Ralph commits after each successful task. To recover:

```bash
# See recent commits
git log --oneline -20

# Reset to known good state
git reset --hard <commit_sha>

# Restart Ralph
~/.ralph-v2/loop.sh
```

## Recommendations

1. **Development:** Docker local sandbox
2. **CI/CD:** E2B or Docker
3. **Production loops:** E2B with custom template
4. **Long-running work:** Sprites on Fly.io
5. **ML/Python heavy:** Modal

Always:
- Use network isolation when possible
- Set resource limits
- Inject credentials at runtime
- Monitor for anomalies
- Have recovery procedures ready
