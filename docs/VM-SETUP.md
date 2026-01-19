# Fresh VM Setup Guide

This guide walks through setting up a fresh Linux VM as a devstation.

## Recommended Specifications

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Ubuntu 22.04 LTS | Ubuntu 24.04 LTS |
| CPU | 4 cores | 8+ cores |
| RAM | 8 GB | 16+ GB |
| Disk | 30 GB | 100+ GB SSD |
| Network | 10 Mbps | 100+ Mbps |

### Why These Specs?

- **CPU**: Devcontainers can build in parallel. More cores = faster builds.
- **RAM**: Each running container uses ~2-4GB. With 16GB you can run 3-4 containers comfortably.
- **Disk**: Docker images, node_modules, and .NET packages add up. SSD strongly recommended.
- **Network**: Initial setup downloads several GB of Docker images and npm packages.

## Initial VM Setup

### 1. Create the VM

**Cloud Providers:**
- **Azure**: Standard_D4s_v3 or larger
- **AWS**: t3.xlarge or larger
- **GCP**: e2-standard-4 or larger
- **Hetzner**: CPX31 or larger (great value)

**Local/Hypervisor:**
- VMware Workstation/Fusion
- VirtualBox
- Hyper-V
- Proxmox

### 2. Install Ubuntu 24.04 LTS

Download from: https://ubuntu.com/download/server

During installation:
- Choose "Ubuntu Server" (minimal)
- Enable OpenSSH server
- Skip additional packages (we'll install what we need)

### 3. Initial SSH Access

```bash
# From your local machine
ssh ubuntu@YOUR_VM_IP

# Or if you created a different user
ssh youruser@YOUR_VM_IP
```

### 4. Create the vscode User

```bash
# Create user with home directory
sudo adduser vscode

# Add to sudo group
sudo usermod -aG sudo vscode

# Optional: Enable passwordless sudo
echo "vscode ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/vscode

# Switch to vscode user
su - vscode
```

### 5. Set Up SSH Keys

On the VM as vscode user:

```bash
# Create .ssh directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add your public key
# Option A: Copy from your local machine
# On your local machine: cat ~/.ssh/id_ed25519.pub
# Then paste into this file on the VM:
nano ~/.ssh/authorized_keys

# Set permissions
chmod 600 ~/.ssh/authorized_keys
```

Or use ssh-copy-id from your local machine:
```bash
ssh-copy-id vscode@YOUR_VM_IP
```

### 6. Configure SSH Agent Forwarding

On your local machine, edit `~/.ssh/config`:

```
Host devstation
    HostName YOUR_VM_IP
    User vscode
    ForwardAgent yes
```

Test it:
```bash
ssh devstation
ssh-add -l  # Should show your keys
```

### 7. Run the Installer

```bash
# Clone the setup repo
git clone https://github.com/YOUR_USERNAME/devstation-setup.git ~/devstation-setup

# Run installer
cd ~/devstation-setup
./install.sh
```

## Post-Installation

### Verify Docker

```bash
# Should work without sudo
docker run hello-world

# If permission denied, log out and back in
exit
ssh devstation
docker run hello-world
```

### Verify devcontainer CLI

```bash
devcontainer --version
# Should output: 0.81.1 or similar
```

### Build Your First Container

```bash
# Build all repos
~/devcontainer-rebuild.sh ~/code

# Or a single repo
~/devcontainer-rebuild.sh ~/code/MyRepo

# Fast build (skip AI CLIs)
~/devcontainer-rebuild.sh ~/code --fast
```

## Security Recommendations

### Firewall (UFW)

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable
```

### Disable Password Authentication

Edit `/etc/ssh/sshd_config`:
```
PasswordAuthentication no
PubkeyAuthentication yes
```

Restart SSH:
```bash
sudo systemctl restart sshd
```

### Keep System Updated

```bash
sudo apt update && sudo apt upgrade -y
```

## Troubleshooting

### Cannot Connect via SSH

1. Check VM is running and has network
2. Verify firewall allows port 22
3. Check SSH service: `sudo systemctl status sshd`
4. Verify correct IP address

### Docker Permission Denied

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in
exit
ssh devstation
```

### Out of Disk Space

```bash
# Check disk usage
df -h

# Clean up Docker
docker system prune -af
docker volume prune -f

# Clean apt cache
sudo apt clean
```

## Next Steps

- [SOFTWARE.md](SOFTWARE.md) - Detailed software versions
- [MOBAXTERM.md](MOBAXTERM.md) - Configure MobaXterm for access
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
