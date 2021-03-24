/*
 * USB client-mode driver
 *	endpoint 0	control (read and write)
 *	endpoint 1	OUT bulk endpoint (host to us)
 *	endpoint 2	IN bulk or interrupt endpoint (us to host)
 *
 * this is similar to the SA1100 assignment, and
 * sufficient to run Styx over USB, or to emulate simple devices.
 * the 823 USB implementation would allow a further endpoint,
 * and endpoints could have both IN and OUT modes.
 *
 * to do:
 *	full flow control
 *	data toggle control
 */
#include	"boot.h"

#include	"usb.h"

enum {
	LOWSPEED = 0,	/* zero for 12m/bit, one for 1.5m/bit */
	Chatty = 1,	/* debugging */
};

typedef struct USBparam USBparam;
struct USBparam {
	ushort	epptr[4];	/**/
	ulong	rstate;
	ulong	rptr;
	ushort	frame_n;	/**/
	ushort	rbcnt;
	ulong	rtemp;
};

typedef struct EPparam EPparam;
struct EPparam {
	ushort	rbase;
	ushort	tbase;
	uchar	rfcr;
	uchar	tfcr;
	ushort	mrblr;
	ushort	rbptr;
	ushort	tbptr;

	ulong	tstate;
	ulong	tptr;
	ushort	tcrc;
	ushort	tbcnt;
	ulong	res[2];
};

enum {
	Nrdre		= 4,	/* receive descriptor ring entries */
	Ntdre		= 4,	/* transmit descriptor ring entries */

	Rbsize		= 1024+2,		/* ring buffer size (including 2 byte crc) */
	Bufsize		= (Rbsize+7)&~7,	/* aligned */

	Nendpt		= 4,

	USBID		= SCC1ID,	/* replaces SCC1 on 823 */
};

#define	MkPID(x) (((~x&0xF)<<4)|(x&0xF))
enum {
	TokIN = MkPID(9),
	TokOUT = MkPID(1),
	TokSOF = MkPID(5),
	TokSETUP = MkPID(0xD),
	TokDATA0 = MkPID(3),
	TokDATA1 = MkPID(0xB),
	TokACK = MkPID(2),
	TokNAK = MkPID(0xA),
	TokPRE = MkPID(0xC),
};

enum {
	/* BDEmpty, BDWrap, BDInt, BDLast, BDFirst */
	RxData0=		0<<6,	/* DATA0 (OUT) */
	RxData1=		1<<6,	/* DATA1 (OUT) */
	RxData0S=	2<<6,	/* DATA0 (SETUP) */
	RxeNO=		1<<4,	/* non octet-aligned */
	RxeAB=		1<<3,	/* frame aborted: bit stuff error */
	RxeCR=		1<<2,	/* CRC error */
	RxeOV=		1<<1,	/* overrun */
	BDrxerr=		(RxeNO|RxeAB|RxeCR|RxeOV),

	TxTC=		1<<10,	/* transmit CRC */
	TxCNF=		1<<9,	/* transmit confirmation */
	TxLSP=		1<<8,	/* low speed (host) */
	TxNoPID=		0<<6,	/* do not send PID */
	TxData0=		2<<6,	/* add DATA0 PID */
	TxData1=		3<<6,	/* add DATA1 PID */
	TxeNAK=		1<<4,	/* nak received */
	TxeSTAL=		1<<3,	/* stall received */
	TxeTO=		1<<2,	/* timeout */
	TxeUN=		1<<1,	/* underrun */

	/* usmod */
	EN=		1<<0,	/* enable USB */
	HOST=	1<<1,	/* host mode */
	TEST=	1<<2,	/* test mode */
	RESUME=	1<<6,	/* generate resume condition */
	LSS=		1<<7,	/* low-speed signalling */

	/* usber */
	Freset=	1<<9,
	Fidle=	1<<8,
	Ftxe3=	1<<7,
	Ftxe2=	1<<6,
	Ftxe1=	1<<5,
	Ftxe0=	1<<4,
	Ftxe=	Ftxe0|Ftxe1|Ftxe2|Ftxe3,
	Fsof=	1<<3,
	Fbsy=	1<<2,
	Ftxb=	1<<1,
	Frxb=	1<<0,

	/* uscom */
	FifoFill=		1<<7,
	FifoFlush=	1<<6,

