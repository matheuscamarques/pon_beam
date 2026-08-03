#!/usr/bin/env python3
"""
PON-BEAM Book Builder — Gera site HTML com Tailwind CSS via CDN.

Uso: python3 build.py
"""

import os, re, json, subprocess, hashlib, shutil
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

TAILWIND_CDN = '<script src="https://cdn.tailwindcss.com"></script>'

PARTS = {
    "I": "Fundamentos",
    "II": "Subsistemas PON",
    "III": "Engenharia e Valida\u00e7\u00e3o",
    "IV": "S\u00edntese",
}


def load_config():
    with open(BOOK_JSON) as f:
        return json.load(f)


def render_diagram(dot_code, diagram_id):
    try:
        r = subprocess.run(
            ["dot", "-Tsvg"],
            input=dot_code, capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0:
            svg = re.sub(r'<\?xml.*?\?>|<!DOCTYPE.*?>', '', r.stdout).strip()
            return f'<div class="my-6 text-center bg-[#161b22] border border-[#30363d] p-4 overflow-x-auto">{svg}</div>'
        return f'<pre class="text-red-500 text-sm">{r.stderr}</pre>'
    except FileNotFoundError:
        return '<pre class="text-red-500">Graphviz (dot) n\u00e3o encontrado. Instale: apt install graphviz</pre>'


def extract_frontmatter(text):
    m = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
    if m:
        meta = {}
        for line in m.group(1).strip().split('\n'):
            if ':' in line:
                k, v = line.split(':', 1)
                meta[k.strip()] = v.strip().strip('"\'')
        return meta, text[m.end():]
    return {}, text


def process_body(body):
    def replace_block(m):
        lang = (m.group(1) or '').strip()
        title = (m.group(2) or '').strip()
        code = m.group(3)
        if lang == 'dot':
            did = hashlib.md5(code.encode()).hexdigest()[:8]
            out = render_diagram(code, did)
            if title:
                out += f'<p class="text-center text-sm text-[#8b949e] italic mt-1">{title}</p>'
            return out
        lexer = {'c': CLexer, 'erlang': ErlangLexer, 'elixir': ErlangLexer,
                 'console': BashLexer, 'bash': BashLexer, 'json': JsonLexer}.get(lang)
        if lexer:
            try:
                h = highlight(code, lexer(), HtmlFormatter(style='monokai'))
                return f'<div class="my-4 rounded-none border border-[#30363d] overflow-hidden"><pre class="p-4 bg-[#1e1e1e] overflow-x-auto text-sm leading-relaxed">{h}</pre></div>'
            except Exception:
                pass
        cap = f'<p class="text-xs text-[#8b949e] mb-1 font-mono">{title}</p>' if title else ''
        return f'{cap}<pre class="my-4 p-4 bg-[#1e1e1e] border border-[#30363d] overflow-x-auto text-sm"><code>{code}</code></pre>'

    body = re.sub(r'```(\w*)([^\n]*)\n(.*?)```', replace_block, body, flags=re.DOTALL)
    return body


def make_sidebar(chapters, current_id=None):
    lines = []
    lines.append('<aside id="sidebar" class="fixed top-0 left-0 w-72 h-screen bg-[#161b22] border-r border-[#30363d] overflow-y-auto z-50 transition-transform duration-200">')
    lines.append('<div class="p-4 border-b border-[#30363d]">')
    lines.append('<a href="index.html" class="text-[#58a6ff] font-bold text-lg no-underline hover:underline">PON-BEAM</a>')
    lines.append('</div>')

    for ch in chapters:
        if ch["part"] == "frontmatter":
            active = 'text-[#58a6ff]' if ch["id"] == current_id else 'text-[#8b949e]'
            lines.append(f'<a href="{ch["id"]}.html" class="block px-4 py-1.5 text-sm {active} hover:text-[#e6edf3] no-underline">{ch["title"]}</a>')

    for pn, pname in PARTS.items():
        lines.append(f'<div class="px-4 pt-3 pb-1 text-xs uppercase tracking-wider text-[#8b949e] font-semibold">Parte {pn}: {pname}</div>')
        for ch in chapters:
            if ch["part"] == pn:
                active = 'text-[#58a6ff] border-l-2 border-[#58a6ff] bg-[rgba(88,166,255,0.08)]' if ch["id"] == current_id else 'text-[#8b949e] hover:text-[#e6edf3]'
                lines.append(f'<a href="{ch["id"]}.html" class="block px-4 py-1.5 pl-8 text-sm no-underline {active}">{ch["title"]}</a>')

    for ch in chapters:
        if ch["part"] == "backmatter":
            active = 'text-[#58a6ff]' if ch["id"] == current_id else 'text-[#8b949e]'
            lines.append(f'<a href="{ch["id"]}.html" class="block px-4 py-1.5 text-sm {active} hover:text-[#e6edf3] no-underline">{ch["title"]}</a>')

    lines.append('</aside>')
    return '\n'.join(lines)


def render_page(ch, body_html, config):
    chapters = config["chapters"]
    title = ch["title"]
    sidebar = make_sidebar(chapters, ch["id"])
    hide_ch_header = ch["id"] in ("capa", "folha-de-rosto", "contra-capa")
    ch_header = f'<h1 class="text-2xl font-bold mb-6 pb-4 border-b border-[#30363d]">{title}</h1>' if not hide_ch_header else ''

    prev_ch = None
    next_ch = None
    for i, c in enumerate(chapters):
        if c["id"] == ch["id"]:
            if i > 0: prev_ch = chapters[i - 1]
            if i < len(chapters) - 1: next_ch = chapters[i + 1]
            break

    prev_html = f'<a href="{prev_ch["id"]}.html" class="px-4 py-2 border border-[#30363d] text-sm text-[#8b949e] hover:text-[#e6edf3] hover:bg-[#21262d] no-underline">\u2190 {prev_ch["title"]}</a>' if prev_ch else '<span></span>'
    next_html = f'<a href="{next_ch["id"]}.html" class="px-4 py-2 border border-[#30363d] text-sm text-[#8b949e] hover:text-[#e6edf3] hover:bg-[#21262d] no-underline">{next_ch["title"]} \u2192</a>' if next_ch else '<span></span>'

    capa_style = ''
    if ch["id"] == "capa":
        capa_style = ' style="text-align:center;min-height:100vh;display:flex;flex-direction:column;justify-content:center"'
    elif ch["id"] == "folha-de-rosto":
        capa_style = ' style="text-align:center"'
    elif ch["id"] == "contra-capa":
        capa_style = ' style="text-align:center"'

    nav_link = 'index.html' if ch["id"] == "capa" else f'{ch["id"]}.html'

    return f'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title} — PON-BEAM</title>
    {TAILWIND_CDN}
    <link rel="stylesheet" href="theme/style.css">
    <link rel="stylesheet" href="theme/pygments.css">
</head>
<body class="bg-[#0d1117] text-[#e6edf3]">

{sidebar}

<button id="menuBtn" class="fixed top-3 left-3 z-[60] px-2.5 py-1.5 text-lg bg-[#21262d] border border-[#30363d] text-[#8b949e] cursor-pointer leading-none hover:text-[#e6edf3] hover:bg-[#30363d] transition-colors" onclick="toggleSidebar()">&#9776;</button>

<div id="overlay" class="fixed inset-0 bg-black/50 z-40 hidden" onclick="toggleSidebar()"></div>

<main id="main" class="ml-72 p-8 max-w-4xl transition-all duration-200" style="min-height:100vh">

{ch_header}

<article{capa_style}>
{body_html}
</article>

<footer class="flex justify-between mt-12 pt-6 border-t border-[#30363d]">
    {prev_html}
    {next_html}
</footer>

</main>

<script>
function toggleSidebar() {{
    var s = document.getElementById('sidebar');
    var m = document.getElementById('main');
    var o = document.getElementById('overlay');
    var b = document.getElementById('menuBtn');
    var open = s.style.transform !== 'translateX(0%)' && s.style.transform !== '';
    if (!open) {{
        s.style.transform = 'translateX(0%)';
        m.style.marginLeft = '18rem';
        o.classList.add('hidden');
        b.innerHTML = '&#9776;';
        localStorage.setItem('sidebar', 'open');
    }} else {{
        s.style.transform = 'translateX(-100%)';
        m.style.marginLeft = '0';
        if (window.innerWidth < 768) o.classList.remove('hidden');
        b.innerHTML = '&#10005;';
        localStorage.setItem('sidebar', 'closed');
    }}
}}
(function() {{
    var pref = localStorage.getItem('sidebar');
    var s = document.getElementById('sidebar');
    var m = document.getElementById('main');
    var b = document.getElementById('menuBtn');
    if (pref === 'closed') {{
        s.style.transform = 'translateX(-100%)';
        m.style.marginLeft = '0';
        b.innerHTML = '&#10005;';
    }}
}})();
</script>

</body>
</html>'''


def render_index(config):
    chapters = config["chapters"]
    sidebar = make_sidebar(chapters)
    chs_by_part = {}
    for ch in chapters:
        chs_by_part.setdefault(ch["part"], []).append(ch)

    parts_html = ''
    for pn, pname in PARTS.items():
        parts_html += f'<section class="mb-8"><h2 class="text-xl font-bold text-[#58a6ff] mb-2">Parte {pn}: {pname}</h2><ol class="list-none p-0">'
        for ch in chs_by_part.get(pn, []):
            parts_html += f'<li class="my-1"><a href="{ch["id"]}.html" class="text-[#58a6ff] no-underline hover:underline">{ch["title"]}</a></li>'
        parts_html += '</ol></section>'

    return f'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PON-BEAM — Uma M\u00e1quina Virtual Orientada a Notifica\u00e7\u00f5es</title>
    {TAILWIND_CDN}
    <link rel="stylesheet" href="theme/style.css">
</head>
<body class="bg-[#0d1117] text-[#e6edf3]">
{sidebar}
<button id="menuBtn" class="fixed top-3 left-3 z-[60] px-2.5 py-1.5 text-lg bg-[#21262d] border border-[#30363d] text-[#8b949e] cursor-pointer leading-none hover:text-[#e6edf3] hover:bg-[#30363d] transition-colors" onclick="toggleSidebar()">&#9776;</button>
<div id="overlay" class="fixed inset-0 bg-black/50 z-40 hidden" onclick="toggleSidebar()"></div>
<main id="main" class="ml-72 p-8 max-w-4xl transition-all duration-200">
<header class="text-center py-12 border-b border-[#30363d] mb-8">
    <h1 class="text-4xl font-extrabold text-[#58a6ff] mb-2">PON-BEAM</h1>
    <p class="text-xl text-[#8b949e] font-light mb-1">Uma M\u00e1quina Virtual Orientada a Notifica\u00e7\u00f5es</p>
    <p class="text-sm text-[#8b949e]">{config["author"]}</p>
</header>
<section class="mb-8 p-6 bg-[#161b22] border border-[#30363d]">
    <h2 class="text-lg font-bold mb-2">Sobre este livro</h2>
    <p class="text-[#8b949e] leading-relaxed">A <strong class="text-[#e6edf3]">PON-BEAM</strong> \u00e9 uma re-arquitetura da m\u00e1quina virtual BEAM usando o <strong class="text-[#e6edf3]">Paradigma Orientado a Notifica\u00e7\u00f5es (PON)</strong> de Jean Marcelo Sim\u00e3o. Cada subsistema interno da VM — scheduler, selective receive, timer wheel, ETS, garbage collector — \u00e9 redesenhado como uma entidade PON reativa.</p>
</section>
{parts_html}
<footer class="text-center text-sm text-[#8b949e] mt-8 pt-4 border-t border-[#30363d]">
    <p>Reposit\u00f3rio: <a href="{config["repo"]}" class="text-[#58a6ff]">{config["repo"]}</a></p>
</footer>
</main>
<script src="theme/search.js"></script>
<script>
function toggleSidebar() {{
    var s = document.getElementById('sidebar');
    var m = document.getElementById('main');
    var o = document.getElementById('overlay');
    var b = document.getElementById('menuBtn');
    var open = s.style.transform !== 'translateX(0%)' && s.style.transform !== '';
    if (!open) {{
        s.style.transform = 'translateX(0%)'; m.style.marginLeft = '18rem';
        o.classList.add('hidden'); b.innerHTML = '&#9776;';
        localStorage.setItem('sidebar', 'open');
    }} else {{
        s.style.transform = 'translateX(-100%)'; m.style.marginLeft = '0';
        if (window.innerWidth < 768) o.classList.remove('hidden');
        b.innerHTML = '&#10005;'; localStorage.setItem('sidebar', 'closed');
    }}
}}
(function() {{
    if (localStorage.getItem('sidebar') === 'closed') {{
        document.getElementById('sidebar').style.transform = 'translateX(-100%)';
        document.getElementById('main').style.marginLeft = '0';
        document.getElementById('menuBtn').innerHTML = '&#10005;';
    }}
}})();
</script>
</body>
</html>'''


def build():
    config = load_config()
    chapters = config["chapters"]
    (OUTPUT / "theme").mkdir(parents=True, exist_ok=True)

    # copy theme assets
    for f in ["style.css", "pygments.css", "search.js", "author.jpg", "capa.svg"]:
        src = THEME / f
        if src.exists():
            shutil.copy(src, OUTPUT / "theme" / f)

    if not (OUTPUT / "theme" / "pygments.css").exists():
        css = HtmlFormatter(style='monokai').get_style_defs('.code-block')
        with open(OUTPUT / "theme" / "pygments.css", 'w') as f:
            f.write(css)

    chapter_data = []
    raw_bodies = []

    for ch in chapters:
        src_file = CHAPTERS / f"{ch['id']}.md"
        if not src_file.exists():
            print(f"AVISO: {src_file} não encontrado, pulando.")
            continue
        with open(src_file) as f:
            raw = f.read()
        _, body = extract_frontmatter(raw)
        body_html = process_body(body)
        body_html = markdown(body_html, extensions=['fenced_code', 'tables', 'sane_lists'])
        body_html = re.sub(r'href="([^"]+)\.md"', r'href="\1.html"', body_html)
        body_html = re.sub(r'<li><a href="(?:FL|PL|KG)-\d+\.html">.*?</a></li>\s*', '', body_html)
        # Fix image paths in capa/author
        body_html = body_html.replace('src="theme/', 'src="theme/')
        chapter_data.append((ch, body_html))
        raw_bodies.append(body)

    # index
    with open(OUTPUT / "index.html", 'w') as f:
        f.write(render_index(config))
    print("✓ index.html")

    # chapters
    for ch, body_html in chapter_data:
        html = render_page(ch, body_html, config)
        with open(OUTPUT / f"{ch['id']}.html", 'w') as f:
            f.write(html)
        print(f"✓ {ch['id']}.html")

    # search index
    idx = []
    for ch, raw in zip(chapters, raw_bodies):
        text = re.sub(r'[#*`>\[\]]', '', raw)
        text = re.sub(r'\n+', ' ', text)
        idx.append({"id": ch["id"], "title": ch["title"], "part": ch["part"], "text": text[:500]})
    with open(OUTPUT / "search-index.json", 'w') as f:
        json.dump(idx, f, ensure_ascii=False)
    print("✓ search-index.json")

    total = sum(len(b) for b in raw_bodies)
    print(f"\nLivro gerado: {len(chapter_data)} capítulos, ~{total} caracteres")
    print(f"Saída: {OUTPUT}")


if __name__ == "__main__":
    build()
