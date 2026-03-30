"
BytecodeCFG-Core
=================
Control Flow Graph builder for Pharo compiled methods.
Identifies basic blocks, edges, and merge points from bytecodes.

Author: Apex Poudel
Date: March 2026
"

Object subclass: #BcInstruction
	instanceVariableNames: 'offset bytecode arguments isJump isBranch isReturn jumpTarget'
	classVariableNames: ''
	package: 'BytecodeCFG-Core'.

"--- BcInstruction methods ---"

BcInstruction >> offset
	^ offset

BcInstruction >> offset: anInteger
	offset := anInteger

BcInstruction >> bytecode
	^ bytecode

BcInstruction >> bytecode: aSymbol
	bytecode := aSymbol

BcInstruction >> arguments
	^ arguments ifNil: [ #() ]

BcInstruction >> arguments: aCollection
	arguments := aCollection

BcInstruction >> isJump
	^ isJump ifNil: [ false ]

BcInstruction >> isJump: aBoolean
	isJump := aBoolean

BcInstruction >> isBranch
	"A branch is a conditional jump (has two successors)"
	^ isBranch ifNil: [ false ]

BcInstruction >> isBranch: aBoolean
	isBranch := aBoolean

BcInstruction >> isReturn
	^ isReturn ifNil: [ false ]

BcInstruction >> isReturn: aBoolean
	isReturn := aBoolean

BcInstruction >> jumpTarget
	^ jumpTarget

BcInstruction >> jumpTarget: anInteger
	jumpTarget := anInteger

BcInstruction >> isControlFlow
	^ self isJump or: [ self isBranch or: [ self isReturn ] ]

BcInstruction >> printOn: aStream
	aStream
		print: offset;
		nextPutAll: ': ';
		nextPutAll: bytecode asString.
	self isJump ifTrue: [
		aStream nextPutAll: ' -> '; print: jumpTarget ].
	self isBranch ifTrue: [
		aStream nextPutAll: ' ? -> '; print: jumpTarget ].


"============================================================"

Object subclass: #BcBasicBlock
	instanceVariableNames: 'id startOffset endOffset instructions predecessors successors'
	classVariableNames: ''
	package: 'BytecodeCFG-Core'.

"--- BcBasicBlock methods ---"

BcBasicBlock >> initialize
	predecessors := OrderedCollection new.
	successors := OrderedCollection new.
	instructions := OrderedCollection new.

BcBasicBlock >> id
	^ id

BcBasicBlock >> id: anInteger
	id := anInteger

BcBasicBlock >> startOffset
	^ startOffset

BcBasicBlock >> startOffset: anInteger
	startOffset := anInteger

BcBasicBlock >> endOffset
	^ endOffset

BcBasicBlock >> endOffset: anInteger
	endOffset := anInteger

BcBasicBlock >> instructions
	^ instructions

BcBasicBlock >> addInstruction: aBcInstruction
	instructions add: aBcInstruction

BcBasicBlock >> predecessors
	^ predecessors

BcBasicBlock >> addPredecessor: aBlock
	(predecessors includes: aBlock) ifFalse: [
		predecessors add: aBlock ]

BcBasicBlock >> successors
	^ successors

BcBasicBlock >> addSuccessor: aBlock
	(successors includes: aBlock) ifFalse: [
		successors add: aBlock ]

BcBasicBlock >> isMergePoint
	"A merge point has more than one predecessor.
	 This is where register allocation state reconciliation is needed."
	^ predecessors size > 1

BcBasicBlock >> fanIn
	^ predecessors size

BcBasicBlock >> lastInstruction
	^ instructions ifEmpty: [ nil ] ifNotEmpty: [ instructions last ]

BcBasicBlock >> endsWithJump
	| last |
	last := self lastInstruction.
	^ last notNil and: [ last isJump ]

BcBasicBlock >> endsWithBranch
	| last |
	last := self lastInstruction.
	^ last notNil and: [ last isBranch ]

BcBasicBlock >> endsWithReturn
	| last |
	last := self lastInstruction.
	^ last notNil and: [ last isReturn ]

BcBasicBlock >> instructionCount
	^ instructions size

BcBasicBlock >> printOn: aStream
	aStream
		nextPutAll: 'Block ';
		print: id;
		nextPutAll: ' [';
		print: startOffset;
		nextPutAll: '-';
		print: endOffset;
		nextPut: $].
	self isMergePoint ifTrue: [
		aStream nextPutAll: ' *MERGE* ('; print: self fanIn; nextPutAll: ' preds)' ]


