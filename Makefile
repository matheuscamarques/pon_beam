# PON-BEAM — Makefile
#
# Comandos principais:
#   make build-stock        Compila OTP 30 stock (baseline) — worktree otp-stock
#   make build-pon          Compila OTP com PON-BEAM — otp/ (branch pon-beam)
#   make build-all          Compila ambos
#   make emulator-stock     Recompila só a VM stock (rápido, ~1-3 min)
#   make emulator-pon       Recompila só a VM PON (rápido, ~1-3 min)
#   make benchmark          Roda harness completo
#   make benchmark-fase1    Roda só fase 1
#   make benchmark-list     Lista benchmarks
#   make report             Abre último diff report
#   make status             Mostra estado do repositório
#   make clean              Limpa artefatos de build

SHELL = /bin/bash
OTP_DIR = otp
OTP_STOCK_DIR = /home/sanonichan/projetos/otp-stock
HARNESS_DIR = harness

PREFIX_STOCK = /opt/erlang/30-stock
PREFIX_PON   = /opt/erlang/30-pon

BUILD_OPTS = --without-javac --without-odbc --without-wx
MAKE_OPTS  = -j$$(nproc)

.PHONY: all build-stock build-pon build-all benchmark benchmark-list report status clean emulator-stock emulator-pon docker-build bench-docker bench-docker-run bench-docker-copy

all: build-stock build-pon

## === Build (primeira vez, ~30 min cada) ===

build-stock:
	@echo "=== Compilando OTP 30 stock (baseline) em $(OTP_STOCK_DIR) ==="
	cd $(OTP_STOCK_DIR) && ./configure $(BUILD_OPTS) --prefix=$(PREFIX_STOCK) && make $(MAKE_OPTS) && make install

build-pon:
	@echo "=== Compilando OTP 30 com PON-BEAM em $(OTP_DIR) ==="
	cd $(OTP_DIR) && make clean && ./otp_build autoconf && ./configure $(BUILD_OPTS) --prefix=$(PREFIX_PON) --enable-pon-beam && make $(MAKE_OPTS) && make install

build-pon-debug:
	@echo "=== Compilando OTP 30 com PON-BEAM (debug) ==="
	cd $(OTP_DIR) && make clean && ./configure $(BUILD_OPTS) --prefix=$(PREFIX_PON)-debug --enable-pon-beam CFLAGS="-DPON_BEAM_DEBUG -g -O0" && make $(MAKE_OPTS) && make install

build-all: build-stock build-pon

build:
	@echo "Uso: make build-stock | make build-pon | make build-pon-debug | make build-all"

## === Iteração rápida (só o emulador C, precisa de build completo antes) ===

emulator-stock:
	@echo "=== Recompilando só a VM stock em $(OTP_STOCK_DIR) ==="
	cd $(OTP_STOCK_DIR)/erts/emulator && make $(MAKE_OPTS)
	cd $(OTP_STOCK_DIR) && make install

emulator-pon:
	@echo "=== Recompilando só a VM PON em $(OTP_DIR) ==="
	cd $(OTP_DIR)/erts/emulator && make $(MAKE_OPTS)
	cd $(OTP_DIR) && make install

## === Benchmarks ===

benchmark:
	cd $(HARNESS_DIR) && ./run.sh

benchmark-fase%:
	cd $(HARNESS_DIR) && ./run.sh --fase=$*

benchmark-only-%:
	cd $(HARNESS_DIR) && ./run.sh --only=$*

benchmark-list:
	cd $(HARNESS_DIR) && ./run.sh --list

report:
	open harness/results/latest/diff/index.html 2>/dev/null || xdg-open harness/results/latest/diff/index.html 2>/dev/null || echo "Relatório: harness/results/latest/diff/index.html"

## === Docker ===

DOCKER_IMAGE = pon-beam-bench
DOCKER_CONTAINER = pon-beam-results
RESULTS_DOCKER = harness/results/docker

docker-build:
	@echo "=== Buildando imagem Docker (OTP30 stock + PON-BEAM, ~30 min) ==="
	docker build --no-cache -f docker/Dockerfile -t $(DOCKER_IMAGE) .

bench-docker-run:
	@echo "=== Rodando benchmarks dentro do container ==="
	docker run --name $(DOCKER_CONTAINER) $(DOCKER_IMAGE)

bench-docker-copy:
	@echo "=== Copiando resultados para $(RESULTS_DOCKER)/ ==="
	rm -rf $(RESULTS_DOCKER)
	docker cp $(DOCKER_CONTAINER):/pon-beam/harness/results/latest/. $(RESULTS_DOCKER)/
	@echo "Relatório: $(RESULTS_DOCKER)/diff/index.html"

bench-docker: bench-docker-run bench-docker-copy

## === Livro PON-BEAM ===

BOOK_DIR = book

book-build:
	@echo "=== Gerando site HTML do livro PON-BEAM ==="
	python3 $(BOOK_DIR)/build.py

book-open:
	@echo "=== Abrindo livro PON-BEAM ==="
	open $(BOOK_DIR)/output/index.html 2>/dev/null || xdg-open $(BOOK_DIR)/output/index.html 2>/dev/null || echo "Índice: $(BOOK_DIR)/output/index.html"

book-clean:
	rm -rf $(BOOK_DIR)/output

## === Utilitários ===

status:
	@echo "=== Git status ==="
	git status
	@echo ""
	@echo "=== Branch ==="
	git branch
	@echo ""
	@echo "=== OTP version ==="
	cat $(OTP_DIR)/OTP_VERSION

clean:
	cd $(OTP_DIR) && git checkout . && git clean -fd
	rm -rf $(HARNESS_DIR)/results
	rm -f $(HARNESS_DIR)/benchmarks/*.beam
	rm -f $(HARNESS_DIR)/benchmarks/lib/*.beam
