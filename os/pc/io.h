#define X86STEPPING(x)	((x) & 0x0F)
#define X86MODEL(x)	(((x)>>4) & 0x0F)
#define X86FAMILY(x)	(((x)>>8) & 0x0F)

enum {
	VectorBPT	= 3,		/* breakpoint */
	VectorCNA	= 7,		/* coprocessor not available */
	VectorCSO	= 9,		/* coprocessor segment overrun */
	VectorPF	= 14,		/* page fault */
	VectorCERR	= 16,		/* coprocessor error */

	VectorLAPIC	= 32,		/* local APIC interrupts */
	VectorLINT0	= VectorLAPIC+0,/* LINT[01] must be offsets 0 and 1 */
	VectorLINT1	= VectorLAPIC+1,
	VectorTIMER	= VectorLAPIC+2,
	VectorERROR	= VectorLAPIC+3,
	VectorPCINT	= VectorLAPIC+4,
	VectorSPURIOUS	= VectorLAPIC+15,/* must have bits [3-0] == 0x0F */
	MaxVectorLAPIC	= VectorLAPIC+15,

	VectorSYSCALL	= 64,

	VectorPIC	= 128,		/* external [A]PIC interrupts */
	VectorCLOCK	= VectorPIC+0,
	VectorKBD	= VectorPIC+1,
	VectorUART1	= VectorPIC+3,
	VectorUART0	= VectorPIC+4,
	VectorPCMCIA	= VectorPIC+5,
	VectorBUSMOUSE	= VectorPIC+5,		/* clash with PCMCIA */
	VectorFLOPPY	= VectorPIC+6,
	VectorLPT	= VectorPIC+7,
	VectorIRQ7	= VectorPIC+7,
	VectorAUX	= VectorPIC+12,	/* PS/2 port */
	VectorIRQ13	= VectorPIC+13,	/* coprocessor on x386 */
	VectorATA0	= VectorPIC+14,
	MaxVectorPIC	= VectorPIC+15,
};

enum {
	BusCBUS		= 0,		/* Corollary CBUS */
	BusCBUSII,			/* Corollary CBUS II */
	BusEISA,			/* Extended ISA */
	BusFUTURE,			/* IEEE Futurebus */
	BusINTERN,			/* Internal bus */
	BusISA,				/* Industry Standard Architecture */
	BusMBI,				/* Multibus I */
	BusMBII,			/* Multibus II */
	BusMCA,				/* Micro Channel Architecture */
	BusMPI,				/* MPI */
	BusMPSA,			/* MPSA */
	BusNUBUS,			/* Apple Macintosh NuBus */
	BusPCI,				/* Peripheral Component Interconnect */
	BusPCMCIA,			/* PC Memory Card International Association */
	BusTC,				/* DEC TurboChannel */
	BusVL,				/* VESA Local bus */
	BusVME,				/* VMEbus */
	BusXPRESS,			/* Express System Bus */
};

#define MKBUS(t,b,d,f)	(((t)<<24)|(((b)&0xFF)<<16)|(((d)&0x1F)<<11)|(((f)&0x07)<<8))
#define BUSFNO(tbdf)	(((tbdf)>>8)&0x07)
#define BUSDNO(tbdf)	(((tbdf)>>11)&0x1F)
#define BUSBNO(tbdf)	(((tbdf)>>16)&0xFF)
#define BUSTYPE(tbdf)	((tbdf)>>24)
#define BUSBDF(tbdf)	((tbdf)&0x00FFFF00)
#define BUSUNKNOWN	(-1)

enum {
	MaxEISA		= 16,
	CfgEISA		= 0xC80,
};

/*
 * PCI support code.
 */
enum {					/* type 0 and type 1 pre-defined header */
	PciVID		= 0x00,		/* vendor ID */
	PciDID		= 0x02,		/* device ID */
	PciPCR		= 0x04,		/* command */
	PciPSR		= 0x06,		/* status */
	PciRID		= 0x08,		/* revision ID */
	PciCCRp		= 0x09,		/* programming interface class code */
	PciCCRu		= 0x0A,		/* sub-class code */
	PciCCRb		= 0x0B,		/* base class code */
	PciCLS		= 0x0C,		/* cache line size */
	PciLTR		= 0x0D,		/* latency timer */
	PciHDT		= 0x0E,		/* header type */
	PciBST		= 0x0F,		/* BIST */

	PciBAR0		= 0x10,		/* base address */
	PciBAR1		= 0x14,

	PciINTL		= 0x3C,		/* interrupt line */
	PciINTP		= 0x3D,		/* interrupt pin */
};

enum {					/* type 0 pre-defined header */
	PciBAR2		= 0x18,
	PciBAR3		= 0x1C,
	PciBAR4		= 0x20,
	PciBAR5		= 0x24,
	PciCIS		= 0x28,		/* cardbus CIS pointer */
	PciSVID		= 0x2C,		/* subsystem vendor ID */
	PciSID		= 0x2E,		/* cardbus CIS pointer */
	PciEBAR0	= 0x30,		/* expansion ROM base address */
	PciMGNT		= 0x3E,		/* burst period length */
	PciMLT		= 0x3F,		/* maximum latency between bursts */
};

