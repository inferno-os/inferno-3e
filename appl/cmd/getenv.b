implement Getenv;

include "sys.m";
include "draw.m";
include "env.m";

Getenv: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argl: list of string)
{
	sys := load Sys Sys->PATH;
	stderr := sys->fildes(2);
	env := load Env Env->PATH;
	if (env == nil) {
		sys->fprint(stderr, "cannot load Env module\n");
		exit;
	}
	if (len argl != 2) {
		sys->fprint(stderr, "usage: %s <variable>\n", hd argl);
		exit;
	}
	sys->print("%s\n", env->getenv(hd tl argl));
}