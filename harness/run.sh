#!/bin/bash
# run.sh — PON-BEAM Benchmark Harness
# Executa todos os benchmarks nos dois ERTS e gera diff comparativo.
#
# Uso:
#   ./run.sh                    # Suíte completa
#   ./run.sh --fase=1           # Só fase 1
#   ./run.sh --fase=1,2         # Fases 1 e 2
#   ./run.sh --list             # Lista benchmarks disponíveis
#   ./run.sh --only=receive     # Só benchmark específico

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_ROOT="$SCRIPT_DIR"
BENCHMARKS_DIR="$HARNESS_ROOT/benchmarks"
LIB_DIR="$BENCHMARKS_DIR/lib"
RESULTS_DIR="$HARNESS_ROOT/results/$(date +%Y%m%d_%H%M%S)"
OTS=0

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

source "$HARNESS_ROOT/config/baseline.sh"
source "$HARNESS_ROOT/config/ponbeam.sh"

# Parse args
FASE_FILTER=""
ONLY_FILTER=""
LIST_MODE=0

for arg in "$@"; do
    case "$arg" in
        --fase=*) FASE_FILTER="${arg#--fase=}" ;;
        --only=*) ONLY_FILTER="${arg#--only=}" ;;
        --list)   LIST_MODE=1 ;;
        *)        echo "Uso: $0 [--fase=N[,M]] [--only=nome] [--list]"; exit 1 ;;
    esac
done

find_benchmarks() {
    local fase_filter=$1
    local only_filter=$2

    find "$BENCHMARKS_DIR" -name "*.erl" ! -path "*/lib/*" | while read -r f; do
        local name
        name=$(basename "$f" .erl)
        local fase
        fase=$(echo "$name" | sed 's/^fase//; s/_.*//')

        # Filtro por fase
        if [ -n "$fase_filter" ]; then
            local match=0
            IFS=',' read -ra FASES <<< "$fase_filter"
            for ff in "${FASES[@]}"; do
                if [ "$fase" = "$ff" ]; then
                    match=1
                    break
                fi
            done
            [ "$match" -eq 0 ] && continue
        fi

        # Filtro por nome
        if [ -n "$only_filter" ]; then
            [[ "$name" != *"$only_filter"* ]] && continue
        fi

        echo "$name|$f"
    done
}

compile_benchmarks() {
    local erlc=$1
    echo -e "${YELLOW}Compilando benchmarks com $erlc${NC}"
    find "$BENCHMARKS_DIR" -name "*.erl" -exec "$erlc" -I "$LIB_DIR" -o "$BENCHMARKS_DIR" {} +
    # Compila lib
    find "$LIB_DIR" -name "*.erl" -exec "$erlc" -o "$LIB_DIR" {} +
}

# Flags comuns dos ERTS nos benchmarks.
# +S 1:1    — scheduler único: mede o mecanismo (não contention) e faz o
#             pon_stats thread-local do system_info refletir o workload todo.
#
# Observação: +JPemulator NÃO existe neste ERTS (OTP 29/30 relabelado). O
# fast-path PON-Receive (msg_instrs.tab) vive apenas no interpreter; por isso
# o ERTS PON é instalado como FLAVOR=emu (interpreter) nesta etapa. O baseline
# stock deve ser rebuildado como FLAVOR=emu para comparação justa.
#
# Override: ERTS_EXTRA_ARGS="+S 2:2" ./run.sh
ERTS_EXTRA_ARGS="${ERTS_EXTRA_ARGS:-+S 1:1}"

run_benchmarks() {
    local erl=$1
    local output_dir=$2
    local label=$3
    local erlc=$4

    echo -e "\n${CYAN}=== Rodando benchmarks no $label ===${NC}"
    mkdir -p "$output_dir"

    compile_benchmarks "$erlc"

    # Prepara path: lib + benchmarks
    local pa_opts="-pa $LIB_DIR -pa $BENCHMARKS_DIR"

    find_benchmarks "$FASE_FILTER" "$ONLY_FILTER" | sort | while IFS='|' read -r name path; do
        echo -e "  ${YELLOW}[$label]${NC} $name..."
        local out="$output_dir/${name}.json"
        "$erl" -noshell $ERTS_EXTRA_ARGS $pa_opts \
            -eval "pon_harness:run(\"$name\", \"$out\"), halt()." 2>&1 | sed 's/^/    /'
    done
}

generate_diff() {
    echo -e "\n${CYAN}=== Gerando diff report ===${NC}"
    local erl=$1
    local erlc=$2
    local pa_opts="-pa $LIB_DIR -pa $BENCHMARKS_DIR"

    mkdir -p "$RESULTS_DIR/diff"

    # Compila libs do diff
    "$erlc" -o "$LIB_DIR" "$LIB_DIR/pon_diff.erl" 2>/dev/null

    # Gera HTML
    "$erl" -noshell $pa_opts \
        -eval "pon_diff:generate(\"$RESULTS_DIR\"), halt()."

    # Copia assets
    cp "$HARNESS_ROOT/report/assets/"* "$RESULTS_DIR/diff/" 2>/dev/null || true

    # Último resultado link simbólico
    ln -sfn "$RESULTS_DIR" "$HARNESS_ROOT/results/latest"

    echo -e "${GREEN}=== Relatório: $RESULTS_DIR/diff/index.html ===${NC}"
}

list_benchmarks() {
    echo -e "${CYAN}Benchmarks disponíveis:${NC}"
    find_benchmarks "" "" | sort | while IFS='|' read -r name path; do
        echo "  $name ($path)"
    done
}

main() {
    if [ "$LIST_MODE" -eq 1 ]; then
        list_benchmarks
        exit 0
    fi

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  PON-BEAM Benchmark Harness${NC}"
    echo -e "${GREEN}========================================${NC}"

    # Verifica ERTS disponíveis
    for exe in "$BASELINE_ERL" "$PONBEAM_ERL"; do
        if [ ! -x "$exe" ]; then
            echo -e "${RED}ERTS não encontrado: $exe${NC}"
            echo -e "${YELLOW}Configure os paths em config/baseline.sh e config/ponbeam.sh${NC}"
            OTS=1
        fi
    done
    [ "$OTS" -ne 0 ] && exit 1

    # Baseline
    run_benchmarks "$BASELINE_ERL" "$RESULTS_DIR/baseline" "BASELINE (OTP 30 stock)" "$BASELINE_ERLC"

    # PON-BEAM
    run_benchmarks "$PONBEAM_ERL" "$RESULTS_DIR/ponbeam" "PON-BEAM" "$PONBEAM_ERLC"

    # Diff
    generate_diff "$BASELINE_ERL" "$BASELINE_ERLC"

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Concluído!${NC}"
    echo -e "${GREEN}  Relatório: $RESULTS_DIR/diff/index.html${NC}"
    echo -e "${GREEN}========================================${NC}"
}

main
