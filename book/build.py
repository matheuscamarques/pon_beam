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

TWC = '<script>tailwind.config={theme:{extend:{colors:{\'iron-bg\':\'#0d0a0a\',\'iron-surface\':\'#1a0f0f\',\'iron-hover\':\'#2d1515\',\'iron-gold\':\'#FFD700\',\'iron-gold-dim\':\'#8B6914\',\'iron-text\':\'#b8a88a\'}}}}</script>'
TWD = '<script src="https://cdn.tailwindcss.com"></script>'
TW = TWC + '\n' + TWD

PARTS = {"I":"Fundamentals","II":"PON Subsystems","III":"Engineering and Validation","IV":"Synthesis"}


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

    def img_rep(m):
        alt = m.group(1).strip()
        src = m.group(2).strip()
        clean_src = re.sub(r'^.*?docs/assets/charts/', 'assets/charts/', src)
        return f'<figure class="my-6 text-center bg-[#1a0f0f] border border-[#8B6914] p-4 rounded"><img src="{clean_src}" alt="{alt}" class="mx-auto max-w-full h-auto rounded shadow-lg mb-2"><figcaption class="text-center text-sm text-[#b8a88a] italic">{alt}</figcaption></figure>'
    body = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', img_rep, body)
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


def make_shared_js(chapter_ids=None):
    ids = json.dumps(chapter_ids or [])
    head = '''<script>
var BOOK_IDS = "__BOOK_IDS__";
'''.replace('"__BOOK_IDS__"', ids)
    return head + '''function closeSidebar() {
    var b=document.body,s=document.getElementById("sidebar"),f=document.getElementById("floatBtn"),o=document.getElementById("overlay");
    b.classList.add("sidebar-closed"); b.classList.remove("sidebar-open");
    s.style.transform="translateX(-100%)";
    if(o)o.classList.add("hidden"); if(f)f.style.display="flex";
    localStorage.setItem("sidebar","closed");
}
function openSidebar() {
    var b=document.body,s=document.getElementById("sidebar"),f=document.getElementById("floatBtn"),o=document.getElementById("overlay");
    b.classList.remove("sidebar-closed"); b.classList.add("sidebar-open");
    s.style.transform="translateX(0%)";
    if(window.innerWidth<768&&o)o.classList.remove("hidden");
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
function syncSidebar(){
    var b=document.body,w=window.innerWidth,s=document.getElementById("sidebar"),f=document.getElementById("floatBtn");
    if(w<768){
        b.classList.remove("sidebar-open");
        if(s)s.style.transform="translateX(-100%)";
        if(f)f.style.display="flex";
    }else{
        if(localStorage.getItem("sidebar")!=="closed"){b.classList.add("sidebar-open");b.classList.remove("sidebar-closed");if(s)s.style.transform="translateX(0%)";if(f)f.style.display="none";}
        else{b.classList.remove("sidebar-open");b.classList.add("sidebar-closed");if(s)s.style.transform="translateX(-100%)";if(f)f.style.display="flex";}
    }
}
window.addEventListener("resize",syncSidebar);
(function(){
    if(localStorage.getItem("sidebar")==="closed"){
        var s=document.getElementById("sidebar"),f=document.getElementById("floatBtn");
        document.body.classList.add("sidebar-closed");
        if(s)s.style.transform="translateX(-100%)";
        if(f)f.style.display="flex";
    }else{
        document.body.classList.add("sidebar-open");
    }
    syncSidebar();
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

function exportPDF() {
    if (typeof html2pdf !== 'undefined') {
        var element = document.getElementById("main");
        var opt = {
            margin:       [0.4, 0.4, 0.4, 0.4],
            filename:     (document.title || 'PON-BEAM-Livro').replace(/[^a-z0-9]/gi, '_').toLowerCase() + '.pdf',
            image:        { type: 'jpeg', quality: 0.98 },
            html2canvas:  { scale: 2, useCORS: true, backgroundColor: '#0d0a0a' },
            jsPDF:        { unit: 'in', format: 'letter', orientation: 'portrait' }
        };
        html2pdf().set(opt).from(element).save();
    } else {
        window.print();
    }
}

function showPdfStatus(msg) {
    var el = document.getElementById("pdfStatus");
    if (!el) {
        el = document.createElement("div");
        el.id = "pdfStatus";
        el.style.cssText = "position:fixed;inset:0;z-index:9999;display:flex;align-items:center;justify-content:center;background:rgba(13,10,10,0.94)";
        el.innerHTML = '<div style="text-align:center;color:#FFD700;font-family:ui-monospace,SFMono-Regular,monospace;font-size:13px;padding:26px 32px;background:#1a0f0f;border:1px solid #8B6914;border-radius:10px;max-width:80vw;box-shadow:0 0 40px rgba(255,215,0,0.15)"><div style="font-size:15px;font-weight:bold">PON-BEAM</div><div style="margin-top:10px;color:#b8a88a" id="pdfMsg">Preparing PDF...</div></div>';
        document.body.appendChild(el);
    }
    var m = document.getElementById("pdfMsg");
    if (m) m.textContent = msg;
}
function hidePdfStatus() {
    var el = document.getElementById("pdfStatus");
    if (el && el.parentNode) el.parentNode.removeChild(el);
}

function exportFullBookPDF() {
    if (typeof jspdf === 'undefined' || typeof html2canvas === 'undefined') {
        exportPDF();
        return;
    }
    var container = document.getElementById("fullbook");
    if (!container) {
        container = document.createElement("div");
        container.id = "fullbook";
        container.setAttribute("aria-hidden", "true");
        container.style.cssText = "position:absolute;left:-10000px;top:0;width:820px;background:#0d0a0a";
        document.body.appendChild(container);
    }
    container.innerHTML = "";
    showPdfStatus("Loading book chapters...");
    var pending = BOOK_IDS.length;
    if (pending === 0) { hidePdfStatus(); return; }
    BOOK_IDS.forEach(function(id) {
        fetch(id + ".html").then(function(r) {
            if (!r.ok) throw new Error("HTTP " + r.status);
            return r.text();
        }).then(function(html) {
            var doc = new DOMParser().parseFromString(html, "text/html");
            var article = doc.querySelector("article");
            if (article) {
                var holder = document.createElement("div");
                holder.innerHTML = article.innerHTML;
                container.appendChild(holder);
            }
        }).catch(function() {}).finally(function() {
            pending--;
            if (pending === 0) setTimeout(function() { buildFullBookPdf(container); }, 400);
        });
    });
}

function buildFullBookPdf(container) {
    var divs = Array.prototype.slice.call(container.children);
    if (divs.length === 0 || divs.length !== BOOK_IDS.length) {
        hidePdfStatus();
        alert("Incomplete book content - could not load all chapters.");
        return;
    }
    var doc = new jspdf.jsPDF({ unit: "in", format: "letter", orientation: "portrait" });
    var pw = doc.internal.pageSize.getWidth();
    var ph = doc.internal.pageSize.getHeight();
    var margin = 0.4;
    var usableW = pw - 2 * margin;
    var usableH = ph - 2 * margin;
    var pos = 0;
    var first = true;
    function next() {
        if (pos >= divs.length) {
            doc.setProperties({ title: "PON-BEAM - A Notification-Oriented Virtual Machine" });
            doc.save("pon_beam_livro.pdf");
            hidePdfStatus();
            return;
        }
        var div = divs[pos];
        pos++;
        showPdfStatus("Rendering chapter " + pos + " / " + divs.length + " ...");
        html2canvas(div, { scale: 1.3, useCORS: true, backgroundColor: "#0d0a0a", logging: false, windowWidth: 820 })
            .then(function(canvas) {
                var img = canvas.toDataURL("image/jpeg", 0.92);
                var totalH = canvas.height * (usableW / canvas.width);
                var slices = Math.ceil(totalH / usableH);
                for (var i = 0; i < slices; i++) {
                    if (!first) doc.addPage();
                    first = false;
                    doc.addImage(img, "JPEG", margin, margin - i * usableH, usableW, totalH);
                }
                next();
            })
            .catch(function(e) {
                doc.setProperties({ title: "PON-BEAM" });
                doc.save("pon_beam_livro.pdf");
                hidePdfStatus();
                alert("Failed to generate full PDF: " + e.message);
            });
    }
    next();
}
</script>'''


