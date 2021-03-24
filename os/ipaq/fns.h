#include "../port/portfns.h"

ulong	aifinit(uchar *aifarr);
void	aamloop(int);
int	archaudiopower(int);
void	archaudiomute(int);
void	archaudioamp(int);
int	archaudiospeed(int, int);
void	archcodecreset(void);
void	archconfinit(void);
int	archflash12v(int);
void	archflashwp(int);
int	archhooksw(int);
void	archlcdenable(int);
void	archreboot(void);
void	archreset(void);
void	archspeaker(int, int);
void	archrdtsc(vlong *);
ulong archrdtsc32(void);
int	archtadcodecsok(void);
char* bpgetenv(char*);
#define	bpenumenv(i)	0
int	bpoverride(char*, int*);
int	bpoverride_uchar(char*, uchar*);
ulong	call_apcs(ulong addr, int nargs, ...);
ulong	call_apcs0(ulong addr);
ulong	call_apcs1(ulong addr, ulong a1);
ulong	call_apcs2(ulong addr, ulong a1, ulong a2);
ulong	call_apcs3(ulong addr, ulong a1, ulong a2, ulong a3);
void	catchDref(char *s, void *v);
void	catchDval(char *s, ulong v, ulong m);
void	catchIref(char *s, void *a);
void	cisread(int slotno, void (*f)(int, uchar *));
int	cistrcmp(char *, char *);
void	cleanDentry(void *);
void	clockcheck(void);
void	clockinit(void);
void	clockpoll(void);
#define	coherence()		/* nothing to do for cache coherence for uniprocessor */
uint	cpsrr(void);
void	cursorhide(void);
void	cursorunhide(void);
void	dcinval(void);
int	dmaidle(Dma*);
Dma*	dmasetup(int device, int direction, int bigend, void(*)(void*,ulong), void*);
int	dmastart(Dma*, void*, int);
int	dmacontinue(Dma*, void*, int);
void	dmastop(Dma*);
int	dmaerror(Dma*);
void	dmafree(Dma*);
void	dmareset(void);
void	dmawait(Dma*);
void dumplongs(char *, ulong *, int);
void	dumpregs(Ureg* ureg);
void	dumpstk(ulong *);
void	flushicache(void);
void	flushTLB(void);
int	fpiarm(Ureg*);
void	fpinit(void);
ulong	getcallerpc(void*);
void	gotopc(ulong);

void	_idlemode(void);
void	(*idle)(void);
void	idlehands(void);
uchar	inb(ulong);
ushort	ins(ulong);
ulong	inl(ulong);
void	outb(ulong, uchar);
void	outs(ulong, ushort);
void	outl(ulong, ulong);
void inss(ulong, void*, int);
void outss(ulong, void*, int);
void	insb(ulong, void*, int);
void	outsb(ulong, void*, int);
void	intrenable(int, void (*)(Ureg*, void*), void*, int);
void	iofree(int);
#define	iofree(x)
void	ioinit(void);
int	iounused(int, int);
int	ioalloc(int, int, int, char*);
#define	ioalloc(a,b,c,d) 0
int	iprint(char*, ...);
void	installprof(void (*)(Ureg *, int));
int	isvalid_pc(ulong);
int	isvalid_va(void*);
void	kbdinit(void);
void	L3init(void);
int	L3read(int, void*, int);
int	L3write(int, void*, int);
void	lcd_setbacklight(int);
void	lcd_setbrightness(ushort);
void	lcd_setcontrast(ushort);
void	lcd_sethz(int);
void	lights(ulong);
void	links(void);
ulong	mcpgettfreq(void);
void	mcpinit(void);
void	mcpsettfreq(ulong tfreq);
void	mcpspeaker(int, int);
void	mcptelecomsetup(ulong hz, uchar adm, uchar xint, uchar rint);
ushort	mcpadcread(int ts);
void	mcptouchsetup(int ts);
void	mcptouchintrenable(void);
void	mcptouchintrdisable(void);
void	mcpgpiowrite(ushort mask, ushort data);
void	mcpgpiosetdir(ushort mask, ushort dir);
ushort	mcpgpioread(void);
void*	minicached(void*);
void	miniwbflush(void);
ulong	mmuctlregr(void);
void	mmuctlregw(ulong);
void	mmuenable(ulong);
void	mmuinit(void);
ulong	mmuregr(int);
void	mmuregw(int, ulong);
void	mmureset(void);
void	mouseinit(void);
void	nowriteSeg(void *, void *);
void*	pa2va(ulong);
void	pcmcisread(PCMslot*);
int	pcmcistuple(int, int, int, void*, int);
PCMmap*	pcmmap(int, ulong, int, int);
void	pcmunmap(int, PCMmap*);
int	pcmpin(int slot, int type);
void	pcmpower(int slotno, int on);
int	pcmpowered(int);
void	pcmreset(int);
void	pcmsetvcc(int, int);
void	pcmsetvpp(int, int);
int	pcmspecial(char *idstr, ISAConf *isa);
void	pcmspecialclose(int slotno);
void	pcmintrenable(int, void (*)(Ureg*, void*), void*);
void	powerenable(void (*)(int));
void	powerdisable(void (*)(int));
void	powerinit(void);
void	putcsr(ulong);
#define procsave(p)
#define procrestore(p)
long	rtctime(void);
void	screeninit(void);
void	screenputs(char*, int);
int	segflush(void*, ulong);
void	setpanic(void);
void	setr13(int, void*);
uint	spsrr(void);
void	touchrawcal(int q, int px, int py);
int	touchcalibrate(void);
int	touchreadxy(int *fx, int *fy);
int	touchpressed(void);
int	touchreleased(void);
void	touchsetrawcal(int q, int n, int v);
int	touchgetrawcal(int q, int n);
void	trapinit(void);
void	trapspecial(int (*)(Ureg *, uint));
int	uartprint(char*, ...);
void	uartspecial(int, int, char, Queue**, Queue**, int (*)(Queue*, int));
void	umbfree(ulong addr, int size);
ulong	umbmalloc(ulong addr, int size, int align);
void	umbscan(void);
ulong	va2pa(void*);
void	vectors(void);
void	vtable(void);
#define	waserror()	(up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
int	wasbusy(int);
void	wbflush(void*, ulong);
void	vgaputc(char);

#define KADDR(p)	((void *) p)
#define PADDR(v)	va2pa((void*)(v))

// #define timer_start()	(*OSCR)
// #define timer_ticks(t)	(*OSCR - (ulong)(t))
#define DELAY(ms)	timer_delay(MS2TMR(ms))
#define MICRODELAY(us)	timer_delay(US2TMR(us))
ulong	timer_start(void);
ulong	timer_ticks(ulong);
int 	timer_devwait(ulong *adr, ulong mask, ulong val, int ost);
void 	timer_setwatchdog(int ost);
void 	timer_delay(int ost);
ulong	ms2tmr(int ms);
int	tmr2ms(ulong t);
void	delay(int ms);
ulong	us2tmr(int us);
int	tmr2us(ulong t);
void 	microdelay(int us);
