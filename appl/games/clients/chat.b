implement Clientmod;
include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect, Display, Image: import draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "../gameclient.m";
include "commandline.m";
	commandline: Commandline;
	Cmdline: import commandline;

stderr: ref Sys->FD;

playerid := -1;
win: ref Tk->Toplevel;

client(ctxt: ref Draw->Context, argv: list of string, nil: int)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil) {
		sys->fprint(stderr, "chat: cannot load %s: %r\n", Wmlib->PATH);
		sys->raise("fail:bad module");
	}
	commandline = load Commandline Commandline->PATH;
	if (commandline == nil) {
		sys->fprint(stderr, "chat: cannot load %s: %r\n", Commandline->PATH);
		sys->raise("fail:bad module");
	}
	commandline->init();

	wmlib->init();
	client1(ctxt);
}
cmdlinech: chan of string;
cmdline: ref Cmdline;

client1(ctxt: ref Draw->Context)
{
	gamefd := sys->fildes(0);

	sys->pctl(Sys->NEWPGRP, nil);

	winctl: chan of string;
	(win, winctl) = wmlib->titlebar(ctxt.screen, nil,
		"Cards", Wmlib->Appl);
	cmdlinech = chan of string;

	srvcmd := chan of string;
	spawn updateproc(gamefd, srvcmd);

	for (;;) alt {
	c := <-cmdlinech =>
		for (cmds := cmdline.event(c); cmds != nil; cmds = tl cmds)
			gamecmd(gamefd, "say " + quote(hd cmds));
	c := <-srvcmd =>
		applyupdate(c);
		cmd(win, "update");
	c := <-winctl =>
		if (c == "exit")
			sys->write(gamefd, array[0] of byte, 0);
		wmlib->titlectl(win, c);
	}
}

quote(s: string): string
{
	for (i := 0; i < len s; i++)
		if (s[i] == ' ')
			s[i] = '_';
	return s;
}

unquote(s: string): string
{
	for (i := 0; i < len s; i++)
		if (s[i] == '_')
			s[i] = ' ';
	return s;
}

gamecmd(fd: ref Sys->FD, s: string): int
{
	if (sys->fprint(fd, "%s\n", s) == -1) {
		sys->print("chat: cmd error on '%s': %r\n", s);
		return 0;
	}
	return 1;
}


updateproc(fd: ref Sys->FD, srvcmd: chan of string)
{
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn updateproc1(fd, srvcmd);
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("updateproc process exited: %s\n", string buf[0:n]);
}

updateproc1(fd: ref Sys->FD, srvcmd: chan of string)
{
	buf := array[Sys->ATOMICIO] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		(nil, lines) := sys->tokenize(string buf[0:n], "\n");
		for (; lines != nil; lines = tl lines)
			srvcmd <-= hd lines;
	}
	if (n < 0)
		sys->fprint(stderr, "chat: error reading updates: %r\n");
	sys->fprint(stderr, "chat: updateproc exiting\n");
}


applyupdate(s: string)
{
	(nt, toks) := sys->tokenize(s, " ");
	case hd toks {
	"playerid" =>
		# playerid clientid playerid name
		playerid = int hd tl tl toks;
		cmd(win, "frame .me");
		cmd(win, "label .me.l -text {Type here}");
		(cmdline, cmdlinech) = Cmdline.new(win, ".me.f", nil);
		cmd(win, "pack .me -side top -fill x");
		cmd(win, "pack .me.l -side top");
		cmd(win, "pack .me.f -side top -fill both -expand 1 -anchor w");

	"joingame" =>
		# joingame gameid clientid playerid name
		id := int hd tl tl tl toks;
		name := hd tl tl tl tl toks;
		if (id == playerid)
			break;
		f := "." + string id;
		cmd(win, "frame " + f);
		cmd(win, "label " + f + ".l -text '" + name);
		tf := f + ".tf";
		cmd(win, "frame " + tf);
		cmd(win, "scrollbar " + tf + ".s -orient vertical -command {" + tf + ".t yview}");
		cmd(win, "text " + tf + ".t -height 5h");
		cmd(win, "pack " + f + ".l -side top");
		cmd(win, "pack " + tf + ".s -side left -fill y");
		cmd(win, "pack " + tf + ".t -side top -fill both -expand 1");
		cmd(win, "pack " + tf + " -side top -fill both -expand 1");
		cmd(win, "pack " + f + " -side top -fill both -expand 1");

	"say" =>
		# say playerid text
		id := int hd tl toks;
		if (id == playerid)
			break;
		t := "." + string id + ".tf.t";
		cmd(win, t + " insert end '" + unquote(hd tl tl toks) + "\n");
		cmd(win, t + " see end");
	* =>
		sys->fprint(stderr, "chat: unknown update message '%s'\n", s);
	}
}

concat(v: list of string): string
{
	if (v == nil)
		return nil;
	s := hd v;
	for (v = tl v; v != nil; v = tl v)
		s += " " + hd v;
	return s;
}

kill(pid: int)
{
	if ((fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE)) != nil)
		sys->write(fd, array of byte "kill", 4);
}

showtk := 0;
cmd(top: ref Tk->Toplevel, s: string): string
{
	if (showtk)
		sys->print("tk: %s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr, "tk error %s on '%s'\n", e, s);
	return e;
}

