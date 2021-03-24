/*
 * TDK LAC-CD021L ethernet PCMCIA card driver.
 */
#include <lib9.h>
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "etherif.h"

enum {
	tdk_debug=0
};

#define DPRINT if(tdk_debug)print
#define DPRINT1 if(tdk_debug > 1)print

/*
    card type
 */
typedef enum {
	MBH10302,
	MBH10304,
	TDK,
	CONTEC,
	LA501,
	sram_config = 0,
};


/*====================================================================*/
/* 
 *	io port offsets from the base address 
 */
enum {
	TX_STATUS =	0,	/* transmit status register */
	RX_STATUS =	1,	/* receive status register */
	TX_INTR =	2,	/* transmit interrupt mask register */
	RX_INTR =	3,	/* receive interrupt mask register */
	TX_MODE =	4,	/* transmit mode register */
	RX_MODE =	5,	/* receive mode register */
	CONFIG_0 =	6,	/* configuration register 0 */
	CONFIG_1 =	7,	/* configuration register 1 */

	NODE_ID =	8,	/* node ID register            (bank 0) */
	MAR_ADR =	8,	/* multicast address registers (bank 1) */

	DATAPORT =	8,	/* buffer mem port registers   (bank 2) */
	TX_START =	10,	/* transmit start register */
	COL_CTRL =	11,	/* 16 collision control register */
	BMPR12 =	12,	/* reserved */
	BMPR13 =	13,	/* reserved */
	RX_SKIP =	14,	/* skip received packet register */

	LAN_CTRL =	16,	/* LAN card control register */

	MAC_ID =	0x1a,	/* hardware address */
};

/* 
    TX status & interrupt enable bits 
 */
enum {
	TX_TMT_OK =	0x80,
	TX_NET_BSY =	0x40,	/* carrier is detected */
	TX_ERR =	0x10,
	TX_COL =	0x04,
	TX_16_COL =	0x02,
	TX_TBUS_ERR =	0x01,
};

/* 
    RX status & interrupt enable bits 
 */

enum {
	RX_PKT_RDY =	0x80,	/* packet(s) in buffer */
	RX_BUS_ERR =	0x40,	/* bus read error */
	RX_DMA_EOP =	0x20,
	RX_LEN_ERR =	0x08,	/* short packet */
	RX_ALG_ERR =	0x04,	/* frame error */
	RX_CRC_ERR =	0x02,	/* CRC error */
	RX_OVR_FLO =	0x01,	/* overflow error */

};

/*
 * Receiver mode 
 */
enum {
	RM_BUF_EMP =	0x40 /* receive buffer is empty */
};

/*
 * Receiver pointer control
 */
enum {
	RP_SKP_PKT =	0x05 /* drop packet in buffer */
};

/* default bitmaps */
#define D_TX_INTR  ( TX_TMT_OK )
#define D_RX_INTR  ( RX_PKT_RDY | RX_LEN_ERR \
		   | RX_ALG_ERR | RX_CRC_ERR | RX_OVR_FLO )
#define TX_STAT_M  ( TX_TMT_OK )
#define RX_STAT_M  ( RX_PKT_RDY | RX_LEN_ERR \
                   | RX_ALG_ERR | RX_CRC_ERR | RX_OVR_FLO )

/* RX & TX mode settings */
enum {
	D_TX_MODE =	0x06,	/* no tests, detect carrier */
	ID_MATCHED =	0x02,	/* (RX_MODE) */
	RECV_ALL =	0x03,	/* (RX_MODE) */
};

/*
 * config_0
 */
enum {
	CONFIG0_DFL =	0x5a,	/* 16bit bus, 4K x 2 Tx queues */
	CONFIG0_DFL_1 =	0x5e,	/* 16bit bus, 8K x 2 Tx queues */
	CONFIG0_RST =	0xda,	/* Data Link Controler off (CONFIG_0) */
	CONFIG0_RST_1 =	0xde,	/* Data Link Controler off (CONFIG_0) */
};
/*
 * config_1
 */
