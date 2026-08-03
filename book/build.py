#!/usr/bin/env python3
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

TWC = '<script>tailwind.config={theme:{extend:{colors:{\'iron-bg\':\'#0d0a0a\',\'iron-surface\':\'#1a0f0f\',\'iron-hover\':\'#2d1515\',\'iron-gold\':\'#FFD700\',\'iron-gold-dim\':\'#8B6914\',\'iron-text\':\'#b8a88a\'}}}}}</script>'
TWD = '<script src="https://cdn.tailwindcss.com"></script>'
TW = TWC + '\n' + TWD

PARTS = {"I":"Fundamentos","II":"Subsistemas PON","III":"Engenharia e Valida\u00e7\u00e3o","IV":"S\u00edntese"}


def load_config():
    with open(BOOK_JSON) as f: return json.load(f)


def render_diagram(dot_code, diagram_id):
    try:
        r = subprocess.run(["dot","-Tsvg"], input=dot_code, capture_output=True, text=True, timeout=10)
        if r.returncode == 0:
            svg = re.sub(r'<\?xml.*?\?>|<!DOCTYPE.*?>', '', r.stdout).strip()
            return f'<div class="my-6 text-center bg-[#1a0f0f] border border-[#8B6914] p-4 overflow-x-auto">{svg}</div>'
        return f'<pre class="text-red-500 text-sm">{r.stderr}</pre>'
    except FileNotFoundError:
        return '<pre class="text-red-500">Graphviz n\u00e3o encontrado. Instale: apt install graphviz</pre>'


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
    def rep(m):
        lang = (m.group(1) or '').strip()
        title = (m.group(2) or '').strip()
        code = m.group(3)
        if lang == 'dot':
            did = hashlib.md5(code.encode()).hexdigest()[:8]
            out = render_diagram(code, did)
            if title: out += f'<p class="text-center text-sm text-[#b8a88a] italic mt-1">{title}</p>'
            return out
        lexer = {'c':CLexer,'erlang':ErlangLexer,'elixir':ErlangLexer,'console':BashLexer,'bash':BashLexer,'json':JsonLexer}.get(lang)
        if lexer:
            try:
                h = highlight(code, lexer(), HtmlFormatter(style='monokai'))
                return f'<div class="my-4 border border-[#8B6914] overflow-hidden"><pre class="p-4 bg-[#1e1e1e] overflow-x-auto text-sm leading-relaxed">{h}</pre></div>'
            except: pass
        cap = f'<p class="text-xs text-[#b8a88a] mb-1 font-mono">{title}</p>' if title else ''
        return f'{cap}<pre class="my-4 p-4 bg-[#1e1e1e] border border-[#8B6914] overflow-x-auto text-sm"><code>{code}</code></pre>'
    body = re.sub(r'```(\w*)([^\n]*)\n(.*?)```', rep, body, flags=re.DOTALL)
    return body


