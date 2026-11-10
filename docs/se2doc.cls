% se2doc.cls: one class for the RASD, DD and project plan of every project.
% Usage: \documentclass[rasd]{se2doc}   options: rasd | dd | plan, dark, italian
\NeedsTeXFormat{LaTeX2e}
\ProvidesClass{se2doc}[2026/10/23 v0.2 Course-style project documents, article look]

% --- Options ---------------------------------------------------------------
\newcommand\se@doctype{Document}
\newcommand\se@docshort{DOC}
\newif\ifse@dark
\newif\ifse@italian
\DeclareOption{rasd}{%
  \renewcommand\se@doctype{Requirement Analysis and Specification Document}%
  \renewcommand\se@docshort{RASD}}
\DeclareOption{dd}{%
  \renewcommand\se@doctype{Design Document}%
  \renewcommand\se@docshort{DD}}
\DeclareOption{plan}{%
  \renewcommand\se@doctype{Project Plan}%
  \renewcommand\se@docshort{Project Plan}}
\DeclareOption{dark}{\se@darktrue}
\DeclareOption{italian}{\se@italiantrue}
\DeclareOption*{\PassOptionsToClass{\CurrentOption}{article}}
\ProcessOptions\relax
\LoadClass[11pt,a4paper]{article}

% --- Fonts and language ----------------------------------------------------
\RequirePackage[T1]{fontenc}
\RequirePackage{lmodern}
\RequirePackage{microtype}
\ifse@italian
  \RequirePackage[italian]{babel}
\else
  \RequirePackage[english]{babel}
\fi

% --- Page and colours ------------------------------------------------------
\RequirePackage[a4paper,margin=2.8cm,headheight=14pt]{geometry}
\RequirePackage{xcolor}
\ifse@dark
  % same palette as the notes in this repo (darkmode look), for reading on screen
  \definecolor{se2page}{HTML}{293133}
  \definecolor{se2text}{HTML}{EDEDED}
  \definecolor{se2rule}{HTML}{9AA5AA}
  \pagecolor{se2page}
  \AtBeginDocument{\color{se2text}\def\normalcolor{\color{se2text}}}
\else
  \definecolor{se2text}{HTML}{000000}
  \definecolor{se2rule}{HTML}{000000}
\fi

% --- Packages documents rely on --------------------------------------------
\RequirePackage{graphicx}
\RequirePackage{booktabs}
\RequirePackage{longtable}
\RequirePackage{tabularx}
\RequirePackage{array}
\RequirePackage{enumitem}
\RequirePackage{fancyhdr}
\RequirePackage{lastpage}
\RequirePackage{listings}
\RequirePackage{tikz}
\RequirePackage{pgfplots}
\pgfplotsset{compat=1.18}
\RequirePackage{pgfgantt}
\RequirePackage[hidelinks]{hyperref}
\RequirePackage[nameinlink,noabbrev]{cleveref}
\setlist{nosep}

