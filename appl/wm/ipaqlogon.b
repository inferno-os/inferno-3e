implement IpaqLogon;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Rect, Image, Display, Screen: import draw;

include "tk.m";
	tk: Tk;

include "wmlib.m";

include "readdir.m";

include "newns.m";

IpaqLogon: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

Command: module
{
	init: fn(nil: ref Draw->Context, nil: list of string);
};

screen: ref Screen;

tksetup := array [] of {
	"frame .f",
	"listbox .f.lb -yscrollcommand {.f.sb set}",
	"scrollbar .f.sb -orient vertical -command {.f.lb yview}",
	"button .login -text {Login} -command {send cmd login}",
	"pack .f.sb .f.lb -in .f -side left -fill both -expand 1",
	"pack .f -side top -anchor center -fill y -expand 1",
	"pack .login -side top",
	"pack propagate . 0",
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys sys->PATH;
	sys->pctl(Sys->NEWPGRP|Sys->FORKNS, nil);

	draw = load Draw Draw->PATH;
	if(draw == nil)
		badload(Draw->PATH);
	tk = load Tk Tk->PATH;
	if(tk == nil)
		badload(Tk->PATH);
	wmlib := load Wmlib Wmlib->PATH;
	if(wmlib == nil)
		badload(Wmlib->PATH);

	sys->unmount(nil, "/dis/wm/wm.dis");	# in case ipaqlogon has been bound over wm/wm

	wmlib->init();

	getscreen();
	spawn mouse();
	top := tk->toplevel(screen, nil);
	cmd := chan of string;
	tk->namechan(top, cmd, "cmd");
	tkcmds(top, tksetup);
	tkcmd(top, ". configure -width " + string screen.image.r.dx());
	tkcmd(top, ". configure -height " + string screen.image.r.dy());

	usrlist := getusers();

	for (; usrlist != nil; usrlist = tl usrlist) {
		u := hd usrlist;
		u = wmlib->tkquote(u);
		tkcmd(top, ".f.lb insert end " + u );
	}
	tkcmd(top, "update");
	u := "";
	for (;;) {
		<- cmd;
		sel := tkcmd(top, ".f.lb curselection");
		if (sel == nil)
			continue;
		u = tkcmd(top, ".f.lb get " + sel);
		if (u != nil)
			break;
	}

	killgrp();
	screen = nil;

	fd := sys->open("/dev/user", Sys->OWRITE);
	buf := array of byte u;
	if (sys->write(fd, buf, len buf) <= 0) {
		sys->fprint(stderr(), "ipaqlogon: cannot set user: %r\n");
		sys->sleep(4000);
	}
	fd = nil;

	sys->chdir("/usr/"+u);
	newns := load Newns Newns->PATH;
	if (newns != nil) {
		(e, nil) := sys->stat("lib/ipaqns");
		if (e == 0) {
			err := newns->newns(nil, "lib/ipaqns");
			if (err != nil)
				sys->fprint(stderr(), "%s\n", err);
		}
	}
	wm := load Command "/dis/wm/wm.dis";
	if (wm == nil)
		sys->print("cannot load /dis/wm/wm.dis: %r\n");
	else
		spawn wm->init(nil, "wm"::nil);
}

getscreen()
{
	display := Display.allocate(nil);
	if(display == nil)
		err("cannot allocate display: %r");

	disp := display.image;
	fill := display.rgb(73,147, 221);
	screen = Screen.allocate(disp, fill, 1);
	disp.draw(disp.r, screen.fill, nil, disp.r.min);
}

getusers(): list of string
{
	readdir := load Readdir Readdir->PATH;
	if(readdir == nil)
		badload(Readdir->PATH);
	(dirs, nil) := readdir->init("/usr", Readdir->NAME);
	n: list of string;
	for (i := len dirs -1; i >=0; i--)
		if (dirs[i].qid.path & Sys->CHDIR)
			n = dirs[i].name :: n;
	return n;
}

mouse()
{
	fd := sys->open("/dev/pointer", sys->OREAD);
	if(fd == nil)
		err("cannot open /dev/pointer: %r");

	n := 0;
	buf := array[100] of byte;
	for(;;) {
		n = sys->read(fd, buf, len buf);
		if(n <= 0)
			break;

		if(int buf[0] != 'm' || n != 37)
			continue;

		x := int(string buf[ 1:13]);
		y := int(string buf[12:25]);
		b := int(string buf[24:37]);
		tk->mouse(screen, x, y, b);
	}
}

tkcmd(t: ref Tk->Toplevel, cmd: string): string
{
	s := tk->cmd(t, cmd);
	if (s != nil && s[0] == '!') {
		sys->print("%s\n", cmd);
		sys->print("tk error: %s\n", s);
	}
	return s;
}

tkcmds(t: ref Tk->Toplevel, cmds: array of string)
{
	for (i := 0; i < len cmds; i++)
		tkcmd(t, cmds[i]);
}

killgrp()
{
	b := array of byte "killgrp";
	fd := sys->open("#p/"+string sys->pctl(0, nil) + "/ctl", Sys->OWRITE);
	sys->write(fd, b, len b);
}

badload(s: string)
{
	err(sys->sprint("can't load %s: %r", s));
}

err(s: string)
{
	sys->fprint(stderr(), "ipaqlogon: %s\n", s);
	killgrp();
	exit;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}
