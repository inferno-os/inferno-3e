implement WmLicense;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image: import draw;

include "tk.m";
	tk: Tk;

include	"wmlib.m";
	wmlib: Wmlib;

WmLicense: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

license_cfg := array[] of {
	"frame .ft",
	"text .ft.t -yscrollcommand {.ft.s set} -width 70w -height 18h",
	"scrollbar .ft.s -command {.ft.t yview}",
	"pack .ft.t .ft.s -side left -fill y",
	"frame .fb.a -bd 2 -relief sunken",
	"button .fb.a.b -height 2h -text {I Accept} -command {send cmd A}",
	"pack .fb.a.b -padx 5 -pady 5",
	"button .fb.d  -height 2h -text {I Do Not Accept} -command {send cmd D}",
	"frame .fb",
	"pack .fb.a .fb.d -padx 80 -pady 5 -side left",
	"pack .ft .fb",
	"pack propagate . 0",
	"update",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	wmlib= load Wmlib Wmlib->PATH;

	fd := sys->open("/licencedb/LICENCE", sys->OREAD);
	if(fd == nil)
		return;

	buf := array[32768] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return;

	for(i := 0; i < n; i++)
		if(buf[i] == byte '\r')
			buf[i] = byte ' ';

	agreement := string buf[0:n];
	buf = nil;

	wmlib->init();
	(t, menubut) := wmlib->titlebar(ctxt.screen, "", "Licence", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	wmlib->tkcmds(t, license_cfg);

	tk->cmd(t, ".ft.t insert end '"+agreement);
	tk->cmd(t, "update");

	for(;;) alt {
	menu := <-menubut =>
		if(menu == "exit") {
			wmlib->dialog(t, "warning -fg yellow",
				"Accept Terms",
				"You must either accept or decline\n"+
				"the terms of the licence",
				0, "Proceed"::nil);
			break;
		}
		wmlib->titlectl(t, menu);
	s := <-cmd =>
		case s[0] {
		'A' =>
			agree();
			return;
		'D' =>
			wmlib->dialog(t, "", "Terms not accepted",
					"Please reconsider!\n"+
					"Failing that, if you installed it, please delete the Inferno system from\n"+
					"your system and return the CD ROM\n"+
					"to Vita Nuova or its distributor, or discuss\n"+
					"your objections in comp.os.inferno.\n\n",
					0, "Exit"::nil);
			kill(1);
			kill(sys->pctl(0, nil));
			exit;
		}
	}
}

agree()
{
	user := rf("/dev/user");
	host := rf("/dev/sysname");

	uh := 0;
	for(i := 0; i < len user; i++)
		uh = uh*3 + user[i];
	hh := 0;
	for(i = 0; i < len host; i++)
		hh = hh*3 + host[i];

	path := sys->sprint("/licencedb/%.16bx", (big uh<<32)+big hh);
	fd := sys->create(path, sys->OWRITE, 8r444);
	sys->fprint(fd, "%s@%s %s", user, host, rf("/dev/time"));
}

rf(path: string) : string
{
	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		return "Anon";

	buf := array[512] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "Anon";

	return string buf[0:n];
}

kill(pid: int)
{
	fd := sys->open(sys->sprint("#p/%d/ctl", pid), sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "killgrp");
}
