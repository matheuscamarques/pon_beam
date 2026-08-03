# PON-BEAM Benchmark Docker
# Build OTP 30 stock + PON-BEAM e executa harness comparativo
#
# Uso: docker compose up --build
# Resultados em: ./results/

FROM ubuntu:24.04 AS builder

LABEL description="PON-BEAM Benchmark Environment"

# Evita prompts interativos
ENV DEBIAN_FRONTEND=noninteractive
ENV ERL_TOP=/otp

# Dependncias de build do OTP
RUN apt-get update && apt-get install -y \
    build-essential autoconf m4 \
    libncurses-dev \
    libssl-dev libxslt1-dev libxml2-utils \
    unixodbc-dev \
    perl \
    git \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# ESTGIO 1: Build OTP 30 stock (baseline)
# ============================================================
COPY otp /otp

RUN cd /otp && \
    rm -rf erts/x86_64-pc-linux-gnu erts/emulator/x86_64-pc-linux-gnu \
           config.* config.log config.status config.mk erts/config.log \
           lib/*/x86_64-pc-linux-gnu lib/*/config.* lib/*/config.log \
    && ./configure --prefix=/opt/erlang/30-stock \
    --without-javac --without-odbc --without-wx --without-ssl \
    && make -j$(nproc) && make install

# ============================================================
# ESTGIO 2: Build OTP 30 com PON-BEAM
# ============================================================
RUN cd /otp && \
    make clean && \
    ./configure --prefix=/opt/erlang/30-pon \
    --without-javac --without-odbc --without-wx --without-ssl \
    --disable-dynamic-ssl-lib \
    --enable-pon-beam \
    && make TYPE=ponbeam -j$(nproc) && make install

# ============================================================
# ESTGIO 3: Usamos o builder como imagem final
# (contm todos os ERTS e ferramentas)
# ============================================================
FROM ubuntu:24.04

# Runtime dependencies
RUN apt-get update && apt-get install -y \
    libncurses6 libtinfo6 libssl3t64 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copia os ERTS instalados
COPY --from=builder /opt/erlang /opt/erlang

# Copia o harness
COPY harness /pon-beam/harness
COPY docs /pon-beam/docs

# Script de entrada
RUN echo '#!/bin/bash\n\
echo "PON-BEAM Benchmark Runner"\n\
echo "========================================="\n\
echo ""\n\
echo "OTP Stock:"\n\
/opt/erlang/30-stock/bin/erl -noshell -eval '\''\
  io:format("  Verso: ~s~n", [erlang:system_info(otp_release)]),\
  halt().'\''\n\
echo ""\n\
echo "PON-BEAM:"\n\
/opt/erlang/30-pon/bin/erl -noshell -eval '\''\
  io:format("  Verso: ~s~n", [erlang:system_info(otp_release)]),\
  io:format("  PON_BEAM: ~p~n", [erlang:system_info(pon_stats) /= undefined]),\
  halt().'\''\n\
echo ""\n\
echo "========================================="\n\
echo "Executando benchmarks..."\n\
export OTP_BASELINE_ROOT=/opt/erlang/30-stock\n\
export OTP_PONBEAM_ROOT=/opt/erlang/30-pon\n\
cd /pon-beam/harness\n\
bash run.sh 2>&1\n\
echo ""\n\
echo "Resultados:"\n\
ls -la results/latest/diff/\n' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
