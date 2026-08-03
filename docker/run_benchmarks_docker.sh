#!/bin/bash
# run_benchmarks_docker.sh — Executa benchmarks PON-BEAM via Docker
#
# Todo log salvo em .build/ para debug.
#
# Uso:
#   ./run_benchmarks_docker.sh              # Build + benchmark completo
#   ./run_benchmarks_docker.sh --build-only # S compila OTP
#   ./run_benchmarks_docker.sh --run-only   # S roda benchmarks
#   ./run_benchmarks_docker.sh --extract    # S extrai resultados
#   ./run_benchmarks_docker.sh --help       # Ajuda

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$SCRIPT_DIR/.build"
RESULTS_DIR="$PROJECT_ROOT/harness/results/docker"

mkdir -p "$LOG_DIR" "$RESULTS_DIR"

BUILD_ONLY=0
RUN_ONLY=0
EXTRACT=0

for arg in "$@"; do
  case "$arg" in
    --build-only) BUILD_ONLY=1 ;;
    --run-only)   RUN_ONLY=1 ;;
    --extract)    EXTRACT=1 ;;
    --help) echo "Uso: $0 [--build-only|--run-only|--extract]"; exit 0 ;;
  esac
done

if [ "$EXTRACT" -eq 1 ]; then
  echo "=== Extraindo resultados ==="
  docker cp pon-beam-bench:/pon-beam/harness/results/latest/. "$RESULTS_DIR/" 2>/dev/null || true
  ls -la "$RESULTS_DIR/diff/" 2>/dev/null || echo "Sem resultados ainda"
  exit 0
fi

# ============================================================
# PASSO 1: Build das imagens Docker
# ============================================================
if [ "$RUN_ONLY" -eq 0 ]; then
  echo "=========================================="
  echo " PON-BEAM — Build Docker"
  echo " Log: $LOG_DIR/build.log"
  echo "=========================================="
  echo "Inicio: $(date)" > "$LOG_DIR/build.log"

  cd "$SCRIPT_DIR"
  docker compose build bench 2>&1 | tee -a "$LOG_DIR/build.log"
  BUILD_EXIT=${PIPESTATUS[0]}

  echo "Fim:    $(date)" >> "$LOG_DIR/build.log"

  if [ "$BUILD_EXIT" -ne 0 ]; then
    echo ""
    echo "  ERRO: Build falhou (código $BUILD_EXIT)"
    echo "  Log completo: $LOG_DIR/build.log"
    echo ""
    echo "  Últimas 30 linhas:"
    tail -30 "$LOG_DIR/build.log"
    exit $BUILD_EXIT
  fi

  echo "  Build concluído com sucesso!"
  echo ""
fi

if [ "$BUILD_ONLY" -eq 1 ]; then
  echo "Build concluído. Para rodar: $0 --run-only"
  exit 0
fi

# ============================================================
# PASSO 2: Executar benchmarks
# ============================================================
echo "=========================================="
echo " PON-BEAM — Executando Benchmarks"
echo " Log: $LOG_DIR/benchmark.log"
echo "=========================================="

cd "$SCRIPT_DIR"
docker compose run --rm bench 2>&1 | tee "$LOG_DIR/benchmark.log"
RUN_EXIT=${PIPESTATUS[0]}

if [ "$RUN_EXIT" -ne 0 ]; then
  echo ""
  echo "  ERRO: Benchmark falhou (código $RUN_EXIT)"
  echo "  Últimas 30 linhas:"
  tail -30 "$LOG_DIR/benchmark.log"
  exit $RUN_EXIT
fi

# ============================================================
# PASSO 3: Extrair resultados
# ============================================================
echo ""
echo "=========================================="
echo " Extraindo resultados"
echo "=========================================="

docker cp pon-beam-bench:/pon-beam/harness/results/latest/. "$RESULTS_DIR/" 2>/dev/null || true

if [ -f "$RESULTS_DIR/diff/index.html" ]; then
  cp "$RESULTS_DIR/diff/index.html" "$LOG_DIR/diff-report.html"
  echo ""
  echo "  RESULTADOS:"
  echo "  Diff report: $RESULTS_DIR/diff/index.html"
  echo "  Cópia local: $LOG_DIR/diff-report.html"
  echo ""

  # Mostra tabela resumo
  echo "  Tabela de resultados:"
  echo "  Benchmark                    Baseline        PON-BEAM        Ganho"
  echo "  ---------------------------  --------------  --------------  ------"
  for f in "$RESULTS_DIR/baseline/"*.json; do
    name=$(basename "$f" .json)
    b=$(grep -oP '"duration_us":[0-9.]+' "$f" 2>/dev/null | head -1 | grep -oP '[0-9.]+')
    p=$(grep -oP '"duration_us":[0-9.]+' "$RESULTS_DIR/ponbeam/$name.json" 2>/dev/null | head -1 | grep -oP '[0-9.]+')
    if [ -n "$b" ] && [ -n "$p" ] && [ "$(echo "$p > 0" | bc -l 2>/dev/null)" = "1" ]; then
      ratio=$(echo "scale=2; $b / $p" | bc -l 2>/dev/null)
      printf "  %-28s  %-14s  %-14s  %s\n" "$name" "${b}us" "${p}us" "${ratio}x"
    fi
  done
else
  echo "  Aviso: diff report no encontrado"
  echo "  Log: $LOG_DIR/benchmark.log"
fi

echo ""
echo "=========================================="
echo " Concluído!"
echo " Logs: $LOG_DIR/"
echo "=========================================="
