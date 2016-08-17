---
layout: index
---
[Installation]: /installation
[TABLEAUX'15 paper]: http://dx.doi.org/10.1007/978-3-319-24312-2_20
{:target="_blank"}
[binary release]: https://github.com/ngorogiannis/cyclist/releases/tag/TABLEAUX15
{:target="_blank"}

A heuristic procedure for disproving SL entailments.
====================================================

OVERVIEW:
----------------------------------------------------
The tool is described in the [TABLEAUX'15 paper]:

>  J. Brotherston and N. Gorogiannis.
>  Disproving Inductive Entailments in Separation Logic 
>  via Base Pair Approximation

QUICKSTART:
----------------------------------------------------
If you downloaded the [binary release] from GitHub a x64 binary
should be already present in this directory.  If you 
do not have such a binary, look at the [Installation].

Running the executable `sl_disprove.native` without options will produce 
some help text explaining its usage.

TEST SUITE:
----------------------------------------------------
There are three classes of benchmarks described in the paper.  The classes
SLL and UDP are from the SL-COMP14 competition:

  https://github.com/mihasighi/smtcomp14-sl

The benchmarks for SLL and UDP can be downloaded from the repository above.

The third class (LEM) is included in this tree, in *benchmarks/sl_disproof*.
  
The definitions are in "all.defs" and the sequents in "seqs".  The "invbench.sh"
script will execute the LEM benchmark.