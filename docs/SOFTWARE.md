# Software Documentation

This document lists all software installed on the devstation and within devcontainers.

## Host System Software

Software installed on the VM host (outside containers).

### Core Tools

| Software | Version | Purpose |
|----------|---------|---------|
| Ubuntu | 24.04 LTS | Operating system |
| Docker CE | 29.1.5 | Container runtime |
| Docker Compose | 2.x (plugin) | Multi-container orchestration |
| Docker Buildx | latest | Extended build capabilities |
| Git | 2.43.0 | Version control |
| Git LFS | latest | Large file storage |

### Node.js Ecosystem

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 18.19.1+ | JavaScript runtime |
| npm | 9.2.0+ | Package manager |
| @devcontainers/cli | 0.81.1 | Headless devcontainer management |

### GitHub Tools

| Software | Version | Purpose |
|----------|---------|---------|
| GitHub CLI (gh) | 2.45.0 | GitHub API and repo management |

## Devcontainer Software

Software available inside devcontainers (varies by template).

### .NET Template

| Software | Version | Purpose |
|----------|---------|---------|
| .NET SDK | 9.0 | .NET development |
| PostgreSQL | 16+ | Database server |
| Node.js | 22.11.0 | Frontend tooling |
| Bun | 1.1.34 | Fast JS runtime/bundler |
| Python | 3.12+ | Scripting |
| GitHub CLI | latest | GitHub integration |

### Node.js Template

| Software | Version | Purpose |
|----------|---------|---------|
| Node.js | 20.x LTS | JavaScript runtime |
| npm | 10.x | Package manager |
| Python | 3.12+ | Build tools |
| GitHub CLI | latest | GitHub integration |

### Python Template

| Software | Version | Purpose |
|----------|---------|---------|
| Python | 3.12 | Python runtime |
| pip | latest | Package manager |
| venv | built-in | Virtual environments |
| GitHub CLI | latest | GitHub integration |

## AI CLIs (Optional)

These are installed via post-create script if not skipped:

| Tool | Purpose |
|------|---------|
| Claude CLI | Anthropic's Claude assistant |
| Gemini CLI | Google's Gemini assistant |
| Codex CLI | OpenAI Codex integration |

Skip during build with `--skip-ai-clis` or `--fast`.

## VS Code Extensions (Devcontainer)

Extensions installed automatically in devcontainers:

### .NET Development
- `ms-dotnettools.csharp` - C# language support
- `ms-dotnettools.vscode-dotnet-runtime` - .NET runtime
- `ms-azuretools.vscode-docker` - Docker integration

### Web Development
- `esbenp.prettier-vscode` - Code formatting
- `dbaeumer.vscode-eslint` - JavaScript linting
- `msjsdiag.vscode-react-native` - React Native support

## Version Checking Commands

```bash
# Host system
docker --version
node --version
npm --version
git --version
gh --version
devcontainer --version

# Inside container
dotnet --version
psql --version
python3 --version
bun --version
```

## Updating Software

### Host System

```bash
# System packages
sudo apt update && sudo apt upgrade -y

# @devcontainers/cli
sudo npm update -g @devcontainers/cli

# Docker (via apt)
sudo apt update && sudo apt install docker-ce docker-ce-cli
```

### Devcontainer Images

Rebuild containers to get updated base images:

```bash
# Full rebuild with no cache
~/devcontainer-rebuild.sh ~/code --force --prune
```

## Disk Usage

Typical disk usage for a devstation:

| Component | Size |
|-----------|------|
| Ubuntu base | ~5 GB |
| Docker images (per repo) | 2-5 GB |
| node_modules (per repo) | 0.5-2 GB |
| .nuget packages | 0.5-1 GB |
| Git repos | varies |

Clean up unused resources:
```bash
~/devcontainer-cleanup.sh --all
docker system prune -af
```

## Network Ports

Default ports used:

| Port | Service |
|------|---------|
| 22 | SSH |
| 5432 | PostgreSQL |
| 5135 | .NET API (typical) |
| 8081 | React Native web |
| 3000 | Node.js dev server |

Ports are forwarded from containers automatically via devcontainer config.
