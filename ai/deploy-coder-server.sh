#!/usr/bin/env bash

# Suggested Vultr instance: vcg-a16-12c-128g-32vram
set -euo pipefail

MODEL_TAG="${1:-qwen3-coder-next:latest}"
AGENT_MODEL_NAME="${AGENT_MODEL_NAME:-coder-next-agent}"
OLLAMA_HOST_ADDR="${OLLAMA_HOST_ADDR:-0.0.0.0:11434}"
OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-24h}"
OLLAMA_NUM_CTX="${OLLAMA_NUM_CTX:-32768}"
SMOKE_TEST_PROMPT="${SMOKE_TEST_PROMPT:-Write a tiny Python HTTP server that returns JSON hello world.}"

command -v sudo >/dev/null 2>&1 || {
  echo "ERROR: sudo is required for package installation and service setup."
  exit 1
}

echo "==> Updating apt packages"
sudo apt-get update
sudo apt-get install -y curl ca-certificates git ufw

echo "==> Checking NVIDIA driver"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
else
  echo "WARNING: nvidia-smi not found. Ollama can still install, but GPU acceleration may not be active."
fi

echo "==> Installing Ollama"
curl -fsSL https://ollama.com/install.sh | sh

echo "==> Writing systemd override so Ollama listens externally"
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=${OLLAMA_HOST_ADDR}"
Environment="OLLAMA_KEEP_ALIVE=${OLLAMA_KEEP_ALIVE}"
EOF

echo "==> Reloading and restarting Ollama"
sudo systemctl daemon-reload
sudo systemctl enable ollama
sudo systemctl restart ollama

echo "==> Waiting for Ollama API"
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
  echo "ERROR: Ollama API did not become ready on http://127.0.0.1:11434"
  exit 1
fi

echo "==> Opening firewall port 11434"
sudo ufw allow 11434/tcp || true

echo "==> Pulling model: ${MODEL_TAG}"
ollama pull "${MODEL_TAG}"

echo "==> Creating an agentic coding alias model: ${AGENT_MODEL_NAME}"
cat >/tmp/Modelfile.coder-next <<EOF
FROM ${MODEL_TAG}
SYSTEM You are a careful agentic coding assistant. Work repo-first: inspect the project, identify the smallest safe change set that satisfies the request, preserve existing behavior unless the task requires otherwise, and prefer edits that are easy to review as local git commits. Before major edits, state the plan briefly. After edits, summarize what changed, note how to validate it, and propose a concise commit message. When shell commands are needed, assume Ubuntu 22.04 unless told otherwise.
PARAMETER temperature 0.1
PARAMETER num_ctx ${OLLAMA_NUM_CTX}
EOF

ollama create "${AGENT_MODEL_NAME}" -f /tmp/Modelfile.coder-next
rm -f /tmp/Modelfile.coder-next

echo "==> Installed models"
ollama list

echo "==> Quick smoke test"
curl -s http://127.0.0.1:11434/api/generate \
  -d "{
    \"model\": \"${AGENT_MODEL_NAME}\",
    \"prompt\": \"${SMOKE_TEST_PROMPT}\",
    \"stream\": false
  }" | sed -n '1,120p'

PUBLIC_IP="$(curl -s https://api.ipify.org || true)"

echo
echo "============================================================"
echo "Ollama is up."
echo "Local API:   http://127.0.0.1:11434"
if [ -n "${PUBLIC_IP}" ]; then
  echo "Remote API:  http://${PUBLIC_IP}:11434"
fi
echo
echo "Agent model: ${AGENT_MODEL_NAME}"
echo "Base model:  ${MODEL_TAG}"
echo "Context:     ${OLLAMA_NUM_CTX}"
echo
echo "Useful commands:"
echo "  ollama run ${AGENT_MODEL_NAME}"
echo "  ollama run ${MODEL_TAG}"
echo "  curl http://127.0.0.1:11434/api/tags"
echo
echo "To override the context window:"
echo "  OLLAMA_NUM_CTX=16384 ./$(basename "$0")"
echo
echo "To change the agent alias name:"
echo "  AGENT_MODEL_NAME=my-coder-agent ./$(basename "$0")"
echo "============================================================"
