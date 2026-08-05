#!/usr/bin/env python3
import os
import sqlite3
import json

DB_PATH = "/home/sanonichan/projetos/pon-beam/harness/db/pon_beam_benchmarks.db"
OUTPUT_HTML = "/home/sanonichan/projetos/pon-beam/harness/results/dashboard.html"

def generate_dashboard():
    if not os.path.exists(DB_PATH):
        print(f"Banco de dados {DB_PATH} ainda não foi inicializado.")
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    cursor.execute("SELECT run_id, git_commit_hash, erts_type, benchmark_name, duration_ms, ops_per_sec, cpu_idle_percent FROM benchmark_runs ORDER BY timestamp DESC")
    rows = cursor.fetchall()
    conn.close()
    
    table_rows_html = ""
    for r in rows:
        run_id, commit, erts, bench, dur, ops, cpu = r
        badge_color = "#5cb85c" if erts == "ponbeam" else "#d9534f"
        table_rows_html += f"""
        <tr>
            <td><code>{commit[:8]}</code></td>
            <td><span style="background-color:{badge_color}; color:white; padding:2px 8px; border-radius:4px; font-weight:bold;">{erts.upper()}</span></td>
            <td><strong>{bench}</strong></td>
            <td>{dur:.2f} ms</td>
            <td>{ops:,.2f} ops/s</td>
            <td>{cpu:.1f}%</td>
        </tr>
        """
        
    html_content = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <title>PON-BEAM — Laboratório de Observabilidade Contínua</title>
    <style>
        body {{ font-family: 'Helvetica Neue', Arial, sans-serif; background-color: #f4f6f9; margin: 0; padding: 20px; color: #333; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }}
        h1 {{ color: #1a252f; border-bottom: 2px solid #3498db; padding-bottom: 10px; }}
        table {{ width: 100%; border-collapse: collapse; margin-top: 20px; }}
        th, td {{ padding: 12px 15px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background-color: #2c3e50; color: white; }}
        tr:hover {{ background-color: #f1f1f1; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 PON-BEAM — Laboratório de Observabilidade Contínua</h1>
        <p>Série Histórica de Benchmarks e Rastreabilidade por Git Commit Hash</p>
        <table>
            <thead>
                <tr>
                    <th>Commit Hash</th>
                    <th>ERTS Engine</th>
                    <th>Benchmark</th>
                    <th>Duração (ms)</th>
                    <th>Throughput</th>
                    <th>CPU Idle</th>
                </tr>
            </thead>
            <tbody>
                {table_rows_html if table_rows_html else '<tr><td colspan="6">Nenhum dado registrado ainda. Execute o harness para alimentar o banco de dados.</td></tr>'}
            </tbody>
        </table>
    </div>
</body>
</html>
"""
    
    os.makedirs(os.path.dirname(OUTPUT_HTML), exist_ok=True)
    with open(OUTPUT_HTML, 'w') as f:
        f.write(html_content)
        
    print(f"Dashboard de Observabilidade gerado com sucesso em: {OUTPUT_HTML}")

if __name__ == '__main__':
    generate_dashboard()
