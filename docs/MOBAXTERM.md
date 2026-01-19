# MobaXterm Configuration

MobaXterm is a Windows terminal with built-in SSH, X11 forwarding, and multi-tab support. This guide covers optimal configuration for the devstation workflow.

## Download and Install

1. Download from: https://mobaxterm.mobatek.net/download.html
2. Choose "Home Edition" (free) or "Professional"
3. Portable or Installer version both work

## Creating an SSH Session

### Basic Session

1. Click **Session** > **SSH**
2. Configure:
   - **Remote host**: `YOUR_VM_IP`
   - **Username**: `vscode`
   - **Port**: `22`
3. Click **OK**

### Advanced Settings

Click **Advanced SSH settings**:

- **SSH-browser type**: `SCP (normal speed)`
- **X11-Forwarding**: Enabled (optional, for GUI apps)
- **Compression**: Enabled (faster over slow networks)

### SSH Agent Forwarding

1. Go to **Settings** > **Configuration** > **SSH**
2. Enable **Forward SSH agents**
3. Add your private key to MobaXterm's key manager:
   - **Settings** > **Configuration** > **SSH** > **SSH agents**
   - Click **+** and add your `id_ed25519` or `id_rsa` file

## Auto-Execute into Devcontainer

The killer feature: automatically shell into a devcontainer when connecting.

### Single Repo Session

1. Right-click your session > **Edit session**
2. Go to **Advanced SSH settings**
3. In **Execute command**, enter:
   ```
   /home/vscode/dexec /home/vscode/code/YOUR_REPO_NAME
   ```
4. Click **OK**

Now double-clicking this session will:
1. SSH into the VM
2. Automatically exec into the devcontainer

### Create Multiple Sessions

Create a session for each repo you work with:

| Session Name | Execute Command |
|--------------|-----------------|
| DevStation - RepoA | `/home/vscode/dexec /home/vscode/code/RepoA` |
| DevStation - RepoB | `/home/vscode/dexec /home/vscode/code/RepoB` |
| DevStation - Shell | (empty - lands on VM host) |

### Session Folder Organization

1. Right-click in sessions panel > **New folder**
2. Name it "DevStation"
3. Drag your sessions into the folder

## Multi-Tab Workflow

### Opening Multiple Containers

1. Double-click a session to open in new tab
2. Repeat for other repos
3. Use `Ctrl+Tab` to switch between tabs

### Split Panes

- Right-click tab > **Split horizontally/vertically**
- Or use keyboard: `Ctrl+Shift+Arrow`

### Tab Naming

Sessions auto-name based on session name. For clarity:
- Name sessions: `Dev: RepoName` or `[Container] RepoName`

## SSH Key Setup

### Using MobaXterm's Key Manager

1. **Settings** > **Configuration** > **SSH**
2. Check **Use internal SSH agent "MobAgent"**
3. Click the **+** button under **Load following keys at MobAgent startup**
4. Select your private key file

### Converting Keys (if needed)

MobaXterm can convert PuTTY keys:
1. **Tools** > **MobaKeyGen**
2. **Load** your `.ppk` file
3. **Conversions** > **Export OpenSSH key**

### Verifying Agent Forwarding

Inside the VM:
```bash
ssh-add -l
# Should show your key(s)

ssh -T git@github.com
# Should say: "Hi username! You've successfully authenticated..."
```

## Useful Settings

### Settings > Configuration > Terminal

- **Default terminal shell**: `/bin/bash`
- **Terminal font**: Consolas, 11pt (or your preference)
- **Scrollback lines**: 10000

### Settings > Configuration > SSH

- **SSH keepalive**: 60 seconds
- **Forward SSH agents**: Enabled
- **X11-Forwarding**: Enabled (if you need GUI)

### Settings > Configuration > Display

- **Fullscreen mode shortcut**: F11
- **Tab bar position**: Top (personal preference)

## Troubleshooting

### "Connection refused"

1. Verify VM is running
2. Check IP address is correct
3. Verify SSH service: `sudo systemctl status sshd`
4. Check firewall: `sudo ufw status`

### "Permission denied (publickey)"

1. Verify key is loaded: **Settings** > **SSH** > **SSH agents**
2. Check authorized_keys on VM:
   ```bash
   cat ~/.ssh/authorized_keys
   ```
3. Verify key permissions:
   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

### dexec Fails

If the execute command fails silently:

1. SSH without execute command first
2. Run manually: `/home/vscode/dexec /home/vscode/code/RepoName`
3. Check for errors
4. Verify container is running: `docker ps`

### Slow Connection

1. Enable compression in session settings
2. Disable X11 forwarding if not needed
3. Check network latency: `ping YOUR_VM_IP`

## Tips and Tricks

### Quick Session Launch

- Assign keyboard shortcuts to favorite sessions
- Use the search bar in sessions panel

### File Transfer

- Drag and drop files to/from the left panel (SFTP browser)
- Or use `scp` commands in terminal

### Persistent Settings

- Export settings: **Settings** > **Configuration** > **Export**
- Import on new machine or after reinstall

### Multi-Desktop

Keep different workspaces in different MobaXterm windows:
- Window 1: Development containers
- Window 2: Infrastructure/DevOps
- Window 3: Logs and monitoring
