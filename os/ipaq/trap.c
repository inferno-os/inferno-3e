#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"io.h"
#include	"ureg.h"
#include	"../port/error.h"

#define waslo(sr) (!((sr) & (PsrDirq|PsrDfiq)))

typedef struct IrqEntry IrqEntry;

struct IrqEntry {
	void	(*r)(Ureg*, void*);
	void	*a;
	int	v;
	IrqEntry	*next;
};

enum {
	NumIRQ = 32,

	MinGpioIRQbit = 11,
	NumGpioIRQbits = MaxGPIObit-MinGpioIRQbit+1,
	GpioIRQmask = ((1<<NumGpioIRQbits)-1)<<MinGpioIRQbit,
};

/*
 * saved state during power down. 
 * it's only used up to 164/4.
 * it's only used by routines in l.s
 */
ulong power_resume[200/4];

static IrqEntry Irq[NumIRQ];
static IrqEntry GPIOIrq[NumGpioIRQbits];
static Lock veclock;

Instr BREAK = 0xE6BAD010;

int (*breakhandler)(Ureg*, Proc*);
int (*catchdbg)(Ureg *, uint);
void (*idle)(void);

extern void (*serwrite)(char *, int);

/*
 * Interrupt sources not masked by splhi() -- these are special
 *  interrupt handlers (e.g. profiler or watchdog), not allowed
 *  to share regular kernel data structures.  All interrupts are
 *  masked by splfhi(), which should only be used herein.
 */
enum {
	IRQ_NONMASK = (1 << OSTimerbit(3)) | (1 << OSTimerbit(2)),
};
int splfhi(void);	/* disable all */
int splflo(void);	/* enable FIQ */

static int actIrq = -1;	/* Active Irq handler, 0-31, or -1 if none */
static int wasIrq = -1;	/* Interrupted Irq handler */

static Proc *iup;	/* Interrupted kproc */

void	serputc(int);

void
intrenable(int v, void (*f)(Ureg*, void*), void* a, int tbdf)
{
	int x;
	GpioReg *g;

	ilock(&veclock);
	switch(tbdf) {
	case BusGPIOfalling:
	case BusGPIOrising:
	case BusGPIOboth:
		if(v < 0 || v > MaxGPIObit)
			panic("intrenable: gpio source %d out of range\n", v);
		g = GPIOREG;
		switch(tbdf){
		case BusGPIOfalling:
			g->gfer |= 1<<v;
			g->grer &= ~(1<<v);
			break;
		case BusGPIOrising:
			g->grer |= 1<<v;
			g->gfer &= ~(1<<v);
			break;
		case BusGPIOboth:
			g->grer |= 1<<v;
			g->gfer |= 1<<v;
			break;
		}
		g->gpdr &= ~(1<<v);
		if(v >= MinGpioIRQbit) {
			GPIOIrq[v-MinGpioIRQbit].r = f;
			GPIOIrq[v-MinGpioIRQbit].a = a;
			iunlock(&veclock);
			return;
		}
		/*FALLTHROUGH for GPIO sources 0-10 */
	case BUSUNKNOWN:
	case BusCPU:
		if(v < 0 || v > MaxIRQbit)
			panic("intrenable: irq source %d out of range\n", v);
		Irq[v].r = f;
		Irq[v].a = a;

		x = splfhi();
		/* Enable the interrupt by setting the mask bit */
		INTRREG->icmr |= 1 << v;
		splx(x);
		break;
	default:
		panic("intrenable: unknown irq bus %d\n", tbdf);
	}
	iunlock(&veclock);
}

static void
safeintr(Ureg *, void *a)
{
	int v = (int)a;
	int x;

	/* No handler - clear the mask so we don't loop */
	x = splfhi();
	INTRREG->icmr &= ~(1 << v);
	splx(x);
	iprint("spurious interrupt %d\n", v);
}

static void
gpiointr(Ureg *ur, void*)
{
	IrqEntry *cur;
	ulong e;
	int i;

	e = GPIOREG->gedr & GpioIRQmask;
	GPIOREG->gedr = e;
	for(i = MinGpioIRQbit; i <= MaxGPIObit; i++){
		if(e & (1<<i)){
			cur = &GPIOIrq[i-MinGpioIRQbit];
			if(cur->r != nil){
				cur->r(ur, cur->a);
				e &= ~(1<<i);
			}
		}
	}
	if(e != 0){
		GPIOREG->gfer &= ~e;
		GPIOREG->grer &= ~e;
		iprint("spurious GPIO interrupt: %8.8lux\n", e);
	}
}

