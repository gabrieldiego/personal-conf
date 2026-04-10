#!/usr/bin/env bash
set -euo pipefail

# Detect host capabilities and recommend a practical Ollama coding model.
# Focused on local agentic coding use, with conservative defaults for context.
# Output is human-readable; use --json for machine-readable output.

JSON=0
if [[ "${1:-}" == "--json" ]]; then
  JSON=1
fi

have() { command -v "$1" >/dev/null 2>&1; }

trim() {
  awk '{$1=$1;print}' <<<"${1:-}"
}

json_escape() {
  python3 - <<'PY' "$1"
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

model_to_alias() {
  local model base
  model="${1:-coder}"
  base="${model%%:*}"
  base="$(tr '[:upper:]' '[:lower:]' <<<"$base" | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//')"
  printf '%s-agent\n' "${base:-coder}"
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/deploy-coder-server.sh" ]]; then
  DEPLOY_SCRIPT="$SCRIPT_DIR/deploy-coder-server.sh"
else
  DEPLOY_SCRIPT="./deploy-coder-server.sh"
fi

# System basics
OS_NAME="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" || uname -s)"
ARCH="$(uname -m)"
KERNEL="$(uname -r)"
CPU_MODEL="$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ //')"
CPU_CORES="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
RAM_GB="$(awk '/MemTotal/ {printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo)"
SWAP_GB="$(awk '/SwapTotal/ {printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo)"
ROOT_FS="$(df -PT / | awk 'NR==2 {print $1}')"
ROOT_FSTYPE="$(df -PT / | awk 'NR==2 {print $2}')"
ROOT_FREE_BYTES="$(df -B1 / | awk 'NR==2 {print $4}')"
ROOT_FREE_GB="$(python3 - <<'PY2' "$ROOT_FREE_BYTES"
import sys
b = int(sys.argv[1]) if sys.argv[1] else 0
print((b + (1 << 30) - 1) // (1 << 30))
PY2
)"
ROOT_USE_PCT="$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5+0}')"

# Model storage path heuristic
if [[ -n "${OLLAMA_MODELS:-}" ]]; then
  MODEL_DIR="$OLLAMA_MODELS"
elif [[ -d /usr/share/ollama/.ollama/models ]]; then
  MODEL_DIR="/usr/share/ollama/.ollama/models"
else
  MODEL_DIR="$HOME/.ollama/models"
fi
MODEL_PARENT="$(dirname "$MODEL_DIR")"
mkdir -p "$MODEL_PARENT" 2>/dev/null || true
MODEL_FREE_BYTES="$(df -B1 "$MODEL_PARENT" 2>/dev/null | awk 'NR==2 {print $4}')"
MODEL_FREE_GB="$(python3 - <<'PY2' "$MODEL_FREE_BYTES"
import sys
b = int(sys.argv[1]) if sys.argv[1] else 0
print((b + (1 << 30) - 1) // (1 << 30))
PY2
)"
MODEL_FS="$(df -PT "$MODEL_PARENT" 2>/dev/null | awk 'NR==2 {print $1}')"

# Clamp clearly bogus df values seen in some containers/live environments
if (( ROOT_FREE_GB > 100000 )); then
  ROOT_FREE_GB=0
fi
if (( MODEL_FREE_GB > 100000 )); then
  MODEL_FREE_GB=0
fi

# GPU detection
GPU_VENDOR="none"
GPU_NAME=""
GPU_DRIVER_OK=0
GPU_COUNT=0
TOTAL_VRAM_GB=0
NVIDIA_DRIVER_VERSION=""
CUDA_VERSION=""

if have nvidia-smi; then
  if nvidia-smi -L >/dev/null 2>&1; then
    GPU_VENDOR="nvidia"
    GPU_DRIVER_OK=1
    GPU_COUNT="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l | awk '{print $1}')"
    GPU_NAME="$(trim "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)")"
    TOTAL_VRAM_GB="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{sum+=$1} END {printf "%d", (sum/1024)+0.5}')"
    NVIDIA_DRIVER_VERSION="$(trim "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1)")"
    CUDA_VERSION="$(nvidia-smi 2>/dev/null | awk -F'CUDA Version: ' '/CUDA Version:/ {split($2,a," "); print a[1]; exit}')"
  fi
fi

