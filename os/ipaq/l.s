#include "mem.h"

/*
 * Entered here from the handheld.org boot loader with
 *	supervisor mode, interrupts disabled;
 *	MMU, IDC and WB disabled.
 */

TEXT _startup(SB), $-4
	MOVW		$setR12(SB), R12 	/* static base (SB) */
	MOVW	$1, R0		/* dance to make 5l think that the magic */
	MOVW	$1, R1		/* numbers in WORDs below are being used */
	CMP.S	R0, R1		/* and to align them to where bootldr wants */
	BEQ	_start2
	WORD	$0x016f2818	/* magic number to say we are a kernel */
	WORD	$0xc0008010	/* entry point address */
	WORD	$0		/* size?, or end of data? */
_start2:
	MOVW		$(MACHADDR+KSTACK-4), R13	/* stack; 4 bytes for link */

	MOVW		$(PsrDirq|PsrDfiq|PsrMsvc), R1	/* Switch to SVC mode */
	MOVW		R1, CPSR

	BL		main(SB)		/* jump to kernel */

dead:
	B	dead

TEXT mmuregr(SB), $-4
	CMP		$CpCPUID, R0
	BNE		_fsrr
	MRC		CpMMU, 0, R0, C(CpCPUID), C(0)
	RET

_fsrr:
	CMP		$CpFSR, R0
	BNE		_farr
	MRC		CpMMU, 0, R0, C(CpFSR), C(0)
	RET

_farr:
	CMP		$CpFAR, R0
	BNE		_domr
	MRC		CpMMU, 0, R0, C(CpFAR), C(0)
	RET

_domr:
	CMP		$CpDAC, R0
	BNE		_ttbr
	MRC		CpMMU, 0, R0, C(CpDAC), C(0)
	RET

_ttbr:
	CMP		$CpTTB, R0
	BNE		_noner
	MRC		CpMMU, 0, R0, C(CpTTB), C(0)
	RET

_noner:
	MOVW		$-1, R0
	RET

TEXT mmuregw(SB), $-4
	MOVW		4(FP), R1
	CMP		$CpFSR, R0
	BNE		_domw
	MCR		CpMMU, 0, R1, C(CpFSR), C(0)
	RET

_domw:
	CMP		$CpDAC, R0
	BNE		_ttbw
	MCR		CpMMU, 0, R1, C(CpDAC), C(0)
	RET

_ttbw:
	CMP		$CpTTB, R0
	BNE		_nonew
	MCR		CpMMU, 0, R1, C(CpTTB), C(0)

_nonew:
	RET

TEXT flushTLB(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTLBops), C(7)
	RET

TEXT mmuenable(SB), $-4
	MCR		CpMMU, 0, R0, C(CpTTB), C(0)	/* set TTB */

	MOVW	$3, R1
	MCR	CpMMU, 0, R1, C(3), C(3)	/* set domain 0 to manager */

	/* disable and flush all caches and TLB's before enabling MMU */
	MOVW	$0, R0				/* disable everything */
	MCR	CpMMU, 0, R0, C(1), C(0), 0
	MCR	CpMMU, 0, R0, C(7), C(7), 0	/* Flush I&D Caches */
	MCR	CpMMU, 0, R0, C(7), C(10), 4	/* drain write buffer */
	MCR	CpMMU, 0, R0, C(8), C(7), 0	/* Flush I&D TLB */
	MCR	CpMMU, 0, R0, C(9), C(0), 0	/* Flush Read Buffer */

	/* enable mmu & system mode */
	MRC		CpMMU, 0, R0, C(CpControl), C(0)
	MOVW	$(CpCmmu|CpCsystem|CpCi32|CpCd32), R1
	ORR	R1, R0
	MCR	CpMMU, 0, R0, C(1), C(0)	/* enable the MMU */
	MOVW	R0, R0
	MOVW	R0, R0
	MOVW	R0, R0
	MOVW	R0, R0
	RET				/* start running in remapped area */

TEXT rDBAR(SB), $-4
	MRC		CpMMU, 0, R0, C(CpDebug), C(CpDBAR)
	RET

TEXT rDBVR(SB), $-4
	MRC		CpMMU, 0, R0, C(CpDebug), C(CpDBVR)
	RET