enum {
	BANK_0 = 	0xa0, /* bank 0 (CONFIG_1) */
	BANK_1 = 	0xa4, /* bank 1 (CONFIG_1) */
	BANK_2 = 	0xa8, /* bank 2 (CONFIG_1) */
	CHIP_OFF = 	0x80, /* contrl chip power off (CONFIG_1) */
};

enum {
/* TX_START */
	DO_TX =		0x80,	/* do transmit packet */
	SEND_PKT =	0x81,	/* send a packet */
/* COL_CTRL */
	AUTO_MODE =	0x07,	/* Auto skip packet on 16 col detected */
	MANU_MODE =	0x03,	/* Stop and skip packet on 16 col */
	TDK_AUTO_MODE =	0x47,	/* Auto skip packet on 16 col detected */
	TDK_MANU_MODE =	0x43,	/* Stop and skip packet on 16 col */

/* LAN_CTRL */
	INTR_OFF =	0x0d,	/* LAN controler ignores interrupts */
	INTR_ON =	0x1d,	/* LAN controler will catch interrupts */
};

typedef struct {
	int	config0_dfl;
	int	config0_rst;
	int	sram;
} Ctlr;


static void
attach(Ether* ether)
{
	int port, crap;
	Ctlr *ctlr;

	ctlr = ether->ctlr;
	port = ether->port;

	/*
	 * Set the receiver packet filter for this and broadcast addresses,
	 * set the interrupt masks for all interrupts, enable the receiver
	 * and transmitter.
	 */
        outb(port + RX_MODE, ID_MATCHED);
        // outb(port + RX_MODE, RECV_ALL);

	/* reset Skip packet reg. */
	outb(port + RX_SKIP, 0x01);

	/* Enable Tx and Rx */
	outb(port + CONFIG_0, ctlr->config0_dfl);

	/* Init receive pointer ? */
	crap = ins(port + DATAPORT); USED(crap);
	crap = ins(port + DATAPORT); USED(crap);

	/* Clear all status */
	outb(port + TX_STATUS, 0xff);
	outb(port + RX_STATUS, 0xff);
}

static int
transmit(uchar *d, uint len)
{
	int port;
	Ctlr *ctlr;
	Ether *ether = &eth0;

	port = ether->port;
	ctlr = ether->ctlr;

	while((inb(port + TX_START) & 0x7f) != 0) 
		continue;

	if (len < ETHERMINTU)
		outs(port + DATAPORT, ETHERMINTU);
	else
		outs(port + DATAPORT, len);

	len = ROUNDUP(len, 2);
	outss(port + DATAPORT, d, len/2);
	while (len < ETHERMINTU)
	{
		outs(port + DATAPORT, 0);
		len += 2;
	}

	outb(port + TX_START, DO_TX | 1);

	/*	
	while(!(inb(port+TX_STATUS) & TX_TMT_OK))
		continue;
	*/
	
	return len;
}


static int
poll(uchar *pkt)
{
	Ether *ether = &eth0;
	int len, port, rxstatus;

	port = ether->port;

	while ((inb(port + RX_MODE) & RM_BUF_EMP) == 0) {
	
		rxstatus = ins(port + DATAPORT);

		DPRINT1("tdk rxing packet mode %2.2x rxstatus %4.4x.\n",
			inb(port + RX_MODE), rxstatus);

		if(rxstatus == 0) {
			outb(port + RX_SKIP, RP_SKP_PKT);
			continue;
		}

		if ((rxstatus & 0xF0) != RX_DMA_EOP) {    /* There was an error. */
			/*
			if (rxstatus & RX_LEN_ERR) ether->buffs++;
			if (rxstatus & RX_ALG_ERR) ether->frames++;
			if (rxstatus & RX_CRC_ERR) ether->crcs++;
			if (rxstatus & RX_OVR_FLO) ether->overflows++;
			*/
			continue;
		}

		len = ins(port + DATAPORT);

		if (len > sizeof(Etherpkt)) {
			/* print("LAC-CD021L claimed a very large packet, size %d.\n",
				len);
			*/
			outb(port + RX_SKIP, RP_SKP_PKT);
			/* ether->buffs++; */
			continue;
		}
 
		inss(port + DATAPORT, pkt, HOWMANY(len, 2));

		return len;
	}
	return 0;
}