def make_sidebar(chapters, current_id=None):
    lid = lambda i: f'id="{i}"' if i else ''
    active_cls = lambda cid: 'text-[#FFD700] border-l-2 border-[#FFD700] bg-[rgba(255,215,0,0.1)]' if cid == current_id else 'text-[#b8a88a] hover:text-[#e6edf3]'
    fm_cls = lambda cid: 'text-[#FFD700]' if cid == current_id else 'text-[#b8a88a] hover:text-[#e6edf3]'

    html = '<aside id="sidebar" class="fixed top-0 left-0 w-72 h-screen bg-[#1a0f0f] border-r border-[#8B6914] flex flex-col z-50 transition-transform duration-200">\n'

    # header with close button
    html += '<div class="flex items-center justify-between px-4 py-3 border-b border-[#8B6914] shrink-0">\n'
    html += '<a href="index.html" class="text-[#FFD700] font-bold text-lg no-underline hover:underline">PON-BEAM</a>\n'
    html += '<button onclick="closeSidebar()" class="text-[#b8a88a] hover:text-[#e6edf3] text-lg leading-none px-1 cursor-pointer bg-transparent border-0">&#10005;</button>\n'
    html += '</div>\n'

    # search input
    html += '<div class="px-3 py-2 shrink-0">\n'
    html += '<input type="text" placeholder="🔍 Buscar no livro..." oninput="filterChapters(this.value)" class="w-full px-3 py-1.5 text-sm bg-[#0d0a0a] border border-[#8B6914] text-[#e6edf3] placeholder-[#b8a88a] outline-none">\n'
    html += '</div>\n'

    # scrollable body
    html += '<div class="flex-1 overflow-y-auto">\n'

    # frontmatter
    for ch in chapters:
        if ch["part"] == "frontmatter":
            html += f'<a href="{ch["id"]}.html" class="block px-4 py-1 text-sm no-underline {fm_cls(ch["id"])} sidebar-item">{ch["title"]}</a>\n'

    # parts
    FIRST_PART = list(PARTS.keys())[0]
    for pn, pname in PARTS.items():
        chs = [c for c in chapters if c["part"] == pn]
        default_open = 'open' if pn == FIRST_PART else 'closed'
        html += f'<div class="part-header" onclick="togglePart(\'{pn}\')" style="cursor:pointer;user-select:none">\n'
        html += f'<div class="flex items-center px-4 pt-3 pb-1 text-xs uppercase tracking-wider text-[#b8a88a] font-semibold">\n'
        html += f'<span id="btn-{pn}">{"[-]" if default_open == "open" else "[+]"}</span>\n'
        html += f'<span class="ml-1">Parte {pn}: {pname}</span>\n'
        html += '</div></div>\n'
        html += f'<div id="ch-{pn}" class="part-list {"hidden" if default_open == "closed" else ""}">\n'
        for ch in chs:
            html += f'<a href="{ch["id"]}.html" class="block px-4 py-1 pl-8 text-sm no-underline {active_cls(ch["id"])} sidebar-item">{ch["title"]}</a>\n'
        html += '</div>\n'

    # backmatter
    for ch in chapters:
        if ch["part"] == "backmatter":
            html += f'<a href="{ch["id"]}.html" class="block px-4 py-1 text-sm no-underline {fm_cls(ch["id"])} sidebar-item">{ch["title"]}</a>\n'

    html += '</div>\n'  # scrollable
    html += '</aside>\n'

    # floating button
    html += '<button id="floatBtn" onclick="openSidebar()" class="fixed left-0 top-1/2 -translate-y-1/2 z-[60] w-8 h-16 bg-[#1a0f0f] border border-[#8B6914] border-l-0 text-[#b8a88a] text-lg cursor-pointer hidden hover:text-[#e6edf3] items-center justify-center" style="border-radius:0 4px 4px 0;display:none">&#9776;</button>\n'

    return html


def make_shared_js():
    return '''<script>
function closeSidebar() {
    var s=document.getElementById("sidebar"),m=document.getElementById("main"),f=document.getElementById("floatBtn");
    s.style.transform="translateX(-100%)"; if(m)m.style.marginLeft="0";
    if(f)f.style.display="flex"; localStorage.setItem("sidebar","closed");
}
function openSidebar() {
    var s=document.getElementById("sidebar"),m=document.getElementById("main"),f=document.getElementById("floatBtn");
    s.style.transform="translateX(0%)"; if(m)m.style.marginLeft="18rem";
    if(f)f.style.display="none"; localStorage.setItem("sidebar","open");
}
function togglePart(id) {
    var l=document.getElementById("ch-"+id),b=document.getElementById("btn-"+id);
    if(!l||!b)return;
    var h=l.classList.toggle("hidden");
    b.textContent=h?"[+]":"[-]";
    localStorage.setItem("part-"+id,h?"closed":"open");
}
function filterChapters(q) {
    q=q.toLowerCase().trim();
    document.querySelectorAll(".sidebar-item").forEach(function(el){
        el.style.display=!q||el.textContent.toLowerCase().includes(q)?"":"none";
    });
    document.querySelectorAll(".part-list").forEach(function(list){
        var ph=list.previousElementSibling;
        if(!ph)return;
        if(!q){ph.style.display="";return;}
        var has=Array.from(list.querySelectorAll(".sidebar-item")).some(function(el){return el.style.display!="none";});
        ph.style.display=has?"":"none";
    });
}
(function(){
    if(localStorage.getItem("sidebar")==="closed"){
        var s=document.getElementById("sidebar"),m=document.getElementById("main"),f=document.getElementById("floatBtn");
        if(s)s.style.transform="translateX(-100%)";
        if(m)m.style.marginLeft="0";
        if(f)f.style.display="flex";
    }
    ["I","II","III","IV"].forEach(function(p){
        var pref=localStorage.getItem("part-"+p);
        if(pref){
            var l=document.getElementById("ch-"+p),b=document.getElementById("btn-"+p);
            if(l&&b){
                if(pref==="closed"){l.classList.add("hidden");b.textContent="[+]";}
                else{l.classList.remove("hidden");b.textContent="[-]";}
            }
        }
    });
})();
</script>'''


