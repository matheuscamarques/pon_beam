# PON-BEAM Build config
# Paths para o PON-BEAM ERTS
# ATENÇÃO: quando o build PON-BEAM estiver pronto, mude para:
#   OTP_PONBEAM_ROOT=/opt/erlang/30-pon

OTP_PONBEAM_ROOT=${OTP_PONBEAM_ROOT:-/home/sanonichan/.asdf/installs/erlang/29.0.3}
PONBEAM_ERL=${OTP_PONBEAM_ROOT}/bin/erl
PONBEAM_ERLC=${OTP_PONBEAM_ROOT}/bin/erlc
