# PON-BEAM — The Book

This directory contains the complete technical book documenting **PON-BEAM**: the re-architecture of the BEAM Virtual Machine using the Notification-Oriented Paradigm (PON / NOP).

## Structure

```
book/
├── src/
│   ├── chapters/        # 21 chapters in Markdown
│   └── (automatically indexed)
├── theme/               # CSS, JS, site assets, search engine
├── output/              # Generated HTML site (build destination)
├── build.py             # Python HTML build engine script
├── book.json            # Configuration metadata and chapter sequence
└── README.md            # This file
```

## How to Build

```bash
make book-build    # Generates HTML site in book/output/
make book-open     # Opens book/output/index.html in browser
make book-clean    # Cleans book/output/ directory
```

## Book Organization

| Part | Chapters | Theme |
| :---: | :---: | :--- |
| **I** | 1–3 | **Foundations**: Polling Diagnosis, Notification Paradigm, Architectural Overview |
| **II** | 4–10 | **PON Subsystems**: PON-Receive, PON-Timer, PON-Spawn, PON-Scheduler, PON-ETS, PON-GC, PON-Compiler |
| **III** | 11–13 | **Engineering & Validation**: Fork Infrastructure, Benchmark Harness, Roadmap & Tradeoffs |
| **IV** | 14–16 | **Synthesis**: Case Studies, Related Works, Master Conclusions & Future Work |

## Format & Rendering Features

- Source text written in GitHub-Flavored Markdown (`src/chapters/*.md`).
- Responsive HTML interface in `output/` with collapsible sidebar, real-time client-side search, embedded diagrams, syntax highlighting, and 1-click PDF export.
