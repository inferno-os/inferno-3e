#include "mem.h"
#include "armv4.h"


TEXT		_main(SB),1,$-4
		MOVW	$setR12(SB), R12
		MOVW	$mach0(SB), R13
		MOVW	R13,m(SB)
		ADD		$(MACHSIZE-12), R13
		
		MOVW	$(PsrMirq), R0
		MOVW	$mach0(SB), R1
		ADD		$(100), R1
		SUB		$(8), R13
		MOVW	R1, 4(SP)
		BL		setr13(SB)
		ADD		$(8), R13
	loop:
		B		loop

TEXT		idle(SB),$0
		RET

/*
 * Function: setr13( mode, pointer )
 * Purpose:
 *		Sets the stack pointer for a particular mode
 */

TEXT setr13(SB), $-4
	MOVW		0(FP), R1

	MOVW		CPSR, R2
	BIC			$PsrMask, R2, R3
	ORR			R0, R3
	MOVW		R3, CPSR

	MOVW		R13, R0
	MOVW		R1, R13

	MOVW		R2, CPSR
	RET


GLOBL	mach0+0(SB), $MACHSIZE
GLOBL	m(SB), $4
