# Devstation Setup

Automated setup for a Linux devcontainer-based development environment. This repository documents and automates the setup of a fresh Linux VM to replicate a fully configured development station.

## Features

- **Docker CE** with compose plugin and buildx for container management
- **@devcontainers/cli** for headless devcontainer operations (no VS Code required)
- **Management scripts** for rebuilding, starting, stopping, and cleaning up devcontainers
- **Multi-repo support** - run multiple devcontainers simultaneously
- **SSH-based workflow** - connect via MobaXterm, VS Code Remote SSH, or terminal

## Quick Start

### On a Fresh Ubuntu VM

```bash
# Clone this repo
git clone https://github.com/YOUR_USERNAME/devstation-setup.git ~/devstation-setup

# Run the interactive installer
cd ~/devstation-setup
./install.sh
```

The installer will:
1. Install Docker, Node.js, and @devcontainers/cli
2. Install git and GitHub CLI (gh)
3. Prompt for your GitHub username/org
4. Show repos with `.devcontainer/` folders for you to select
5. Clone selected repos to `~/code`
6. Copy management scripts to `~/`
7. Add shell customizations to `~/.bashrc`
8. Optionally build devcontainers

### Manual Installation

See [docs/VM-SETUP.md](docs/VM-SETUP.md) for step-by-step manual instructions.

## Management Scripts

After installation, you'll have these scripts in your home directory:

| Script | Description |
|--------|-------------|
| `~/devcontainer-rebuild.sh [path]` | Rebuild devcontainer(s) |
| `~/devcontainer-open.sh [path]` | Start existing container(s) |
| `~/devcontainer-stop-all.sh` | Stop all running devcontainers |
| `~/devcontainer-cleanup.sh` | Clean up stopped containers/images |
| `~/dexec [path]` | Shell into a container by repo path |

See [scripts/README.md](scripts/README.md) for detailed usage.

## Daily Workflow

```bash
# Start all containers
~/devcontainer-open.sh ~/code

# Shell into a specific repo's container
~/dexec ~/code/MyRepo

# Or use the alias (if configured)
dexec-myrepo

# Stop everything at end of day
~/devcontainer-stop-all.sh
```

## Repository Structure

```
devstation-setup/
├── README.md                    # This file
├── install.sh                   # Interactive installer
├── docs/
│   ├── VM-SETUP.md             # Fresh VM setup guide
│   ├── SOFTWARE.md             # Software versions and details
│   ├── MOBAXTERM.md            # MobaXterm configuration
│   └── TROUBLESHOOTING.md      # Common issues and solutions
├── scripts/
│   ├── devcontainer-rebuild.sh
│   ├── devcontainer-open.sh
│   ├── devcontainer-stop-all.sh
│   ├── devcontainer-cleanup.sh
│   ├── devcontainer-start-all.sh
│   ├── dexec
│   └── README.md               # Script usage reference
├── config/
│   ├── bashrc-additions        # Custom .bashrc content
│   └── ssh-config-template     # SSH config template
└── templates/
    ├── dotnet/
    │   └── .devcontainer/
    ├── node/
    │   └── .devcontainer/
    └── python/
        └── .devcontainer/
```

## Documentation

- [VM-SETUP.md](docs/VM-SETUP.md) - Setting up a fresh Ubuntu VM
- [SOFTWARE.md](docs/SOFTWARE.md) - Detailed software list and versions
- [MOBAXTERM.md](docs/MOBAXTERM.md) - Configuring MobaXterm for SSH access
- [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues and fixes

## Devcontainer Templates

The `templates/` directory contains starter devcontainer configurations:

- **dotnet/** - .NET 9 with PostgreSQL, EF Core, AI CLIs
- **node/** - Node.js 20 with npm, Playwright, AI CLIs
- **python/** - Python 3.12 with pip, AI CLIs

Copy a template to your project:
```bash
cp -r ~/devstation-setup/templates/dotnet/.devcontainer ./
```

## Requirements

- Ubuntu 24.04 LTS (recommended) or Debian 12+
- 4+ CPU cores
- 16GB+ RAM (8GB minimum, but limited parallel builds)
- 50GB+ disk space
- SSH access

## License

MIT
