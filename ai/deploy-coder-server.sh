#!/usr/bin/env bash
set -euo pipefail

MODEL_TAG="${1:-qwen2.5-coder:7b}"   # change to qwen2.5-coder:3b if you want a smaller model
OLLAMA_HOST_ADDR="${OLLAMA_HOST_ADDR:-0.0.0.0:11434}"
OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-24h}"

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
for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> Opening firewall port 11434"
sudo ufw allow 11434/tcp || true

echo "==> Pulling model: ${MODEL_TAG}"
ollama pull "${MODEL_TAG}"

echo "==> Creating a coder-specialized alias model"
cat >/tmp/Modelfile.coder <<EOF
FROM ${MODEL_TAG}
SYSTEM You are a careful coding assistant. Prefer complete, runnable answers. When editing code, explain the bug briefly, then show the corrected code. For shell commands, assume Ubuntu 22.04 unless told otherwise.
PARAMETER temperature 0.2
PARAMETER num_ctx 8192
EOF

ollama create coder-server -f /tmp/Modelfile.coder
rm -f /tmp/Modelfile.coder

echo "==> Installed models"
ollama list

echo "==> Quick smoke test"
curl -s http://127.0.0.1:11434/api/generate \
  -d '{
    "model": "coder-server",
    "prompt": "Write a tiny Python HTTP server that returns JSON hello world.",
    "stream": false
  }' | sed -n '1,120p'

PUBLIC_IP="$(curl -s https://api.ipify.org || true)"

echo
echo "============================================================"
echo "Ollama is up."
echo "Local API:   http://127.0.0.1:11434"
if [ -n "${PUBLIC_IP}" ]; then
  echo "Remote API:  http://${PUBLIC_IP}:11434"
fi
echo
echo "Useful commands:"
echo "  ollama run coder-server"
echo "  ollama run ${MODEL_TAG}"
echo "  curl http://127.0.0.1:11434/api/tags"
echo
echo "To use a smaller model on a cheaper instance:"
echo "  ./deploy-coder-server.sh qwen2.5-coder:3b"
echo "============================================================"