if [[ "$GPU_DRIVER_OK" -eq 0 ]] && have lspci; then
  PCI_GPU_LINES="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
  if grep -qi nvidia <<<"$PCI_GPU_LINES"; then
    GPU_VENDOR="nvidia"
    GPU_NAME="$(trim "$(grep -i nvidia <<<"$PCI_GPU_LINES" | head -n1 | sed 's/^[^:]*: //')")"
  elif grep -qi 'amd\|advanced micro devices' <<<"$PCI_GPU_LINES"; then
    GPU_VENDOR="amd"
    GPU_NAME="$(trim "$(grep -Ei 'amd|advanced micro devices' <<<"$PCI_GPU_LINES" | head -n1 | sed 's/^[^:]*: //')")"
  elif grep -qi 'intel corporation' <<<"$PCI_GPU_LINES"; then
    GPU_VENDOR="intel"
    GPU_NAME="$(trim "$(grep -i 'intel corporation' <<<"$PCI_GPU_LINES" | head -n1 | sed 's/^[^:]*: //')")"
  fi
fi

# Ollama detection
OLLAMA_INSTALLED=0
OLLAMA_VERSION=""
OLLAMA_RUNNING=0
if have ollama; then
  OLLAMA_INSTALLED=1
  OLLAMA_VERSION="$(ollama --version 2>/dev/null | head -n1 || true)"
fi
if curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  OLLAMA_RUNNING=1
fi

# Warnings
WARNINGS=()
add_warning() {
  WARNINGS+=("$1")
}

if [[ "$ROOT_FS" == "/cow" || "$ROOT_FSTYPE" == "overlay" ]]; then
  add_warning "Root filesystem appears to be a live-session overlay ($ROOT_FS / $ROOT_FSTYPE). Large model pulls may fail unless OLLAMA_MODELS points to persistent storage."
fi
if (( ROOT_USE_PCT >= 90 || ROOT_FREE_GB < 10 )); then
  add_warning "Root filesystem is tight (${ROOT_FREE_GB}GB free, ${ROOT_USE_PCT}% used)."
fi
if (( MODEL_FREE_GB < 10 )); then
  add_warning "Model storage path has very little free space (${MODEL_FREE_GB}GB at $MODEL_PARENT)."
fi
if [[ "$GPU_VENDOR" == "nvidia" && "$GPU_DRIVER_OK" -eq 0 ]]; then
  add_warning "NVIDIA hardware appears present, but the NVIDIA driver is not working yet (nvidia-smi unavailable or failing). GPU inference will not be active until the driver is fixed."
fi
if (( RAM_GB < 16 )); then
  add_warning "System RAM is below 16GB. Local agentic coding will be limited; use a smaller model and shorter context."
fi

# Recommendation heuristics
RECOMMENDED_MODEL=""
RECOMMENDED_CONTEXT=0
RECOMMENDED_NOTES=""
FALLBACK_MODEL=""
MIN_DISK_GB=0

if (( RAM_GB >= 250 )); then
  RECOMMENDED_MODEL="qwen3-coder:480b"
  RECOMMENDED_CONTEXT=65536
  MIN_DISK_GB=280
  RECOMMENDED_NOTES="Best local coding quality if you truly have workstation/server-class memory. Heavy and likely sluggish."
  FALLBACK_MODEL="qwen3-coder-next:latest"
elif (( GPU_DRIVER_OK == 1 && TOTAL_VRAM_GB >= 24 && RAM_GB >= 64 )); then
  RECOMMENDED_MODEL="qwen3-coder-next:latest"
  if (( TOTAL_VRAM_GB >= 48 )); then
    RECOMMENDED_CONTEXT=65536
  else
    RECOMMENDED_CONTEXT=32768
  fi
  MIN_DISK_GB=70
  RECOMMENDED_NOTES="Best local recommendation for agentic coding on a strong single GPU box."
  FALLBACK_MODEL="qwen3-coder:30b"
