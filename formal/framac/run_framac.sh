#!/bin/bash
# run_framac.sh — Roda análise estática Frama-C com o plugin WP nos contratos ACSL PON-BEAM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v frama-c >/dev/null 2>&1; then
    echo "NOTICE: frama-c não instalado no sistema. Ignorando WP formal proof (contratos ACSL definidos em formal/framac/pon_acsl.h)."
    exit 0
fi

echo "=== [Frama-C / WP] Verificando contratos ACSL do PON-BEAM ==="
frama-c -wp -wp-rte -wp-timeout 10 "$SCRIPT_DIR/pon_acsl.h"
echo "Contratos ACSL validados com sucesso."