void
trapinit(void)
{
	int v;
	IntrReg *intr = INTRREG;

	intr->icmr = 0;
	intr->iclr = IRQ_NONMASK;

	/* set up stacks for various exceptions */
	setr13(PsrMfiq, m->fiqstack+nelem(m->fiqstack));
	setr13(PsrMirq, m->irqstack+nelem(m->irqstack));
	setr13(PsrMabt, m->abtstack+nelem(m->abtstack));
	setr13(PsrMund, m->undstack+nelem(m->undstack));

	for (v = 0; v < nelem(Irq); v++) {
		Irq[v].r = nil;
		Irq[v].a = nil;
		Irq[v].v = v;
	}
	for (v = 0; v < nelem(GPIOIrq); v++) {
		GPIOIrq[v].r = nil;
		GPIOIrq[v].a = nil;
		GPIOIrq[v].v = v+MinGpioIRQbit;
	}

	memmove(page0->vectors, vectors, sizeof(page0->vectors));
	memmove(page0->vtable, vtable, sizeof(page0->vtable));
	wbflush(page0, sizeof(*page0));

	idle = xspanalloc(13*sizeof(ulong), CACHELINESZ, 0);
	memmove(idle, _idlemode, 13*sizeof(ulong));
	wbflush(idle, 13*sizeof(ulong));

	flushicache();

	intrenable(MinGpioIRQbit, gpiointr, nil, BusCPU);
}

static char *trapnames[PsrMask+1] = {
	[ PsrMfiq ] "Fiq interrupt",
	[ PsrMirq ] "Mirq interrupt",
	[ PsrMsvc ] "SVC/SWI Exception",
	[ PsrMabt ] "Prefetch Abort/Data Abort",
	[ PsrMabt+1 ] "Data Abort",
	[ PsrMund ] "Undefined instruction",
	[ PsrMsys ] "Sys trap"
};

static char *
trapname(int psr)
{
	char *s;

	s = trapnames[psr & PsrMask];
	if(s == nil)
		s = "Undefined trap";
	return s;
}

static void
sys_trap_error(int type)
{
	char errbuf[ERRLEN];
	sprint(errbuf, "sys: trap: %s\n", trapname(type));
	error(errbuf);
}

void
dflt(Ureg *ureg, ulong far)
{
	char buf[ERRLEN];

	if(0)
		dumpregs(ureg);
	sprint(buf, "trap: fault pc=%N addr=0x%lux", (ulong)ureg->pc, far);
	disfault(ureg, buf);
}

/*
 *  All traps come here.  It is slower to have all traps call trap
 *  rather than directly vectoring the handler.
 *  However, this avoids
 *  a lot of code dup and possible bugs.
 *  trap is called splfhi().
 */
