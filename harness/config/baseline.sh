# PON-BEAM Build config
# Paths para os dois ERTS
# ATENÇÃO: Build OTP 30 leva ~30 min. Enquanto isso, usamos o Erlang 29 do sistema.
# Para resultados reais, execute: make build-stock && make build-pon

OTP_BASELINE_ROOT=${OTP_BASELINE_ROOT:-/opt/erlang/30-stock}
BASELINE_ERL=${OTP_BASELINE_ROOT}/bin/erl
BASELINE_ERLC=${OTP_BASELINE_ROOT}/bin/erlc
