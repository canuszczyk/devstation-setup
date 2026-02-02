# Troubleshooting Guide

Common issues and their solutions when working with the devstation.

## Container Issues

### Container Won't Start

**Symptoms:**
- `docker: Error response from daemon: driver failed programming external connectivity`
- Container exits immediately after starting

**Solutions:**

1. Check if another container is using the same ports:
   ```bash
   docker ps -a
   docker stop $(docker ps -aq)  # Stop all containers
   ```

2. Check Docker daemon:
   ```bash
   sudo systemctl status docker
   sudo systemctl restart docker
   ```

3. Check disk space:
   ```bash
   df -h
   docker system prune -af  # If low on space
   ```

### "No running container found"

**Symptoms:**
- `dexec` reports no container for the repo

**Solutions:**

1. Check if container is running:
   ```bash
   docker ps --filter "label=com.devcontainer.repo"
   ```

2. Start the container:
   ```bash
   ~/devcontainer-open.sh ~/code/RepoName
   ```

3. If container doesn't exist, rebuild:
   ```bash
   ~/devcontainer-rebuild.sh ~/code/RepoName
   ```

### Container Build Fails

**Symptoms:**
- `devcontainer up` fails with error
- Build hangs or times out

**Solutions:**

1. Check Docker logs:
   ```bash
   docker logs $(docker ps -lq)
   ```

2. Try a clean rebuild:
   ```bash
   ~/devcontainer-rebuild.sh ~/code/RepoName --force --prune
   ```

3. Check for syntax errors in devcontainer.json:
   ```bash
   cat ~/code/RepoName/.devcontainer/devcontainer.json | jq .
   ```

4. Check available memory:
   ```bash
   free -h
   ```

## Docker Issues

### "Permission denied" with Docker

**Symptoms:**
- `Got permission denied while trying to connect to the Docker daemon socket`

**Solutions:**

1. Add user to docker group:
   ```bash
   sudo usermod -aG docker $USER
   ```

2. Log out and back in (SSH disconnect/reconnect)

3. Verify group membership:
   ```bash
   groups  # Should include 'docker'
   ```

### Docker Daemon Not Running

**Symptoms:**
- `Cannot connect to the Docker daemon`

**Solutions:**

```bash
# Check status
sudo systemctl status docker

# Start if stopped
sudo systemctl start docker

# Enable on boot
sudo systemctl enable docker
```

### Out of Disk Space

**Symptoms:**
- Build fails with "no space left on device"
- `df -h` shows full disk

**Solutions:**

1. Clean up Docker resources:
   ```bash
   ~/devcontainer-cleanup.sh --all
   docker system prune -af
   docker volume prune -f
   ```

2. Remove old images:
   ```bash
   docker images -a
   docker rmi $(docker images -f "dangling=true" -q)
   ```

3. Check what's using space:
   ```bash
   du -sh /var/lib/docker/*
   ```

## SSH and Network Issues

### Cannot SSH to VM

**Checklist:**

1. VM is running and has network
2. Correct IP address
3. SSH service running:
   ```bash
   sudo systemctl status sshd
   ```
4. Firewall allows SSH:
   ```bash
   sudo ufw status
   sudo ufw allow ssh
   ```
5. Correct username and key

### SSH Agent Forwarding Not Working

**Symptoms:**
- `ssh-add -l` shows "Could not open connection to authentication agent"
- Git operations fail with authentication errors

**Solutions:**

1. Verify agent is running locally:
   ```bash
   # On your local machine
   ssh-add -l
   ```

2. Check SSH config has ForwardAgent:
   ```
   # ~/.ssh/config
   Host devstation
       ForwardAgent yes
   ```

3. Check VM allows agent forwarding:
   ```bash
   # /etc/ssh/sshd_config
   AllowAgentForwarding yes
   ```

### Git Authentication Fails

**Symptoms:**
- `Permission denied (publickey)` when pushing/pulling

**Solutions:**

1. Verify SSH agent forwarding:
   ```bash
   ssh-add -l  # Should show your key
   ```

2. Test GitHub connection:
   ```bash
   ssh -T git@github.com
   ```

3. Check repo remote URL:
   ```bash
   git remote -v
   # Should be git@github.com:... not https://
   ```

## Performance Issues

### Container Builds Are Slow

**Solutions:**

1. Use `--fast` flag to skip AI CLIs:
   ```bash
   ~/devcontainer-rebuild.sh ~/code --fast
   ```

2. Ensure sufficient CPU/RAM allocated to Docker

3. Use SSD storage

4. Check network speed (initial builds download GBs)

### Running Out of Memory

**Symptoms:**
- OOM killer terminates processes
- Container crashes unexpectedly

**Solutions:**

1. Check container memory limits in devcontainer.json:
   ```json
   "runArgs": ["--memory=4g"]
   ```

2. Run fewer containers simultaneously

3. Add swap space:
   ```bash
   sudo fallocate -l 4G /swapfile
   sudo chmod 600 /swapfile
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

### High CPU Usage

**Solutions:**

1. Check which container is using CPU:
   ```bash
   docker stats
   ```

2. Limit container CPU:
   ```json
   "runArgs": ["--cpus=2"]
   ```

3. Check for runaway processes inside container

## Database Issues

### PostgreSQL Won't Start

**Symptoms:**
- Container starts but PostgreSQL is down
- Connection refused on port 5432

**Solutions:**

1. Check PostgreSQL logs inside container:
   ```bash
   sudo tail -f /var/log/postgresql/*.log
   ```

2. Check data directory permissions:
   ```bash
   ls -la /workspaces/*/devcontainer/pgdata
   ```

3. Reset PostgreSQL data:
   ```bash
   rm -rf .devcontainer/pgdata
   # Rebuild container
   ```

### Database Connection Refused

**Solutions:**

1. Verify PostgreSQL is running:
   ```bash
   pg_isready
   ```

2. Check port mapping:
   ```bash
   docker port $(docker ps -q)
   ```

3. Use correct connection string:
   ```
   Host=localhost;Port=5432;Username=postgres;Password=postgres
   ```

## Development Issues

### npm install Fails

**Solutions:**

1. Clear npm cache:
   ```bash
   npm cache clean --force
   ```

2. Delete node_modules and reinstall:
   ```bash
   rm -rf node_modules package-lock.json
   npm install
   ```

3. Check npm registry access:
   ```bash
   npm ping
   ```

### dotnet restore Fails

**Solutions:**

1. Clear NuGet cache:
   ```bash
   dotnet nuget locals all --clear
   ```

2. Check NuGet sources:
   ```bash
   dotnet nuget list source
   ```

3. Restore with verbosity:
   ```bash
   dotnet restore --verbosity detailed
   ```

## Getting Help

### Collecting Diagnostics

When reporting issues, include:

```bash
# System info
uname -a
docker --version
docker info
free -h
df -h

# Container status
docker ps -a
docker logs $(docker ps -lq) 2>&1 | tail -50

# devcontainer config
cat ~/code/RepoName/.devcontainer/devcontainer.json
```

### Where to Get Help

1. Check logs first (Docker, container, application)
2. Search GitHub issues for the project
3. Stack Overflow with `[devcontainer]` tag
4. VS Code Remote Development GitHub issues