TEXT rDBMR(SB), $-4
	MRC		CpMMU, 0, R0, C(CpDebug), C(CpDBMR)
	RET

TEXT rDBCR(SB), $-4
	MRC		CpMMU, 0, R0, C(CpDebug), C(CpDBCR)
	RET

TEXT wDBAR(SB), $-4
	MCR		CpMMU, 0, R0, C(CpDebug), C(CpDBAR)
	RET

TEXT wDBVR(SB), $-4
	MCR		CpMMU, 0, R0, C(CpDebug), C(CpDBVR)
	RET

TEXT wDBMR(SB), $-4
	MCR		CpMMU, 0, R0, C(CpDebug), C(CpDBMR)
	RET

TEXT wDBCR(SB), $-4
	MCR		CpMMU, 0, R0, C(CpDebug), C(CpDBCR)
	RET

TEXT wIBCR(SB), $-4
	MCR		CpMMU, 0, R0, C(CpDebug), C(CpIBCR)
	RET

TEXT setr13(SB), $-4
	MOVW		4(FP), R1

	MOVW		CPSR, R2
	BIC		$PsrMask, R2, R3
	ORR		R0, R3
	MOVW		R3, CPSR

	MOVW		R13, R0
	MOVW		R1, R13

	MOVW		R2, CPSR
	RET

TEXT vectors(SB), $-4
	MOVW	0x18(R15), R15			/* reset */
	MOVW	0x18(R15), R15			/* undefined */
	MOVW	0x18(R15), R15			/* SWI */
	MOVW	0x18(R15), R15			/* prefetch abort */
	MOVW	0x18(R15), R15			/* data abort */
	MOVW	0x18(R15), R15			/* reserved */
	MOVW	0x18(R15), R15			/* IRQ */
	MOVW	0x18(R15), R15			/* FIQ */

TEXT vtable(SB), $-4
	WORD	$_vsvc(SB)			/* reset, in svc mode already */
	WORD	$_vund(SB)			/* undefined, switch to svc mode */
	WORD	$_vsvc(SB)			/* swi, in svc mode already */
	WORD	$_vpab(SB)			/* prefetch abort, switch to svc mode */
	WORD	$_vdab(SB)			/* data abort, switch to svc mode */
	WORD	$_vsvc(SB)			/* reserved */
	WORD	$_virq(SB)			/* IRQ, switch to svc mode */
	WORD	$_vfiq(SB)			/* FIQ, switch to svc mode */

TEXT _vund(SB), $-4			
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMund, R0
	B		_vswitch

TEXT _vsvc(SB), $-4				
	MOVW.W		R14, -4(R13)
	MOVW		CPSR, R14
	MOVW.W		R14, -4(R13)
	BIC		$PsrMask, R14
	ORR		$(PsrDirq|PsrDfiq|PsrMsvc), R14
	MOVW		R14, CPSR
	MOVW		$PsrMsvc, R14
	MOVW.W		R14, -4(R13)
	B		_vsaveu

TEXT _vpab(SB), $-4			
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMabt, R0
	B		_vswitch

TEXT _vdab(SB), $-4	
	MOVM.DB		[R0-R3], (R13)
	MOVW		$(PsrMabt+1), R0
	B		_vswitch

TEXT _vfiq(SB), $-4				/* FIQ */
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMfiq, R0
	B		_vswitch

TEXT _virq(SB), $-4				/* IRQ */
	MOVM.DB		[R0-R3], (R13)
	MOVW		$PsrMirq, R0

_vswitch:					/* switch to svc mode */
	MOVW		SPSR, R1
	MOVW		R14, R2
	MOVW		R13, R3

	MOVW		CPSR, R14
	BIC		$PsrMask, R14
	ORR		$(PsrDirq|PsrDfiq|PsrMsvc), R14
	MOVW		R14, CPSR

	MOVM.DB.W 	[R0-R2], (R13)
	MOVM.DB	  	(R3), [R0-R3]

_vsaveu:						/* Save Registers */
	MOVW.W		R14, -4(R13)			/* save link */
	MCR		CpMMU, 0, R0, C(0), C(0), 0	

	SUB		$8, R13
	MOVM.DB.W 	[R0-R12], (R13)

	MOVW		R0, R0				/* gratuitous noop */

	MOVW		$setR12(SB), R12		/* static base (SB) */
	MOVW		R13, R0				/* argument is ureg */
	SUB		$8, R13				/* space for arg+lnk*/
	BL		trap(SB)


