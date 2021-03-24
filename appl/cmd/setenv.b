implement Setenv;

include "sys.m";
include "draw.m";
include "env.m";

Setenv: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argl: list of string)
{
	val : string;

	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	env := load Env Env->PATH;
	if (env == nil) {
		sys->fprint(stderr, "cannot load Env module\n");
		exit;
	}
	if (len argl == 2)
		val = nil;
	else if (len argl == 3)
		val = hd tl tl argl;
	else {
		sys->fprint(stderr, "usage: %s <variable> <value> or %s <variable>\n", hd argl, hd argl);
		exit;
	}
	if (env->setenv(hd tl argl, val) < 0)
		sys->fprint(stderr, "setenv failed: %r\n");
	exit;
}