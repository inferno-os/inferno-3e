implement CsGet;

Mod: con "csget";

include "sys.m";
  sys: Sys;
  stderr: ref Sys->FD;

include "draw.m";
include "string.m";

CsGet: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

verbose := 0;

init(nil: ref Draw->Context, args: list of string)
{ 
	name: string;

	if(args != nil)
		args = tl args;
	if(args != nil)
		(name, args) = (hd args, tl args);
	if (name != nil && name[0] == '-') {
		name = nil;
		verbose = 1;
		if (args != nil)
			name = hd args;
	}
	(truename, address, other) := hostinfo(name);
	if (truename != nil) {
		sys->print("hostname: %s, address: %s, other addrs: ", truename, address);
		printl(other);
	}
}

BUFLEN: con 64;

hostinfo(name: string): (string, string, list of string)
{
	if (sys == nil) {
		sys = load Sys Sys->PATH;
		if (sys == nil)
			return (nil, nil, nil);
		stderr = sys->fildes(2);
	}

	if (name == nil) name = sysname();

	address: string = nil;
	maddrs: list of string;

	fd := sys->open("/net/cs", sys->ORDWR);
	if (fd == nil) {
		sys->fprint(stderr, Mod+": Cs unavailable: %r\n");
		return (nil, nil, nil);
	}

	(n, nil) := sys->tokenize(name, "!");
	query: array of byte;
	if (n == 1)
		query = array of byte ("tcp!"+name+"!styx");
	else if (n == 3)
		query = array of byte (name);
	else {
		sys->fprint(stderr, Mod+": incomplete host name: %s\n", name);
		return (nil, nil, nil);
	}

	st, wt, rt, dt: int;

	if (verbose) st = sys->millisec();
	n = sys->write(fd, query, len query);
	if (n < 0) {
		sys->fprint(stderr, Mod+": can't write: %r\n");
		return (nil, nil, nil);
	}

	buf := array[BUFLEN] of byte;
	r: string;

	if (verbose) wt = sys->millisec();
	if (sys->seek(fd, 0, sys->SEEKSTART) < 0) {
		sys->fprint(stderr, Mod+": seek error %r\n");
		return (name, nil , nil);
	}

	if (verbose) rt = sys->millisec();
	while ((n = sys->read(fd, buf, len buf)) > 0)
		r += string buf[0:n]+"\n";
	if(n < 0)
		sys->fprint(stderr, Mod+": read error %r\n");

	if (verbose) dt = sys->millisec();

	(ok, l) := sys->tokenize(r, " \t\n");
	rl: list of string;
	for (; l != nil; l = tl l) {
		r = hd l;
		(n, rl) = sys->tokenize(r, "!");
		if (n > 1) maddrs = hd rl :: maddrs;
	}
  
	if (verbose)
		sys->fprint(stderr, Mod+": timing write %d read %d respond %d\n", wt -st, rt -wt, dt -rt);
  
	if (maddrs == nil)
		return (name, nil, nil);
	maddrs = reverse(maddrs);
	return (name, hd maddrs, tl maddrs);
}

printl(args: list of string)
{
	sys->print("(");
	if (args != nil)
		for(;; args = tl(args)) {
			sys->print("%s", hd(args));
			if( tl(args) == nil)
				break;
			else
				sys->print(" ");
		}
	sys->print(")\n");
}

reverse(l: list of string): list of string
{
	t: list of string;
	for(; l != nil; l = tl l)
		t = hd l :: t;
	return t;
}

sysname(): string
{
	buf := array[64] of byte;
	fd := sys->open("/dev/sysname", sys->OREAD);
	n := sys->read(fd, buf, len buf);
	if (n <= 0) {
		sys->fprint(stderr, Mod+": read /dev/sysname %r\n");
		return "*";
	}
	return string buf[0:n];
}
