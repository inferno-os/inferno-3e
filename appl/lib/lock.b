implement Lock;

include "sys.m";
	sys:	Sys;
include "lock.m";

b := array[4] of {* => byte 0};

Semaphore.obtain(l: self ref Semaphore)
{
	sys->read(l.q[1], b, len b);
}

Semaphore.release(l: self ref Semaphore)
{
	sys->write(l.q[0], b, len b);
}

Semaphore.new(): ref Semaphore
{
	l := ref Semaphore;
	l.q = array[2] of ref Sys->FD;
	if (sys->pipe(l.q) < 0)
		sys->raise("lock alloc");
	sys->write(l.q[0], b, len b);
	return l;
}

init()
{
	sys = load Sys Sys->PATH;
}
