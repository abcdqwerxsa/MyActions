#!/bin/bash
set -e

# Set default values
TZ=${TZ:-Asia/Shanghai}

# Configure timezone
if [ -f /usr/share/zoneinfo/$TZ ]; then
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime
    echo $TZ > /etc/localtime
fi

# Generate SSH host keys if they don't exist
ssh-keygen -A 2>/dev/null

# Ensure required directories exist
mkdir -p /run/sshd /root/.ssh /models
chmod 700 /root/.ssh

# Set root home to /models (ensure it persists)
if [ "$(eval echo ~root)" != "/models" ]; then
    usermod -d /models root
fi

# Populate authorized_keys from mounted Secret if available
if [ -f /ssh/authorized_keys ]; then
    cp /ssh/authorized_keys /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# If user's SSH keys are provided via individual files, concatenate them
if [ -d /ssh-keys ]; then
    cat /ssh-keys/*.pub >> /root/.ssh/authorized_keys 2>/dev/null || true
    chmod 600 /root/.ssh/authorized_keys
fi

echo "=========================================="
echo "SSH Development Environment is starting..."
echo "Workspace: /models"
echo "SSH Port: 22"
echo "=========================================="

# Start sshd in foreground mode
exec /usr/sbin/sshd -D -e "$@"
