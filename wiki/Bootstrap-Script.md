# Bootstrap Script

The `bootstrap.sh` script is Phase 1 of the devstation setup process. It installs all core dependencies on a fresh Ubuntu/Debian server.

## Usage

### One-liner (recommended)

```bash
curl -sSL https://raw.githubusercontent.com/canuszczyk/devstation-setup/master/bootstrap.sh | bash
```

### Manual execution

```bash
git clone https://github.com/canuszczyk/devstation-setup.git ~/devstation-setup
chmod +x ~/devstation-setup/bootstrap.sh
~/devstation-setup/bootstrap.sh
```

## What It Does

### 1. OS Validation

Checks that you're running Ubuntu or Debian. Other distributions are not supported.

```
[INFO] Detected OS: Ubuntu 22.04.3 LTS
[OK] Supported OS detected
```

### 2. Base Packages

Installs essential development tools:

| Package | Purpose |
|---------|---------|
| curl, wget | HTTP clients |
| ca-certificates | SSL certificates |
| gnupg | GPG for package verification |
| lsb-release | OS identification |
| git, git-lfs | Version control |
| build-essential, gcc, g++, make | C/C++ compilation |
| jq | JSON processing |
| unzip | Archive extraction |

### 3. Docker CE

Installs Docker Community Edition with:
- Docker Engine
- Docker CLI
- containerd
- Docker Buildx plugin
- Docker Compose plugin

Adds your user to the `docker` group (requires logout/login to take effect).

### 4. Node.js 20 LTS

Installs Node.js 20.x via NodeSource repository. Skips if Node.js 18+ is already installed.

### 5. GitHub CLI

Installs `gh` (GitHub CLI) from the official GitHub package repository.

### 6. Devcontainer CLI

Installs `@devcontainers/cli` globally via npm:

```bash
npm install -g @devcontainers/cli
```

### 7. Clone Devstation Repo

Clones (or updates) the devstation-setup repository to `~/devstation-setup`.

### 8. Symlink Scripts

Creates symlinks in your home directory:

| Symlink | Target |
|---------|--------|
| `~/devcontainer-rebuild.sh` | Build/rebuild devcontainers |
| `~/devcontainer-open.sh` | Open devcontainer in VS Code |
| `~/devcontainer-stop-all.sh` | Stop all running devcontainers |
| `~/devcontainer-cleanup.sh` | Clean up unused containers/images |
| `~/devcontainer-start-all.sh` | Start all devcontainers |
| `~/dexec` | Shell into a devcontainer |

### 9. Shell Integration

Appends customizations to `~/.bashrc`:
- PATH additions for `~/.local/bin`
- `dexec()` function for quick container access
- Aliases: `dc-stop-all`, `dc-start-all`, `dc-rebuild-all`, `dc-cleanup`

### 10. Git Credential Store

Configures git to store credentials in plain text:

```bash
git config --global credential.helper store
```

Credentials are saved to `~/.git-credentials`. This is suitable for development VMs but **not recommended for shared or production systems**.

## Exit Message

On successful completion:

```
==============================================
  Bootstrap Complete!
==============================================

Next steps:
  1. Log out and back in (for docker group membership)
  2. Run: source ~/.bashrc
  3. Run: ~/devstation-setup/install.sh

The install.sh script will help you:
  - Authenticate with GitHub and/or Bitbucket
  - Discover and clone repos with devcontainers
  - Build devcontainers
```

## Idempotency

The bootstrap script is safe to run multiple times:
- Skips packages that are already installed
- Updates the devstation-setup repo if it exists
- Replaces symlinks if they already exist
- Appends bashrc customizations only if not present

## Troubleshooting

### Docker permission denied

If you get "permission denied" when running `docker`:

```bash
# Log out and back in, or:
newgrp docker
```

### Node.js version too old

If you have an old Node.js version:

```bash
sudo apt-get remove nodejs
# Then re-run bootstrap.sh
```

### GPG key errors

If you get GPG errors during package installation:

```bash
sudo rm /etc/apt/keyrings/docker.gpg
sudo rm /usr/share/keyrings/githubcli-archive-keyring.gpg
# Then re-run bootstrap.sh
```
