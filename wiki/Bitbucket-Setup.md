# Bitbucket Setup

This guide explains how to configure Bitbucket access for the devstation install script.

## Overview

Unlike GitHub (which has its own CLI), Bitbucket access uses:
- **App Passwords** for authentication
- **REST API** for repository discovery
- **HTTPS with embedded credentials** for cloning

## Creating an App Password

### Step 1: Open App Password Settings

1. Log in to [bitbucket.org](https://bitbucket.org)
2. Click your avatar (bottom-left) → **Personal settings**
3. Under **Access management**, click **App passwords**
4. Or go directly to: https://bitbucket.org/account/settings/app-passwords/

### Step 2: Create New App Password

1. Click **Create app password**
2. Enter a label (e.g., "devstation-setup")
3. Select permissions:

| Permission | Required | Purpose |
|------------|----------|---------|
| **Repositories: Read** | Yes | List repos, check for .devcontainer |
| Repositories: Write | No | Only needed if pushing changes |
| Account: Read | No | Not needed |

4. Click **Create**
5. **Copy the password immediately** - it won't be shown again!

### Step 3: Store Securely

Save the app password somewhere secure (password manager, encrypted notes). You'll need it when running `install.sh`.

## Finding Your Workspace Name

Your workspace name is in your Bitbucket URLs:

```
https://bitbucket.org/WORKSPACE_NAME/repo-name
                      ^^^^^^^^^^^^^^
```

To find it:
1. Go to any repository in your organization
2. Look at the URL
3. The workspace is the first path segment after `bitbucket.org`

Common patterns:
- Personal account: Usually your username
- Team/Organization: The organization's slug (lowercase, no spaces)

## Using with install.sh

When prompted during `install.sh`:

```
--- Bitbucket Repository Setup ---
Configure Bitbucket repos? (y/N): y

Bitbucket authentication requires:
  - Your Bitbucket username
  - An app password (create at: https://bitbucket.org/account/settings/app-passwords)
  - Your workspace name

App password permissions needed: Repositories (Read)

Bitbucket username: jsmith
App password: [paste your app password - hidden]
Workspace name: mycompany

[INFO] Testing Bitbucket authentication...
[OK] Bitbucket authentication successful
```

## How Credentials Are Stored

### During Install

Credentials are embedded in the clone URL:
```bash
git clone https://jsmith:APP_PASSWORD@bitbucket.org/mycompany/repo.git
```

### After Install

The bootstrap script configures git credential store:
```bash
git config --global credential.helper store
```

After the first successful clone, credentials are saved to `~/.git-credentials`:
```
https://jsmith:APP_PASSWORD@bitbucket.org
```

Future git operations (pull, fetch) will use these stored credentials automatically.

### Security Considerations

The credential store saves passwords in **plain text**. This is acceptable for:
- Development VMs
- Personal workstations
- Ephemeral cloud instances

**Not recommended for:**
- Shared systems
- Production servers
- Systems with multiple users

For enhanced security, consider:
- Using SSH keys instead (requires manual setup)
- Encrypting your home directory
- Using a credential manager like `git-credential-libsecret`

## Multiple Workspaces

To clone from multiple Bitbucket workspaces, run `install.sh` multiple times:

```bash
# First run - workspace A
~/devstation-setup/install.sh
# Choose Bitbucket, enter workspace-a credentials

# Second run - workspace B
~/devstation-setup/install.sh
# Choose Bitbucket, enter workspace-b credentials
```

Existing repos are skipped, and aliases are regenerated to include all repos.

## Troubleshooting

### Authentication Failed

```
[ERROR] Bitbucket authentication failed. Please check your credentials.
```

Verify:
1. Username is correct (your Bitbucket username, not email)
2. App password was copied correctly (no extra spaces)
3. Workspace name is correct (case-sensitive)
4. App password has "Repositories: Read" permission

### No Repos Found

```
[WARN] No repos found in workspace mycompany
```

Check:
1. Workspace name is spelled correctly
2. Your account has access to repos in that workspace
3. The workspace has at least one repository

### No Devcontainer Repos Found

```
[WARN] No repos with .devcontainer/ found
```

This means repos exist but none have a `.devcontainer/` directory on the default branch.

### Rate Limiting

Bitbucket API has rate limits. If you hit them:
1. Wait a few minutes
2. Re-run `install.sh`

### Credential Issues After Install

If git operations fail after install:

```bash
# Check stored credentials
cat ~/.git-credentials

# Remove and re-authenticate
git config --global --unset credential.helper
rm ~/.git-credentials
git config --global credential.helper store

# Re-run install.sh for the affected workspace
~/devstation-setup/install.sh
```

## App Password vs SSH Keys

| Feature | App Password | SSH Key |
|---------|--------------|---------|
| Setup complexity | Simple | More steps |
| Storage | Plain text file | Encrypted key file |
| Multiple accounts | One password per workspace | One key for all |
| Rotation | Easy to regenerate | Requires key replacement |
| 2FA compatible | Yes | Yes |

App passwords are recommended for devstation because:
- Simpler automated setup
- Works well with git credential store
- Easy to revoke/regenerate
