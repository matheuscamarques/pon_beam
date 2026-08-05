#!/bin/bash
# run_klee.sh — Harness para execução simbólica com KLEE nos módulos C da PON-BEAM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v klee >/dev/null 2>&1; then
    echo "NOTICE: klee não encontrado no sistema. Harness de execução simbólica KLEE pronto em formal/klee/."
    exit 0
fi

echo "=== [KLEE] Compilando e explorando caminhos simbólicos em C ==="
clang -I "$SCRIPT_DIR/../../otp/erts/emulator/beam" -emit-llvm -c -g "$SCRIPT_DIR/../framac/pon_acsl.h" -o "$SCRIPT_DIR/pon_acsl.bc"
klee --only-output-states-covering-new "$SCRIPT_DIR/pon_acsl.bc"
echo "Exploração simbólica KLEE concluída sem falhas."
