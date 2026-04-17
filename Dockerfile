# SSH-enabled Development Environment based on MindSpeed LLM Ascend
# Base: swr.cn-south-1.myhuaweicloud.com/ascendhub/mindspeed-llm:openeuler22.03-mindspeed-llm-2.3.0-a3-arm
# Provides SSH access for remote IDE development (VS Code Remote-SSH, PyCharm, etc.)

FROM swr.cn-south-1.myhuaweicloud.com/ascendhub/mindspeed-llm:openeuler22.03-mindspeed-llm-2.3.0-a3-arm

USER root

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH="/root/.local/bin:${PATH}" \
    HOME="/models"

# Fix broken yum/dnf and configure openEuler 22.03-LTS-SP4 repos in single layer
RUN set -e; \
    ARCH=$(uname -m); \
    REPO_URL="http://repo.openeuler.org/openEuler-22.03-LTS-SP4/OS/${ARCH}/Packages"; \
    (command -v rpm >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && \
        mkdir -p /tmp/rpm-packages && cd /tmp/rpm-packages && \
        (curl -fsSL -O "${REPO_URL}/python3-dnf-4.14.0-15.oe2203sp4.${ARCH}.rpm" 2>/dev/null || \
         curl -fsSL -O "${REPO_URL}/python3-dnf-4.14.0-14.oe2203sp4.${ARCH}.rpm" 2>/dev/null || true) && \
        if ls python3-dnf*.rpm 1>/dev/null 2>&1; then \
            rpm -ivh --nodeps python3-dnf*.rpm 2>/dev/null || true; \
        fi; \
        rm -rf /tmp/rpm-packages) || true; \
    REPO_DIR="/etc/yum.repos.d"; \
    mkdir -p "$REPO_DIR"; \
    printf '[OS]\nname=OS\nbaseurl=http://repo.openeuler.org/openEuler-22.03-LTS-SP4/OS/$basearch/\nenabled=1\ngpgcheck=0\n\n' > "$REPO_DIR/openEuler.repo" && \
    printf '[everything]\nname=everything\nbaseurl=http://repo.openeuler.org/openEuler-22.03-LTS-SP4/everything/$basearch/\nenabled=1\ngpgcheck=0\n\n' >> "$REPO_DIR/openEuler.repo" && \
    printf '[EPOL]\nname=EPOL\nbaseurl=http://repo.openeuler.org/openEuler-22.03-LTS-SP4/EPOL/main/$basearch/\nenabled=1\ngpgcheck=0\n\n' >> "$REPO_DIR/openEuler.repo" && \
    printf '[update]\nname=update\nbaseurl=http://repo.openeuler.org/openEuler-22.03-LTS-SP4/update/$basearch/\nenabled=1\ngpgcheck=0\n' >> "$REPO_DIR/openEuler.repo" && \
    echo "openEuler 22.03-LTS-SP4 repo configured"

# Install system dependencies and configure SSH server in single layer
RUN set -e; \
    if dnf --version >/dev/null 2>&1; then \
        dnf clean all && dnf makecache && \
        dnf install -y --setopt=install_weak_deps=False \
            curl wget git vim sudo \
            openssh-server openssh-clients \
            procps lsof net-tools iproute \
            tzdata ca-certificates openssl util-linux \
            buildah podman && \
        dnf clean all; \
    elif yum --version >/dev/null 2>&1; then \
        yum clean all && yum makecache && \
        yum install -y curl wget git vim sudo openssh-server openssh-clients procps lsof net-tools iproute tzdata ca-certificates openssl util-linux buildah podman && \
        yum clean all; \
    fi; \
    rm -rf /var/cache/dnf /var/cache/yum /var/log /tmp/*; \
    buildah --version

# Configure SSH server: create dirs, set root home, write sshd_config, generate host keys
RUN set -e; \
    mkdir -p /run/sshd /root/.ssh /models; \
    usermod -d /models root; \
    chmod 700 /root/.ssh; \
    printf 'Port 22\nAddressFamily any\nListenAddress 0.0.0.0\n\nHostKey /etc/ssh/ssh_host_rsa_key\nHostKey /etc/ssh/ssh_host_ecdsa_key\nHostKey /etc/ssh/ssh_host_ed25519_key\n\nPermitRootLogin yes\nPubkeyAuthentication yes\nAuthorizedKeysFile .ssh/authorized_keys\nPasswordAuthentication no\nChallengeResponseAuthentication no\nUsePAM yes\n\nX11Forwarding yes\nPrintMotd no\nAcceptEnv LANG LC_*\nMaxAuthTries 6\nLoginGraceTime 60\n\nClientAliveInterval 30\nClientAliveCountMax 3\n\nTCPKeepAlive yes\nCompression no\nMaxSessions 10\n' > /etc/ssh/sshd_config; \
    ssh-keygen -A

# Pre-install common Python packages for AI/ML development
RUN pip install --no-cache-dir \
    jupyter ipykernel pandas numpy matplotlib seaborn scikit-learn scipy \
    requests tqdm rich transformers accelerate datasets tiktoken fastapi uvicorn 2>/dev/null || \
    echo "Some pip packages may already be installed" && \
    rm -rf /root/.cache /tmp/*

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
WORKDIR /models

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD sshd -t 2>/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
