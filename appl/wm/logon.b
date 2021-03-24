implement WmLogon;
#
# Logon program for Wm environment
#
include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Screen, Display, Image, Context, Point, Rect: import draw;
	ctxt: ref Context;

include "tk.m";
	tk: Tk;

include "sh.m";
include "newns.m";

include "keyring.m";
include "security.m";

WmLogon: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

cfg := array[] of {
	"label .p -bitmap @/icons/inferno.bit -borderwidth 2 -relief raised",
	"frame .l -bg red",
	"label .l.u -fg black -bg silver -text {User Name:} -anchor w",
	"pack .l.u -fill x",
	"frame .e",
	"entry .e.u -bg white",
	"pack .e.u -fill x",
	"frame .f -borderwidth 2 -relief raised",
	"pack .l .e -side left -in .f",
	"pack .p .f -fill x",
	"bind .e.u <Key-\n> {send cmd ok}",
	"focus .e.u"
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	sys->pctl(sys->NEWPGRP, nil);

	mfd := sys->open("/dev/pointer", sys->OREAD);
	if(mfd == nil) {
		sys->fprint(stderr(), "logon: cannot open /dev/pointer: %r\n");
		sys->raise("fail:no mouse");
	}
	keyfd := sys->open("/dev/keyboard", sys->OREAD);
	if(keyfd == nil) {
		sys->fprint(stderr(), "logon: cannot open /dev/keyboard: %r");
		sys->raise("fail:no keyboard");
	}

	ctxt = ref Context;
	ctxt.display = Display.allocate(nil);
	if(ctxt.display == nil) {
		sys->fprint(stderr(), "logon: cannot initialize display: %r\n");
		sys->raise("fail:no display");
	}

	disp := ctxt.display.image;
	ctxt.screen = Screen.allocate(disp, ctxt.display.rgb(73, 147, 221), 1);
	disp.draw(disp.r, ctxt.screen.fill, nil, disp.r.min);

	progdir := "#p/" + string sys->pctl(0, nil);
	kfd := sys->open(progdir+"/ctl", sys->OWRITE);
	if(kfd == nil) {
		notice(sys->sprint("cannot open %s:  %r", progdir+"/ctl"));
		sys->raise("fail:bad prog dir");
	}
	waitfd := sys->open(progdir+"/wait", sys->OREAD);
	if(waitfd == nil) {
		notice(sys->sprint("cannot open %s: %r", progdir+"/wait"));
		sys->raise("fail:bad prog dir");
	}
	waitdone := chan of int;
	spawn waiter(waitfd, 2, waitdone);
	<-waitdone;
	spawn mouse(ctxt.screen, mfd);
	spawn keyboard(ctxt.screen, keyfd);
	usr := "";
	if(args != nil) {
		args = tl args;
		if(args != nil && hd args == "-u") {
			args = tl args;
			if(args != nil) {
				usr = hd args;
				args = tl args;
			}
		}
	}

	if (usr == nil || !logon(usr)) {
		(panel, cmd) := makepanel(ctxt);
		for(;;) {
			tk->cmd(panel, "focus .e.u; update");
			<-cmd;
			usr = tk->cmd(panel, ".e.u get");
			if(usr == "") {
				notice("You must supply a user name to login");
				continue;
			}
			if(logon(usr)) {
				panel = nil;
				break;
			}
			tk->cmd(panel, ".e.u delete 0 end");
		}
	}
	t := tk->toplevel(ctxt.screen, "-x 4000 -y 0");
	tk->cmd(t, "cursor -bitmap cursor.wait");
	(ok, nil) := sys->stat("namespace");
	if(ok >= 0) {
		ns := load Newns Newns->PATH;
		if(ns == nil)
			notice("failed to load namespace builder");
		else if ((nserr := ns->newns(nil, nil)) != nil)
			notice("namespace error:\n"+nserr);
	}
	sys->fprint(kfd, "killgrp");
	mfd = nil;
	keyfd = nil;
	tk->cmd(t, "cursor -default");
	<- waitdone;
	errch := chan of string;
	spawn exec(args, errch);
	err := <-errch;
	if (err != nil) {
		sys->fprint(stderr(), "logon: %s\n", err);
		sys->raise("fail:exec failed");
	}
}

makepanel(ctxt: ref Draw->Context): (ref Tk->Toplevel, chan of string)
{
	t := tk->toplevel(ctxt.screen, "-x 4000 -y 0 -bd 2 -bg silver");

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	for(i := 0; i < len cfg; i++)
		tk->cmd(t, cfg[i]);
	err := tk->cmd(t, "variable lasterr");
	if(err != nil) {
		sys->fprint(stderr(), "logon: tk error: %s\n", err);
		sys->raise("fail:config error");
	}
	tk->cmd(t, "update");
	org: Point;
	org.x = ctxt.display.image.r.dx() / 2 - t.image.r.dx() / 2;
	org.y = ctxt.display.image.r.dy() / 3 - t.image.r.dy() / 2;
	if (org.y < 0)
		org.y = 0;
	tk->cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
	return (t, cmd);
}

