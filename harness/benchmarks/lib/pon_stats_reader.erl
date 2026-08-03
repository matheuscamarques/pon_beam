-module(pon_stats_reader).
-export([read/0, read/1, reset/0]).

%% read() -> map() | undefined
read() ->
    try erlang:system_info(pon_stats) of
        Stats -> Stats
    catch
        error:badarg -> undefined
    end.

%% read(Key) -> {ok, Value} | undefined
read(Key) ->
    case read() of
        #{Key := Value} -> {ok, Value};
        _ -> undefined
    end.

%% reset() -> ok | undefined
reset() ->
    try erlang:system_info(reset_pon_stats) of
        _ -> ok
    catch
        error:badarg -> undefined
    end.
