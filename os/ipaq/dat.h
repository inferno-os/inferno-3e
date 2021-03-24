typedef struct Conf	Conf;
typedef struct Dma	Dma;
typedef struct FPU	FPU;
typedef struct FPenv	FPenv;
typedef struct Label	Label;
typedef struct Lock	Lock;
typedef struct Mach	Mach;
typedef struct Ureg	Ureg;
typedef struct ISAConf	ISAConf;
typedef struct PCMconftab PCMconftab;
typedef struct PCMmap	PCMmap;
typedef struct PCMslot	PCMslot;
typedef struct PCIcfg	PCIcfg;
typedef struct Vmode Vmode;

typedef ulong Instr;

#define NISAOPT 8
struct Conf
{
	ulong	nmach;			/* processors */
	ulong	nproc;			/* processes */
	ulong	npage0;			/* total physical pages of memory */
	ulong	npage1;			/* total physical pages of memory */
	ulong	topofmem;		/* highest physical address + 1 */
	ulong	npage;			/* total physical pages of memory */
	ulong	base0;			/* base of bank 0 */
	ulong	base1;			/* base of bank 1 */
	ulong	ialloc;			/* max interrupt time allocation in bytes */
	ulong	interps;			/* number of interpreter processes */
	ulong	flashbase;
	ulong	cpuspeed;

	int		useminicache;		/* use mini cache: screen.c/lcd.c */
	int		cansetbacklight;	/* screen.c/lcd.c */
	int		cansetcontrast;		/* screen.c/lcd.c */
	int		textwrite;			/* writeable text segment, for debug */
	int	portrait;	/* display orientation */
};

struct ISAConf {
	char	type[NAMELEN];
	ulong	port;
	ulong	irq;
	int	itype;
	ulong	dma;
	ulong	mem;
	ulong	size;
	ulong	freq;

	int	nopt;
	char	*opt[NISAOPT];
};

/*
 * FPenv.status
 */
enum
{
	FPINIT,
	FPACTIVE,
	FPINACTIVE,
};

struct	FPenv
{
	ulong	status;
	ulong	control;
	ushort	fpistate;	/* emulated fp */
	ulong	regs[8][3];	/* emulated fp */	
};

/*
 * This structure must agree with fpsave and fprestore asm routines
 */
struct	FPU
{
	FPenv	env;
};

struct Label
{
	ulong	sp;
	ulong	pc;
};

struct Lock
{
	ulong	key;
	ulong	sr;
	ulong	pc;
	int	pri;
};

#include "../port/portdat.h"

/*
 *  machine dependent definitions not used by ../port/dat.h
 */
struct Mach
{
	/* OFFSETS OF THE FOLLOWING KNOWN BY l.s */
	ulong	splpc;		/* pc of last caller to splhi */

	/* ordering from here on irrelevant */

	ulong	ticks;			/* of the clock since boot time */
	Proc	*proc;			/* current process on this processor */
	Label	sched;			/* scheduler wakeup */
	Lock	alarmlock;		/* access to alarm list */
	void	*alarm;			/* alarms bound to this clock */
	int	nrdy;

	/* stacks for exceptions */
	ulong	fiqstack[4];
	ulong	irqstack[4];
	ulong	abtstack[4];
	ulong	undstack[4];

	int	stack[1];
};

#define	MACHP(n)	(n == 0 ? (Mach*)(MACHADDR) : (Mach*)0)

extern Mach *m;
extern Proc *up;

typedef struct MemBank {
	uint	pbase;
	uint	plimit;
	uint	vbase;
	uint	vlimit;
} MemBank;

/*
 * Layout at virtual address 0.
 */
typedef struct Page0 {
	void	(*vectors[8])(void);
	uint	vtable[8];

	uint	stacks[0x20][4];

	uint	ttb;
	uint	ttbsize;

	MemBank membank[4];
} Page0;
extern Page0 *page0;

enum {
	// DMA configuration parameters

	 // DMA Direction
	DmaOUT=		0,
	DmaIN=		1,

	 // dma endianess
	DmaLittle=	0,
	DmaBig=		1,

	 // dma devices
	DmaUDC=		0,
	DmaSDLC=	2,
	DmaUART0=	4,
	DmaHSSP=	6,
	DmaUART1=	7,	// special case (is really 6)
	DmaUART2=	8,
	DmaMCPaudio=	10,
	DmaMCPtelecom=	12,
	DmaSSP=		14,
};

/*
 *	Interface to PCMCIA stubs
 */
enum {
	/* argument to pcmpin() */
	PCMready,
	PCMeject,
	PCMstschng,
};

/*
 * PCMCIA structures known by both port/cis.c and the pcmcia driver
 */

/*
 * Map between ISA memory space and PCMCIA card memory space.
 */
struct PCMmap {
	ulong	ca;			/* card address */
	ulong	cea;			/* card end address */
	ulong	isa;			/* local virtual address */
	int	len;			/* length of the ISA area */
	int	attr;			/* attribute memory */
};

/*
 *  a PCMCIA configuration entry
 */
struct PCMconftab
{
	int	index;
	ushort	irqs;		/* legal irqs */
	uchar	irqtype;
	uchar	bit16;		/* true for 16 bit access */
	struct {
		ulong	start;
		ulong	len;
	} io[16];
	int	nio;
	uchar	vpp1;
	uchar	vpp2;
	uchar	memwait;
	ulong	maxwait;
	ulong	readywait;
	ulong	otherwait;
};

/*
 *  PCMCIA card slot
 */
struct PCMslot
{
	RWlock;

	Ref	ref;

	long	memlen;		/* memory length */
	uchar	slotno;		/* slot number */
	void	*regs;		/* i/o registers */
	void	*mem;		/* memory */
	void	*attr;		/* attribute memory */

	/* status */
	uchar	occupied;	/* card in the slot */
	uchar	configed;	/* card configured */
	uchar	busy;
	uchar	powered;
	uchar	battery;
	uchar	wrprot;
	uchar	enabled;
	uchar	special;
	uchar	dsize;

	/* cis info */
	int	cisread;	/* set when the cis has been read */
	char	verstr[512];	/* version string */
	uchar	cpresent;	/* config registers present */
	ulong	caddr;		/* relative address of config registers */
	int	nctab;		/* number of config table entries */
	PCMconftab	ctab[8];
	PCMconftab	*def;		/* default conftab */

	/* maps are fixed */
	PCMmap memmap;
	PCMmap attrmap;
};

#define	swcursor	1
