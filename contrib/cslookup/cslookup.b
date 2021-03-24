implement Cslookup;

include "sys.m";
	sys: Sys;
include "draw.m";

stderr: ref Sys->FD;

Cslookup: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	if (argv == nil || tl argv == nil) {
		sys->fprint(stderr, "usage: cslookup addr...\n");
		sys->raise("fail:usage");
	}
	cs := sys->open("/net/cs", Sys->ORDWR);
	if (cs == nil) {
		sys->fprint(stderr, "cslookup: cannot open cs: %r\n");
		sys->raise("fail:no cs");
	}
	err := 0;
	for (argv = tl argv; argv != nil; argv = tl argv)
		err = lookup(cs, hd argv) || err;
	if (err)
		sys->raise("fail:errors");
}

lookup(cs: ref Sys->FD, addr: string): int
{
	if (sys->fprint(cs, "%s", addr) == -1) {
		sys->fprint(stderr, "cslookup: address translation error: %r\n");
		return -1;
	}
	sys->seek(cs, 0, Sys->SEEKSTART);
	d := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(cs, d, len d)) > 0) {
		sys->print("%s\n", string d[0:n]);
	}
	if (n == -1) {
		sys->fprint(stderr, "cslookup: address translation error: %r\n");
		return -1;
	}
	return 0;
}
