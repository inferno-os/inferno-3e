/*
 * Memory and machine-specific definitions.  Used in C and assembler.
 */

/*
 * Sizes
 */
#define	BI2BY		8			/* bits per byte */
#define BI2WD		32			/* bits per word */
#define	BY2WD		4			/* bytes per word */
#define	BY2V		8			/* bytes per double word */
#define	BY2PG		4096			/* bytes per page */
#define	WD2PG		(BY2PG/BY2WD)		/* words per page */
#define	PGSHIFT		12			/* log(BY2PG) */
#define ROUND(s, sz)	(((s)+(sz-1))&~(sz-1))
#define PGROUND(s)	ROUND(s, BY2PG)
#define BIT(n)		(1<<n)
#define BITS(a,b)	((1<<(b+1))-(1<<a))

#define	MAXMACH		1			/* max # cpus system can run */

/*
 * Time
 */
#define	HZ		(100)			/* clock frequency */
#define	MS2HZ		(1000/HZ)		/* millisec per clock tick */
#define	TK2SEC(t)	((t)/HZ)		/* ticks to seconds */
#define	TK2MS(t)	((t)*MS2HZ)		/* ticks to milliseconds */
#define	MS2TK(t)	((t)/MS2HZ)		/* milliseconds to ticks */

/*
 * More accurate time
 */
#define TIMER_HZ	3686400
#define MS2TMR(t)	((ulong)(((uvlong)(t)*TIMER_HZ)/1000))
#define US2TMR(t)	((ulong)(((uvlong)(t)*TIMER_HZ)/1000000))

/*
 *  Address spaces
 *	nearly everything maps 1-1 with physical addresses
 *	0 to 1Mb is not mapped
 *	cache strategy varies as needed (see mmu.c)
 */

#define KZERO		0xC0000000
#define MACHADDR	(KZERO+0x00001000)
#define KTTB		(KZERO+0x00004000)
#define KTZERO	(KZERO+0x00008010)
#define KSTACK	8192			/* Size of kernel stack */
#define FLUSHMEM	0xE0000000	/* internally decoded memory (for cache flushing) */
#define DCFADDR	FLUSHMEM	/* cached and buffered for cache writeback */
#define MCFADDR	(FLUSHMEM+(1<<20))	/* cached and unbuffered for minicache writeback */
#define UCDRAMZERO	0xC8000000	/* base of memory doubly-mapped as uncached */
#define FLASHMEM	0x50000000	/* map flash at phys 0 to otherwise unused virtual space */

#define PHYSMEM0	0xC0000000	/* physical memory base */

#define	CACHELINELOG	5
#define	CACHELINESZ	(1<<CACHELINELOG)

/*
 * PSR
 */
#define PsrMusr		0x10 	/* mode */
#define PsrMfiq		0x11 
#define PsrMirq		0x12
#define PsrMsvc		0x13
#define PsrMabt		0x17
#define PsrMund		0x1B
#define PsrMsys		0x1F
#define PsrMask		0x1F

#define PsrDfiq		0x00000040	/* disable FIQ interrupts */
#define PsrDirq		0x00000080	/* disable IRQ interrupts */

#define PsrV		0x10000000	/* overflow */
#define PsrC		0x20000000	/* carry/borrow/extend */
#define PsrZ		0x40000000	/* zero */
#define PsrN		0x80000000	/* negative/less than */

/*
 * Internal MMU coprocessor registers
 */
#define CpCPUID		0		/* R: */
#define CpControl	1		/* R: */
#define CpTTB		2		/* W: translation table base */
#define CpDAC		3		/* W: domain access control */
#define CpFSR		5		/* R: fault status */
#define CpFAR		6		/* R: fault address */
#define CpCacheCtl	7		/* W: */
#define CpTLBops	8		/* W: TLB operations */
#define CpPID		13		/* R/W: Process ID Virtual Mapping */
#define CpDebug	14		/* R/W: debug registers */
#define CpTest		15		/* W: Test, Clock and Idle Control */

/*
 * Coprocessors
 */
