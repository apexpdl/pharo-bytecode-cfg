# Bytecode CFG Analyzer

Builds control flow graphs from Pharo compiled methods and identifies merge points.

I built this to understand where register allocation breaks down in the Pharo VM's JIT compiler. Before you can improve how the JIT handles merge points, you need to know which methods have them and how many.

## What it does

- Scans a compiled method's bytecodes into `BcInstruction` objects
- Identifies basic block boundaries (branch targets, jumps, returns)
- Constructs a `BcControlFlowGraph` with edges between blocks
- Detects merge points (blocks with >1 predecessor), which is where the JIT currently flushes all register assignments

## Usage

```smalltalk
"Analyze a single method"
cfg := BcCFGBuilder buildFrom: (Integer >> #factorial).
BcCFGAnalyzer reportMergePoints: cfg.

"Analyze all methods in a class"
BcCFGAnalyzer analyzeClass: OrderedCollection.

"Analyze an entire package"
BcCFGAnalyzer analyzePackage: 'Collections-Sequenceable'.
```

## What I found

Running this against core collection classes, roughly 30-35% of methods have at least one merge point. Some methods like `do:separatedBy:` have merge points with 3-4 predecessors. Even a simple `ifTrue:ifFalse:` creates a merge point because it compiles to two jumps (one conditional, one unconditional).

## Installation

File in `BytecodeCFG-Core.st` into a Pharo 13 image using the File Browser or Playground:

```smalltalk
'path/to/BytecodeCFG-Core.st' asFileReference fileIn.
```

## Context

This is part of my exploration for the GSoC 2026 Register Allocation project with Pharo Consortium. The goal is to improve how `StackToRegisterMappingCogit` handles merge points instead of flushing all register assignments.

## Author

Apex Poudel - apexpoudel111@gmail.com
