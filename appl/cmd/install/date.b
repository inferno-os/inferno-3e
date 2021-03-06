implement Date;

include "sys.m";
include "draw.m";
include "daytime.m";
include "arg.m";
include "bufio.m";
include "wrap.m";

Date: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	daytime := load Daytime Daytime->PATH;
	if(daytime == nil) {
		sys->fprint(stderr, "date: cannot load %s: %r\n", Daytime->PATH);
		sys->raise("fail:bad module");
	}
	arg := load Arg Arg->PATH;
	if (arg == nil) {
		sys->fprint(stderr, "date: cannot load %s: %r\n", Arg->PATH);
		sys->raise("fail:bad module");
	}
	wrap := load Wrap Wrap->PATH;
	if (wrap == nil) {
		sys->fprint(stderr, "date: cannot load %s: %r\n", Wrap->PATH);
		sys->raise("fail:bad module");
	}
	nflag := uflag := 0;
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'n' =>
			nflag = 1;
		'u' =>
			uflag = 1;
		* =>
			sys->fprint(stderr, "usage: date [-un] [seconds]\n");
			sys->raise("fail:usage");
		}
	}
	argv = arg->argv();
	if (argv != nil && (tl argv != nil || !isnum(hd argv))) {
		sys->fprint(stderr, "usage: date [-un] [seconds]\n");
		sys->raise("fail:usage");
	}
	now: int;
	if (argv != nil){
		s := hd argv;
		if(len s  == 9 && (s[0] >= 'A' && s[0] <= 'L'))
			now = wrap->string2now(s, 1);
		else
			now = int s;
	}
	else
		now = daytime->now();
	if (nflag)
		sys->print("%d\n", now);
	else if (uflag)
		sys->print("%s\n", daytime->text(daytime->gmt(now)));
	else
		sys->print("%s\n", daytime->text(daytime->local(now)));
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++){
		if (i == 0 && s[i] >= 'A' && s[i] <= 'L')
			continue;
		if (s[i] < '0' || s[i] > '9')
			return 0;
	}
	return 1;
}
