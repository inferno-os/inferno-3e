/*
 * Memory Map (SA1100/SA1110)
 */

#define PCMCIAbase	0x20000000
#define PCMCIAsize	0x10000000
#define PCMCIAcard(n)	(PCMCIAbase+((n)*PCMCIAsize))
#define INTERNALbase	0x80000000
#define DRAMbase	0xC0000000
#define ZERObase	0xE0000000

#define SERIALbase(n)	(0x80000000+0x10000*(n))

#define PCMCIAIO(n)	(PCMCIAcard(n)+0x0)		/* I/O space */
#define PCMCIAAttr(n)	(PCMCIAcard(n)+0x8000000) /* Attribute space*/
#define PCMCIAMem(n)	(PCMCIAcard(n)+0xC000000) /* Memory space */


#define INTRREG 	((IntrReg*)(0x90050000))
typedef struct IntrReg IntrReg;
struct IntrReg {
	ulong	icip;	// IRQ pending
	ulong	icmr;	// mask
	ulong	iclr;	// level
	ulong	iccr;	// control
	ulong	icfp;	// FIQ pending
	ulong	rsvd[3];
	ulong	icpr;	// pending
};

#define GPIOvec(n)	((n)<11 ? n : n+(32-11))
#define GPIObit(n)	((n))			/* GPIO Edge Detect bits */
#define LCDbit		(12)			/* LCD Service Request */
#define UDCbit		(13)			/* UDC Service Request */
#define SDLCbit		(14)			/* SDLC Service Request */
#define UARTbit(n)	(15+((n)-1))		/* UART Service Request */
#define HSSPbit		(16)			/* HSSP Service Request */
#define MCPbit		(18)			/* MCP Service Request */
#define SSPbit		(19)			/* SSP Serivce Request */
#define DMAbit(chan)	(20+(chan))		/* DMA channel Request */
#define OSTimerbit(n)	(26+(n))		/* OS Timer Request */
#define RTCticbit	(30)			/* One Hz tic occured */
#define RTCalarmbit	(31)			/* RTC = alarm register */
#define MaxIRQbit	31			/* Maximum IRQ */
#define MaxGPIObit	27			/* Maximum GPIO */


#define GPIOREG		((GpioReg*)(0x90040000))
typedef struct GpioReg GpioReg;
struct GpioReg {
	ulong gplr;
	ulong gpdr;
	ulong gpsr;
	ulong gpcr;
	ulong grer;
	ulong gfer;
	ulong gedr;
	ulong gafr;
};

#define RTCREG		((RtcReg*)(0x90010000))
typedef struct RtcReg RtcReg;
struct RtcReg {
	ulong	rtar;	// alarm
	ulong	rcnr;	// count
	ulong	rttr;	// trim
	ulong	rsvd;
	ulong	rtsr;	// status
};

#define OSTMRREG	((OstmrReg*)(0x90000000))
typedef struct OstmrReg OstmrReg;
struct OstmrReg {
	ulong	osmr[4];	// match
	ulong	oscr;		// counter
	ulong	ossr;		// status
	ulong	ower;		// watchdog
	ulong	oier;		// interrupt enable
};

#define PMGRREG		((PmgrReg*)(0x90020000))
typedef struct PmgrReg PmgrReg;
struct PmgrReg {
	ulong	pmcr;	// ctl register
	ulong	pssr;	// sleep status
	ulong	pspr;	// scratch pad
	ulong	pwer;	// wakeup enable
	ulong	pcfr;	// general conf
	ulong	ppcr;	// PLL configuration
	ulong	pgsr;	// GPIO sleep state
	ulong	posr;	// oscillator status
};

#define RESETREG	((ResetReg*)(0x90030000))
typedef struct ResetReg ResetReg;
struct ResetReg {
	ulong	rsrr;	// software reset
	ulong	rcsr;	// status
	ulong	tucr;	// reserved for test
};

#define MEMCFGREG	((MemcfgReg*)(0xA0000000))
typedef struct MemcfgReg MemcfgReg;
struct MemcfgReg {
	ulong	mdcnfg;		// DRAM config
	ulong	mdcas0[3];	/* dram banks 0/1 */
	ulong	msc0;		/* static memory or devices */
	ulong	msc1;
	ulong	mecr;		/* expansion bus (pcmcia, CF) */
	ulong	mdrefr;		/* dram refresh */
	ulong	mdcas2[3];	/* dram banks 2/3 */
	ulong	msc2;		/* static memory or devices */
	ulong	smcnfg;		/* SMROM config */
};

