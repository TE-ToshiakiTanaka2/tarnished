%% icse.cls
%% LaTeX class for ICSE paper submissions (English)
%%
%% This is a wrapper around the ACM acmart class with sigconf format,
%% optimized for ICSE (International Conference on Software Engineering) submissions.
%%
%% Usage:
%%   \documentclass{icse}
%%   \documentclass[anonymous,review]{icse}  % for double-blind review
%%   \documentclass[draft]{icse}             % for draft mode
%%

\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{icse}[2025/01/01 v1.0 ICSE paper class]

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
%% Load style package
%% ========================================

\RequirePackage{icse}

\endinput