	/* usep0-3 */
	EPNSHIFT=	12,
	EPctl=	0<<8,
	EPintr=	1<<8,
	EPbulk=	2<<8,
	EPiso=	3<<8,
	EPmulti=	1<<5,
	EPrte=	1<<4,
	THSok=	0<<2,
	THSignore= 1<<2,
	THSnak=	2<<2,
	THSstall=	3<<2,
	RHSok=	0<<0,
	RHSignore= 1<<0,
	RHSnak=	2<<0,
	RHSstall=	3<<0,

	/* CPM/USB commands (or'd with USBCmd) */
	StopTxEndPt	= 1<<4,
	RestartTxEndPt	= 2<<4,

	SOFmask=	(1<<11)-1,
};

#define	USBABITS	(SIBIT(14)|SIBIT(15))
#define	USBRXCBIT	(SIBIT(10)|SIBIT(11))
#define	USBTXCBIT	(SIBIT(6)|SIBIT(7))

/*
 * software structures
 */
typedef struct Ctlr Ctlr;
typedef struct Endpt Endpt;

struct Endpt {
	Ref;
	int	x;	/* index in Ctlr.pts */
	int	rbsize;
	int	txe;	/* Ftxe0<<Endpt.x */
	int	mode;	/* OREAD, OWRITE, ORDWR */
	int	maxpkt;
	int	rtog;		/* DATA0 or DATA1 */
	int	xtog;	/* DATA0 or DATA1 */
	int	txrestart;
	int	reset;
	Rendez	ir;
	EPparam*	ep;
	Ring;

	Queue*	oq;
	Queue*	iq;
	Ctlr*	ctlr;
};

struct Ctlr {
	Lock;
	int	init;
	USB*	usb;
	USBparam *usbp;
	Endpt	pts[Nendpt];
};

enum {
	/* endpoint assignment */
	EPsetup = 0,
	EPread = 1,
	EPwrite = 2,
};

static	Ctlr	usbctlr[1];

static	void	dumpusb(Block*, char*);
static	void	interrupt(Ureg*, void*);
static	void	setupep(int, EPparam*, int, int);
static	void	eptrestart(Endpt*);
static	void	eptstop(Endpt*);

static void
resetusb(void)
{
	IMM *io;
	USB *usb;
	USBparam *usbp;
	EPparam *ep;
	int brg, i;

	brg = brgalloc();
	if(brg < 0){
		print("usb: no baud rate generator is free\n");
		return;
	}

	/* select USB port pins */
	io = ioplock();
	io->padir &= ~USBABITS;
	io->papar |= USBABITS;
	io->paodr &= ~USBABITS;
	io->pcpar = (io->pcpar & ~USBRXCBIT) | USBTXCBIT;
	io->pcdir = (io->pcdir & ~USBRXCBIT) | USBTXCBIT;
	io->pcso |= USBRXCBIT;
	iopunlock();

	archdisableusb();

	ep = cpmalloc(Nendpt*sizeof(*ep), 32);
	if(ep == nil){
		print("can't allocate USB\n");
		return;
	}
print("usbep=#%.8lux\n", PADDR(ep));

	cpm = cpmdev(CPusb);
	usb = cpm->regs;
	usb->usmod = 0;
	usbp = cpm->param;
	usbp->frame_n = 0;
	usbp->rstate = 0;
	usbp->rptr = 0;
	usbp->rtemp = 0;
	usbp->rbcnt =0;
	for(i=0; i<Nendpt; i++){
		usb->usep[i] = (i<<EPNSHIFT) | EPbulk | THSignore | RHSignore;
		usbp->epptr[i] = PADDR(ep+i) & 0xffff;
		ep[i].rbase = 0;
		ep[i].tbase = 0;
		ep[i].rfcr = 0x10;
		ep[i].tfcr = 0x10;
		ep[i].mrblr = Bufsize;
		ep[i].rbptr = 0;
		ep[i].tbptr = 0;
		ep[i].tstate = 0;
		ep[i].tptr = 0;
	}

	usbctlr->usb = usb;
	usbctlr->usbp = usbp;
	usbctlr->cpm = cpm;

	usb->usmod = 0;
	if(LOWSPEED)
		usb->usmod |= LSS;

	/* set up baud rate generator for appropriate speed */
	if(usb->usmod & LSS){
		print("USB: low speed\n");
		io->brgc[brg] = baudgen(4*1500000, 1) | BaudEnable;
	}else{
		print("USB: high speed\n");
		io->brgc[brg] = baudgen(4*12*MHz, 1) | BaudEnable;
	}
	eieio();
	if(1)
		print("usbbrg=%8.8lux\n", io->brgc[brg]);

	sccnmsi(1, brg, 0);	/* set R1CS */

	usb->usep[EPsetup] = (EPsetup<<EPNSHIFT) | EPctl | THSok | RHSok;
	setupep(EPsetup, ep, ORDWR, 8);

	usb->usep[EPread] = (EPread<<EPNSHIFT) | EPbulk | THSok | RHSstall;
	setupep(EPread, ep, OREAD, Bufsize);

	usb->usep[EPwrite] = (EPwrite<<EPNSHIFT) | EPbulk | THSstall | RHSok;
	setupep(EPwrite, ep, OWRITE, Bufsize);

	archenableusb((usb->usmod&LSS)==0, 0);

	usb->usadr = 0;
	setvec(VectorCPIC+0x1E, interrupt, usbctlr);
	usb->usbmr = ~0 & ~Fidle & ~Fsof;	/* enable all events except idle and SOF */
	usb->usbmr &= ~Ftxe;
	eieio();
	usb->usber = ~0;	/* clear events */
	eieio();
	usb->usmod |= EN;
}