_vrfe:							/* Restore Regs */
	MOVW		CPSR, R0			/* splhi on return */
	ORR		$(PsrDirq|PsrDfiq), R0, R1
	MOVW		R1, CPSR
	ADD		$(8+4*15), R13		/* [r0-R14]+argument+link */
	MOVW		(R13), R14			/* restore link */
	MOVW		8(R13), R0
	MOVW		R0, SPSR
	MOVM.DB.S 	(R13), [R0-R14]		/* restore user registers */
	MOVW		R0, R0				/* gratuitous nop */
	ADD		$12, R13		/* skip saved link+type+SPSR*/
	RFE					/* MOVM.IA.S.W (R13), [R15] */
	
TEXT splhi(SB), $-4					
	MOVW		CPSR, R0
	ORR		$(PsrDirq), R0, R1
	MOVW		R1, CPSR
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)	/* m->splpc */
	RET

TEXT spllo(SB), $-4
	MOVW		CPSR, R0
	BIC		$(PsrDirq|PsrDfiq), R0, R1
	MOVW		R1, CPSR
	RET

TEXT splx(SB), $-4
	MOVW	$(MACHADDR), R6
	MOVW	R14, (R6)	/* m->splpc */

TEXT _splx(SB), $-4
	MOVW		R0, R1
	MOVW		CPSR, R0
	MOVW		R1, CPSR
	RET

TEXT spldone(SB), $-4
	RET

TEXT islo(SB), $-4
	MOVW		CPSR, R0
	AND		$(PsrDirq), R0
	EOR		$(PsrDirq), R0
	RET

TEXT splfhi(SB), $-4					
	MOVW		CPSR, R0
	ORR		$(PsrDfiq|PsrDirq), R0, R1
	MOVW		R1, CPSR
	RET

TEXT splflo(SB), $-4
	MOVW		CPSR, R0
	BIC		$(PsrDfiq), R0, R1
	MOVW		R1, CPSR
	RET

TEXT cpsrr(SB), $-4
	MOVW		CPSR, R0
	RET

TEXT spsrr(SB), $-4
	MOVW		SPSR, R0
	RET

TEXT getcallerpc(SB), $-4
	MOVW		0(R13), R0
	RET

TEXT tas(SB), $-4
	MOVW		R0, R1
	MOVW		$0xDEADDEAD, R2
	SWPW		R2, (R1), R0
	RET

TEXT setlabel(SB), $-4
	MOVW		R13, 0(R0)		/* sp */
	MOVW		R14, 4(R0)		/* pc */
	MOVW		$0, R0
	RET

TEXT gotolabel(SB), $-4
	MOVW		0(R0), R13		/* sp */
	MOVW		4(R0), R14		/* pc */
	MOVW		$1, R0
	RET

TEXT mmuctlregr(SB), $-4
	MRC		CpMMU, 0, R0, C(CpControl), C(0)
	RET	

TEXT mmuctlregw(SB), $-4
	MCR		CpMMU, 0, R0, C(CpControl), C(0)
	MOVW		R0, R0
	MOVW		R0, R0
	RET	

TEXT flushicache(SB), $-4
	MCR	 	CpMMU, 0, R0, C(CpCacheCtl), C(5), 0	
	MOVW		R0,R0							
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

/*
 * write back data cache and drain write buffer
 */
TEXT wbflush(SB), $-4
	MOVW		$(DCFADDR), R0
	MOVW		$8192, R1
	ADD		R0, R1

wbflush1:
	MOVW.P.W	32(R0), R2
	CMP		R1,R0
	BNE		wbflush1
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	MOVW		R0,R0								
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

/*
 * invalidate data caches
 */
TEXT dcinval(SB), $-4
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(6), 0	
	RET

/*
 * write back mini data cache
 */
TEXT miniwbflush(SB), $-4		
	MOVW		$(MCFADDR), R0
	MOVW		$0x200, R1
	ADD		R0, R1

