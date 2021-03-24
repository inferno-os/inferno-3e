implement Touch;

include "sys.m";
	sys: Sys;

include "draw.m";

include "daytime.m";
	daytime: Daytime;

include "arg.m";

stderr: ref Sys->FD;

Touch: module
{
	init: fn(ctxt: ref Draw->Context, argl: list of string);
};

usage()
{
	sys->fprint(stderr, "usage: touch [-c] files\n");
	sys->raise("fail:touch");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	force := 1;
	status := 0;
	arg := load Arg Arg->PATH;
	if(arg == nil)
		cantload(Arg->PATH);
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'c' =>	force = 0;
		* =>	usage();
		}
	args = arg->argv();
	arg = nil;
	if(args == nil)
		usage();
	daytime = load Daytime Daytime->PATH;
	if(daytime == nil)
		cantload(Arg->PATH);
	for(; args != nil; args = tl args)
		status += touch(force, hd args);
	if(status)
		sys->raise("fail:touch");
}

cantload(s: string)
{
	sys->fprint(stderr, "touch: can't load %s: %r\n", s);
	sys->raise("fail:load");
}

touch(force: int, name: string): int
{
	(ok, dir) := sys->stat(name);
	if(ok < 0 && force == 0) {
		sys->fprint(stderr, "touch: %s: cannot stat: %r\n", name);
		return 1;
	}
	if(ok < 0) {
		if((fd := sys->create(name, 0, 8r666)) == nil) {
			sys->fprint(stderr, "touch: %s: cannot create: %r\n", name);
			return 1;
		}
		return 0;
	}
	dir.mtime = dir.atime = daytime->now();
	if(sys->wstat(name, dir) < 0) {
		sys->fprint(stderr, "touch: %s: cannot change time: %r\n", name);
		return 1;
	}
	return 0;
}