def render_page(ch, body_html, config):
    chapters = config["chapters"]
    sidebar = make_sidebar(chapters, ch["id"])
    hide_hdr = ch["id"] in ("capa","folha-de-rosto","contra-capa")
    ch_hdr = f'<h1 class="text-2xl font-bold mb-6 pb-4 border-b border-[#8B6914]">{ch["title"]}</h1>' if not hide_hdr else ''

    prev_ch = next_ch = None
    for i,c in enumerate(chapters):
        if c["id"]==ch["id"]:
            if i>0: prev_ch=chapters[i-1]
            if i<len(chapters)-1: next_ch=chapters[i+1]
            break
    prev_s = f'<a href="{prev_ch["id"]}.html" class="px-4 py-2 border border-[#8B6914] text-sm text-[#b8a88a] hover:text-[#e6edf3] hover:bg-[#2d1515] no-underline">\u2190 {prev_ch["title"]}</a>' if prev_ch else '<span></span>'
    next_s = f'<a href="{next_ch["id"]}.html" class="px-4 py-2 border border-[#8B6914] text-sm text-[#b8a88a] hover:text-[#e6edf3] hover:bg-[#2d1515] no-underline">{next_ch["title"]} \u2192</a>' if next_ch else '<span></span>'

    capa_style = ''
    if ch["id"]=="capa": capa_style=' style="text-align:center;min-height:100vh;display:flex;flex-direction:column;justify-content:center"'
    elif ch["id"]=="folha-de-rosto": capa_style=' style="text-align:center"'
    elif ch["id"]=="contra-capa": capa_style=' style="text-align:center"'

    return f'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{ch["title"]} — PON-BEAM</title>
{TW}
<link rel="stylesheet" href="theme/style.css">
<link rel="stylesheet" href="theme/pygments.css">
</head>
<body class="bg-[#0d0a0a] text-[#e6edf3]">
{sidebar}
<div id="overlay" class="fixed inset-0 bg-black/50 z-40 hidden" onclick="closeSidebar()"></div>
<main id="main" class="ml-72 p-8 max-w-4xl transition-all duration-200" style="min-height:100vh">
{ch_hdr}
<article{capa_style}>
{body_html}
</article>
<footer class="flex justify-between mt-12 pt-6 border-t border-[#8B6914]">
{prev_s}
{next_s}
</footer>
</main>
{make_shared_js()}
</body>
</html>'''


def render_index(config):
    chapters = config["chapters"]
    sidebar = make_sidebar(chapters)

    chs = {}
    for c in chapters: chs.setdefault(c["part"],[]).append(c)

    parts_html = ''
    for pn,pname in PARTS.items():
        parts_html += f'<section class="mb-8"><h2 class="text-xl font-bold text-[#FFD700] mb-2">Parte {pn}: {pname}</h2><ol class="list-none p-0">'
        for ch in chs.get(pn,[]):
            parts_html += f'<li class="my-1"><a href="{ch["id"]}.html" class="text-[#FFD700] no-underline hover:underline">{ch["title"]}</a></li>'
        parts_html += '</ol></section>'

    return f'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PON-BEAM — Uma M\u00e1quina Virtual Orientada a Notifica\u00e7\u00f5es</title>
{TW}
<link rel="stylesheet" href="theme/style.css">
</head>
<body class="bg-[#0d0a0a] text-[#e6edf3]">
{sidebar}
<div id="overlay" class="fixed inset-0 bg-black/50 z-40 hidden" onclick="closeSidebar()"></div>
<main id="main" class="ml-72 p-8 max-w-4xl transition-all duration-200">
<header class="text-center py-12 border-b border-[#8B6914] mb-8">
<h1 class="text-4xl font-extrabold text-[#FFD700] mb-2">PON-BEAM</h1>
<p class="text-xl text-[#b8a88a] font-light mb-1">Uma M\u00e1quina Virtual Orientada a Notifica\u00e7\u00f5es</p>
<p class="text-sm text-[#b8a88a]">{config["author"]}</p>
</header>
<section class="mb-8 p-6 bg-[#1a0f0f] border border-[#8B6914]">
<h2 class="text-lg font-bold mb-2">Sobre este livro</h2>
<p class="text-[#b8a88a] leading-relaxed">A <strong class="text-[#e6edf3]">PON-BEAM</strong> \u00e9 uma re-arquitetura da m\u00e1quina virtual BEAM usando o <strong class="text-[#e6edf3]">Paradigma Orientado a Notifica\u00e7\u00f5es (PON)</strong> de Jean Marcelo Sim\u00e3o.</p>
</section>
{parts_html}
<footer class="text-center text-sm text-[#b8a88a] mt-8 pt-4 border-t border-[#8B6914]">
<p>Reposit\u00f3rio: <a href="{config["repo"]}" class="text-[#FFD700]">{config["repo"]}</a></p>
</footer>
</main>
<script src="theme/search.js"></script>
{make_shared_js()}
</body>
</html>'''