wbbflush:
	MOVW.P.W	32(R0), R2
	CMP		R1,R0
	BNE		wbbflush
	MCR		CpMMU, 0, R0, C(CpCacheCtl), C(10), 4	/* drain write buffer */
	MOVW		R0,R0								
	MOVW		R0,R0
	MOVW		R0,R0
	MOVW		R0,R0
	RET

/* for devboot */
TEXT	gotopc(SB), $-4
	MOVW	R0, R1
	MOVW	$0, R0
	MOVW	R1, PC
	RET

/*
* the following code was written for Plan 9 by nemo@gsyc.escet.urjc.es
*/

/*
 * save the state machine in power_resume[] for an upcoming suspend
 */
TEXT setpowerlabel(SB), $-4
	MOVW	$power_resume+0(SB), R0
	/* svc */				/* power_resume[]: what */
	MOVW		R1, 0(R0)
	MOVW		R2, 4(R0)
	MOVW		R3, 8(R0)
	MOVW		R4, 12(R0)
	MOVW		R5, 16(R0)
	MOVW		R6, 20(R0)
	MOVW		R7, 24(R0)
	MOVW		R8, 28(R0)
	MOVW		R9, 32(R0)
	MOVW		R10,36(R0)
	MOVW		R11,40(R0)
	MOVW		R12,44(R0)
	MOVW		R13,48(R0)
	MOVW		R14,52(R0)
	MOVW		SPSR, R1
	MOVW		R1, 56(R0)
	MOVW		CPSR, R2
	MOVW		R2, 60(R0)
	/* copro */
	MRC		CpMMU, 0, R3, C(CpDAC), C(0x0)
	MOVW		R3, 144(R0)
	MRC		CpMMU, 0, R3, C(CpTTB), C(0x0)
	MOVW		R3, 148(R0)
	MRC		CpMMU, 0, R3, C(CpControl), C(0x0)
	MOVW		R3, 152(R0)
	MRC		CpMMU, 0, R3, C(CpFSR), C(0x0)
	MOVW		R3, 156(R0)
	MRC		CpMMU, 0, R3, C(CpFAR), C(0x0)
	MOVW		R3, 160(R0)
	MRC		CpMMU, 0, R3, C(CpPID), C(0x0)
	MOVW		R3, 164(R0)
	/* irq */
	BIC		$(PsrMask), R2, R3
	ORR		$(PsrDirq|PsrMirq), R3
	MOVW		R3, CPSR
	MOVW		SPSR, R11
	MOVW		R11, 64(R0)
	MOVW		R12, 68(R0)
	MOVW		R13, 72(R0)
	MOVW		R14, 76(R0)
	/* und */
	BIC		$(PsrMask), R2, R3
	ORR		$(PsrDirq|PsrMund), R3
	MOVW		R3, CPSR
	MOVW		SPSR, R11
	MOVW		R11, 80(R0)
	MOVW		R12, 84(R0)
	MOVW		R13, 88(R0)
	MOVW		R14, 92(R0)
	/* abt */
	BIC		$(PsrMask), R2, R3
	ORR		$(PsrDirq|PsrMabt), R3
	MOVW		R3, CPSR
	MOVW		SPSR, R11
	MOVW		R11, 96(R0)
	MOVW		R12, 100(R0)
	MOVW		R13, 104(R0)
	MOVW		R14, 108(R0)
	/* fiq */
	BIC		$(PsrMask), R2, R3
	ORR		$(PsrDirq|PsrMfiq), R3
	MOVW		R3, CPSR
	MOVW		SPSR, R7
	MOVW		R7, 112(R0)
	MOVW		R8, 116(R0)
	MOVW		R9, 120(R0)
	MOVW		R10,124(R0)
	MOVW		R11,128(R0)
	MOVW		R12,132(R0)
	MOVW		R13,136(R0)
	MOVW		R14,140(R0)
	/* done */
	MOVW		R2, CPSR
	MOVW		R1, SPSR
	MOVW		$0, R0
	RET

/*
 * Entered after a resume from suspend state.
 * The bootldr jumps here after a processor reset.
 */ 
