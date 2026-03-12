#!/usr/bin/env perl

$do_cd = 1;

$pdf_mode = 3;
$latex = 'platex -synctex=1 -file-line-error -halt-on-error %O %S';
$dvipdf = 'dvipdfmx %O -o %D %S';
$max_repeat = 5;

$bibtex_use=2;
$bibtex = 'upbibtex %O %S';
$biber = 'biber --bblencoding=utf8 -u -U --output_safechars %O %S';

$makeindex = 'upmendex %O -o %D %S -s jpbase';

# 出力フォルダ指定
$out_dir = "output";
# 中間ファイルを別フォルダに隠しておける
$emulate_aux = 1;
$aux_dir = ".intermediates";

# 中間ファイル登録
$clean_ext="$clean_ext run.xml";