enum {					/* type 1 pre-defined header */
	PciPBN		= 0x18,		/* primary bus number */
	PciSBN		= 0x19,		/* secondary bus number */
	PciUBN		= 0x1A,		/* subordinate bus number */
	PciSLTR		= 0x1B,		/* secondary latency timer */
	PciIBR		= 0x1C,		/* I/O base */
	PciILR		= 0x1D,		/* I/O limit */
	PciSPSR		= 0x1E,		/* secondary status */
	PciMBR		= 0x20,		/* memory base */
	PciMLR		= 0x22,		/* memory limit */
	PciPMBR		= 0x24,		/* prefetchable memory base */
	PciPMLR		= 0x26,		/* prefetchable memory limit */
	PciPUBR		= 0x28,		/* prefetchable base upper 32 bits */
	PciPULR		= 0x2C,		/* prefetchable limit upper 32 bits */
	PciIUBR		= 0x30,		/* I/O base upper 16 bits */
	PciIULR		= 0x32,		/* I/O limit upper 16 bits */
	PciEBAR1	= 0x28,		/* expansion ROM base address */
	PciBCR		= 0x3E,		/* bridge control register */
};

enum {					/* type 2 pre-defined header */
	PciCBExCA	= 0x10,
	PciCBSPSR	= 0x16,
	PciCBPBN	= 0x18,		/* primary bus number */
	PciCBSBN	= 0x19,		/* secondary bus number */
	PciCBUBN	= 0x1A,		/* subordinate bus number */
	PciCBSLTR	= 0x1B,		/* secondary latency timer */
	PciCBMBR0	= 0x1C,
	PciCBMLR0	= 0x20,
	PciCBMBR1	= 0x24,
	PciCBMLR1	= 0x28,
	PciCBIBR0	= 0x2C,		/* I/O base */
	PciCBILR0	= 0x30,		/* I/O limit */
	PciCBIBR1	= 0x34,		/* I/O base */
	PciCBILR1	= 0x38,		/* I/O limit */
	PciCBSVID	= 0x40,		/* subsystem vendor ID */
	PciCBSID	= 0x42,		/* subsystem ID */
	PciCBLMBAR	= 0x44,		/* legacy mode base address */
};

typedef struct Pcisiz Pcisiz;
struct Pcisiz
{
	Pcidev*	dev;
	int	siz;
	int	bar;
};

typedef struct Pcidev Pcidev;
struct Pcidev
{
	int	tbdf;			/* type+bus+device+function */
	ushort	vid;			/* vendor ID */
	ushort	did;			/* device ID */

	uchar	rid;
	uchar	ccrp;
	uchar	ccru;
	uchar	ccrb;

	struct {
		ulong	bar;		/* base address */
		int	size;
	} mem[6];

	uchar	intl;			/* interrupt line */

	Pcidev*	list;
	Pcidev*	link;			/* next device on this bno */

	Pcidev*	bridge;			/* down a bus */
	struct {
		ulong	bar;
		int	size;
	} ioa, mema;
	ulong	pcr;
};

#define PCIWINDOW	0
#define PCIWADDR(va)	(PADDR(va)+PCIWINDOW)
#define ISAWINDOW	0
#define ISAWADDR(va)	(PADDR(va)+ISAWINDOW)

/* SMBus transactions */
enum
{
	SMBquick,		/* sends address only */

	/* write */
	SMBsend,		/* sends address and cmd */
	SMBbytewrite,		/* sends address and cmd and 1 byte */
	SMBwordwrite,		/* sends address and cmd and 2 bytes */

	/* read */
	SMBrecv,		/* sends address, recvs 1 byte */
	SMBbyteread,		/* sends address and cmd, recv's byte */
	SMBwordread,		/* sends address and cmd, recv's 2 bytes */
};

typedef struct SMBus SMBus;
struct SMBus {
	QLock;		/* mutex */
	Rendez	r;	/* rendezvous point for completion interrupts */
	void	*arg;	/* implementation dependent */
	ulong	base;	/* port or memory base of smbus */
	int	busy;
	void	(*transact)(SMBus*, int, int, int, uchar*);
};

/*
 * PCMCIA support code.
 */
/*
 * Map between ISA memory space and PCMCIA card memory space.
 */
struct PCMmap
{
	ulong	ca;			/* card address */
	ulong	cea;			/* card end address */
	ulong	isa;			/* ISA address */
	int	len;			/* length of the ISA area */
	int	attr;			/* attribute memory */
	int	ref;
};

/*
 *  SCSI bus
 */
enum {
	MaxScsi		= 8,
	NTarget		= 8,		/* should be 16... */
};

typedef struct Target Target;
struct Target {
	int	ctlrno;
	int	target;
	uchar*	inq;
	uchar*	scratch;

	Rendez	rendez;

	int	ok;
};

typedef int (*Scsiio)(Target*, int, uchar*, int, void*, int*);

typedef struct SCSIdev {
	char*	type;
	Scsiio	(*reset)(int, ISAConf*);
} SCSIdev;
void	addscsilink(SCSIdev*);