exec(argv: list of string, errch: chan of string)
{
	sys->pctl(sys->NEWFD, 0 :: 1 :: 2 :: nil);
	e := ref Sys->Exception;
	if (sys->rescue("fail:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		exit;
	}

	argv = "/dis/wm/wm.dis" :: nil;
	cmd := load Command hd argv;
	if (cmd == nil) {
		errch <-= sys->sprint("cannot load %s: %r", hd argv);
	} else {
		errch <-= nil;
		spawn cmd->init(nil, argv);
	}
}

logon(user: string): int
{
	userdir := "/usr/"+user;
	if(sys->chdir(userdir) < 0) {
		notice("There is no home directory for \""+
			user+"\"\nmounted on this machine");
		return 0;
	}

	#
	# Set the user id
	#
	fd := sys->open("/dev/user", sys->OWRITE);
	if(fd == nil) {
		notice(sys->sprint("failed to open /dev/user: %r"));
		return 0;
	}
	b := array of byte user;
	if(sys->write(fd, b, len b) < 0) {
		notice("failed to write /dev/user\nwith error "+sys->sprint("%r"));
		return 0;
	}

	licence(user);

	return 1;
}

notecmd := array[] of {
	"frame .f",
	"label .f.l -bitmap error -foreground red",
	"button .b -text Continue -command {send cmd done}",
	"focus .f",
	"bind .f <Key-\n> {send cmd done}",
	"pack .f.l .f.m -side left -expand 1",
	"pack .f .b",
	"pack propagate . 0",
};

centre(t: ref Tk->Toplevel)
{
	org: Point;
	sz := Point(int tk->cmd(t, ". cget -width"), int tk->cmd(t, ". cget -height"));
	r := t.image.screen.image.r;
	if (sz.x > r.dx())
		tk->cmd(t, ". configure -width " + string r.dx());
	org.x = t.image.screen.image.r.dx() / 2 - t.image.r.dx() / 2;
	org.y = t.image.screen.image.r.dy() / 3 - t.image.r.dy() / 2;
	if (org.y < 0)
		org.y = 0;
	tk->cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
}

notice(message: string)
{
	
	t := tk->toplevel(ctxt.screen, "-borderwidth 2 -relief raised");
	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	tk->cmd(t, "label .f.m -anchor nw -text '"+message);
	for(i := 0; i < len notecmd; i++)
		tk->cmd(t, notecmd[i]);
	centre(t);
	tk->cmd(t, "update; cursor -default");
	<-cmd;
}

mouse(s: ref Draw->Screen, fd: ref Sys->FD)
{
	n := 0;
	buf := array[100] of byte;
	for(;;) {
		n = sys->read(fd, buf, len buf);
		if(n <= 0)
			break;

		if(int buf[0] == 'm' && n == 37) {
			x := int(string buf[ 1:13]);
			y := int(string buf[12:25]);
			b := int(string buf[24:37]);
			tk->mouse(s, x, y, b);
		}
	}
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

keyboard(s: ref Draw->Screen, dfd: ref Sys->FD)
{
	buf := array[10] of byte;
	i := 0;
	for(;;) {
		n := sys->read(dfd, buf[i:], len buf - i);
		if(n < 1){
			notice(sys->sprint("keyboard read error: %r"));
			break;
		}
		i += n;
		while(i >0 && (nutf := sys->utfbytes(buf, i)) > 0){
			str := string buf[0:nutf];
			for (j := 0; j < len str; j++)
				tk->keyboard(s, int str[j]);
			buf[0:] = buf[nutf:i];
			i -= nutf;
		}
	}
}

licence(user: string)
{
	host := rf("/dev/sysname");

	uh := 0;
	for(i := 0; i < len user; i++)
		uh = uh*3 + user[i];
	hh := 0;
	for(i = 0; i < len host; i++)
		hh = hh*3 + host[i];

	path := sys->sprint("/licencedb/%.16bx", (big uh<<32)+big hh);
	(ok, nil) := sys->stat(path);
	if(ok >= 0)
		return;

	wm := load Command "/dis/wm/license.dis";
	if(wm == nil)
		return;

	wm->init(ctxt, "license.dis" :: nil);
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

waiter(waitfd: ref Sys->FD, n: int, waitdone: chan of int)
{
	sys->pctl(sys->NEWPGRP, nil);
	waitdone <-= 0;
	if (waitfd != nil) {
		b := array[sys->WAITLEN] of byte;
		while(n > 0) {
			if(sys->read(waitfd, b, sys->WAITLEN) <= 0)
				break;
			n--;
		}
	}
	waitdone <-= 0;
}
