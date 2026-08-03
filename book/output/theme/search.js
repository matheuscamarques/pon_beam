/**
 * PON-BEAM Book — Search Client
 * Client-side search using pre-built index.
 */

(function() {
    const searchIndex = [];

    function loadSearchIndex() {
        return fetch('/search-index.json')
            .then(r => r.json())
            .then(data => {
                searchIndex.length = 0;
                searchIndex.push(...data);
            })
            .catch(() => {
                // Try relative path
                return fetch('search-index.json')
                    .then(r => r.json())
                    .then(data => {
                        searchIndex.length = 0;
                        searchIndex.push(...data);
                    })
                    .catch(() => {});
            });
    }

    function normalize(text) {
        return text
            .toLowerCase()
            .normalize('NFD')
            .replace(/[\u0300-\u036f]/g, '')
            .replace(/[^a-z0-9\s]/g, ' ')
            .replace(/\s+/g, ' ')
            .trim();
    }

    function search(query) {
        if (!query || query.length < 2) return [];
        const q = normalize(query);
        const terms = q.split(/\s+/).filter(t => t.length > 0);
        
        const results = [];
        for (const entry of searchIndex) {
            const text = normalize(entry.title + ' ' + entry.text);
            const matchCount = terms.filter(t => text.includes(t)).length;
            if (matchCount > 0) {
                // Find snippet
                const idx = text.indexOf(terms[0]);
                const snippet = idx >= 0 
                    ? entry.text.substring(Math.max(0, idx - 40), idx + 160) + '...'
                    : entry.text.substring(0, 200) + '...';
                results.push({
                    id: entry.id,
                    title: entry.title,
                    part: entry.part,
                    snippet: snippet,
                    score: matchCount / terms.length
                });
            }
        }
        
        results.sort((a, b) => b.score - a.score);
        return results.slice(0, 10);
    }

    function renderResults(results, container) {
        if (results.length === 0) {
            container.innerHTML = '<p class="search-no-results">Nenhum resultado encontrado.</p>';
            return;
        }
        
        container.innerHTML = results.map(r => `
            <div class="search-result-item">
                <a href="${r.id}.html">${r.title}</a>
                <div class="snippet">${r.snippet}</div>
            </div>
        `).join('');
    }

    document.addEventListener('DOMContentLoaded', function() {
        loadSearchIndex();
        
        const input = document.getElementById('search-input');
        const results = document.getElementById('search-results');
        
        if (!input || !results) return;
        
        let timeout = null;
        input.addEventListener('input', function() {
            clearTimeout(timeout);
            timeout = setTimeout(() => {
                const q = input.value.trim();
                if (q.length < 2) {
                    results.innerHTML = '';
                    return;
                }
                const r = search(q);
                renderResults(r, results);
            }, 200);
        });
    });
})();