% --- Metadata (set in meta.tex) --------------------------------------------
\newcommand\se@project{Project}
\newcommand\se@version{0.1}
\newcommand\se@authors{}
\newcommand\se@date{\today}
\newcommand\se@institution{}
\newcommand\project[1]{\renewcommand\se@project{#1}}
\newcommand\docversion[1]{\renewcommand\se@version{#1}}
\newcommand\authors[1]{\renewcommand\se@authors{#1}}
\newcommand\docdate[1]{\renewcommand\se@date{#1}}
\newcommand\institution[1]{\renewcommand\se@institution{#1}}
\AtBeginDocument{\hypersetup{pdftitle={\se@project{} -- \se@docshort{} v\se@version},
  pdfauthor={\se@authors}}}

% --- Header and footer -----------------------------------------------------
\pagestyle{fancy}
\fancyhf{}
\fancyhead[L]{\small\scshape\se@project}
\fancyhead[R]{\small\scshape\se@docshort\ v\se@version}
\fancyfoot[C]{\small\thepage}
\renewcommand\headrulewidth{0.4pt}
\renewcommand\headrule{{\color{se2rule}\hrule height\headrulewidth\relax}}
\fancypagestyle{plain}{\fancyhf{}\fancyfoot[C]{\small\thepage}%
  \renewcommand\headrulewidth{0pt}}

% --- Revision history: \revision{version}{date}{what changed} -------------
\newcommand\se@revisions{}
\newcommand\revision[3]{\g@addto@macro\se@revisions{#1 & #2 & #3 \\}}
\newcommand\printrevisions{%
  \begin{center}\small
  \begin{tabularx}{0.9\linewidth}{@{}l l X@{}}
    \toprule
    Version & Date & Changes \\
    \midrule
    \se@revisions
    \bottomrule
  \end{tabularx}
  \end{center}}

% --- Title block (article style, on the first page) ------------------------
\renewcommand\maketitle{%
  \thispagestyle{plain}%
  \begin{center}
    {\LARGE\bfseries \se@project\par}
    \vspace{0.5em}
    {\large \se@doctype\par}
    \vspace{1em}
    {\se@authors\par}
    \ifx\se@institution\@empty\else{\small\itshape\se@institution\par}\fi
    \vspace{0.5em}
    {\small Version \se@version\ \textperiodcentered\ \se@date\par}
  \end{center}
  \vspace{1em}
  \ifx\se@revisions\@empty\else
    \begin{center}\small\bfseries Revision history\end{center}
    \vspace{-1.5em}
    \printrevisions
  \fi
  \tableofcontents
  \vspace{1.5em}}

% --- Numbered entries: goals, assumptions, requirements -------------------
% Each ID becomes a label: \idref{R7} prints "R7" and links to it.
\newcommand\idref[1]{\hyperref[#1]{#1}}
\newcommand\se@label[1]{\phantomsection\def\@currentlabel{#1}\label{#1}}
\newcommand\se@entry[2]{% id, text
  \par\smallskip
  \noindent\hangindent=3em\hangafter=1
  \makebox[3em][l]{\se@label{#1}\textbf{#1}}#2\par\smallskip}
\newcommand\goal[2]{\se@entry{#1}{#2}}
\newcommand\assumption[2]{\se@entry{#1}{#2}}
\newcommand\requirement[2]{\se@entry{#1}{#2}}

% Use cases: \begin{usecase}{UC1}{Book a slot} \ucfield{Actors}{...} ... \end{usecase}
\newenvironment{usecase}[2]{%
  \par\medskip\noindent
  \setlist[enumerate]{nosep,leftmargin=*,
    before={\leavevmode\vspace{-\baselineskip}},after={\vspace{-\baselineskip}\leavevmode}}%
  \se@label{#1}\textbf{#1\quad #2}\par\nopagebreak
  \noindent\tabularx{\linewidth}{@{}>{\itshape}p{2.6cm}X@{}}
  \toprule}
  {\bottomrule\endtabularx\par\medskip}
\newcommand\ucfield[2]{#1 & #2 \\}

% --- Definitions: \term{word}{meaning}, printed with \printterms ------------
\newcommand\se@terms{}
\newcommand\term[2]{\g@addto@macro\se@terms{#1 & #2 \\}}
\newcommand\printterms{%
  \begin{longtable}{@{}p{0.25\linewidth}p{0.7\linewidth}@{}}
    \toprule Term & Meaning \\ \midrule
    \se@terms
    \bottomrule
  \end{longtable}}

% --- Traceability: \traces{R7}{Component}, printed with \printtraceability --
\newcommand\se@traces{}
\newcommand\traces[2]{\g@addto@macro\se@traces{\idref{#1} & #2 \\}}
\newcommand\printtraceability{%
  \begin{longtable}{@{}l p{0.75\linewidth}@{}}
    \toprule Requirement & Component \\ \midrule
    \se@traces
    \bottomrule
  \end{longtable}}

% --- Effort spent: \effort{task}{hours}, printed with \printeffort --------
\newcommand\se@effort{}
\def\se@efforttotal{0}
\newcommand\effort[2]{%
  \g@addto@macro\se@effort{#1 & #2 \\}%
  \xdef\se@efforttotal{\fpeval{\se@efforttotal + #2}}}
\newcommand\printeffort{%
  \begin{center}
  \begin{tabular}{@{}l r@{}}
    \toprule Task & Hours \\ \midrule
    \se@effort
    \midrule Total & \se@efforttotal \\
    \bottomrule
  \end{tabular}
  \end{center}}

% --- Alloy listings --------------------------------------------------------
\lstdefinelanguage{Alloy}{
  morekeywords={module,open,as,sig,abstract,extends,in,one,lone,some,all,no,
    set,seq,disj,fact,pred,fun,assert,check,run,for,but,exactly,let,and,or,
    not,implies,iff,else,univ,none,iden,Int,this,var,always,eventually,
    after,before,historically,once,until,since,steps},
  sensitive=true,
  morecomment=[l]{//}, morecomment=[l]{--}, morecomment=[s]{/*}{*/}}
\lstset{basicstyle=\ttfamily\small,keywordstyle=\bfseries,
  commentstyle=\itshape,columns=fullflexible,breaklines=true,
  frame=lines,rulecolor=\color{se2rule},numbers=left,numberstyle=\tiny,
  xleftmargin=1.5em,framexleftmargin=1.5em}
\lstnewenvironment{alloy}[1][]{\lstset{language=Alloy,#1}}{}

% --- Gantt defaults (greyscale) --------------------------------------------
\ganttset{
  bar/.append style={fill=gray!35,draw=se2rule},
  group/.append style={fill=se2rule,draw=se2rule},
  milestone/.append style={fill=se2rule,draw=se2rule},
  link/.style={->,thin,draw=se2rule}}

\endinput
