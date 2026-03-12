#!/usr/bin/env perl

# arXiv English template - pdflatex configuration

# PDF mode: 1 = pdflatex
$pdf_mode = 1;
$pdflatex = 'pdflatex -synctex=1 -file-line-error -halt-on-error %O %S';

# BibTeX settings
$bibtex = 'bibtex %O %S';
$bibtex_use = 2;

# Maximum repetitions
$max_repeat = 5;

# Output directory
$out_dir = "output";

# Intermediate files directory
$emulate_aux = 1;
$aux_dir = ".intermediates";

# Add libs directory to search path
ensure_path('TEXINPUTS', './libs//');
ensure_path('BSTINPUTS', './libs//');

# Clean extensions
$clean_ext = "$clean_ext run.xml synctex.gz";