#define DMAREG(n)	((DmaReg*)(0xB0000000+0x20*(n)))
typedef struct DmaReg DmaReg;
struct DmaReg {
	ulong	ddar;	// DMA device address
	ulong	dcsr_s;	// set 
	ulong	dcsr_c; // clear 
	ulong	dcsr;   // read
	struct {
		ulong	start;
		ulong	count;
	} buf[2];
};

#define LCDREG		((LcdReg*)(0xB0100000))
typedef struct LcdReg LcdReg;
struct LcdReg {
	ulong	lccr0;	// control 0
	ulong	lcsr;		// status 
	ulong	rsvd[2];
	ulong	dbar1;	// DMA chan 1, base
	ulong	dcar1;	// DMA chan 1, count
	ulong	dbar2;	// DMA chan 2, base
	ulong	dcar2;	// DMA chan 2, count
	ulong	lccr1;	// control 1
	ulong	lccr2;	// control 2
	ulong	lccr3;	// control 3
};

/* Serial devices:
 *	0	USB		Serial Port 0
 *	1	UART		\_ Serial Port 1
 *	2	SDLC		/
 *	3	UART		\_ Serial Port 2 (eia1)
 *	4	ICP/HSSP	/
 *	5	ICP/UART	Serial Port 3 (eia0)
 *	6	MPC		\_ Serial Port 4
 *	7	SSP		/
 */ 

#define USBREG	((UsbReg*)(0x80000000))
typedef struct UsbReg UsbReg;
struct UsbReg {
	ulong	udccr;	// control
	ulong	udcar;	// address
	ulong	udcomp;	// out max packet
	ulong	udcimp;	// in max packet
	ulong	udccs0;	// endpoint 0 control/status
	ulong	udccs1;	// endpoint 1(out) control/status
	ulong	udccs2;	// endpoint 2(int) control/status
	ulong	udcd0;	// endpoint 0 data register
	ulong	udcwc;	// endpoint 0 write control register
	ulong	rsvd1;
	ulong	udcdr;	// transmit/receive data register (FIFOs)
	ulong	rsvd2;
	ulong	dcsr;	// status/interrupt register
};

#define GPCLKREG	((GpclkReg*)0x80020060)
typedef struct GpclkReg GpclkReg;
struct GpclkReg {
	ulong	gpclkr0;
	ulong	rsvd[2];
	ulong	gpclkr1;
	ulong	gpclkr2;
};

/* UARTs 1, 2, 3 are mapped to serial devices 1, 3, and 5 */
#define UARTREG(n)	((UartReg*)(SERIALbase(2*(n)-1)))
typedef struct UartReg UartReg;
struct UartReg {
	ulong	utcr0;	// control 0 (bits, parity, clocks)
	ulong	utcr1;	// control 1 (bps div hi)
	ulong	utcr2;	// control 2 (bps div lo)
	ulong	utcr3;	// control 3
	ulong	utcr4;	// control 4 (only serial port 2 (device 3))
	ulong	utdr;	// data
	ulong	rsvd;
	ulong	utsr0;	// status 0
	ulong	utsr1;	// status 1
};

enum {
	UTCR0_PE=	0x01,
	UTCR0_OES=	0x02,
	UTCR0_SBS=	0x04,
	UTCR0_DSS=	0x08,
	UTCR0_SCE=	0x10,
	UTCR0_RCE=	0x20,
	UTCR0_TCE=	0x40,

	UTCR3_RXE=	0x01,
	UTCR3_TXE=	0x02,
	UTCR3_BRK=	0x04,
	UTCR3_RIM=	0x08,
	UTCR3_TIM=	0x10,
	UTCR3_LBM=	0x20,

	UTSR0_TFS=	0x01,
	UTSR0_RFS=	0x02,
	UTSR0_RID=	0x04,
	UTSR0_RBB=	0x08,
	UTSR0_REB=	0x10,
	UTSR0_EIF=	0x20,

	UTSR1_TBY=	0x01,
	UTSR1_RNE=	0x02,
	UTSR1_TNF=	0x04,
	UTSR1_PRE=	0x08,
	UTSR1_FRE=	0x10,
	UTSR1_ROR=	0x20,
};

#define HSSPREG		((HsspReg*)(0x80040060))
typedef struct HsspReg HsspReg;
struct HsspReg {
	ulong	hscr0;	// control 0
	ulong	hscr1;	// control 1
	ulong	rsvd1;
	ulong	hsdr;	// data
	ulong	rsvd2;
	ulong	hssr0;	// status 0
	ulong	hssr1;	// status 1
};