"============================================================"

Object subclass: #BcControlFlowGraph
	instanceVariableNames: 'blocks edges methodName'
	classVariableNames: ''
	package: 'BytecodeCFG-Core'.

"--- BcControlFlowGraph methods ---"

BcControlFlowGraph >> initialize
	blocks := OrderedCollection new.
	edges := OrderedCollection new.

BcControlFlowGraph >> methodName
	^ methodName

BcControlFlowGraph >> methodName: aString
	methodName := aString

BcControlFlowGraph >> blocks
	^ blocks

BcControlFlowGraph >> addBlock: aBlock
	blocks add: aBlock

BcControlFlowGraph >> edges
	^ edges

BcControlFlowGraph >> addEdgeFrom: srcBlock to: dstBlock
	edges add: (srcBlock -> dstBlock).
	srcBlock addSuccessor: dstBlock.
	dstBlock addPredecessor: srcBlock.

BcControlFlowGraph >> mergePoints
	"Return all blocks that are merge points (>1 predecessor)"
	^ blocks select: [ :b | b isMergePoint ]

BcControlFlowGraph >> mergePointCount
	^ self mergePoints size

BcControlFlowGraph >> maxFanIn
	"Maximum number of predecessors at any merge point"
	| merges |
	merges := self mergePoints.
	merges ifEmpty: [ ^ 0 ].
	^ (merges collect: [ :b | b fanIn ]) max

BcControlFlowGraph >> blockCount
	^ blocks size

BcControlFlowGraph >> edgeCount
	^ edges size

BcControlFlowGraph >> blockAtOffset: anOffset
	"Find the block that contains the given bytecode offset"
	^ blocks detect: [ :b |
		anOffset >= b startOffset and: [ anOffset <= b endOffset ] ]
		ifNone: [ nil ]

BcControlFlowGraph >> printOn: aStream
	aStream
		nextPutAll: 'CFG(';
		nextPutAll: (methodName ifNil: [ 'unnamed' ]);
		nextPutAll: ', ';
		print: blocks size;
		nextPutAll: ' blocks, ';
		print: self mergePointCount;
		nextPutAll: ' merge points)'


"============================================================"

Object subclass: #BcBytecodeScanner
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BytecodeCFG-Core'.

"--- BcBytecodeScanner class methods ---"

BcBytecodeScanner class >> scanMethod: aCompiledMethod
	"Scan a compiled method and return a collection of BcInstruction objects.
	 Uses Pharo's InstructionStream to iterate bytecodes."
	| instructions |
	instructions := OrderedCollection new.
	aCompiledMethod symbolicBytecodes do: [ :assoc |
		| instr |
		instr := BcInstruction new.
		instr offset: assoc offset.
		instr bytecode: assoc description.
		"Detect control flow instructions from description"
		(assoc description includesSubstring: 'jump') ifTrue: [
			| target |
			"Try to extract jump target from the bytecode description"
			target := self extractJumpTargetFrom: assoc description offset: assoc offset.
			target ifNotNil: [
				(assoc description includesSubstring: 'If')
					ifTrue: [
						instr isBranch: true.
						instr jumpTarget: target ]
					ifFalse: [
						instr isJump: true.
						instr jumpTarget: target ] ] ].
		(assoc description includesSubstring: 'return') ifTrue: [
			instr isReturn: true ].
		instructions add: instr ].
	^ instructions

BcBytecodeScanner class >> extractJumpTargetFrom: description offset: currentOffset
	"Extract absolute jump target from bytecode description.
	 Pharo's symbolic bytecodes show jump targets in various formats."
	| tokens |
	tokens := description substrings.
	tokens do: [ :token |
		(token allSatisfy: [ :c | c isDigit ]) ifTrue: [
			^ token asInteger ] ].
	"If we can't extract it, try looking for relative offset patterns"
	^ nil


