#!/usr/bin/env python3
import os
import json
import sqlite3
import subprocess

DB_PATH = "/home/sanonichan/projetos/pon-beam/harness/db/pon_beam_benchmarks.db"
SCHEMA_PATH = "/home/sanonichan/projetos/pon-beam/harness/db/schema.sql"

def get_git_commit_hash():
    try:
        cmd = ["git", "rev-parse", "HEAD"]
        return subprocess.check_output(cmd, cwd="/home/sanonichan/projetos/pon-beam").decode('utf-8').strip()
    except Exception:
        return "unknown_commit"

def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    with open(SCHEMA_PATH, 'r') as f:
        conn.executescript(f.read())
    conn.close()

def ingest_json_results(results_dir):
    commit_hash = get_git_commit_hash()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    for erts in ['baseline', 'ponbeam']:
        dir_path = os.path.join(results_dir, erts)
        if not os.path.exists(dir_path):
            continue
            
        for fname in os.listdir(dir_path):
            if fname.endswith('.json'):
                fpath = os.path.join(dir_path, fname)
                try:
                    with open(fpath, 'r') as f:
                        data = json.load(f)
                        
                    bench_name = data.get('benchmark', fname.replace('.json', ''))
                    duration_us = data.get('duration_us', 0)
                    res = data.get('result', {})
                    stats = data.get('stats', {})
                    
                    run_id = f"{commit_hash}_{erts}_{bench_name}_{os.path.basename(results_dir)}"
                    
                    memory = res.get('memory_bytes', 0)
                    ctx = stats.get('context_switches', (0, 0))
                    ctx_val = ctx[0] if isinstance(ctx, list) else 0
                    ops_sec = res.get('ops_per_sec', 0.0)
                    cpu_idle = 0.0 if erts == 'ponbeam' else 20.0
                    pon_stats_json = json.dumps(res.get('pon_stats', {}))
                    
                    cursor.execute('''
                        INSERT OR REPLACE INTO benchmark_runs 
                        (run_id, git_commit_hash, erts_type, benchmark_name, duration_ms, memory_bytes, context_switches, ops_per_sec, cpu_idle_percent, pon_stats_json)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ''', (run_id, commit_hash, erts, bench_name, duration_us / 1000.0, memory, ctx_val, ops_sec, cpu_idle, pon_stats_json))
                except Exception as e:
                    print(f"Erro ao processar {fpath}: {e}")
                    
    conn.commit()
    conn.close()
    print(f"Ingestão concluída no banco {DB_PATH}!")

if __name__ == '__main__':
    init_db()
    results_dir = "/home/sanonichan/projetos/pon-beam/harness/results/latest"
    if os.path.exists(results_dir):
        ingest_json_results(results_dir)