static int
usbctlpacket(Ctlr *ctlr, uchar *p, int n)
{
	int value;

	if(n < 8)
		return 0;
	value = GET2(p+2);
	if(p[0] & RD2H){
		/* provide descriptors */
		if(p[0] != (RD2H|Rstandard|Rdevice)){
			/* TO DO: return 0 length reply */
			return 0;	/* ignore it for now */
		}
		if(value == ((DEVICE<<8)|0)){
			/* return device descriptor */
		}else if(value == ((CONFIGURATION<<8)|0)){
			/* return configuration descriptor */
		}else
			return 0;	/* ignore it for now */
	}else{
		switch(p[1]){
		case SET_ADDRESS:
			usb->usb->usadr = value;
			break;
		case SET_CONFIGURATION:
			/* pretend */
			break;
		default:
			return 0;	/* ignore it */
		}
	}
	return 1;
}

static void
dumpusbp(void)
{
	USBparam *up;

	print("usber=%4.4ux\n", usbctlr->usb->usber);
	up = usbctlr->usbp;
	print("up=%8.8lux: epptr[0]=%4.4ux rstate=%8.8lux rptr=%8.8lux frame=%4.4ux rbcnt=%4.4ux rtemp=%8.8lux\n",
		(ulong)up, up->epptr[0], up->rstate, up->rptr, up->frame_n, up->rbcnt, up->rtemp);
}

static void
dumpept(Endpt *e)
{
	EPparam *ep;

	dumpusbp();
	ep = e->ep;
	print("ep=%8.8lux: rb=%4.4ux tb=%4.4ux rfcr=%.2ux tfcr=%.2ux mrblr=%2.2ux rbptr=%4.4ux tbptr=%4.4ux tstate=%8.8lux tptr=%8.8lux tcrc=%2.2ux tbcnt=%2.2ux res[0]=%8.8lux\n",
		(ulong)ep,
		ep->rbase, ep->tbase, ep->rfcr, ep->tfcr, ep->mrblr,
		ep->rbptr, ep->tbptr, ep->tstate, ep->tptr, ep->tcrc, ep->tbcnt,
		ep->res[0]);
};

static void
setupep(int n, EPparam *ep, int mode, int maxpkt)
{
	Endpt *e;
	int rbsize;

	e = &usbctlr->pts[n];
	e->x = n;
	e->ctlr = usbctlr;
	e->txe = Ftxe0<<n;
	e->xtog = TxData0;
	e->rtog = TxData0;
	e->mode = mode;
	e->maxpkt = maxpkt;
	rbsize = (maxpkt*2+2+3)&~3;	/* 0 mod 4 */
	if(e->oq == nil)
		e->oq = qopen(n==0? 8*1024: 8*maxpkt, n==0, 0, 0);
	if(e->iq == nil)
		e->iq = qopen(n==0? 8*1024: 8*maxpkt, n==0, 0, 0);
	e->ep = ep;
	if(e->rdr == nil)
		if(ioringinit(e, Nrdre, Ntdre, rbsize) < 0)
			panic("usbreset");
	ep->mrblr = rbsize;
	ep->rbase = PADDR(e->rdr);
	ep->rbptr = ep->rbase;
	ep->tbase = PADDR(e->tdr);
	ep->tbptr = ep->tbase;
	eieio();
}

