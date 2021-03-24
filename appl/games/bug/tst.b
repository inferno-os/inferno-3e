implement Test;

include "sys.m";
	sys: Sys;
include "draw.m";
include "styxlib.m";
	styxlib: Styxlib;
	Styxserver, Tmsg, Rmsg: import styxlib;

Test: module {
	init: fn(nil: ref Draw->Context, nil: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	styxlib = load Styxlib Styxlib->PATH;

	mount();

	sys->fprint(sys->open("/prog/" + string sys->pctl(0, nil) + "/ctl", Sys->OWRITE), "killgrp");
	sys->print("done killgrp\n");
	exit;
}

mount()
{
	fds := array[2] of ref Sys->FD;
	sys->pipe(fds);
	(tch, srv) := Styxserver.new(fds[0]);
	sync := chan of int;
	spawn server(sync, srv, tch);
	<-sync;
	if (sys->mount(fds[1], "/n/remote", Sys->MREPL, nil) == -1) {
		sys->print("mount failed: %r\n");
		exit;
	}
	sys->print("mounted\n");
}

server(sync: chan of int, srv: ref Styxserver, tch: chan of ref Tmsg)
{
#	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	for (;;) {
		msg := <-tch;
		if (msg == nil) {
			sys->print("EOF for server\n");
			exit;
		}
		pick m := msg {
		Attach =>
			srv.devattach(m);
		Clone =>
			srv.devclone(m);
		Clunk =>
			srv.devclunk(m);
		Flush =>
			srv.reply(ref Rmsg.Flush(m.tag));
		* =>
			srv.reply(ref Rmsg.Error(msg.tag, "error"));
		}
	}
}