#define MCPREG		((McpReg*)(0x80060000))
typedef struct McpReg McpReg;
struct McpReg {
	ulong	mccr;
	ulong	rsvd1;
	ulong	mcdr0;
	ulong	mcdr1;
	ulong	mcdr2;
	ulong	rsvd2;
	ulong	mcsr;
};

enum {
	MCCR_M_LBM= 0x800000,
	MCCR_M_ARM= 0x400000,
	MCCR_M_ATM= 0x200000,
	MCCR_M_TRM= 0x100000,
	MCCR_M_TTM= 0x080000,
	MCCR_M_ADM= 0x040000,
	MCCR_M_ECS= 0x020000,
	MCCR_M_MCE= 0x010000,
	MCCR_V_TSD= 8,
	MCCR_V_ASD= 0,

	MCDR2_M_nRW= 0x010000,
	MCDR2_V_RN= 17,

	MCSR_M_TCE= 0x8000,
	MCSR_M_ACE= 0X4000,
	MCSR_M_CRC= 0x2000,
	MCSR_M_CWC= 0x1000,
	MCSR_M_TNE= 0x0800,
	MCSR_M_TNF= 0x0400,
	MCSR_M_ANE= 0x0200,
	MCSR_M_ANF= 0x0100,
	MCSR_M_TRO= 0x0080,
	MCSR_M_TTU= 0x0040,
	MCSR_M_ARO= 0x0020,
	MCSR_M_ATU= 0x0010,
	MCSR_M_TRS= 0x0008,
	MCSR_M_TTS= 0x0004,
	MCSR_M_ARS= 0x0002,
	MCSR_M_ATS= 0x0001,
};

#define SSPREG		((SspReg*)(0x80070060))
typedef struct SspReg SspReg;
struct SspReg {
	ulong	sscr0;	// control 0
	ulong	sscr1;	// control 1
	ulong	rsvd1;
	ulong	ssdr;	// data
	ulong	rsvd2;
	ulong	sssr;	// status
};


enum {
	SSCR0_V_SCR= 0x08,
	SSCR0_V_SSE= 0x07,
	SSCR0_V_ECS= 0x06,
	SSCR0_V_FRF= 0x04,

	SSPCR0_M_DSS= 0x0000000F,
	SSPCR0_M_FRF= 0x00000030,
	SSPCR0_M_SSE= 0x00000080,
	SSPCR0_M_SCR= 0x0000FF00,
	SSPCR0_V_DSS= 0,
	SSPCR0_V_FRF= 4,
	SSPCR0_V_SSE= 7,
	SSPCR0_V_SCR= 8,

	SSPCR1_M_RIM= 0x00000001,
	SSPCR1_M_TIN= 0x00000002,
	SSPCR1_M_LBM= 0x00000004,
	SSPCR1_V_RIM= 0,
	SSPCR1_V_TIN= 1,
	SSPCR1_V_LBM= 2,

	SSPSR_M_TNF= 0x00000002,
	SSPSR_M_RNE= 0x00000004,
	SSPSR_M_BSY= 0x00000008,
	SSPSR_M_TFS= 0x00000010,
	SSPSR_M_RFS= 0x00000020,
	SSPSR_M_ROR= 0x00000040,
	SSPSR_V_TNF= 1,
	SSPSR_V_RNE= 2,
	SSPSR_V_BSY= 3,
	SSPSR_V_TFS= 4,
	SSPSR_V_RFS= 5,
	SSPSR_V_ROR= 6,
};

#define PPCREG		((PpcReg*)(0x90060000))
typedef struct PpcReg PpcReg;
struct PpcReg {
	ulong	ppdr;	// pin direction
	ulong	ppsr;	// pin state
	ulong	ppar;	// pin assign
	ulong	psdr;	// sleep mode
	ulong	ppfr;	// pin flag reg
	uchar	rsvd[0x1c]; // pad to 0x30
	ulong	mccr1;	// MCP control register 1
};

enum {
	PPC_V_SPR= 18,
};

/*
 *	Irq Bus goo
 */

enum {
	BusCPU= 1,
	BusGPIOfalling= 2,	/* falling edge */
	BusGPIOrising = 3,	/* rising edge */
	BusGPIOboth = 4,	/* both edges */
	BusMAX= 4,
	BUSUNKNOWN= -1,
};
