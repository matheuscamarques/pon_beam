#!/bin/bash
# run_benchmarks_docker.sh — Executa benchmarks PON-BEAM via Docker
#
# Constrói OTP 30 stock + PON-BEAM dentro de um container,
# executa o harness comparativo, e extrai os resultados.
#
# Pré-requisitos: Docker, docker compose
#
# Uso:
#   ./run_benchmarks_docker.sh              # Build + benchmark completo
#   ./run_benchmarks_docker.sh --quick      # Só benchmark (pula build)
#   ./run_benchmarks_docker.sh --extract    # Só extrai resultados
#   ./run_benchmarks_docker.sh --help       # Ajuda

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/harness/results/docker"
REPORT_DIR="$PROJECT_ROOT/harness/report"

QUICK=0
EXTRACT=0

for arg in "$@"; do
  case "$arg" in
    --quick) QUICK=1 ;;
    --extract) EXTRACT=1 ;;
    --help) echo "Uso: $0 [--quick] [--extract]"; exit 0 ;;
  esac
done

mkdir -p "$RESULTS_DIR" "$REPORT_DIR"

if [ "$EXTRACT" -eq 1 ]; then
  echo "=== Extraindo resultados ==="
  docker cp pon-beam-bench:/pon-beam/harness/results/latest/. "$RESULTS_DIR/"
  echo "Resultados em: $RESULTS_DIR"
  echo "Diff report: $RESULTS_DIR/diff/index.html"
  exit 0
fi

if [ "$QUICK" -eq 0 ]; then
  echo "=========================================="
  echo " PON-BEAM Benchmark via Docker"
  echo "=========================================="
  echo ""
  echo "Construindo imagens (OTP 30 stock + PON-BEAM)..."
  echo "Isso leva ~20-30 minutos na primeira vez."
  echo ""

  cd "$SCRIPT_DIR"
  docker compose build bench 2>&1
fi

echo ""
echo "Executando benchmarks..."
cd "$SCRIPT_DIR"
docker compose run --rm bench 2>&1 | tee "$RESULTS_DIR/benchmark.log"

echo ""
echo "Extraindo resultados..."
docker cp pon-beam-bench:/pon-beam/harness/results/latest/. "$RESULTS_DIR/" 2>/dev/null || true

echo ""
echo "=========================================="
echo " RESULTADOS"
echo "=========================================="
if [ -f "$RESULTS_DIR/diff/index.html" ]; then
  echo "Diff report: $RESULTS_DIR/diff/index.html"
  echo "Log:         $RESULTS_DIR/benchmark.log"
  echo ""
  echo "Para abrir: xdg-open $RESULTS_DIR/diff/index.html"
else
  echo "Aguardando resultados..."
fi

echo ""
echo "Para extrair resultados manualmente:"
echo "  docker cp pon-beam-bench:/pon-beam/harness/results/latest/. $RESULTS_DIR/"
