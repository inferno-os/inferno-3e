#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"

static void
lockloop(Lock *l, ulong pc)
{
	setpanic();
	print("lock loop 0x%lux key 0x%lux pc 0x%lux held by pc 0x%lux\n", l, l->key, pc, l->pc);
	dumplongs("lock area", (ulong*)(l-4), 5*sizeof *l/sizeof (ulong));
	panic("lockloop");
}

void
lock(Lock *l)
{
	int pri, i;
	ulong pc;

	pc = getcallerpc(&l);
	if(up == 0) {
		if (tas(&l->key) != 0) {
			for(i=0; ; i++) {
				if(tas(&l->key) == 0)
					break;
				if (i >= 1000000) {
					lockloop(l, pc);
					break;
				}
			}
		}
		l->pc = pc;
		return;
	}

	pri = up->pri;
	up->pri = PriLock;
	for(i=0; ; i++) {
		if(tas(&l->key) == 0)
			break;
		if (i >= 1000) {
			lockloop(l, pc);
			break;
		}
		if(conf.nmach == 1 && up->state == Running && islo()) {
			up->pc = pc;
			sched();
		}
	}
	l->pri = pri;
	l->pc = pc;
}

void
ilock(Lock *l)
{
	ulong x, pc;
	int i;

	pc = getcallerpc(&l);
	x = splhi();
	for(;;) {
		if(tas(&l->key) == 0) {
			l->sr = x;
			l->pc = pc;
			return;
		}
		if(conf.nmach < 2)
			panic("ilock: no way out: pc 0x%lux: lock 0x%lux held by pc 0x%lux", pc, l, l->pc);
		for(i=0; ; i++) {
			if(l->key == 0)
				break;
			clockcheck();
			if (i > 100000) {
				lockloop(l, pc);
				break;
			}
		}
	}
}

int
canlock(Lock *l)
{
	int pri;

	if (up == 0) {
		if(tas(&l->key))
			return 0;
	}
	else {
		pri = up->pri;
		up->pri = PriLock;
		if (tas(&l->key)) {
			up->pri = pri;
			return 0;
		}
		l->pri = pri;
	}
	l->pc = getcallerpc(&l);
	return 1;
}

void
unlock(Lock *l)
{
	int p;

	if(l->key == 0)
		print("unlock: not locked: pc %lux\n", getcallerpc(&l));
	p = l->pri;
	l->pc = 0;
	l->key = 0;
	if(up)
		up->pri = p;
	coherence();
}

void
iunlock(Lock *l)
{
	ulong sr;

	if(l->key == 0)
		print("iunlock: not locked: pc %lux\n", getcallerpc(&l));
	sr = l->sr;
	l->pc = 0;
	l->key = 0;
	coherence();
	_splx(sr);
}
