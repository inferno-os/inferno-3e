implement Gameclient;
include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";

Gameclient: module {
	init:   fn(ctxt: ref Draw->Context, argv: list of string);
};

GAMESRVPATH: con "./gamesrv.dis";
GAMEDIR: con "/n/remote";
stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

badmodule(p: string)
{
	sys->fprint(stderr(), "gameclient: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	local := 1;

	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);
	gameclient(ctxt, local);
}

gameclient(ctxt: ref Draw->Context, local: int)
{
	mountgame(ctxt, local);
	fd := sys->open(GAMEDIR + "/players", Sys->ORDWR);
	if (fd == nil) {
		sys->fprint(stderr(), "gameclient: game server not available\n");
		sys->raise("fail:errors");
	}

	updatech := chan of string;
	spawn readplayers(fd, updatech);

	sys->sleep(4000);
	sys->print("killgrp\n");
	if (sys->fprint(sys->open("/prog/" + string sys->pctl(0, nil) + "/ctl", Sys->OWRITE), "killgrp") == -1)
		sys->print("kill failed: %r\n");
	exit;
}

readplayers(fd: ref Sys->FD, updatech: chan of string)
{
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		for (; lines != nil; lines = tl lines)
			;
	}
	if (n < 0) {
		sys->fprint(stderr(), "gameclient: error reading players (fd %d): %r\n", fd.fd);
		sys->raise("panic");
	}
}

mountgame(ctxt: ref Draw->Context, local: int)
{
	startserver(ctxt, 1, nil);
}

startserver(ctxt: ref Draw->Context, local: int, addr: string): string
{
	sh := load Sh Sh->PATH;
	if (sh == nil)
		return sys->sprint("cannot load %s: %r", Sh->PATH);

	args := "-l" :: GAMEDIR :: nil;
	args = "{$* >[2=1] | {wm/logwindow -eg 'game server'&}}" :: GAMESRVPATH :: args;
	if (sh->run(ctxt, args) != nil)
		return "cannot start server";
	return nil;
}
