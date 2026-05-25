#!/usr/bin/env bash
# setup-runner.sh — provisions an Ubuntu 24.04 VM to act as the self-hosted
# GitHub Actions runner for this repository.
#
# Idempotent. The token-based registration step is INTENTIONALLY left
# manual — the assignment forbids placing the runner token in the repo, so
# the operator runs `config.sh --token ...` themselves once the runner
# software is in place.
#
# Run as root:   sudo bash setup-runner.sh
#
set -euo pipefail

RUNNER_USER="runner"
RUNNER_VERSION="${RUNNER_VERSION:-2.328.0}"
RUNNER_ARCH="x64"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner"

# --- 1. base packages -------------------------------------------------------
echo "[runner] installing prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    ca-certificates curl tar sudo openssh-client jq

# --- 2. runner user ---------------------------------------------------------
id "$RUNNER_USER" &>/dev/null || useradd -m -s /bin/bash "$RUNNER_USER"

# --- 3. download the GitHub Actions runner ---------------------------------
sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [ ! -f config.sh ]; then
    echo "[runner] downloading runner v${RUNNER_VERSION}..."
    sudo -u "$RUNNER_USER" curl -L -o runner.tar.gz \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
    sudo -u "$RUNNER_USER" tar xzf runner.tar.gz
    sudo -u "$RUNNER_USER" rm runner.tar.gz
fi

# Install OS dependencies declared by the runner.
if [ -f ./bin/installdependencies.sh ]; then
    ./bin/installdependencies.sh
fi

# --- 4. SSH key for the runner -> target node -----------------------------
SSH_KEY="/home/${RUNNER_USER}/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    echo "[runner] generating SSH key pair (id_ed25519)..."
    sudo -u "$RUNNER_USER" mkdir -p "/home/${RUNNER_USER}/.ssh"
    sudo -u "$RUNNER_USER" chmod 700 "/home/${RUNNER_USER}/.ssh"
    sudo -u "$RUNNER_USER" ssh-keygen -t ed25519 -N "" -f "$SSH_KEY" -C "github-runner"
fi

cat <<EOF

================================================================
 Runner software installed.

 1. Register the runner with your GitHub repository.
    Go to:
        Settings  →  Actions  →  Runners  →  New self-hosted runner

    Copy the suggested ./config.sh command (it contains a one-time
    registration token). Then run it AS THE RUNNER USER:

        sudo -iu ${RUNNER_USER}
        cd ${RUNNER_DIR}
        ./config.sh --url https://github.com/<owner>/<repo> --token <TOKEN>

 2. Install the runner as a systemd service so it starts on boot:

        cd ${RUNNER_DIR}
        sudo ./svc.sh install ${RUNNER_USER}
        sudo ./svc.sh start

 3. Wire up SSH from this runner to the target node.

    Public key generated for the runner:
EOF
echo "        $(cat ${SSH_KEY}.pub)"
cat <<EOF
    Add it to the deploy user's authorized_keys on the target node:
        /home/deploy/.ssh/authorized_keys

    Then copy the private key into the GitHub repo secrets:
        TARGET_SSH_KEY = (contents of ${SSH_KEY})
        TARGET_HOST    = (target node hostname/IP)
        TARGET_USER    = deploy

 4. When the lab is finished — stop or destroy this VM.

================================================================
EOF
