implement Logwindow;

#
# Copyright © 1999 Vita Nuova Limited.  All rights reserved.
#

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
	cmd: import tk;
include "wmlib.m";
	wmlib: Wmlib;
include "arg.m";

Logwindow: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

cfg := array[] of {
	"frame .bf",
	"checkbutton .bf.scroll -text Scroll -variable scroll -command {send cmd scroll}",
	".bf.scroll select",
	"checkbutton .bf.popup -text {Pop up} -variable popup -command {send cmd popup}",
	".bf.popup select",
	"pack .bf.scroll .bf.popup -side left",
	"frame .t",
	"scrollbar .t.scroll -command {.t.t yview}",
	"text .t.t -height 7c -yscrollcommand {.t.scroll set}",
	"pack .t.scroll -side left -fill y",
	"pack .t.t -fill both -expand 1",
	"pack .Wm_t -fill x",
	"pack .bf -anchor w",
	"pack .t -fill both -expand 1",
	"pack propagate . 0",
};

eflag := 0;

badmodule(p: string)
{
	sys->fprint(stderr, "logwindow: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil)
		badmodule(Wmlib->PATH);
	wmlib->init();

	tk = load Tk Tk->PATH;
	if (tk == nil)
		badmodule(Tk->PATH);

	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);

	if (ctxt == nil) {
		sys->fprint(stderr, "logwindow: nil Draw->Context\n");
		sys->raise("fail:no draw context");
	}
	gflag := 0;
	title := "Log Window";
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'e' =>
			eflag = 1;
		'g' =>
			gflag = 1;
		* =>
			sys->fprint(stderr, "usage: logwindow [-ge] [title]\n");
			sys->raise("fail:usage");
		}
	}
	argv = arg->argv();
	if (argv != nil)
		title = hd argv;

	if (!gflag)
		sys->pctl(Sys->NEWPGRP, nil);

	(top, wmchan) := wmlib->titlebar(ctxt.screen, "", title, Wmlib->Hide|Wmlib->Resize);
	if (top == nil) {
		sys->fprint(stderr, "logwindow: couldn't make window\n");
		sys->raise("fail: no window");
	}
	cmd(top, ". unmap");

	wmlib->tkcmds(top, cfg);
	if ((err := tk->cmd(top, "variable lasterror")) != nil) {
		sys->fprint(stderr, "logwindow: tk error: %s\n", err);
		sys->raise("fail: tk error");
	}

	logwin(sys->fildes(0), top, wmchan);
}

scrolling := 1;
popup := 1;

logwin(fd: ref Sys->FD, top: ref Tk->Toplevel, wmchan: chan of string)
{
	cmd := chan of string;
	tk->namechan(top, cmd, "cmd");
	raised := 0;
	spawn hide(top, wmchan);
	ichan := chan of int;
	spawn inputmon(fd, top, ichan);
	for (;;) alt {
	e := <-ichan =>
		if (e == 0 && eflag) {
			wmlib->titlectl(top, "exit");
			exit;
		}
		if (!raised && popup)
			wmlib->unhide();
	msg := <-cmd =>
		case msg {
		"scroll" =>
			scrolling = int tk->cmd(top, "variable scroll");
		"popup" =>
			popup = int tk->cmd(top, "variable popup");
		}
	msg := <-wmchan =>
		case msg {
		"task" =>
			raised = 0;
			spawn hide(top, wmchan);
		"untask" =>
			raised = 1;
		* =>
			wmlib->titlectl(top, msg);
		}
	}
}

hide(top: ref Tk->Toplevel, wmchan: chan of string)
{
	wmlib->titlectl(top, "task");
	wmchan <-= "untask";
}

inputmon(fd: ref Sys->FD, top: ref Tk->Toplevel, ichan: chan of int)
{
	buf := array[Sys->ATOMICIO] of byte;
	t := 0;
	while ((n := sys->read(fd, buf[t:], len buf-t)) > 0) {
		t += n;
		cl := 0;
		for (i := t - 1; i >= 0; i--) {
			(nil, cl, nil) = sys->byte2char(buf, i);
			if (cl > 0)
				break;
		}
		if (cl == 0)
			continue;
		logmsg(top, ichan, string buf[0:i+cl]);
		buf[0:] = buf[i+cl:t];
		t -= i + cl;
	}
	if (n < 0)
		logmsg(top, ichan, sys->sprint("Input error: %r\n"));
	else
		logmsg(top, ichan, "Got EOF\n");
	if (eflag)
		ichan <-= 0;
}

logmsg(top: ref Tk->Toplevel, ichan: chan of int, m: string)
{
	tk->cmd(top, ".t.t insert end '"+m);
	if (scrolling)
		tk->cmd(top, ".t.t see end");
	tk->cmd(top, "update");
	ichan <-= 1;
}
