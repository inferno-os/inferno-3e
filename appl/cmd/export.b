#
# export current name space on a connection
#

implement Export;

include "sys.m";
	sys: Sys;
include "draw.m";

Export: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr(), "Usage: export [-a] [-n] dir [connection]\n");
	sys->raise("fail:usage");
}

init(nil: ref Draw->Context, argv: list of string)
{
	# usage: export dir [connection]
	sys = load Sys Sys->PATH;
	if(argv != nil)
		argv = tl argv;
	newns := 1;
	eflag := Sys->EXPWAIT;
	for(; argv != nil && (hd argv)[0] == '-'; argv = tl argv)
		for(i := 1; i < len hd argv; i++)
			case (hd argv)[i] {
			'a' => eflag = Sys->EXPASYNC;
			'n' => newns = 0;
			* => usage();
			}
	n := len argv;
	if (n < 1 || n > 2)
		usage();
	fd: ref Sys->FD;
	if (n == 2) {
		if ((fd = sys->open(hd tl argv, Sys->ORDWR)) == nil) {
			sys->fprint(stderr(), "export: can't open %s: %r\n", hd tl argv);
			sys->raise("fail:open");
		}
	} else
		fd = sys->fildes(0);
	dir := hd argv;
	if(newns || dir != "/")
		sys->pctl(Sys->FORKNS, nil);
	if (dir != "/") {
		if (sys->bind(dir, "/", Sys->MREPL | Sys->MCREATE) == -1) {
			sys->fprint(stderr(), "export: cannot bind %s: %r\n", dir);
			sys->raise("fail:bind");
		}
	}
	if (sys->export(fd, eflag) < 0) {
		sys->fprint(stderr(), "export: can't export: %r\n");
		sys->raise("fail:export");
	}
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