void
trap(Ureg* ureg)
{
	ulong far, fsr;
	int rem;

	 //
	 // This is here to make sure that a clock interrupt doesn't
	 // cause the process we just returned into to get scheduled
	 // before it single stepped to the next instruction.
	 //
	static struct {int callsched;} c = {1};
	int itype;

	if(up != nil)
		rem = ((char*)ureg)-up->kstack;
	else
		rem = ((char*)ureg)-(char*)MACHP(0)->stack;
	if(rem < 256)
		panic("trap %d bytes remaining (%s)", rem, up?up->text:"");

	/*
	 * All interrupts/exceptions should be resumed at ureg->pc-4,
	 * except for Data Abort which resumes at ureg->pc-8.
	 */
	ureg->pc -= 4;
	ureg->sp = (ulong)(ureg+1);
	itype = ureg->type;
	if (itype == PsrMirq || itype == PsrMfiq) {	/* Interrupt Request */

		Proc *saveup;
		int t;

		SET(t);
		SET(saveup);

		if (itype == PsrMirq) {
			splflo();	/* Allow nonmasked interrupts */
			if (saveup = up) {
				t = m->ticks;	/* CPU time per proc */
				saveup->pc = ureg->pc;	/* debug info */
				saveup->dbgreg = ureg;
			}
		} else {
					 /* for profiler(wasbusy()): */
			wasIrq = actIrq; /* Save ID of interrupted handler */
			iup = up;	 /* Save ID of interrupted proc */
		}

		for(;;) {		/* Use up all the active interrupts */
			ulong ibits;
			IrqEntry *cur;
			IntrReg *intr = INTRREG;
			int i, s;

			if (itype == PsrMirq)
				ibits = intr->icip;	/* screened by icmr */
			else
				ibits = intr->icfp;	/* screened by icmr */
			if(ibits == 0)
				break;
			for(i=0; i<nelem(Irq) && ibits; i++)
				if(ibits & (1<<i)){
					cur = &Irq[i];
					if(cur->r != nil){
						actIrq = cur->v; /* show active interrupt handler */
						up = 0;		/* Make interrupted process invisible */
						cur->r(ureg, cur->a);
						ibits &= ~(1<<i);
					}
				}
			if(ibits != 0){
				iprint("spurious irq interrupt: %8.8lux\n", ibits);
				s = splfhi();
				intr->icmr &= ~ibits;
				splx(s);
			}
		}
		if (itype == PsrMirq) {
			up = saveup;	/* Make interrupted process visible */
			actIrq = -1;	/* No more interrupt handler running */
			if (saveup) {
				if (saveup->state == Running) {
					t = m->ticks - t;	/* See if timer advanced */
					if (anyhigher() || t && anyready()) {
						if(c.callsched){
							sched();
							splhi();
						}
					}
				}
				saveup->dbgreg = nil;
			}
		} else {
			actIrq = wasIrq;
			up = iup;
		}
		return;
	}

	/* All other traps */

	if (ureg->psr & PsrDfiq)
		goto faultpanic;
	if (up)
		up->dbgreg = ureg;
	switch(itype) {

	case PsrMund:				/* Undefined instruction */
		if(*(ulong*)ureg->pc == BREAK && breakhandler) {
			int s;
			Proc *p;

			p = up;
			/* if (!waslo(ureg->psr) || ureg->pc >= (ulong)splhi && ureg->pc < (ulong)islo)
				p = 0; */
			s = breakhandler(ureg, p);
			if(s == BrkSched) {
				c.callsched = 1;
				sched();
			} else if(s == BrkNoSched) {
				c.callsched = 0;
				if(up)
					up->dbgreg = 0;
				return;
			}
			break;
		}
		if (up == nil)
			goto faultpanic;
		spllo();
		if (waserror()) {
			if(waslo(ureg->psr) && up->type == Interp)
				disfault(ureg, up->env->error);
			setpanic();
			dumpregs(ureg);
			panic("%s", up->env->error);
		}
		if (!fpiarm(ureg)) {
			dumpregs(ureg);
			sys_trap_error(ureg->type);
		}
		poperror();
		break;

	case PsrMsvc:				/* Jump through 0 or SWI */
		if (waslo(ureg->psr) && up && up->type == Interp) {
			spllo();
			dumpregs(ureg);
			sys_trap_error(ureg->type);
		}
		goto faultpanic;

	case PsrMabt:				/* Prefetch abort */
		if (catchdbg && catchdbg(ureg, 0))
			break;
		ureg->pc -= 4;

	case PsrMabt+1:			/* Data abort */
		fsr = mmuregr(CpFSR);
		far = mmuregr(CpFAR);
		if (fsr & (1<<9)) {
			mmuregw(CpFSR, fsr & ~(1<<9));
			if (catchdbg && catchdbg(ureg, fsr))
				break;
			print("Debug/");
		}
		if (waslo(ureg->psr) && up && up->type == Interp) {
			spllo();
			dflt(ureg, far);
		}
		/* FALL THROUGH */

	default:				/* ??? */
faultpanic:
		setpanic();
		dumpregs(ureg);
		panic("exception %uX %s\n", ureg->type, trapname(ureg->type));
		break;
	}

	splhi();
	if(up)
		up->dbgreg = 0;		/* becomes invalid after return from trap */
}

void
serputc(int c)
{
	if (!c)
		return;
	if (c == '\n')
		serputc('\r');
	while(!(*(ulong*)0x80050020 & 0x04))
		;
	*(ulong*)0x80050014 = c;
	if (c == '\n')
		while((*(ulong*)0x80050020 & 0x01))	/* flush xmit fifo */
			;
}

static void
_serwrite(char *data, int len)
{
	int x;

	clockpoll();
	x = splfhi();
	while(--len >= 0)
		serputc(*data++);
	splx(x);
}

static int
_serread(char *data, int len)
{
	clockcheck();
	while(--len >= 0) {
		while(!(*(ulong*)0x80050020 & 0x02))
			clockcheck();
		*data++ = *(ulong*)0x80050014;
	}
	return 0;
}

int
iprint(char *fmt, ...)
{
	int n;
	va_list arg;
	char buf[PRINTSIZE];

	va_start(arg, fmt);
	n = doprint(buf, buf+sizeof(buf), fmt, arg) - buf;
	va_end(arg);
	_serwrite(buf, n);

	return n;
}

void
setpanic(void)
{
	extern void screenon(int);
	extern int consoleprint;

	if (breakhandler != 0)	/* don't mess up debugger */
		return;
	INTRREG->icmr = 0;
	spllo();
	/* screenon(!consoleprint); */
	consoleprint = 1;
	serwrite = _serwrite;
}

