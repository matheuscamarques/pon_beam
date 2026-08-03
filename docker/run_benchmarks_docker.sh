#!/bin/bash
# run_benchmarks_docker.sh — PON-BEAM Benchmarks via Docker
#
# Constrói OTP 30 stock + PON-BEAM dentro de container,
# executa o harness comparativo, extrai resultados.
#
# Uso:
#   ./docker/run_benchmarks_docker.sh              # Build + benchmark
#   ./docker/run_benchmarks_docker.sh --run        # Só executa (pula build)
#   ./docker/run_benchmarks_docker.sh --extract    # Só extrai resultados

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/harness/results/docker"
LOG_DIR="$SCRIPT_DIR/.build"

mkdir -p "$RESULTS_DIR" "$LOG_DIR"

case "${1:-}" in
  --run)
    echo "Executando benchmarks (pulando build)..."
    cd "$SCRIPT_DIR"
    docker compose run --rm bench 2>&1 | tee "$LOG_DIR/benchmark.log"
    ;;
  --extract)
    echo "Extraindo resultados..."
    docker cp pon-beam-results:/pon-beam/harness/results/latest/. "$RESULTS_DIR/" 2>/dev/null || true
    if [ -f "$RESULTS_DIR/diff/index.html" ]; then
      cp "$RESULTS_DIR/diff/index.html" "$LOG_DIR/diff-report.html"
      echo "Diff: $RESULTS_DIR/diff/index.html"
      echo "Cópia: $LOG_DIR/diff-report.html"
    else
      echo "Sem resultados ainda. Execute o benchmark primeiro."
    fi
    ;;
  *)
    echo "=========================================="
    echo " PON-BEAM — Build + Benchmark via Docker"
    echo "=========================================="
    echo "Isso leva ~20-30 minutos na primeira vez."
    echo "Log: $LOG_DIR/build.log"
    echo ""

    cd "$SCRIPT_DIR"
    docker compose build bench 2>&1 | tee "$LOG_DIR/build.log"

    echo ""
    echo "Build concluído. Executando benchmarks..."
    docker compose run --rm bench 2>&1 | tee "$LOG_DIR/benchmark.log"

    echo ""
    echo "Extraindo resultados..."
    docker cp pon-beam-results:/pon-beam/harness/results/latest/. "$RESULTS_DIR/" 2>/dev/null || true

    if [ -f "$RESULTS_DIR/diff/index.html" ]; then
      cp "$RESULTS_DIR/diff/index.html" "$LOG_DIR/diff-report.html"
      echo ""
      echo "=========================================="
      echo " RESULTADOS"
      echo "=========================================="
      echo "Diff: $RESULTS_DIR/diff/index.html"
      echo ""
      grep -oP '(?<=<td>)[^<]+(?=</td>)' "$RESULTS_DIR/diff/index.html" 2>/dev/null | head -30
    fi
    ;;
esac
