%% icse-ja.cls
%% LaTeX class for ICSE paper submissions (Japanese)
%%
%% This is a hybrid wrapper using ACM acmart class with LuaLaTeX
%% and luatexja for Japanese language support.
%%
%% Usage:
%%   \documentclass{icse-ja}
%%   \documentclass[anonymous,review]{icse-ja}  % for double-blind review
%%   \documentclass[draft]{icse-ja}             % for draft mode
%%
%% Build with: lualatex
%%

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{icse-ja}[2025/01/01 v1.0 ICSE paper class (Japanese)]

%% ========================================
%% Option handling
%% ========================================

% Pass options to acmart
\DeclareOption{anonymous}{\PassOptionsToClass{anonymous}{acmart}}
\DeclareOption{review}{\PassOptionsToClass{review}{acmart}}
\DeclareOption{draft}{\PassOptionsToClass{draft}{acmart}}
\DeclareOption{final}{\PassOptionsToClass{final}{acmart}}
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{acmart}}

\ProcessOptions\relax

%% ========================================
%% Load base class
%% ========================================

\LoadClass[sigconf]{acmart}

%% ========================================
%% Japanese support via LuaLaTeX
%% ========================================

\RequirePackage{luatexja}
\RequirePackage{luatexja-fontspec}

% Japanese fonts - use Haranoaji fonts (included in TeX Live)
% Fallback to IPAex if Haranoaji not available
\IfFontExistsTF{HaranoAjiMincho-Regular}{%
  \setmainjfont[BoldFont=HaranoAjiMincho-Bold]{HaranoAjiMincho-Regular}
  \setsansjfont[BoldFont=HaranoAjiGothic-Bold]{HaranoAjiGothic-Regular}
}{%
  \IfFontExistsTF{IPAexMincho}{%
    \setmainjfont{IPAexMincho}
    \setsansjfont{IPAexGothic}
  }{%
    % Use system default if no fonts found
  }
}

%% ========================================
%% Disable unnecessary ACM features
%% ========================================

% Remove ACM reference format footer
\settopmatter{printacmref=false}

% Remove copyright permission text
\renewcommand\footnotetextcopyrightpermission[1]{}

% Use plain page style (no ACM headers)
\pagestyle{plain}

% Remove CCS concepts requirement
\settopmatter{printccs=false}

%% ========================================
%% Japanese title/author support
%% ========================================

\newcommand{\jtitle}[1]{\gdef\@jtitle{#1}}
\newcommand{\jauthor}[1]{\gdef\@jauthor{#1}}

% Initialize with empty values
\gdef\@jtitle{}
\gdef\@jauthor{}

%% ========================================
%% Load style package
%% ========================================

\RequirePackage{icse-ja}

\endinput