TEXT sa1100_power_resume(SB), $-4
	MOVW	$setR12(SB), R12		/* load the SB */
	/* SVC mode, interrupts disabled */
	MOVW	$(PsrDirq|PsrDfiq|PsrMsvc), R1
	MOVW	R1, CPSR
	/* flush caches */
	MCR	CpMMU, 0, R0, C(CpCacheCtl), C(0x7), 0
	/* drain prefetch */
	MOVW	R0,R0						
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	/* drain write buffer */
	MCR	CpMMU, 0, R0, C(CpCacheCtl), C(0xa), 4
	/* gotopowerlabel() */
	/* svc */
	MOVW	$power_resume+0(SB), R0
	MOVW	56(R0), R1		/* R1: SPSR, R2: CPSR */
	MOVW	60(R0), R2
	/* copro */
	MOVW		148(R0), R3
	MCR		CpMMU, 0, R3, C(CpTTB), C(0x0)
	MOVW		144(R0), R3
	MCR		CpMMU, 0, R3, C(CpDAC), C(0x0)
	MOVW		152(R0), R3
	MCR		CpMMU, 0, R3, C(CpControl), C(0x0)
	MOVW		156(R0), R3
	MCR		CpMMU, 0, R3, C(CpFSR), C(0x0)
	MOVW		160(R0), R3
	MCR		CpMMU, 0, R3, C(CpFAR), C(0x0)
	MOVW		164(R0), R3
	MCR		CpMMU, 0, R3, C(CpPID), C(0x0)
	MCR		CpMMU, 0, R0, C(CpTLBops), C(0x7)
	/* irq */
	BIC	$(PsrMask), R2, R3
	ORR	$(PsrDirq|PsrMirq), R3
	MOVW	R3, CPSR
	MOVW	64(R0), R11
	MOVW	68(R0), R12
	MOVW	72(R0), R13
	MOVW	76(R0), R14
	MOVW	R11, SPSR
	/* und */
	BIC	$(PsrMask), R2, R3
	ORR	$(PsrDirq|PsrMund), R3
	MOVW	R3, CPSR
	MOVW	80(R0), R11
	MOVW	84(R0), R12
	MOVW	88(R0), R13
	MOVW	92(R0), R14
	MOVW	R11, SPSR
	/* abt */
	BIC	$(PsrMask), R2, R3
	ORR	$(PsrDirq|PsrMabt), R3
	MOVW	R3, CPSR
	MOVW	96(R0), R11
	MOVW	100(R0), R12
	MOVW	104(R0), R13
	MOVW	108(R0), R14
	MOVW	R11, SPSR
	/* fiq */
	BIC	$(PsrMask), R2, R3
	ORR	$(PsrDirq|PsrMfiq), R3
	MOVW	R3, CPSR
	MOVW	112(R0), R7
	MOVW	116(R0), R8
	MOVW	120(R0), R9
	MOVW	124(R0), R10
	MOVW	128(R0), R11
	MOVW	132(R0), R12
	MOVW	136(R0), R13
	MOVW	140(R0), R14
	MOVW	R7, SPSR
	/* svc */
	MOVW	56(R0), R1
	MOVW	60(R0), R2
	MOVW	R1, SPSR
	MOVW	R2, CPSR
	MOVW	0(R0), R1
	MOVW	4(R0), R2
	MOVW	8(R0), R3
	MOVW	12(R0),R4
	MOVW	16(R0),R5
	MOVW	20(R0),R6
	MOVW	24(R0),R7
	MOVW	28(R0),R8
	MOVW	32(R0),R9
	MOVW	36(R0),R10
	MOVW	40(R0),R11
	MOVW	44(R0),R12
	MOVW	48(R0),R13
	MOVW	52(R0),R14
	RET
loop:
	B	loop

/*
 * See page 9-26 of the SA1110 developer's manual
 */
TEXT	_idlemode(SB), $-4
	MOVW	$UCDRAMZERO, R1
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	MOVW	R0,R0
	/* the following must be on a cache line boundary */
	MCR		CpPWR, 0, R0, C(CpTest), C(0x2), 2	/* disable clock switching */
	MOVW	(R1), R0	/* non-cacheable memory read */
	MCR		CpPWR, 0, R0, C(CpTest), C(0x8), 2
	MCR		CpPWR, 0, R0, C(CpTest), C(0x2), 1	/* enable clock switching */
	RET