"============================================================"

Object subclass: #BcCFGBuilder
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BytecodeCFG-Core'.

"--- BcCFGBuilder class methods ---"

BcCFGBuilder class >> buildFrom: aCompiledMethod
	"Build a control flow graph from a compiled method.
	 Steps:
	   1. Scan bytecodes into BcInstruction objects
	   2. Identify basic block boundaries (leaders)
	   3. Create BcBasicBlock objects
	   4. Add edges based on jumps/branches/fall-throughs
	 Returns a BcControlFlowGraph."
	| instructions leaders cfg blocks blockMap |
	
	"Step 1: Scan bytecodes"
	instructions := BcBytecodeScanner scanMethod: aCompiledMethod.
	instructions ifEmpty: [ ^ BcControlFlowGraph new ].
	
	"Step 2: Find leaders (basic block start points)"
	leaders := self findLeaders: instructions.
	
	"Step 3: Build basic blocks"
	blocks := self buildBlocks: instructions leaders: leaders.
	
	"Step 4: Build CFG with edges"
	cfg := BcControlFlowGraph new.
	cfg methodName: aCompiledMethod printString.
	
	"Build offset -> block map for edge construction"
	blockMap := Dictionary new.
	blocks do: [ :block |
		cfg addBlock: block.
		blockMap at: block startOffset put: block ].
	
	"Step 5: Add edges"
	blocks doWithIndex: [ :block :index |
		| lastInstr |
		lastInstr := block lastInstruction.
		lastInstr ifNotNil: [
			"If block ends with unconditional jump, add edge to target"
			lastInstr isJump ifTrue: [
				lastInstr jumpTarget ifNotNil: [ :target |
					(blockMap at: target ifAbsent: [ nil ]) ifNotNil: [ :targetBlock |
						cfg addEdgeFrom: block to: targetBlock ] ] ].
			
			"If block ends with conditional branch, add edges to both target and fall-through"
			lastInstr isBranch ifTrue: [
				"Edge to branch target"
				lastInstr jumpTarget ifNotNil: [ :target |
					(blockMap at: target ifAbsent: [ nil ]) ifNotNil: [ :targetBlock |
						cfg addEdgeFrom: block to: targetBlock ] ].
				"Edge to fall-through (next block)"
				index < blocks size ifTrue: [
					cfg addEdgeFrom: block to: (blocks at: index + 1) ] ].
			
			"If block doesn't end with jump/return, add fall-through edge"
			(lastInstr isJump not and: [ lastInstr isBranch not and: [ lastInstr isReturn not ] ]) ifTrue: [
				index < blocks size ifTrue: [
					cfg addEdgeFrom: block to: (blocks at: index + 1) ] ] ] ].
	
	^ cfg

BcCFGBuilder class >> findLeaders: instructions
	"A leader is:
	  1. The first instruction
	  2. Any jump target
	  3. Any instruction immediately after a jump/branch"
	| leaders |
	leaders := Set new.
	instructions ifNotEmpty: [
		leaders add: instructions first offset ].
	
	instructions do: [ :instr |
		(instr isJump or: [ instr isBranch ]) ifTrue: [
			"The jump target is a leader"
			instr jumpTarget ifNotNil: [ :t | leaders add: t ].
			"The instruction after this jump is a leader"
			instructions
				detect: [ :next | next offset > instr offset ]
				ifFound: [ :next | leaders add: next offset ]
				ifNone: [ ] ] ].
	
	^ leaders asSortedCollection asArray