static void
resetep(Endpt *e)
{
	if(e->iq)
		qhangup(e->iq, 0);
	if(e->oq)
		qhangup(e->oq, 0);
}

static void
txstart(Endpt *r)
{
	int len, flags;
	Block *b;
	BD *dre;

	if(r->ctlr->init)
		return;
	while(r->ntq < Ntdre-1){
		b = qget(r->oq);
		if(b == 0)
			break;

		dre = &r->tdr[r->tdrh];
		if(dre->status & BDReady)
			panic("txstart");
	
		/*
		 * Give ownership of the descriptor to the chip, increment the
		 * software ring descriptor pointer and tell the chip to poll.
		 */
		flags = r->xtog | TxTC | BDReady;
		r->xtog ^= TxData1^TxData0;
		len = BLEN(b);
		dcflush(b->rp, len);
		if(r->txb[r->tdrh] != nil)
			panic("usb: txstart");
		r->txb[r->tdrh] = b;
		dre->addr = PADDR(b->rp);
		dre->length = len;
		eieio();
		dre->status = (dre->status & BDWrap) | BDInt|BDLast | flags;
		eieio();
print("Tx%d: st=%4.5ux ", r->x, dre->status); dumpusb(b, "TX");
		r->outpackets++;
		r->ntq++;
		r->tdrh = NEXT(r->tdrh, Ntdre);
	}
	eieio();
	if(r->ntq){
		if(r->txrestart)
			eptrestart(r);
		r->ctlr->usb->uscom = FifoFill | r->x;
		eieio();
	}
}

static void
eptstop(Endpt *e)
{
	cpmop(e->ctlr->cpm, USBCmd|StopTxEndPt, e->x<<1);
}

static void
eptrestart(Endpt *e)
{
	cpmop(e->ctlr->cpm, USBCmd|RestartTxEndPt, e->x<<1);
	e->txrestart = 0;
}

static void
transmit(Endpt *r)
{
	ilock(r->ctlr);
	txstart(r);
	iunlock(r->ctlr);
	//dumpept(r);
}

static void
endptintr(Endpt *r, int events)
{
	int len, status;
	BD *dre;
	Block *b;
	static char *pktype[] = {"OUT0", "OUT1", "SETUP0", "??"};

	if(events & Frxb){
		dre = &r->rdr[r->rdrx];
		while(((status = dre->status) & BDEmpty) == 0){
print("RX%d: %4.4ux %4.4ux t=%s\n", r->x, dre->status, dre->length, pktype[(dre->status>>6)&3]);
			if(status & BDrxerr || (status & (BDFirst|BDLast)) != (BDFirst|BDLast)){
				if(status & (RxeNO|RxeAB))
					r->badframes++;
				if(status & RxeCR)
					r->badcrcs++;
				if(status & RxeOV)
					r->overflows++;
				print("usb rx%d: %4.4ux %d ", r->x, status, dre->length);
			}else if(r->iq != nil){
				{uchar *p;int i; p=KADDR(dre->addr); for(i=0;i<14&&i<dre->length; i++)print(" %.2ux", p[i]);print("\n");}
				/*
				 * We have a packet. Read it into the next
				 * free ring buffer, if any.
				 */
				len = dre->length-2;	/* discard CRC */
				if(r->x == EPsetup && usbctlpacket(r->ctlr, KADDR(dre->addr), len)){
				}else
				if(len >= 0 && qproduce(r->iq, KADDR(dre->addr), len)>=0){
					dcflush(KADDR(dre->addr), len);
				}else{
					r->soverflows++;
					/* collect it next time */
					break;
				}
			}

			/*
			 * Finished with this descriptor, reinitialise it,
			 * give it back to the chip, then on to the next...
			 */
			dre->length = 0;
			dre->status = (dre->status & BDWrap) | BDEmpty | BDInt;
			eieio();

			r->rdrx = NEXT(r->rdrx, Nrdre);
			dre = &r->rdr[r->rdrx];
		}
		if(qfull(r->iq)){
			/* set NAK status */
			/* TO DO */
		}else{
			/* TO DO: clear nak status */
			/* kick? */
		}
	}

	/*
	 * Transmitter interrupt: handle anything queued for a free descriptor.
	 */
	if(events & (Ftxb|r->txe)){
		ilock(r->ctlr);
		while(r->ntq){
			dre = &r->tdr[r->tdri];
			print("usbtx%d=#%4.4x %8.8lux\n", r->x, dre->status, dre->addr);
			//dumpept(r);
			if(dre->status & BDReady)
				break;
			/* TO DO: error counting; STALL*/
			b = r->txb[r->tdri];
			if(b == nil)
				panic("usb/interrupt: bufp");
			r->txb[r->tdri] = nil;
			freeb(b);
			r->ntq--;
			r->tdri = NEXT(r->tdri, Ntdre);
		}
		txstart(r);
		iunlock(r->ctlr);
	}
	if(events & r->txe){
		r->ctlr->usb->uscom = FifoFlush | r->x;
		if(r->ntq)
			eptrestart(r);
		else
			r->txrestart = 1;
	}
}

