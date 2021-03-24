implement Echo;

include "sys.m";
	sys: Sys;
include "draw.m";

Echo: module
{
	init:	fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	argv = tl argv;
	nonewline := 0;
	if (len argv > 0 && (hd argv == "-n" || hd argv == "--")) {
		nonewline = (hd argv == "-n");
		argv = tl argv;
	}
	s := "";
	if (argv != nil) {
		s = hd argv;
		for (argv = tl argv; argv != nil; argv = tl argv)
			s += " " + hd argv;
	}
	if (nonewline == 0) 
		s[len s] = '\n';
	a := array of byte s;
	if (sys->write(sys->fildes(1), a, len a) != len a) {
		sys->fprint(sys->fildes(2), "echo: write error: %r\n");
		sys->raise("fail: write error");
	}
}