static void
tdkcis(int slot, uchar *bp)
{
	Ether *ether = &eth0;
	int nb;

	DPRINT1("ET: %2.2x d[0-2]: %2.2x %2.2x %2.2x\n", bp[0], bp[2], bp[3], bp[4]);
	switch(bp[0])
	{
	case 0x22:		/* LAN info, Node address */
		if (bp[2] != 4)
			break;
		nb = bp[3];
		if (nb > nelem(ether->ea))
			nb = nelem(ether->ea);
		memmove(ether->ea, &bp[4], nb);
		DPRINT("ID from card: %2.2x %2.2x %2.2x %2.2x %2.2x %2.2x\n",
			ether->ea[0], ether->ea[1], ether->ea[2],
			ether->ea[3], ether->ea[4], ether->ea[5]);
		break;
	}
}

int
ethertdkreset(Ether* ether)
{
	int i, port;
	uchar ea[Eaddrlen];
	Ctlr *ctlr;

	port = ether->port;

	/*
	 * Allocate a controller structure, clear out the
	 * adapter statistics, clear the statistics logged into ctlr
	 * and enable statistics collection. Xcvr is needed in order
	 * to collect the BadSSD statistics.
	 */
	ether->ctlr = ctlr = malloc(sizeof(Ctlr));

	if( sram_config == 0 )
	{
		ctlr->sram = 4096;
		ctlr->config0_dfl =  CONFIG0_DFL;	/* 4K sram */
		ctlr->config0_rst =  CONFIG0_RST;
	}
	else
	{
		ctlr->sram = 8192;
		ctlr->config0_dfl =  CONFIG0_DFL_1;	/* 8K sram */
		ctlr->config0_rst =  CONFIG0_RST_1;
	}

	outb(port + CONFIG_0, ctlr->config0_rst);
	/*
	 * Check if the adapter's station address is to be overridden.
	 * If not, read it from the card and set in ether->ea prior to loading the
	 * station address.
	 */
	memset(ea, 0, Eaddrlen);

	if(memcmp(ea, ether->ea, Eaddrlen) == 0){
		DPRINT("Read ethernet card cis\n");
		cisread(ether->pcmslot, tdkcis);
	}

	/* Set hardware address */
	for (i = 0; i < 6; i++)
		outb(port + NODE_ID + i, ether->ea[i]);

	/* Switch to bank 1 */
	outb(port + CONFIG_1, BANK_1);

	/* set the multicast table to accept none. */
	for (i = 0; i < 6; i++)
		outb(port + MAR_ADR + i, 0x00);

	/* Switch to bank 2 (runtime mode) */
	outb(port + CONFIG_1, BANK_2);

	/* set 16col ctrl bits */
	outb(port + COL_CTRL, TDK_AUTO_MODE); 

	/* clear Reserved Regs */
	outb(port + BMPR12, 0x00);
	outb(port + BMPR13, 0x00);
 
	/*
	 * Linkage to the generic ethernet driver.
	 */
	ether->port = port;
	ether->transmit = transmit;
	ether->poll = poll;

	return 0;
}

static int
tdkreset(Ether *ether)
{
	int slot;
	int port;

	if(ether->port == 0)
		ether->port = 0x240;

	slot = pcmspecial("LAC-CD02x", ether);
	DPRINT("Ethernet found in slot #%d\n",slot);
	if(slot < 0)
		return -1;

	ether->pcmslot = slot;

	port = ether->port;

	if(ethertdkreset(ether) < 0){
		print("ethertdk driver did not reset\n");
		pcmspecialclose(slot);
		return -1;
	}

	attach(ether);

	return 0;
}


void
ethertdklink(void)
{
	addethercard("tdk",  tdkreset);
}