elif (( (GPU_DRIVER_OK == 1 && TOTAL_VRAM_GB >= 12 && RAM_GB >= 64) || RAM_GB >= 96 )); then
  RECOMMENDED_MODEL="qwen3-coder:30b"
  if (( GPU_DRIVER_OK == 1 && TOTAL_VRAM_GB >= 24 )); then
    RECOMMENDED_CONTEXT=32768
  else
    RECOMMENDED_CONTEXT=16384
  fi
  MIN_DISK_GB=30
  RECOMMENDED_NOTES="Strong, more efficient local coding model and the safest serious choice on 12GB+ VRAM with plenty of RAM."
  FALLBACK_MODEL="qwen2.5-coder:14b"
elif (( RAM_GB >= 32 )); then
  RECOMMENDED_MODEL="qwen2.5-coder:14b"
  RECOMMENDED_CONTEXT=16384
  MIN_DISK_GB=15
  RECOMMENDED_NOTES="Reasonable coding-focused local model for CPU-heavy or midrange systems."
  FALLBACK_MODEL="qwen2.5-coder:7b"
elif (( RAM_GB >= 16 )); then
  RECOMMENDED_MODEL="qwen2.5-coder:7b"
  RECOMMENDED_CONTEXT=8192
  MIN_DISK_GB=10
  RECOMMENDED_NOTES="Practical floor for useful local coding on a modest machine."
  FALLBACK_MODEL="qwen2.5-coder:3b"
elif (( RAM_GB >= 8 )); then
  RECOMMENDED_MODEL="qwen2.5-coder:3b"
  RECOMMENDED_CONTEXT=4096
  MIN_DISK_GB=6
  RECOMMENDED_NOTES="Lightweight local coding model for low-memory systems."
  FALLBACK_MODEL="qwen2.5-coder:1.5b"
elif (( RAM_GB >= 4 )); then
  RECOMMENDED_MODEL="qwen2.5-coder:1.5b"
  RECOMMENDED_CONTEXT=2048
  MIN_DISK_GB=4
  RECOMMENDED_NOTES="Tiny fallback only; useful for toy edits and short prompts."
  FALLBACK_MODEL="qwen2.5-coder:0.5b"
else
  RECOMMENDED_MODEL="qwen2.5-coder:0.5b"
  RECOMMENDED_CONTEXT=2048
  MIN_DISK_GB=2
  RECOMMENDED_NOTES="Very constrained system. Prefer remote inference if possible."
  FALLBACK_MODEL=""
fi

# Extra caution if storage is insufficient
if (( MODEL_FREE_GB < MIN_DISK_GB )); then
  add_warning "Recommended model likely needs more free storage than currently available in the model directory. Need roughly ${MIN_DISK_GB}GB free at $MODEL_PARENT."
fi

RECOMMENDED_AGENT_MODEL_NAME="$(model_to_alias "$RECOMMENDED_MODEL")"
printf -v DEPLOY_COMMAND \
  'AGENT_MODEL_NAME=%q OLLAMA_NUM_CTX=%q %q %q' \
  "$RECOMMENDED_AGENT_MODEL_NAME" \
  "$RECOMMENDED_CONTEXT" \
  "$DEPLOY_SCRIPT" \
  "$RECOMMENDED_MODEL"

if (( JSON == 1 )); then
  printf '{\n'
  printf '  "os": %s,\n' "$(json_escape "$OS_NAME")"
  printf '  "arch": %s,\n' "$(json_escape "$ARCH")"
  printf '  "kernel": %s,\n' "$(json_escape "$KERNEL")"
  printf '  "cpu_model": %s,\n' "$(json_escape "$CPU_MODEL")"
  printf '  "cpu_cores": %s,\n' "$CPU_CORES"
  printf '  "ram_gb": %s,\n' "$RAM_GB"
  printf '  "swap_gb": %s,\n' "$SWAP_GB"
  printf '  "root_free_gb": %s,\n' "$ROOT_FREE_GB"
  printf '  "model_storage_parent": %s,\n' "$(json_escape "$MODEL_PARENT")"
  printf '  "model_storage_free_gb": %s,\n' "$MODEL_FREE_GB"
  printf '  "gpu_vendor": %s,\n' "$(json_escape "$GPU_VENDOR")"
  printf '  "gpu_name": %s,\n' "$(json_escape "$GPU_NAME")"
  printf '  "gpu_driver_ok": %s,\n' "$GPU_DRIVER_OK"
  printf '  "gpu_count": %s,\n' "$GPU_COUNT"
  printf '  "total_vram_gb": %s,\n' "$TOTAL_VRAM_GB"
  printf '  "recommended_model": %s,\n' "$(json_escape "$RECOMMENDED_MODEL")"
  printf '  "recommended_context": %s,\n' "$RECOMMENDED_CONTEXT"
  printf '  "fallback_model": %s,\n' "$(json_escape "$FALLBACK_MODEL")"
  printf '  "recommended_agent_model_name": %s,\n' "$(json_escape "$RECOMMENDED_AGENT_MODEL_NAME")"
  printf '  "deploy_script": %s,\n' "$(json_escape "$DEPLOY_SCRIPT")"
  printf '  "deploy_command": %s,\n' "$(json_escape "$DEPLOY_COMMAND")"
  printf '  "notes": %s,\n' "$(json_escape "$RECOMMENDED_NOTES")"
  printf '  "warnings": ['
  for i in "${!WARNINGS[@]}"; do
    (( i > 0 )) && printf ', '
    printf '%s' "$(json_escape "${WARNINGS[$i]}")"
  done
  printf ']\n}\n'
  exit 0