#define CpMMU		15
#define CpPWR		15

/*
 * Internal MMU coprocessor registers
 */

/*
 * CpControl bits
 */
#define CpCmmu		0x00000001	/* M: MMU enable */
#define CpCalign	0x00000002	/* A: alignment fault enable */
#define CpCDcache	0x00000004	/* C: instruction/data cache on */
#define CpCwb		0x00000008	/* W: write buffer turned on */
#define CpCi32		0x00000010	/* P: 32-bit programme space */
#define CpCd32		0x00000020	/* D: 32-bit data space */
#define CpCbe		0x00000080	/* B: big-endian operation */
#define CpCsystem	0x00000100	/* S: system permission */
#define CpCrom		0x00000200	/* R: ROM permission */
#define CpCIcache	0x00001000	/* C: Instruction Cache on */
#define CpCaltivec	0x00002000	/* X: alternate interrupt vectors */

/*
 * Debug support internal registers
 */
#define CpDBAR	0
#define CpDBVR	1
#define CpDBMR	2
#define CpDBCR	3
#define CpIBCR	8

/*
 * alternate interupt vectors
 */
#define ALT_IVEC	0xFFFF0000

/*
 * MMU
 */
/*
 * Small pages:
 *	L1: 12-bit index -> 4096 descriptors -> 16Kb
 *	L2:  8-bit index ->  256 descriptors ->  1Kb
 * Each L2 descriptor has access permissions for 4 1Kb sub-pages.
 *
 *	TTB + L1Tx gives address of L1 descriptor
 *	L1 descriptor gives PTBA
 *	PTBA + L2Tx gives address of L2 descriptor
 *	L2 descriptor gives PBA
 */
#define MmuSection	(1<<20)
#define MmuLargePage	(1<<16)
#define MmuSmallPage	(1<<12)
#define MmuTTB(pa)	((pa) & ~0x3FFF)	/* translation table base */
#define MmuL1x(pa)	(((pa)>>20) & 0xFFF)	/* L1 table index */
#define MmuPTBA(pa)	((pa) & ~0x3FF)		/* page table base address */
#define MmuL2x(pa)	(((pa)>>12) & 0xFF)	/* L2 table index */
#define MmuPBA(pa)	((pa) & ~0xFFF)		/* page base address */
#define MmuSBA(pa)	((pa) & ~0xFFFFF)	/* section base address */

#define MmuL1type	0x03
#define MmuL1page	0x01			/* descriptor is for L2 pages */
#define MmuL1section	0x02			/* descriptor is for section */

#define MmuL2invalid	0x000
#define MmuL2large	0x001			/* large */
#define MmuL2small	0x002			/* small */
#define MmuWB		0x004			/* data goes through write buffer */
#define MmuIDC		0x008			/* data placed in cache */

#define MmuDAC(d)	(((d) & 0xF)<<5)	/* L1 domain */
#define MmuAP(i, v)	((v)<<(((i)*2)+4))	/* access permissions */
#define MmuL1AP(v)	MmuAP(3, (v))
#define MmuL2AP(v)	MmuAP(3, (v))|MmuAP(2, (v))|MmuAP(1, (v))|MmuAP(0, (v))
#define MmuAPsro	0			/* supervisor ro if S|R */
#define MmuAPsrw	1			/* supervisor rw */
#define MmuAPuro	2			/* supervisor rw + user ro */
#define MmuAPurw	3			/* supervisor rw + user rw */

/*
 * Memory Interface Control Registers
 */
#define	MDCNFG	0xA0000000
#define	MDCAS0	0xA0000004
#define	MDCAS1	0xA0000008
#define	MDCAS2	0xA000000C
#define	MSC0	0xA0000010
#define	MSC1	0xA0000014
#define	MSC2	0xA000002C	/* SA1110, not SA1100 */

#define	MSCx(RRR, RDN, RDF, RBW, RT)	((((RRR)&0x7)<<13)|(((RDN)&0x1F)<<8)|(((RDF)&0x1F)<<3)|(((RBW)&1)<<2)|((RT)&3))
