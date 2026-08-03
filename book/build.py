#!/usr/bin/env python3
"""
PON-BEAM Book Builder — Gera site HTML interativo a partir dos capítulos Markdown.
 
Uso: python3 build.py [--watch]
"""

import os
import re
import json
import subprocess
import hashlib
from pathlib import Path
from markdown import markdown
from pygments import highlight
from pygments.lexers import CLexer, ErlangLexer, BashLexer, JsonLexer
from pygments.formatters import HtmlFormatter

ROOT = Path(__file__).parent
SRC = ROOT / "src"
CHAPTERS = SRC / "chapters"
OUTPUT = ROOT / "output"
THEME = ROOT / "theme"

BOOK_JSON = ROOT / "book.json"


def load_config():
    with open(BOOK_JSON) as f:
        return json.load(f)


def render_diagram(dot_code, diagram_id):
    """Render a Graphviz DOT block to SVG inline."""
    try:
        result = subprocess.run(
            ["dot", "-Tsvg"],
            input=dot_code,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            svg = result.stdout
            # Remove XML declaration and DOCTYPE for inline embedding
            svg = re.sub(r'<\?xml.*?\?>', '', svg)
            svg = re.sub(r'<!DOCTYPE.*?>', '', svg)
            svg = svg.strip()
            return f'<div class="diagram" id="diag-{diagram_id}">{svg}</div>'
        else:
            return f'<pre class="diagram-error">Erro DOT: {result.stderr}</pre>'
    except FileNotFoundError:
        return '<pre class="diagram-error">Graphviz (dot) não encontrado. Instale: apt install graphviz</pre>'


def extract_frontmatter(text):
    """Extract YAML-like frontmatter from markdown."""
    m = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
    if m:
        meta = {}
        for line in m.group(1).strip().split('\n'):
            if ':' in line:
                key, val = line.split(':', 1)
                meta[key.strip()] = val.strip().strip('"\'')
        body = text[m.end():]
        return meta, body
    return {}, text


def process_code_blocks(body):
    """Process fenced code blocks with language-specific highlighting."""
    def replace_code(m):
        lang = m.group(1) or 'text'
        code = m.group(2)
        lexer_map = {
            'c': CLexer,
            'erlang': ErlangLexer,
            'elixir': ErlangLexer,
            'console': BashLexer,
            'bash': BashLexer,
            'json': JsonLexer,
            'dot': None,  # handled separately
        }
        lexer_cls = lexer_map.get(lang)
        if lexer_cls:
            try:
                highlighted = highlight(code, lexer_cls(), HtmlFormatter(style='monokai'))
                return f'<div class="code-block lang-{lang}">{highlighted}</div>'
            except Exception:
                pass
        return f'<pre><code class="lang-{lang}">{code}</code></pre>'
    
    # First, handle DOT blocks for diagrams
    def replace_dot(m):
        lang = m.group(1) or 'text'
        title = m.group(2).strip() if m.group(2) else ''
        code = m.group(3)
        if lang == 'dot':
            diagram_id = hashlib.md5(code.encode()).hexdigest()[:8]
            caption = f'<div class="diagram-caption">{title}</div>' if title else ''
            return render_diagram(code, diagram_id) + caption
        # Fallback to regular code
        lexer_map = {
            'c': CLexer,
            'erlang': ErlangLexer,
            'elixir': ErlangLexer,
            'console': BashLexer,
            'bash': BashLexer,
            'json': JsonLexer,
        }
        lexer_cls = lexer_map.get(lang)
        if lexer_cls:
            try:
                highlighted = highlight(code, lexer_cls(), HtmlFormatter(style='monokai'))
                return f'<div class="code-block lang-{lang}">{highlighted}</div>'
            except Exception:
                pass
        title_html = f'<div class="code-caption">{title}</div>' if title else ''
        return f'{title_html}<pre><code class="lang-{lang}">{code}</code></pre>'
    
    # Process dot diagrams first, then regular code
    # Handles: ```dot [optional title]
    #           digraph code...
    #           ```
    body = re.sub(r'```(\w+)([^\n]*)\n(.*?)```', replace_dot, body, flags=re.DOTALL)
    return body


def make_toc(chapters, current_id=None):
    """Generate sidebar navigation HTML."""
    parts = {
        "frontmatter": "",
        "I": "Fundamentos",
        "II": "Subsistemas PON",
        "III": "Engenharia e Validação",
        "IV": "Síntese",
        "backmatter": "",
    }
    html = '<nav class="sidebar-nav">\n'
    html += '<div class="nav-header">\n'
    html += '<h3><a href="index.html">PON-BEAM</a></h3>\n'
    html += '</div>\n'
    
    # Frontmatter (capa, folha de rosto) — without "Parte" label
    for ch in chapters:
        if ch.get("part") == "frontmatter":
            active = ' class="active"' if ch["id"] == current_id else ''
            label = ch["title"]
            html += f'<div class="nav-frontmatter"><a href="{ch["id"]}.html">{label}</a></div>\n'
    
    for part_num, part_name in parts.items():
        if part_num in ("frontmatter", "backmatter"):
            continue
        html += f'<div class="nav-part">Parte {part_num}: {part_name}</div>\n'
        html += '<ul>\n'
        for ch in chapters:
            if ch.get("part") == part_num:
                active = ' class="active"' if ch["id"] == current_id else ''
                html += f'<li{active}><a href="{ch["id"]}.html">{ch["title"]}</a></li>\n'
        html += '</ul>\n'
    
    # Backmatter (contra-capa)
    for ch in chapters:
        if ch.get("part") == "backmatter":
            active = ' class="active"' if ch["id"] == current_id else ''
            label = ch["title"]
            html += f'<div class="nav-frontmatter"><a href="{ch["id"]}.html">{label}</a></div>\n'
    
    html += '</nav>\n'
    return html


def make_search_index(chapters, chapter_bodies):
    """Build a search index JSON."""
    index = []
    for ch, body in zip(chapters, chapter_bodies):
        # Extract text content, remove markdown formatting
        text = re.sub(r'[#*`>\[\]]', '', body)
        text = re.sub(r'\n+', ' ', text)
        index.append({
            "id": ch["id"],
            "title": ch["title"],
            "part": ch["part"],
            "text": text[:500],  # Store first 500 chars for snippet
        })
    return index


def render_chapter(ch, body_html, config):
    """Render a complete HTML page for a chapter."""
    chapters = config["chapters"]
    prev_ch = None
    next_ch = None
    for i, c in enumerate(chapters):
        if c["id"] == ch["id"]:
            if i > 0:
                prev_ch = chapters[i-1]
            if i < len(chapters) - 1:
                next_ch = chapters[i+1]
            break
    
    toc = make_toc(chapters, ch["id"])
    
    # ABNT special pages — hidden sidebar by default
    is_special = ch["id"] in ("capa", "folha-de-rosto", "contra-capa")
    body_class = f'{ch["id"]} sidebar-hidden' if is_special else ''

    prev_html = f'<a href="{prev_ch["id"]}.html" class="nav-prev">← {prev_ch["title"]}</a>' if prev_ch else ''
    next_html = f'<a href="{next_ch["id"]}.html" class="nav-next">{next_ch["title"]} →</a>' if next_ch else ''

    hide_header = is_special
    header_html = f'<header class="chapter-header"><h1>{ch["title"]}</h1></header>' if not hide_header else ''
    
    return f'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{ch["title"]} — PON-BEAM</title>
    <link rel="stylesheet" href="theme/style.css">
    <link rel="stylesheet" href="theme/pygments.css">
</head>
<body class="{body_class}">
    <button class="menu-toggle" aria-label="Abrir menu" onclick="document.body.classList.toggle('sidebar-hidden')">☰</button>
    <div class="layout">
        {toc}
        <main class="content">
            {header_html}
            <article>
                {body_html}
            </article>
            <footer class="chapter-nav">
                {prev_html}
                {next_html}
            </footer>
        </main>
    </div>
    <script src="theme/search.js"></script>
</body>
</html>'''


def render_index(config):
    """Render the book index page."""
    chapters = config["chapters"]
    toc = make_toc(chapters)
    
    part_descriptions = {
        "I": "Diagnóstico dos custos de polling na BEAM, introdução ao Paradigma Orientado a Notificações e mapa arquitetural da PON-BEAM.",
        "II": "Cada subsistema da BEAM redesenhado como entidade PON: Premises, Instigações, Conditions, Watchers, marcação causal e compilação automática.",
        "III": "Infraestrutura do fork, harness de benchmarking e análise de tradeoffs com roadmap priorizado.",
        "IV": "Casos de estudo, posicionamento frente à literatura e síntese da proposta.",
    }
    
    chapters_by_part = {}
    for ch in chapters:
        chapters_by_part.setdefault(ch["part"], []).append(ch)
    
    parts_html = ""
    for part_num in ["I", "II", "III", "IV"]:
        chs = chapters_by_part.get(part_num, [])
        parts_html += f'''
        <section class="index-part">
            <h2>Parte {part_num}</h2>
            <p class="part-desc">{part_descriptions[part_num]}</p>
            <ol>
        '''
        for ch in chs:
            parts_html += f'<li><a href="{ch["id"]}.html">{ch["title"]}</a></li>\n'
        parts_html += '</ol></section>\n'
    
    return f'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PON-BEAM — Uma Máquina Virtual Orientada a Notificações</title>
    <link rel="stylesheet" href="theme/style.css">
</head>
<body>
    <div class="layout">
        {toc}
        <main class="content">
            <header class="book-header">
                <h1>PON-BEAM</h1>
                <p class="subtitle">Uma Máquina Virtual Orientada a Notificações</p>
                <p class="author">{config["author"]}</p>
                <p class="version">v{config["version"]}</p>
            </header>
            
            <section class="book-abstract">
                <h2>Sobre este livro</h2>
                <p>
                    A <strong>PON-BEAM</strong> é uma re-arquitetura da máquina virtual BEAM (Bogdan/Björn's Erlang Abstract Machine)
                    usando o <strong>Paradigma Orientado a Notificações (PON)</strong> de Jean Marcelo Simão.
                    Cada subsistema interno da VM — scheduler, selective receive, timer wheel, ETS, garbage collector —
                    é redesenhado como uma entidade PON reativa: sem polling, sem scanning linear, apenas notificações pontuais.
                </p>
                <p>
                    Este livro documenta a arquitetura, o plano de engenharia e o progresso da implementação,
                    combinando fundamentos teóricos, código C do ERTS, diagramas estruturais e benchmarks comparativos.
                </p>
            </section>
            
            <section class="book-search">
                <h2>Busca</h2>
                <input type="text" id="search-input" placeholder="Buscar no livro..." />
                <div id="search-results"></div>
            </section>
            
            <section class="book-toc">
                <h2>Sumário</h2>
                {parts_html}
            </section>
            
            <footer class="book-footer">
                <p>
                    Repositório: <a href="{config["repo"]}">{config["repo"]}</a>
                </p>
                <p>
                    Licença: Apache 2.0
                </p>
            </footer>
        </main>
    </div>
    <script src="theme/search.js"></script>
</body>
</html>'''


def build():
    config = load_config()
    chapters = config["chapters"]
    
    # Ensure output dirs exist
    (OUTPUT / "theme").mkdir(parents=True, exist_ok=True)
    (OUTPUT / "chapters").mkdir(exist_ok=True)
    
    # Copy theme files
    import shutil
    for f in ["style.css", "pygments.css", "search.js", "author.jpg", "capa.svg"]:
        src = THEME / f
        if src.exists():
            shutil.copy(src, OUTPUT / "theme" / f)
    
    # Generate pygments CSS if needed
    if not (OUTPUT / "theme" / "pygments.css").exists():
        from pygments.styles import get_style_by_name
        css = HtmlFormatter(style='monokai').get_style_defs('.code-block')
        with open(OUTPUT / "theme" / "pygments.css", 'w') as f:
            f.write(css)
    
    chapter_data = []
    chapter_bodies = []
    
    for ch in chapters:
        src_file = CHAPTERS / f"{ch['id']}.md"
        if not src_file.exists():
            print(f"AVISO: {src_file} não encontrado, pulando.")
            continue
        
        with open(src_file) as f:
            raw = f.read()
        
        meta, body = extract_frontmatter(raw)
        
        # Process code blocks and diagrams
        body_html = process_code_blocks(body)
        
        # Convert markdown to HTML
        body_html = markdown(body_html, extensions=['fenced_code', 'tables', 'sane_lists'])
        
        # Fix .md links to .html in the rendered HTML body
        body_html = re.sub(r'href="([^"]+)\.md"', r'href="\1.html"', body_html)
        # Remove links to non-existent template pages (FL, PL, KG)
        body_html = re.sub(r'<li><a href="(?:FL|PL|KG)-\d+\.html">.*?</a></li>\s*', '', body_html)
        
        chapter_data.append((ch, body_html))
        chapter_bodies.append(body)
    
    # Render index
    index_html = render_index(config)
    with open(OUTPUT / "index.html", 'w') as f:
        f.write(index_html)
    print("✓ index.html")
    
    # Render chapters
    for ch, body_html in chapter_data:
        html = render_chapter(ch, body_html, config)
        out_file = OUTPUT / f"{ch['id']}.html"
        with open(out_file, 'w') as f:
            f.write(html)
        print(f"✓ {ch['id']}.html")
    
    # Generate search index
    index = make_search_index(chapters, chapter_bodies)
    with open(OUTPUT / "search-index.json", 'w') as f:
        json.dump(index, f, ensure_ascii=False)
    print("✓ search-index.json")
    
    total_chars = sum(len(b) for b in chapter_bodies)
    print(f"\nLivro gerado: {len(chapter_data)} capítulos, ~{total_chars} caracteres")
    print(f"Saída: {OUTPUT}")


if __name__ == "__main__":
    build()
