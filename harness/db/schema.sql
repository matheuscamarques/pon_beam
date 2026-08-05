-- Schema do Banco de Dados de Observabilidade Contínua da PON-BEAM
-- Armazena histórico irrefutável de execuções de benchmarks por Git Commit Hash

CREATE TABLE IF NOT EXISTS benchmark_runs (
    run_id TEXT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    git_commit_hash TEXT NOT NULL,
    erts_type TEXT NOT NULL, -- 'baseline' ou 'ponbeam'
    benchmark_name TEXT NOT NULL,
    duration_ms REAL NOT NULL,
    memory_bytes INTEGER NOT NULL,
    context_switches INTEGER NOT NULL,
    p50_latency_us REAL,
    p90_latency_us REAL,
    p99_latency_us REAL,
    ops_per_sec REAL,
    cpu_idle_percent REAL,
    pon_stats_json TEXT
);

CREATE TABLE IF NOT EXISTS telemetry_time_series (
    sample_id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id TEXT NOT NULL,
    second INTEGER NOT NULL,
    cpu_user_ms REAL NOT NULL,
    memory_bytes INTEGER NOT NULL,
    active_processes INTEGER NOT NULL,
    context_switches INTEGER NOT NULL,
    FOREIGN KEY(run_id) REFERENCES benchmark_runs(run_id)
);
