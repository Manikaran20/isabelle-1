theory Evaluation
imports Codegen_Basics.Setup
begin (*<*)

ML \<open>
  Isabelle_System.mkdirs (File.tmp_path (Path.basic "examples"))
\<close> (*>*)

section \<open>Evaluation \label{sec:evaluation}\<close>

text \<open>
  Recalling \secref{sec:principle}, code generation turns a system of
  equations into a program with the \emph{same} equational semantics.
  As a consequence, this program can be used as a \emph{rewrite
  engine} for terms: rewriting a term @{term "t"} using a program to a
  term @{term "t'"} yields the theorems @{prop "t \<equiv> t'"}.  This
  application of code generation in the following is referred to as
  \emph{evaluation}.
\<close>


subsection \<open>Evaluation techniques\<close>

text \<open>
  There is a rich palette of evaluation
  techniques, each comprising different aspects:

  \begin{description}

    \item[Expressiveness.]  Depending on the extent to which symbolic
      computation is possible, the class of terms which can be evaluated
      can be bigger or smaller.

    \item[Efficiency.]  The more machine-near the technique, the
      faster it is.

    \item[Trustability.]  Techniques which a huge (and also probably
      more configurable infrastructure) are more fragile and less
      trustable.

  \end{description}
\<close>


subsubsection \<open>The simplifier (@{text simp})\<close>

text \<open>
  The simplest way for evaluation is just using the simplifier with
  the original code equations of the underlying program.  This gives
  fully symbolic evaluation and highest trustablity, with the usual
  performance of the simplifier.  Note that for operations on abstract
  datatypes (cf.~\secref{sec:invariant}), the original theorems as
  given by the users are used, not the modified ones.
\<close>


subsubsection \<open>Normalization by evaluation (@{text nbe})\<close>

text \<open>
  Normalization by evaluation @{cite "Aehlig-Haftmann-Nipkow:2008:nbe"}
  provides a comparably fast partially symbolic evaluation which
  permits also normalization of functions and uninterpreted symbols;
  the stack of code to be trusted is considerable.
\<close>


subsubsection \<open>Evaluation in ML (@{text code})\<close>

text \<open>
  Considerable performance can be achieved using evaluation in ML, at the cost
  of being restricted to ground results and a layered stack of code to
  be trusted, including a user's specific code generator setup.

  Evaluation is carried out in a target language \emph{Eval} which
  inherits from \emph{SML} but for convenience uses parts of the
  Isabelle runtime environment.  Hence soundness depends crucially
  on the correctness of the code generator setup; this is one of the
  reasons why you should not use adaptation (see \secref{sec:adaptation})
  frivolously.
\<close>


subsection \<open>Dynamic evaluation\<close>

text \<open>
  Dynamic evaluation takes the code generator configuration \qt{as it
  is} at the point where evaluation is issued and computes
  a corresponding result.  Best example is the
  @{command_def value} command for ad-hoc evaluation of
  terms:
\<close>

value %quote "42 / (12 :: rat)"

text \<open>
  \noindent @{command value} tries first to evaluate using ML, falling
  back to normalization by evaluation if this fails.

  A particular technique may be specified in square brackets, e.g.
\<close>

value %quote [nbe] "42 / (12 :: rat)"

text \<open>
  To employ dynamic evaluation in documents, there is also
  a @{text value} antiquotation with the same evaluation techniques 
  as @{command value}.
\<close>

  
subsubsection \<open>Term reconstruction in ML\<close>

text \<open>
  Results from evaluation in ML must be
  turned into Isabelle's internal term representation again.  Since
  that setup is highly configurable, it is never assumed to be trustable. 
  Hence evaluation in ML provides no full term reconstruction
  but distinguishes the following kinds:

  \begin{description}

    \item[Plain evaluation.]  A term is normalized using the vanilla
      term reconstruction from ML to Isabelle; this is a pragmatic
      approach for applications which do not need trustability.

    \item[Property conversion.]  Evaluates propositions; since these
      are monomorphic, the term reconstruction is fixed once and for all
      and therefore trustable -- in the sense that only the regular
      code generator setup has to be trusted, without relying
      on term reconstruction from ML to Isabelle.

  \end{description}

  \noindent The different degree of trustability is also manifest in the
  types of the corresponding ML functions: plain evaluation
  operates on uncertified terms, whereas property conversion
  operates on certified terms.
\<close>


subsubsection \<open>The partiality principle \label{sec:partiality_principle}\<close>

text \<open>
  During evaluation exceptions indicating a pattern
  match failure or a non-implemented function are treated specially:
  as sketched in \secref{sec:partiality}, such
  exceptions can be interpreted as partiality.  For plain evaluation,
  the result hence is optional; property conversion falls back
  to reflexivity in such cases.
\<close>
  

subsubsection \<open>Schematic overview\<close>

text \<open>
  \newcommand{\ttsize}{\fontsize{5.8pt}{8pt}\selectfont}
  \fontsize{9pt}{12pt}\selectfont
  \begin{tabular}{l||c|c|c}
    & @{text simp} & @{text nbe} & @{text code} \tabularnewline \hline \hline
    interactive evaluation & @{command value} @{text "[simp]"} & @{command value} @{text "[nbe]"} & @{command value} @{text "[code]"} \tabularnewline
    plain evaluation & & & \ttsize@{ML "Code_Evaluation.dynamic_value"} \tabularnewline \hline
    evaluation method & @{method code_simp} & @{method normalization} & @{method eval} \tabularnewline
    property conversion & & & \ttsize@{ML "Code_Runtime.dynamic_holds_conv"} \tabularnewline \hline
    conversion & \ttsize@{ML "Code_Simp.dynamic_conv"} & \ttsize@{ML "Nbe.dynamic_conv"}
  \end{tabular}
\<close>

  
subsection \<open>Static evaluation\<close>
  
text \<open>
  When implementing proof procedures using evaluation,
  in most cases the code generator setup is appropriate
  \qt{as it was} when the proof procedure was written in ML,
  not an arbitrary later potentially modified setup.  This is
  called static evaluation.
\<close>


subsubsection \<open>Static evaluation using @{text simp} and @{text nbe}\<close>
  
text \<open>
  For @{text simp} and @{text nbe} static evaluation can be achieved using 
  @{ML Code_Simp.static_conv} and @{ML Nbe.static_conv}.
  Note that @{ML Nbe.static_conv} by its very nature
  requires an invocation of the ML compiler for every call,
  which can produce significant overhead.
\<close>


subsubsection \<open>Intimate connection between logic and system runtime\<close>

text \<open>
  Static evaluation for @{text eval} operates differently --
  the required generated code is inserted directly into an ML
  block using antiquotations.  The idea is that generated
  code performing static evaluation (called a \<^emph>\<open>computation\<close>)
  is compiled once and for all such that later calls do not
  require any invocation of the code generator or the ML
  compiler at all.  This topic deserved a dedicated chapter
  \secref{sec:computations}.
\<close>
  
end
