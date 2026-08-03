# PON-BEAM — O Livro

Este diretório contém a documentação completa da **PON-BEAM**, a re-arquitetura
da máquina virtual BEAM usando o Paradigma Orientado a Notificações (PON).

## Estrutura

```
book/
├── src/
│   ├── chapters/        # 16 capítulos em Markdown
│   └── (índice gerado automaticamente)
├── theme/               # CSS, JS, assets do site
├── output/              # Site HTML gerado (não versionar)
├── build.py             # Script de build Python
├── book.json            # Configuração (metadados, ordem dos capítulos)
└── README.md            # Este arquivo
```

## Como construir

```bash
make book-build    # Gera o site HTML em book/output/
make book-open     # Abre no navegador
make book-clean    # Limpa book/output/
```

## Partes do livro

| Parte | Capítulos | Tema |
|-------|-----------|------|
| I     | 1–3       | Fundamentos: polling, PON, visão geral |
| II    | 4–10      | Subsistemas PON: Receive, Timer, Spawn, Scheduler, ETS, GC, Compiler |
| III   | 11–13     | Engenharia: fork, harness, roadmap |
| IV    | 14–16     | Síntese: casos de estudo, trabalhos relacionados, conclusão |

## Formato

- Markdown fonte em `src/chapters/`
- Site HTML interativo em `output/` (navegação lateral, busca, diagramas Graphviz, syntax highlighting)
- ~7.975 linhas de conteúdo, ~458K caracteres
