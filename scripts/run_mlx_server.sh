#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -f "venv/bin/python" ]; then
    echo "Starting local MLX Parakeet server..."
    exec venv/bin/python mlx_server.py
else
    echo "Virtual environment not found. Setting up..."
    ./scripts/setup_dev.sh
    exec venv/bin/python mlx_server.py
fi