def render_page(ch, body_html, config):
    chapters = config["chapters"]
    sidebar = make_sidebar(chapters, ch["id"])
    hide_hdr = ch["id"] in ("capa","folha-de-rosto","contra-capa")
    
    pdf_btn = '<button onclick="exportFullBookPDF()" class="no-print flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-[#FFD700] bg-[#1a0f0f] border border-[#8B6914] hover:bg-[#2d1515] hover:border-[#FFD700] transition cursor-pointer rounded shrink-0"><svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>Export Book PDF</button>'
    
    if not hide_hdr:
        ch_hdr = f'<div class="flex items-center justify-between mb-6 pb-4 border-b border-[#8B6914]"><h1 class="text-2xl max-md:text-xl font-bold m-0 text-[#FFD700]">{ch["title"]}</h1>{pdf_btn}</div>'
    else:
        ch_hdr = f'<div class="flex justify-end mb-4 no-print">{pdf_btn}</div>'

    prev_ch = next_ch = None
    for i,c in enumerate(chapters):
        if c["id"]==ch["id"]:
            if i>0: prev_ch=chapters[i-1]
            if i<len(chapters)-1: next_ch=chapters[i+1]
            break
    prev_s = f'<a href="{prev_ch["id"]}.html" class="px-3 md:px-4 py-2 border border-[#8B6914] text-sm text-[#b8a88a] hover:text-[#e6edf3] hover:bg-[#2d1515] no-underline max-md:text-xs"><span class="max-md:hidden">\u2190 {prev_ch["title"]}</span><span class="md:hidden">\u2190 Previous</span></a>' if prev_ch else '<span></span>'
    next_s = f'<a href="{next_ch["id"]}.html" class="px-3 md:px-4 py-2 border border-[#8B6914] text-sm text-[#b8a88a] hover:text-[#e6edf3] hover:bg-[#2d1515] no-underline max-md:text-xs"><span class="max-md:hidden">{next_ch["title"]} \u2192</span><span class="md:hidden">Next \u2192</span></a>' if next_ch else '<span></span>'

    capa_style = ''
    if ch["id"]=="capa": capa_style=' style="text-align:center;min-height:100vh;display:flex;flex-direction:column;justify-content:center"'
    elif ch["id"]=="folha-de-rosto": capa_style=' style="text-align:center"'
    elif ch["id"]=="contra-capa": capa_style=' style="text-align:center"'

    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{ch["title"]} — PON-BEAM</title>
{TW}
<link rel="stylesheet" href="theme/style.css">
<link rel="stylesheet" href="theme/pygments.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
</head>
<body class="bg-[#0d0a0a] text-[#e6edf3]">
{sidebar}
<div id="overlay" class="fixed inset-0 bg-black/50 z-40 hidden" onclick="closeSidebar()"></div>
 <main id="main" class="p-8 max-md:p-4 max-w-4xl transition-all duration-200" style="min-height:100vh">
{ch_hdr}
<article{capa_style}>
{body_html}
</article>
<footer class="flex justify-between mt-8 md:mt-12 pt-4 md:pt-6 border-t border-[#8B6914]">
{prev_s}
{next_s}
</footer>
</main>
{make_shared_js([c["id"] for c in chapters])}
</body>
</html>'''


def render_index(config):
    chapters = config["chapters"]
    sidebar = make_sidebar(chapters)

    chs = {}
    for c in chapters: chs.setdefault(c["part"],[]).append(c)

    parts_html = ''
    for pn,pname in PARTS.items():
        parts_html += f'<section class="mb-8"><h2 class="text-xl font-bold text-[#FFD700] mb-2">Part {pn}: {pname}</h2><ol class="list-none p-0">'
        for ch in chs.get(pn,[]):
            parts_html += f'<li class="my-1"><a href="{ch["id"]}.html" class="text-[#FFD700] no-underline hover:underline">{ch["title"]}</a></li>'
        parts_html += '</ol></section>'

    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PON-BEAM — A Notification-Oriented Virtual Machine</title>
{TW}
<link rel="stylesheet" href="theme/style.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
</head>
<body class="bg-[#0d0a0a] text-[#e6edf3]">
{sidebar}
<div id="overlay" class="fixed inset-0 bg-black/50 z-40 hidden" onclick="closeSidebar()"></div>
 <main id="main" class="p-8 max-md:p-4 max-w-4xl transition-all duration-200">
<header class="text-center py-8 md:py-12 border-b border-[#8B6914] mb-6 md:mb-8 relative">
<div class="flex justify-end mb-4 no-print">
  <button onclick="exportFullBookPDF()" class="no-print flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-[#FFD700] bg-[#1a0f0f] border border-[#8B6914] hover:bg-[#2d1515] hover:border-[#FFD700] transition cursor-pointer rounded">
    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path></svg>
    Export Book PDF
  </button>
</div>
<h1 class="text-3xl md:text-4xl font-extrabold text-[#FFD700] mb-2">PON-BEAM</h1>
<p class="text-lg md:text-xl text-[#b8a88a] font-light mb-1">A Notification-Oriented Virtual Machine</p>
<p class="text-sm text-[#b8a88a]">{config["author"]}</p>
</header>
<section class="mb-8 p-4 md:p-6 bg-[#1a0f0f] border border-[#8B6914]">
<h2 class="text-lg font-bold mb-2">About this book</h2>
<p class="text-[#b8a88a] leading-relaxed"><strong class="text-[#e6edf3]">PON-BEAM</strong> is a re-architecture of the BEAM virtual machine using Jean Marcelo Simão's <strong class="text-[#e6edf3]">Notification-Oriented Paradigm (NOP)</strong>.</p>
</section>
{parts_html}
<footer class="text-center text-sm text-[#b8a88a] mt-8 pt-4 border-t border-[#8B6914]">
<p>Repository: <a href="{config["repo"]}" class="text-[#FFD700]">{config["repo"]}</a></p>
</footer>
</main>
<script src="theme/search.js"></script>
{make_shared_js([c["id"] for c in config["chapters"]])}
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

    # Copiar gráficos mestres de docs/assets/charts/ para a saída do livro
    charts_src = ROOT.parent / "docs" / "assets" / "charts"
    for dst_dir in [OUTPUT / "assets" / "charts", OUTPUT / "docs" / "assets" / "charts"]:
        dst_dir.mkdir(parents=True, exist_ok=True)
        if charts_src.exists():
            for img in charts_src.glob("*.png"):
                shutil.copy(img, dst_dir / img.name)

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
