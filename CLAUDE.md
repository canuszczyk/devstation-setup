# Devstation Setup

Bootstrap and configuration scripts for Ubuntu/Debian development servers.

## Architecture

Two-phase setup:
1. **bootstrap.sh** - Installs core dependencies (Docker, Node.js, gh CLI, devcontainers CLI, Claude Code)
2. **install.sh** - Interactive repo cloning from GitHub/Bitbucket, generates shell aliases

## Key Files

| File | Purpose |
|------|---------|
| `bootstrap.sh` | Core dependency installation (run first, typically via curl pipe) |
| `install.sh` | Interactive repo discovery and cloning |
| `scripts/` | Helper scripts installed to ~/bin |
| `templates/` | Devcontainer templates (node, python, dotnet) |
| `config/` | Configuration files |
| `docs/` | Documentation |

## Directory Structure After Setup

```
~/devstation-setup/     # This repo
~/code/                 # Cloned repositories
~/bin/                  # Helper scripts (in PATH)
```

## Devcontainer Workflow

Repos with `.devcontainer/devcontainer.json` can be built headlessly:
- `devcontainer build --workspace-folder ~/code/repo-name`
- `devcontainer up --workspace-folder ~/code/repo-name`
- `devcontainer exec --workspace-folder ~/code/repo-name bash`

## Shell Aliases

`install.sh` generates `dexec` aliases for quick container access:
- `dexec-reponame` - exec into the devcontainer for that repo

## Common Tasks

**Re-run installation:** `~/devstation-setup/install.sh`
**Rebuild containers:** `~/devcontainer-rebuild.sh ~/code`
**Clean up Docker:** `docker system prune -af`
