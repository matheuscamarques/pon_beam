#!/bin/bash
# run_proper.sh — Roda as suítes PropEr da camada formal PON-BEAM.
#
# Uso:
#   ./run_proper.sh                 # Roda todas as propriedades
#   ./run_proper.sh pon_receive     # Só um módulo
#   ./run_proper.sh -n 500          # Personaliza número de testes
#
# Exige um ERTS disponível. Usa harness/config/baseline.sh (primeiro ERTS).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROPER_ROOT="$SCRIPT_DIR/deps/proper"
PROPER_EBIN="$PROPER_ROOT/ebin"
TESTS_DIR="$SCRIPT_DIR/tests"
NUM_TESTS=200
FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        -n) NUM_TESTS="$2"; shift 2 ;;
        *)  FILTER="$1"; shift ;;
    esac
done

# ERTS disponível (config do harness)
HARNESS_CONFIG="$SCRIPT_DIR/../../harness/config"
ERL=""
if [ -f "$HARNESS_CONFIG/baseline.sh" ]; then
    set +u
    source "$HARNESS_CONFIG/baseline.sh" 2>/dev/null || true
    set -u
    ERL="$BASELINE_ERL"
fi
if [ -z "$ERL" ] || [ ! -x "$ERL" ]; then
    ERL="$(command -v erl || true)"
fi
if [ -z "$ERL" ] || [ ! -x "$ERL" ]; then
    echo "ERRO: nenhum ERTS encontrado. Configure harness/config/baseline.sh"
    exit 1
fi

echo "ERTS: $ERL"

# Compila PropEr (se necessário)
if [ ! -d "$PROPER_EBIN" ] || [ -z "$(ls "$PROPER_EBIN"/*.beam 2>/dev/null || true)" ]; then
    echo "Compilando PropEr... "
    mkdir -p "$PROPER_EBIN"
    erlc -I "$PROPER_ROOT/include" -o "$PROPER_EBIN" "$PROPER_ROOT"/src/*.erl 2>&1 | grep -v Warning || true
fi

# Compila os testes (se necessário)
ERLC_BIN="$(dirname "$ERL")/erlc"
[ -x "$ERLC_BIN" ] || ERLC_BIN="erlc"
find "$TESTS_DIR" -name "*.erl" -exec "$ERLC_BIN" -pa "$PROPER_EBIN" -o "$TESTS_DIR" {} +

echo "=== PropEr: suites formais PON-BEAM ==="

FAILED=0
for beam in "$TESTS_DIR"/pon_*_prop.beam; do
    [ -e "$beam" ] || continue
    MOD="$(basename "$beam" .beam)"
    [ -n "$FILTER" ] && [[ "$MOD" != *"$FILTER"* ]] && continue

    echo "--- $MOD ---"
    if ! "$ERL" -noshell \
        -pa "$PROPER_EBIN" -pa "$TESTS_DIR" \
        -eval "pon_prop_run:run(\"$MOD\", $NUM_TESTS), halt()." ; then
        FAILED=1
    fi
done

if [ "$FAILED" -ne 0 ]; then
    echo ""
    echo "ERRO: pelo menos uma propriedade falhou."
    exit 1
fi
echo ""
echo "Todas as propriedades passaram."