int
isvalid_pc(ulong v)
{
	extern char etext[];
	extern void _startup(void);

	return (ulong)_startup <= v && v < (ulong)etext && !(v & 3);
}

int
isvalid_wa(void *v)
{
	return (ulong)v >= KZERO && (ulong)v < conf.topofmem && !((ulong)v & 3);
}

int
isvalid_va(void *v)
{
	return (ulong)v >= KZERO && (ulong)v < conf.topofmem;
}

void
dumplongs(char *msg, ulong *v, int n)
{
	int i, l;

	l = print("%s at %ulx: ", msg, v);
	for(i=0; i<n; i++){
		if(l >= 60){
			print("\n");
			l = print("    %ulx: ", v);
		}
		if (isvalid_va(v))
			l += print(" %ulx", *v++);
		else{
			print(" invalid");
			break;
		}
	}
	print("\n");
}

void
dumpregs(Ureg* ureg)
{
	Proc *p;

	print("TRAP: %s", trapname(ureg->type));
	if ((ureg->psr & PsrMask) != PsrMsvc)
		print(" in %s", trapname(ureg->psr));
	if ((ureg->type == PsrMabt) || (ureg->type == PsrMabt + 1))
		print(" FSR %8.8luX FAR %8.8luX\n", mmuregr(CpFSR), mmuregr(CpFAR));
	print("\n");
	print("PSR %8.8uX type %2.2uX PC %8.8uX LINK %8.8uX\n",
		ureg->psr, ureg->type, ureg->pc, ureg->link);
	print("R14 %8.8uX R13 %8.8uX R12 %8.8uX R11 %8.8uX R10 %8.8uX\n",
		ureg->r14, ureg->r13, ureg->r12, ureg->r11, ureg->r10);
	print("R9  %8.8uX R8  %8.8uX R7  %8.8uX R6  %8.8uX R5  %8.8uX\n",
		ureg->r9, ureg->r8, ureg->r7, ureg->r6, ureg->r5);
	print("R4  %8.8uX R3  %8.8uX R2  %8.8uX R1  %8.8uX R0  %8.8uX\n",
		ureg->r4, ureg->r3, ureg->r2, ureg->r1, ureg->r0);
	print("Stack is at: %8.8luX\n",ureg);
	print("CPSR %8.8uX SPSR %8.8uX ", cpsrr(), spsrr());
	print("PC %N LINK %N\n", (ulong)ureg->pc, (ulong)ureg->link);

	p = (actIrq >= 0) ? iup : up;
	if (p != nil)
		print("Process stack:  %lux-%lux\n",
			p->kstack, p->kstack+KSTACK-4);
	else
		print("System stack: %lux-%lux\n",
			(ulong)(m+1), (ulong)m+KSTACK-4);
	dumplongs("stk", (ulong *)(ureg + 1), 16);
	print("bl's: ");
	dumpstk((ulong *)(ureg + 1));
//	if (isvalid_wa((void *)ureg->pc))
//		dumplongs("code", (ulong *)ureg->pc - 5, 12);
}

void
dumpstack(void)
{
	ulong l;

	if (breakhandler != 0)
		dumpstk(&l);
}

void
dumpstk(ulong *l)
{
	ulong *v, i;
	ulong inst;
	ulong *estk;
	uint len;

	len = KSTACK/sizeof *l;
	if (up == 0)
		len -= l - (ulong *)m;
	else
		len -= l - (ulong *)up->kstack;

	if (len > KSTACK/sizeof *l)
		len = KSTACK/sizeof *l;
	else if (len < 0)
		len = 50;

	i = 0;
	for(estk = l + len; l<estk; l++) {
		if(!isvalid_wa(l)) {
			i += print("invalid(%lux)", l);
			break;
		}
		v = (ulong *)*l;
		if(isvalid_wa(v)) {
			inst = *(v - 1);
			if((inst & 0x0ff0f000) == 0x0280f000 &&
			     (*(v-2) & 0x0ffff000) == 0x028fe000	||
				(inst & 0x0f000000) == 0x0b000000) {
				i += print("%N ", v);
			}
		}
		if(i >= 60) {
			print("\n");
			i = print("    ");
		}
	}
	if(i)
		print("\n");
}

void
trapspecial(int (*f)(Ureg *, uint))
{
	catchdbg = f;
}

int
wasbusy(int idlepri)
{
	return wasIrq >= 0 ||
			nrdy > 0 && rdypri < idlepri ||
			iup != nil && iup->type != IdleGC && iup->pri < idlepri ||
			idlepri > Nrq;
}