fi

printf '=== Host summary ===\n'
printf 'OS:                 %s\n' "$OS_NAME"
printf 'Arch:               %s\n' "$ARCH"
printf 'Kernel:             %s\n' "$KERNEL"
printf 'CPU:                %s\n' "${CPU_MODEL:-unknown}"
printf 'CPU cores:          %s\n' "$CPU_CORES"
printf 'RAM:                %s GB\n' "$RAM_GB"
printf 'Swap:               %s GB\n' "$SWAP_GB"
printf 'Root free:          %s GB (%s%% used)\n' "$ROOT_FREE_GB" "$ROOT_USE_PCT"
printf 'Model storage:      %s (%s GB free)\n' "$MODEL_PARENT" "$MODEL_FREE_GB"
printf 'Ollama installed:   %s\n' "$([[ $OLLAMA_INSTALLED -eq 1 ]] && echo yes || echo no)"
if [[ $OLLAMA_INSTALLED -eq 1 && -n "$OLLAMA_VERSION" ]]; then
  printf 'Ollama version:     %s\n' "$OLLAMA_VERSION"
fi
printf 'Ollama API up:      %s\n' "$([[ $OLLAMA_RUNNING -eq 1 ]] && echo yes || echo no)"
printf 'GPU vendor:         %s\n' "$GPU_VENDOR"
printf 'GPU detected:       %s\n' "${GPU_NAME:-none}"
printf 'GPU driver OK:      %s\n' "$([[ $GPU_DRIVER_OK -eq 1 ]] && echo yes || echo no)"
if [[ $GPU_DRIVER_OK -eq 1 ]]; then
  printf 'GPU count:          %s\n' "$GPU_COUNT"
  printf 'Total VRAM:         %s GB\n' "$TOTAL_VRAM_GB"
  printf 'NVIDIA driver:      %s\n' "${NVIDIA_DRIVER_VERSION:-unknown}"
  printf 'CUDA version:       %s\n' "${CUDA_VERSION:-unknown}"
fi

printf '\n=== Recommendation ===\n'
printf 'Recommended model:  %s\n' "$RECOMMENDED_MODEL"
printf 'Fallback model:     %s\n' "${FALLBACK_MODEL:-none}"
printf 'Context to try:     %s\n' "$RECOMMENDED_CONTEXT"
printf 'Agent alias:        %s\n' "$RECOMMENDED_AGENT_MODEL_NAME"
printf 'Why:                %s\n' "$RECOMMENDED_NOTES"

printf '\nSuggested commands:\n'
printf '  ollama pull %s\n' "$RECOMMENDED_MODEL"
printf '  OLLAMA_CONTEXT_LENGTH=%s ollama run %s\n' "$RECOMMENDED_CONTEXT" "$RECOMMENDED_MODEL"
if [[ -n "$FALLBACK_MODEL" ]]; then
  printf '  ollama pull %s\n' "$FALLBACK_MODEL"
fi

printf '\nSuggested deploy command:\n'
printf '  %s\n' "$DEPLOY_COMMAND"

if (( ${#WARNINGS[@]} > 0 )); then
  printf '\n=== Warnings ===\n'
  for w in "${WARNINGS[@]}"; do
    printf ' - %s\n' "$w"
  done
fi
