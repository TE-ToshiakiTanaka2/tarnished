---
paths:
  - "**/*.tex"
  - "**/*.bib"
---

# LaTeX Writing Rules

## Style

- Format with `latexindent` (the PostToolUse hook runs `latexindent -w -s` automatically on write/edit)
- One sentence per line where practical -- keeps diffs reviewable
- Use `%` comments to annotate non-obvious macros or layout tweaks only
- Keep preamble customizations in `libs/` and content in `tex/`; `index.tex` stays a thin root that inputs sections

## Build

- Build with `latexmk` -- the project `.latexmkrc` drives the full toolchain (default: `platex` + `dvipdfmx`, Japanese-ready with `upbibtex`/`upmendex`)
- Compiled output goes to `output/`, intermediates to `.intermediates/` -- never commit either
- Fix all `latexmk` warnings you introduced (undefined references, multiply-defined labels, overfull boxes where feasible)
- CI builds PDFs via `.github/workflows/build-pdf.yml` with directory-based change detection

## References and Citations

- Keep BibTeX entries in `bib/`, one logical topic per `.bib` file
- Use `\cite`/`\ref` with non-breaking space: `Figure~\ref{fig:...}`, `\cite{...}` after punctuation-free text
- Label conventions: `sec:`, `fig:`, `tab:`, `eq:` prefixes
- Never hardcode reference numbers

## Figures and Tables

- Store figures per paper under the paper's directory; reference with relative paths
- Use `booktabs` style tables (`\toprule`/`\midrule`/`\bottomrule`, no vertical rules)
- Always provide `\caption` and `\label` (label after caption)

## Project Conventions

- Sample papers live under `arxiv/` (`sample-en` ICSE-format English, `sample-ja` Japanese); copy a sample as the starting point for a new paper
- Do not edit generated files (`output/`, `.intermediates/`, `indent.log`, `*.bak`)
