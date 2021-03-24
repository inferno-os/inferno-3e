#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"interp.h"

void
Sleep(Rendez *r, int (*f)(void*), void *arg)
{
	up->r = r;
	lock(&r->l);
	if(f(arg)) {
		up->r = nil;
		unlock(&r->l);
		return;
	}

	if(r->p != nil)
		panic("Sleep %s %s r=0x%lux\n", r->p->text, up->text, r);

	up->swipend = 0;
	r->p = up;
	unlock(&r->l);

	erendezvous(up, 0);

	if(up->swipend) {
		up->swipend = 0;
		error(Eintr);
	}
}

void
Wakeup(Rendez *r)
{
	Proc *p;

	lock(&r->l);
	p = r->p;
	if(p != nil) {
		r->p = nil;
		p->r = nil;
		erendezvous(p, 0);
	}
	unlock(&r->l);
}

void
swiproc(Proc *p)
{
	Rendez *r;
	
	if(p == nil)
		return;

	/*
	 * Pull out of emu Sleep
	 */
	r = p->r;
	if(r != nil) {
		lock(&r->l);
		if(p->r == r) {
			p->swipend = 1;
			r->p = nil;
			p->r = nil;
			erendezvous(p, 0);
		}
		unlock(&r->l);
		return;
	}

	/*
	 * Maybe pull out of Host OS
	 */
	lock(&p->sysio);
	if(p->syscall && p->intwait == 0) {
		p->intwait = 1;
		p->swipend = 1;
		unlock(&p->sysio);
		oshostintr(p);
		return;	
	}
	unlock(&p->sysio);
}

void
osenter(void)
{
	up->syscall = 1;
	strcpy(up->text, "syscall");
}

void
osleave(void)
{
	int r;

	lock(&up->sysio);
	r = up->swipend;
	up->swipend = 0;
	up->syscall = 0;
	unlock(&up->sysio);

	/* Cleared by the signal/note/exception handler */
	while(up->intwait)
		osyield();

	if(r != 0)
		error(Eintr);

	strcpy(up->text, "");
}

void
rptwakeup(void *o, Rept *r)
{
	if(r == nil)
		return;
	lock(&r->l);
	r->o = o;
	unlock(&r->l);
	Wakeup(&r->r);
}

static void
rproc(void *a)
{
	ulong t;
	void *o;
	Rept *r;

	r = a;

SLEEP:
	Sleep(&r->r, r->f0, nil);
	lock(&r->l);
	o = r->o;
	unlock(&r->l);
	t = r->t0;
	for(;;){
		osmillisleep(t);
		t = r->t1;
		acquire();
		if(waserror()){
			release();
			break;
		}
		if(r->f0(o)){
			r->f1(o);
			poperror();
			release();
		}
		else{
			poperror();
			release();
			goto SLEEP;
		}
	}
	pexit("", 0);
}

Rept*
rptproc(char *s, int t0, int t1, int (*f0)(void*), void (*f1)(void*))
{
	Rept *r;

	r = mallocz(sizeof(Rept), 1);
	if(r == nil)
		return nil;
	r->t0 = t0;
	r->t1 = t1;
	r->f0 = f0;
	r->f1 = f1;
	kproc(s, rproc, r, 0);
	return r;
}