def build():
    config = load_config()
    chapters = config["chapters"]
    (OUTPUT/"theme").mkdir(parents=True, exist_ok=True)

    for f in ["style.css","pygments.css","search.js","author.jpg","capa.svg"]:
        src = THEME/f
        if src.exists(): shutil.copy(src, OUTPUT/"theme"/f)

    if not (OUTPUT/"theme"/"pygments.css").exists():
        with open(OUTPUT/"theme"/"pygments.css",'w') as f:
            f.write(HtmlFormatter(style='monokai').get_style_defs('.code-block'))

    data = []
    raws = []

    for ch in chapters:
        sf = CHAPTERS/f"{ch['id']}.md"
        if not sf.exists(): continue
        with open(sf) as f: raw = f.read()
        _, body = extract_frontmatter(raw)
        h = process_body(body)
        h = markdown(h, extensions=['fenced_code','tables','sane_lists'])
        h = re.sub(r'href="([^"]+)\.md"', r'href="\1.html"', h)
        h = re.sub(r'<li><a href="(?:FL|PL|KG)-\d+\.html">.*?</a></li>\s*', '', h)
        data.append((ch, h))
        raws.append(body)

    with open(OUTPUT/"index.html",'w') as f: f.write(render_index(config))
    print("✓ index.html")

    for ch,h in data:
        with open(OUTPUT/f"{ch['id']}.html",'w') as f: f.write(render_page(ch,h,config))
        print(f"✓ {ch['id']}.html")

    idx = [{"id":ch["id"],"title":ch["title"],"part":ch["part"],"text":re.sub(r'[#*`>\[\]]','',raw)[:500]} for ch,raw in zip(chapters,raws)]
    with open(OUTPUT/"search-index.json",'w') as f: json.dump(idx,f,ensure_ascii=False)
    print("✓ search-index.json")

    print(f"\nLivro gerado: {len(data)} capitulos, saida: {OUTPUT}")


if __name__ == "__main__":
    build()
