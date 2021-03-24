implement Rm;

include "sys.m";
	sys: Sys;
include "draw.m";

include "readdir.m";
	readdir: Readdir;

Rm: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

stderr: ref Sys->FD;
quiet := 0;
errcount := 0;

usage()
{
	sys->fprint(stderr, "Usage: rm [-fr] file ...\n");
	sys->raise("fail: usage");
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	argv = tl argv;
Opt:
	while(argv != nil && (s := hd argv)[0] == '-') {
		argv = tl argv;
		for(i := 1; i < len s; i++)
			case s[i] {
			'r' =>
				readdir = load Readdir Readdir->PATH;
				if(readdir == nil)
					sys->fprint(stderr, "rm: can't load Readdir: %r\n");
			'f' =>
				quiet = 1;
			'-' =>
				break Opt;
			* =>
				usage();
			}
	}
	for(; argv != nil; argv = tl argv) {
		name := hd argv;
		if(sys->remove(name) < 0) {
			e := sys->sprint("%r");
			(ok, d) := sys->stat(name);
			if(readdir != nil && ok >= 0 && (d.mode & Sys->CHDIR) != 0)
				rmdir(name);
			else
				err(name, e);
		}
	}
	if(errcount > 0)
		sys->raise("fail: errors");
}

rmdir(name: string)
{
	(d, n) := readdir->init(name, Readdir->NONE|Readdir->COMPACT);
	for(i := 0; i < n; i++){
		path := name+"/"+d[i].name;
		if(d[i].mode & Sys->CHDIR)
			rmdir(path);
		else
			remove(path);
	}
	remove(name);
}

remove(name: string)
{
	if(sys->remove(name) < 0)
		err(name, sys->sprint("%r"));
}

err(name, e: string)
{
	if(!quiet) {
		sys->fprint(stderr, "rm: %s: %s\n", name, e);
		errcount++;
	}
}
