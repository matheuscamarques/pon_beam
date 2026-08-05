#!/bin/bash
# run_tlc.sh — Roda o TLC model checker em todos os modelos TLA+ PON-BEAM.
#
# Uso:
#   ./run_tlc.sh                 # Verifica todos os modelos
#   ./run_tlc.sh PremiseMatch    # Verifica apenas um modelo
#
# Para cada modelo <M>.tla, procura <M>.cfg (especificação TLC).
# Encerra com código de erro != 0 se qualquer modelo falhar.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$SCRIPT_DIR/tools"
TLC="$TOOLS/tla2tools.jar"
WORKDIR="$(mktemp -d)"
FAILED=0

if [ ! -f "$TLC" ]; then
    echo "ERRO: $TLC não encontrado. Baixe tla2tools.jar e coloque em $TOOLS/"
    echo "  curl -L -o $TLC https://github.com/tlaplus/tlaplus/releases/download/v1.8.0/tla2tools.jar"
    exit 1
fi

if ! command -v java >/dev/null 2>&1; then
    echo "ERRO: java não encontrado (necessário para TLC)"
    exit 1
fi

# Filtro opcional: modelo único
FILTER="${1:-}"

run_model() {
    local model="$1"
    local name="$(basename "$model" .tla)"
    local cfg="$2"
    local out="$WORKDIR/$name.out"

    echo "=== [TLC] $name ==="
    if ! java -cp "$TLC" tlc2.TLC -config "$cfg" -metadir "$WORKDIR" -cleanup "$model" > "$out" 2>&1; then
        echo "  FALHA: $name"
        tail -30 "$out" | sed 's/^/    /'
        FAILED=1
    else
        grep -E "Model checking completed|No error has been found" "$out" | sed 's/^/  /'
        echo "  OK: $name"
    fi
}

for tla in "$SCRIPT_DIR"/*.tla; do
    [ -e "$tla" ] || continue
    model="$tla"
    name="$(basename "$tla" .tla)"
    cfg="${model%.tla}.cfg"

    [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue
    [ -f "$cfg" ] || continue

    run_model "$model" "$cfg"
done

rm -rf "$WORKDIR"

if [ "$FAILED" -ne 0 ]; then
    echo ""
    echo "ERRO: pelo menos um modelo TLA+ falhou a verificação."
    exit 1
fi

echo ""
echo "Todos os modelos TLA+ verificados com sucesso."