BcCFGBuilder class >> buildBlocks: instructions leaders: leaders
	"Split instructions into basic blocks based on leader offsets"
	| blocks currentBlock blockId |
	blocks := OrderedCollection new.
	blockId := 0.
	currentBlock := nil.
	
	instructions do: [ :instr |
		"Start a new block if this offset is a leader"
		(leaders includes: instr offset) ifTrue: [
			currentBlock ifNotNil: [
				currentBlock endOffset: (currentBlock instructions last offset) ].
			blockId := blockId + 1.
			currentBlock := BcBasicBlock new.
			currentBlock id: blockId.
			currentBlock startOffset: instr offset.
			blocks add: currentBlock ].
		
		currentBlock ifNotNil: [
			currentBlock addInstruction: instr ] ].
	
	"Close the last block"
	currentBlock ifNotNil: [
		currentBlock endOffset: (currentBlock instructions last offset) ].
	
	^ blocks


"============================================================"

Object subclass: #BcCFGAnalyzer
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'BytecodeCFG-Core'.

"--- BcCFGAnalyzer class methods ---"

BcCFGAnalyzer class >> reportMergePoints: aCFG
	"Print a merge point report for a CFG"
	| merges |
	Transcript cr.
	Transcript show: '=== CFG Analysis: ', (aCFG methodName ifNil: [ 'unnamed' ]), ' ==='.
	Transcript cr.
	Transcript show: 'Basic blocks: ', aCFG blockCount printString.
	Transcript cr.
	Transcript show: 'Edges: ', aCFG edgeCount printString.
	Transcript cr.
	
	merges := aCFG mergePoints.
	Transcript show: 'Merge points: ', merges size printString.
	Transcript cr.
	
	merges do: [ :block |
		Transcript show: '  Block ', block id printString,
			' (bytecodes ', block startOffset printString, '-', block endOffset printString, '): ',
			block fanIn printString, ' predecessors ['.
		block predecessors
			do: [ :pred | Transcript show: 'Block ', pred id printString ]
			separatedBy: [ Transcript show: ', ' ].
		Transcript show: ']'.
		Transcript cr.
		Transcript show: '    → Register state reconciliation needed here'.
		Transcript cr ].

BcCFGAnalyzer class >> analyzeClass: aClass
	"Analyze all methods in a class, report merge point statistics"
	| methodCount mergeMethodCount totalMerges maxFanIn maxFanInMethod |
	methodCount := 0.
	mergeMethodCount := 0.
	totalMerges := 0.
	maxFanIn := 0.
	maxFanInMethod := ''.
	
	Transcript cr.
	Transcript show: '=== Batch Analysis: ', aClass name, ' ==='.
	Transcript cr.
	
	aClass methods do: [ :method |
		| cfg |
		methodCount := methodCount + 1.
		cfg := BcCFGBuilder buildFrom: method.
		cfg mergePointCount > 0 ifTrue: [
			mergeMethodCount := mergeMethodCount + 1.
			totalMerges := totalMerges + cfg mergePointCount.
			cfg maxFanIn > maxFanIn ifTrue: [
				maxFanIn := cfg maxFanIn.
				maxFanInMethod := method printString ] ] ].
	
	Transcript show: 'Methods analyzed: ', methodCount printString.
	Transcript cr.
	Transcript show: 'Total merge points: ', totalMerges printString.
	Transcript cr.
	Transcript show: 'Methods with merge points: ', mergeMethodCount printString,
		' (', ((mergeMethodCount / methodCount asFloat * 100) printShowingDecPlaces: 1), '%)'.
	Transcript cr.
	maxFanIn > 0 ifTrue: [
		Transcript show: 'Max predecessors at a merge: ', maxFanIn printString,
			' (in ', maxFanInMethod, ')'.
		Transcript cr ].
	
	^ Dictionary new
		at: #methodCount put: methodCount;
		at: #mergeMethodCount put: mergeMethodCount;
		at: #totalMerges put: totalMerges;
		at: #maxFanIn put: maxFanIn;
		yourself

BcCFGAnalyzer class >> analyzePackage: packageName
	"Analyze all classes in a package"
	| classes |
	classes := (RPackageOrganizer default packageNamed: packageName ifAbsent: [ ^ 'Package not found' ]) definedClasses.
	Transcript cr.
	Transcript show: '=== Package Analysis: ', packageName, ' ==='.
	Transcript cr.
	Transcript show: 'Classes: ', classes size printString.
	Transcript cr.
	classes do: [ :cls |
		self analyzeClass: cls ].