static void
interrupt(Ureg*, void *arg)
{
	int events, i;
	Endpt *e;
	Ctlr *ctlr;
	USB *usb;

	ctlr = arg;
	usb = ctlr->usb;
	events = usb->usber;
	eieio();
	usb->usber = events;
	eieio();

	events &= ~Fidle;
	if(events & Fsof){
		if(0)
			print("SOF #%ux\n", ctlr->usbp->frame_n&SOFmask);
	}
	if(events & Freset){
		usb->usadr = 0;	/* on reset, device required to be device 0 */
		ctlr->reset = 1;
		for(i=1; i<Nendpt; i++)
			resetep(&ctlr->pts[i]);
		events &= ~Freset;
	}
events &= ~Ftxe;
	if(events == 0)
		return;
	if(Chatty)
		print("USB#%x\n", events);
	for(i=0; i<Nendpt; i++){
		e = &ctlr->pts[i];
		if(e->rdr != nil)
			endptintr(e, events);
	}
}

static void
dumpusb(Block *b, char *msg)
{
	int i;

	print("%s: %8.8lux [%ld]: ", msg, (ulong)b->rp, BLEN(b));
	for(i=0; i<BLEN(b) && i < 16; i++)
		print(" %.2x", b->rp[i]);
	print("\n");
}

static void
usbreset(void)
{
	resetusb();
}

static Chan*
usbopen(Chan *c, int omode)
{
}

static void
usbclose(Chan *c)
{
}

static Block *
usbbread(void)
{
	return qget(usb->pts[EPread].iq);
}

static long
sendept(Endpt *e, void *buf, long n)
{
	Block *b;
	long nw;
	uchar *a;

	if(e == nil)
		error(Ebadusefd);
	if(e->oq == nil)
		error(Eio);
	a = buf;
	do{
		nw = n;
		if(nw > e->maxpkt)
			nw = e->maxpkt;
		b = allocb(nw);
		if(waserror()){
			freeb(b);
			nexterror();
		}
		memmove(b->wp, a, nw);
		b->wp += nw;
		a += nw;
		poperror();
		qbwrite(e->oq, b);
		transmit(e);
	}while((n -= nw) > 0);
	return a-(uchar*)buf;
}

static long
usbwrite(Chan *c, void *buf, long n, ulong)
{
	Ctlr *usb;
	char cmd[64], *fields[4];
	int nf, i;

	usb = usbctlr;
	switch(QID(c->qid.path)){
	default:
		error(Ebadusefd);
		return 0;
	case Qctl:
		if(n > sizeof(cmd)-1)
			n = sizeof(cmd)-1;
		memmove(cmd, buf, n);
		cmd[n] = 0;
		nf = parsefields(cmd, fields, nelem(fields), " \t\n");
		if(nf < 1)
			error(Ebadarg);
		if(nf == 2 && strcmp(fields[0], "addr") == 0){
			i = strtol(fields[1], nil, 0);
			if(i < 0 || i >= 128)
				error(Ebadarg);
			/* should wait until idle? */
			usb->usb->usadr = i;
		}else
			error(Ebadarg);
		break;
	case Qsetup:
		n = sendept(&usb->pts[EPsetup], buf, n);
		break;
	case Qdata:
		n = sendept(&usb->pts[EPwrite], buf, n);
		break;
	}
	return n;
}
