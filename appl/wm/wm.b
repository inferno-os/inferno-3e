implement Wm;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Screen, Display, Image, Rect: import draw;

include "tk.m";
	tk: Tk;

include "wmlib.m";
	wmlib: Wmlib;

include "sh.m";
	shell: Sh;
	Listnode, Context: import shell;
	myself: Shellbuiltin;
myselfbuiltin: Shellbuiltin;

include "arg.m";

Wm: module 
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
	initbuiltin: fn(c: ref Context, sh: Sh): string;
	runbuiltin: fn(c: ref Context, sh: Sh,
			cmd: list of ref Listnode, last: int): string;
	runsbuiltin: fn(c: ref Context, sh: Sh,
			cmd: list of ref Listnode): list of ref Listnode;
	whatis: fn(c: ref Sh->Context, sh: Sh, name: string, wtype: int): string;
	getself: fn(): Shellbuiltin;
};

# execute this if no menu items have been created
# by the init script.
defaultscript :=
	"{menu shell " +
		"{{autoload=std; load $autoload; pctl newpgrp; wm/sh} >/chan/wmstdout >[2] /chan/wmstderr&}}";

TSCRIPT:	con 1024;		# Lines kept in console transcript

EDGE: con 8;

rband: int;
rr, origrr, visr: Draw->Rect;
rubberband := array[8] of ref Image;
screen: ref Draw->Screen;
tbtop: ref Tk->Toplevel;
smallscreen := 0;

WinMinX:	con	100;
WinMinY:	con	80;

RbTotk, RbMove, RbTrack, RbSize, RbDrag: con iota;
DragT, DragB, DragL, DragR: con 1<<iota;

Rdreq: adt
{
	off:	int;
	nbytes:	int;
	fid:	int;
	rc:	chan of (array of byte, string);
};
rdreq: Rdreq;

Icon: adt
{
	name:	string;
	repl:	int;
	fid:	int;
	wc:	Sys->Rwrite;
};
icons: list of Icon;

badmodule(p: string)
{
	sys->fprint(stderr(), "wm: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys  = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk   = load Tk Tk->PATH;

	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil) badmodule(Wmlib->PATH);

	shell = load Sh Sh->PATH;
	if (shell == nil) badmodule(Sh->PATH);

	myselfbuiltin = load Shellbuiltin "$self";
	if (myselfbuiltin == nil) badmodule("$self(Shellbuiltin)");

	sys->bind("#p", "/prog", sys->MREPL);
	sys->bind("#s", "/chan", sys->MBEFORE);

	sys->pctl(sys->NEWPGRP, nil);

	fill: string;
	startmenu := 1;
	arg := load Arg Arg->PATH;
	if (arg != nil) {
		arg->init(argv);
		while((c := arg->opt()) != 0)
			case c {
			'b' =>
				fill = arg->arg();
			's' =>
				startmenu = 0;
			* =>
				;
			}
		argv = arg->argv();
		arg = nil;
	}

	sync := chan of string;
	rbdone := chan of int;
	spawn mouse(sync, rbdone);
	if ((err := <-sync) != nil) {
		sys->fprint(stderr(), "wm: %s\n", err);
		sys->raise("fail:no mouse");
	}

	if (ctxt == nil) {
		err: string;
		(ctxt, err) = makedrawcontext(fill);
		if (ctxt == nil) {
			sys->fprint(stderr(), "wm: %s\n", err);
			sync <-= "die, sucker";
			sys->raise("fail:no draw context");
		}
	}
	screen = ctxt.screen;

	sync <-= nil;			# inform mouse proc that screen is now available.
	smallscreen = ctxt.screen.image.r.dy() < 480;

	bandinit();

	spawn keyboard(screen);

	tbtop = tk->toplevel(screen, nil);
	h := tbheight(tbtop);
	
	cmd(tbtop, ". configure -y "+string (screen.image.r.max.y-h));
	wmlib->init();

	visr = ((EDGE, -(tbht(tbtop)-EDGE)), (screen.image.r.max.x-EDGE, screen.image.r.max.y-h-EDGE));

	shctxt := Context.new(ctxt);
	shctxt.addmodule("wm", myselfbuiltin);

	cmdch := chan of string;
	exec := chan of string;
	task := chan of string;
	tk->namechan(tbtop, cmdch, "cmd");
	tk->namechan(tbtop, exec, "exec");
	tk->namechan(tbtop, task, "task");
	cmd(tbtop, "frame .toolbar -height " + string h + " -width "+string screen.image.r.max.x);
	cmd(tbtop, "pack propagate .toolbar 0");
	if (startmenu) {
		cmd(tbtop, "button .toolbar.start -width 32 -bitmap vitasmall.bit");
		cmd(tbtop, "bind .toolbar.start <ButtonRelease-1> {}");
		cmd(tbtop, "bind .toolbar.start <Button-1> {send cmd post}");

		cmd(tbtop, "pack .toolbar.start -side left");
	}
	cmd(tbtop, "pack .toolbar");

	cmd(tbtop, "menu .m");

	rband = RbTotk;
	wmIO := sys->file2chan("/chan", "wm");
	if(wmIO == nil) {
		wmdialog("error -fg red", "Wm startup",
			"Failed to make /chan/wm:\n"+sys->sprint("%r"),
			0, "Exit"::nil);
		return;
	}
	snarfIO := sys->file2chan("/chan", "snarf");
	if(snarfIO == nil) {
		wmdialog("error -fg red", "Wm startup",
			"Failed to make /chan/snarf:\n"+sys->sprint("%r"),
			0, "Exit"::nil);
		return;
	}
	rdreq.fid = -1;

	iostdout := sys->file2chan("/chan", "wmstdout");
	if(iostdout == nil) {
		wmdialog("error -fg red", "Wm startup",
			"Failed to make file server:\n"+sys->sprint("%r"),
			0, "Exit"::nil);
		return;
	}

	iostderr := sys->file2chan("/chan", "wmstderr");
	if(iostderr == nil) {
		wmdialog("error -fg red", "Wm startup",
			"Failed to make file server:\n"+sys->sprint("%r"),
			0, "Exit"::nil);
		return;
	}
	geomIO := sys->file2chan("/chan", "wmgeom");
	if(geomIO == nil) {
		wmdialog("error -fg red", "Wm startup",
			"Failed to make /chan/wmgeom:\n"+sys->sprint("%r"),
			0, "Exit"::nil);
		return;
	}
	setupfinished := chan of int;
	spawn servewmgeom(geomIO);
	spawn consolex(iostdout, iostderr);
	spawn setup(shctxt, setupfinished);
	snarf: array of byte;
	req := rdreq;
	donesetup := 0;
	for(;;) alt {
	req = <-wmIO.read =>
		if(req.rc == nil)	# not interested in EOF
			break;
		if(rdreq.fid != -1)
			req.rc <-= (nil, "busy");
		else
		if(rband == RbTotk)
			req.rc <-= (array of byte sys->sprint("%5d %5d %5d %5d",
				rr.min.x, rr.min.y, rr.max.x,rr.max.y), nil);
		else
			rdreq = req;
	(off, data, fid, wc) := <-wmIO.write =>
		if(wc == nil)		# not interested in EOF
			break;
		#
		# m rect - request move from this rect
		# s rect - request size change from this rect
		# t name - move to toolbar
		# r name - restore from tool bar
		#
		case int data[0] {
		 *  =>
			wc <-= (0, "bad req len");
		's' or 'm' =>
			setrr(data);
			rband = RbSize;
			if(int data[0] == 'm') {
				rband = RbMove;
				fakemouseup(screen);
			}
			else
				band(DragT|DragB|DragR|DragL);
			wc <-= (len data, nil);
		't' =>
			iconame := iconify(string data[1:len data], fid);
			icons = Icon(iconame, len data, fid, wc) :: icons;
		'r' =>
			deiconify(nil, fid);
			wc <-= (len data, nil);
		}
		data = nil;
	moved := <-rbdone =>
		if(!moved)
			for(i:=0; i<8; i++)
				offscreen(i);
		if(rdreq.fid != -1) {
			rdreq.rc <-= (array of byte sys->sprint("%5d %5d %5d %5d",
				rr.min.x, rr.min.y, rr.max.x,rr.max.y), nil);
			rdreq.fid = -1;
		}
	s := <-cmdch =>
		case s {
		"post" =>
			mh := int cmd(tbtop, ".m cget height");
			cmd(tbtop, ".m post 0 " +
				string (screen.image.r.max.y - h - mh - 4));
		}
	c := <-exec =>
		# guard against parallel access to the shctxt environment
		if (donesetup)
 			shctxt.run(ref Listnode(nil, c) :: nil, 0);
	detask := <-task =>
		deiconify(detask, -1);
	(off, data, fid, wc) := <-snarfIO.write =>
		if(wc == nil)
			break;
		if (off == 0)			# write at zero truncates
			snarf = data;
		else {
			if (off + len data > len snarf) {
				nsnarf := array[off + len data] of byte;
				nsnarf[0:] = snarf;
				snarf = nsnarf;
			}
			snarf[off:] = data;
		}
		wc <-= (len data, "");
	req = <-snarfIO.read =>
		if(req.rc == nil)
			break;
		if (req.off >= len snarf) {
			req.rc <-= (nil, "");
			break;
		}
		e := req.off + req.nbytes;
		if (e > len snarf)
			e = len snarf;
		req.rc <-= (snarf[req.off:e], "");
	donesetup = <-setupfinished =>
		;	
	}
}

tbheight(win: ref Tk->Toplevel): int
{
	if (!smallscreen)
		return 32;
	cmd(win, "button .b -text {XXX}");
	h := int cmd(win, ".b cget -height") + int cmd(win, ".b cget -bd") * 2;
	cmd(win, "destroy .b");
	return h;
}

tbht(win: ref Tk->Toplevel): int
{
	cmd(win, "button .b -bd 1 -bitmap exit.bit");
	h := int cmd(win, ".b cget -height") + int cmd(win, ".b cget -bd") * 2;
	cmd(win, "destroy .b");
	return h;
}

setup(shctxt: ref Context, finished: chan of int)
{
	ctxt := shctxt.copy(0);
	ctxt.run(shell->stringlist2list("run"::"/lib/wmsetup"::nil), 0);
	# if no items in menu, then create some.
	if (tk->cmd(tbtop, ".m type 0")[0] == '!')
		ctxt.run(shell->stringlist2list(defaultscript::nil), 0);
	cmd(tbtop, "update");
	finished <-= 1;
}

makedrawcontext(fillimage: string): (ref Draw->Context, string)
{
	display := Display.allocate(nil);
	if(display == nil)
		return (nil, sys->sprint("cannot initialise display: %r"));

	disp := display.image;
	fill: ref Draw->Image;
	if (fillimage != nil)
		if ((fill = display.open(fillimage)) == nil)
			sys->fprint(stderr(), "wm: cannot open %s: %r\n", fillimage);
	if (fill == nil)
		fill = display.rgb(73,147, 221);
	else {
		fill.repl = 1;
		fill.clipr = display.image.r;
	}
	ctxt := ref Draw->Context;
	ctxt.screen = Screen.allocate(disp, fill, 1);
	ctxt.display = display;
	disp.draw(disp.r, ctxt.screen.fill, nil, disp.r.min);

	return (ctxt, nil);
}

setrr(data: array of byte)
{
	rr.min.x = int string data[1:6];
	rr.min.y = int string data[6:12];
	rr.max.x = int string data[12:18];
	rr.max.y = int string data[18:];
	origrr = rr;
}

iconify(label: string, fid: int): string
{
	n := sys->sprint(".toolbar.%d", fid);
	if(len label > 15) {
		new := "";
		l := 0;
		while(len label > 15 && l < 3) {
			new += label[0:15]+"\n";
			label = label[15:];
			for(v := 0; v < len label; v++)
				if(label[v] != ' ')
					break;
			label = label[v:];
			l++;
		}
		label = new + label;
	}

	# add "-font /fonts/misc/ascii.6x10.font" for small mono font
	c := sys->sprint("button %s -command {send task %s} -text '%s",
			n, n, label);
	cmd(tbtop, c);
	cmd(tbtop, "pack "+n+" -side left -fill y; update");
	return n;
}

deiconify(name: string, fid: int)
{
	tmp: list of Icon;

	deleted := 0;
	while(icons != nil) {
		i := hd icons;
		if(i.name == name || i.fid == fid) {
			deleted = 1;
			alt {
			i.wc <-= (i.repl, nil) =>
				break;
			* =>
				break;
			}
			name = i.name;
		}
		else
			tmp = i :: tmp;
		icons = tl icons;
	}
	icons = tmp;

	if(deleted) {
		tk->cmd(tbtop, "destroy "+name);
		tk->cmd(tbtop, "update");
	}
}

servewmgeom(geomIO: ref Sys->FileIO)
{
	g := ref Draw->Point(0, 0);
	req: Rdreq;
	for (;;) alt {
	(nil, nil, nil, wc) := <-geomIO.write =>
		if (wc != nil)
			wc <-= (0, "permission denied");
	req = <-geomIO.read =>
		if (req.rc == nil)
			break;
		d := array of byte geom(g);
		if (req.nbytes > len d)
			req.nbytes = len d;
		if (req.nbytes < len d)
			d = d[0:req.nbytes];
		req.rc <-= (d, nil);
	}
}

geom(g: ref Draw->Point): string
{
	if (smallscreen)
		return "-x 0 -y 0";
	if(g.x > 130) {
		g.x = 0;
		g.y = 0;
	}
	g.x += 20;
	g.y += 20;
	return "-x "+string g.x+" -y "+string g.y;
}

moving: ref Draw->Image;

mouse(sync: chan of string, rbdone: chan of int)
{
	fd := sys->open("/dev/pointer", sys->OREAD);
	if(fd == nil) {
		sync <-= sys->sprint("cannot open /dev/pointer: %r");
		return;
	}
	sync <-= nil;
	if (<-sync != nil)		# wait until screen is allocated.
		return;			# die if screen wasn't allocated.

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
		if(b == 128)	# window destroyed
			killgrp();
		mouse1(screen, x, y, b, rbdone);
	}
}

lastb, pressx, pressy: int;

mouse1(scr: ref Draw->Screen, x, y, b: int, rbdone: chan of int)
{
	mode, xa, ya: int;
	xr: Draw->Rect;

	case rband {
	RbTotk =>
		if ((b & 1) && !(lastb & 1)) {
			pressx = x;
			pressy = y;
		}
		tk->mouse(scr, x, y, b);
	RbMove =>
		if((b & 1) == 0) {
			moving = nil;
			rband = RbTotk;
			rbdone <-= 1;
			break;
		}
		# rr.min is known to be on top now
		win := tk->intop(scr, rr.min.x, rr.min.y);
		xa = pressx;
		ya = pressy;
		# if mouse is moving when click happens, can get behind.
		# adjust starting point to compensate.
		if(xa < rr.min.x)
			xa = rr.min.x+5;
		if(ya < rr.min.y)
			ya = rr.min.y+5;
		if(xa >= rr.max.x)
			xa = rr.max.x-5;
		if(ya >= rr.max.y)
			ya = rr.max.y-5;
		xr = rr;
		if(win != nil)
			moving = win.image;
		if(moving != nil && (xa != x || ya != y)){
			rr = clip(rr, visr);
			moving.origin(origrr.min, rr.min);
		}
		rband = RbTrack;
	RbTrack=>
		if((b & 1) == 0) {
			moving = nil;
			rband = RbTotk;
			rbdone <-= 1;
			break;
		}
		rr = draw->xr.addpt((x-xa, y-ya));
		if(moving != nil){
			rr = clip(rr, visr);
			moving.origin(origrr.min, rr.min);
		}
	RbSize =>
		band(DragL|DragT|DragR|DragB);
		if(b == 0)
			break;
		mode = 0;
		tt := draw->rr.dx()/3;
		if(x > rr.min.x && x < rr.min.x+tt)
			mode |= DragL;
		else
		if(x > rr.max.x-tt && x < rr.max.x)
			mode |= DragR;
		tt = draw->rr.dy()/3;
		if(y > rr.min.y && y < rr.min.y+tt)
			mode |= DragT;
		else
		if(y > rr.max.y-tt && y < rr.max.y)
			mode |= DragB;
		if(mode == 0) {
			rband = RbTotk;
			rbdone <-= 0;
			break;
		}
		rband = RbDrag;
		xa = x;
		ya = y;
		xr = rr;
	RbDrag =>
		if((b & 1) == 0) {
			rband = RbTotk;
			rbdone <-= 0;
			break;
		}
		dx := x - xa;
		dy := y - ya;
		if(mode & DragL)
			rr.min.x = xr.min.x + dx;
		if(mode & DragR)
			rr.max.x = xr.max.x + dx;
		if(mode & DragT)
			rr.min.y = xr.min.y + dy;
		if(mode & DragB)
			rr.max.y = xr.max.y + dy;
		rr = clip(rr, visr);
		band(mode);
	}
	lastb = b;
}

fakemouseup(scr: ref Draw->Screen)
{
	tk->mouse(scr, pressx, pressy, lastb & ~1);
}

bandr := array[8] of {
	((0, 0), (4, 20)),
	((0, 0), (20, 4)),
	((-4, -20), (0, 0)),
	((-20, -4), (0, 0)),
	((-20, 0), (0, 4)),
	((-4, 0), (0, 20)),
	((0, -20), (4, 0)),
	((0, -4), (20, 0)),
};

bandinit()
{

	for(i:=0; i<8; i++){
		rubberband[i] = screen.newwindow(bandr[i], Draw->Red);
		offscreen(i);
	}
}

offscreen(i: int)
{
	rubberband[i].origin((0, 0), (-64, -64));
}

band(m: int)
{
	r0, r1: Draw->Rect;

	if(draw->rr.dx() < WinMinX)
		rr.max.x = rr.min.x + WinMinX;
	if(draw->rr.dy() < WinMinY)
		rr.max.y = rr.min.y + WinMinY;

	if(m & (DragT|DragL)) {
		r0 = (rr.min, (rr.min.x+4, rr.min.y+20));
		r1 = (rr.min, (rr.min.x+20, rr.min.y+4));
		rubberband[0].origin((0, 0), r0.min);
		rubberband[1].origin((0, 0), r1.min);
	}
	else {
		offscreen(0);
		offscreen(1);
	}

	if(m & (DragB|DragR)) {
		r0 = ((rr.max.x-4, rr.max.y-20), rr.max);
		r1 = ((rr.max.x-20, rr.max.y-4), rr.max);
		rubberband[2].origin((0, 0), r0.min);
		rubberband[3].origin((0, 0), r1.min);
	}
	else {
		offscreen(2);
		offscreen(3);
	}

	if(m & (DragT|DragR)) {
		r0 = ((rr.max.x-20, rr.min.y), (rr.max.x, rr.min.y+4));
		r1 = ((rr.max.x-4, rr.min.y), (rr.max.x, rr.min.y+20));
		rubberband[4].origin((0, 0), r0.min);
		rubberband[5].origin((0, 0), r1.min);
	}
	else {
		offscreen(4);
		offscreen(5);
	}

	if(m & (DragB|DragL)) {
		r0 = ((rr.min.x, rr.max.y-20), (rr.min.x+4, rr.max.y));
		r1 = ((rr.min.x, rr.max.y-4), (rr.min.x+20, rr.max.y));
		rubberband[6].origin((0, 0), r0.min);
		rubberband[7].origin((0, 0), r1.min);
	}
	else {
		offscreen(6);
		offscreen(7);
	}
}

keyboard(scr: ref Draw->Screen)
{
	dfd := sys->open("/dev/keyboard", sys->OREAD);
	if(dfd == nil)
		return;

	buf := array[10] of byte;
	i := 0;
	for(;;) {
		n := sys->read(dfd, buf[i:], len buf - i);
		if(n < 1)
			break;
		i += n;
		while(i >0 && (nutf := sys->utfbytes(buf, i)) > 0){
			s := string buf[0:nutf];
			for (j := 0; j < len s; j++)
				tk->keyboard(scr, int s[j]);
			buf[0:] = buf[nutf:i];
			i -= nutf;
		}
	}
}

wmdialog(ico, title, msg: string, dflt: int, labs: list of string)
{
	dt := tk->toplevel(screen, "-x 0 -y 0");
	wmlib->dialog(dt, ico, title, msg, dflt, labs);
}

con_cfg := array[] of
{
	"frame .cons",
	"scrollbar .cons.scroll -command {.cons.t yview}",
	"text .cons.t -width 60w -height 15w -bg white "+
		"-fg black -font /fonts/misc/latin1.6x13.font "+
		"-yscrollcommand {.cons.scroll set}",
	"pack .cons.scroll -side left -fill y",
	"pack .cons.t -fill both -expand 1",
	"pack .cons -expand 1 -fill both",
	"pack propagate . 0",
	"update"
};

consolex(iostdout, iostderr: ref sys->FileIO)
{
	(constop, titlectl) := wmlib->titlebar(screen, "", "Log", wmlib->Appl); 

	for(i := 0; i < len con_cfg; i++)
		tk->cmd(constop, con_cfg[i]);

	cmd := chan of string; 
	tk->namechan(constop, cmd, "cmd");

	fittoscreen(constop);

	spawn wmlib->titlectl(constop, "task");

	servecons(iostdout, iostderr, constop, titlectl);
}

servecons(iostdout, iostderr: ref sys->FileIO,
			constop: ref Tk->Toplevel, titlectl: chan of string)
{
	rc: Sys->Rread;
	wc: Sys->Rwrite;
	data: array of byte;
	off, nbytes, fid: int;

	for(;;) alt {
	menu := <-titlectl =>
		if(menu == "exit")
			menu = "task";
		spawn wmlib->titlectl(constop, menu);
	(off, nbytes, fid, rc) = <-iostdout.read =>
		if(rc == nil)
			break;
		rc <-= (nil, nil);
	(off, nbytes, fid, rc) = <-iostderr.read =>
		if(rc == nil)
			break;
		rc <-= (nil, nil);
	(off, data, fid, wc) = <-iostdout.write =>
		conout(constop, data, wc, 0);
	(off, data, fid, wc) = <-iostderr.write =>
		conout(constop, data, wc, 1);
	}
}

ll := 0;		# transcript length

conout(constop: ref Tk->Toplevel,
		data: array of byte, wc: Sys->Rwrite, raise: int)
{
	if(wc == nil)
		return;

	if(raise)
		wmlib->unhide();

	tk->cmd(constop, ".cons.t insert end '"+ string data);
	wc <-= (len data, nil);

	nlines := int tk->cmd(constop, ".cons.t index end");
	if(nlines > TSCRIPT) {
		tk->cmd(constop, ".cons.t delete 1.0 "+
			string (nlines-TSCRIPT/4) +".0;update");
	}

	tk->cmd(constop, ".cons.t see end; update");
}

initbuiltin(ctxt: ref Context, nil: Sh): string
{
	if (tbtop == nil) {
		sys = load Sys Sys->PATH;
		sys->fprint(sys->fildes(2), "wm: cannot load wm as a builtin\n");
		sys->raise("fail:usage");
	}
	ctxt.addbuiltin("menu", myselfbuiltin);
	ctxt.addbuiltin("delmenu", myselfbuiltin);
	ctxt.addbuiltin("error", myselfbuiltin);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

runbuiltin(c: ref Context, sh: Sh,
			cmd: list of ref Listnode, nil: int): string
{
	case (hd cmd).word {
	"menu" =>	return builtin_menu(c, sh, cmd);
	"delmenu" =>	return builtin_delmenu(c, sh, cmd);
	}
	return nil;
}

runsbuiltin(nil: ref Context, nil: Sh,
			nil: list of ref Listnode): list of ref Listnode
{
	return nil;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

word(ln: ref Listnode): string
{
	if (ln.word != nil)
		return ln.word;
	if (ln.cmd != nil)
		return shell->cmd2string(ln.cmd);
	return nil;
}

menupath(title: string): string
{
	mpath := ".m."+title;
	for(j := 0; j < len mpath; j++)
		if(mpath[j] == ' ')
			mpath[j] = '_';
	return mpath;
}


builtin_menu(nil: ref Context, nil: Sh, argv: list of ref Listnode): string
{
	n := len argv;
	if (n < 3 || n > 4) {
		sys->fprint(stderr(), "usage: menu topmenu [ secondmenu ] command\n");
		sys->raise("fail:usage");
	}
	primary := (hd tl argv).word;
	argv = tl tl argv;

	if (n == 3) {
		w := word(hd argv);
		if (len w == 0)
			cmd(tbtop, ".m insert 0 separator");
		else
			cmd(tbtop, ".m insert 0 command -label " + wmlib->tkquote(primary) +
				" -command {send exec " + w + "}");
	} else {
		secondary := (hd argv).word;
		argv = tl argv;

		mpath := menupath(primary);
		e := tk->cmd(tbtop, mpath+" cget -width");
		if(e[0] == '!') {
			cmd(tbtop, "menu "+mpath);
			cmd(tbtop, ".m insert 0 cascade -label "+wmlib->tkquote(primary)+" -menu "+mpath);
		}
		w := word(hd argv);
		if (len w == 0)
			cmd(tbtop, mpath + " insert 0 separator");
		else
			cmd(tbtop, mpath+" insert 0 command -label "+wmlib->tkquote(secondary)+
				" -command {send exec "+w+"}");
	}
	return nil;
}

builtin_delmenu(nil: ref Context, nil: Sh, nil: list of ref Listnode): string
{
	delmenu(".m");
	cmd(tbtop, "menu .m");
	return nil;
}

delmenu(m: string)
{
	for (i := int cmd(tbtop, m + " index end"); i >= 0; i--)
		if (cmd(tbtop, m + " type " + string i) == "cascade")
			delmenu(cmd(tbtop, m + " entrycget " + string i + " -menu"));
	cmd(tbtop, "destroy " + m);
}

getself(): Shellbuiltin
{
	return myselfbuiltin;
}

cmd(top: ref Tk->Toplevel, c: string): string
{
	s := tk->cmd(top, c);
	if (s != nil && s[0] == '!')
		sys->fprint(stderr(), "tk error: %s\n", s);
	return s;
}

fittoscreen(win: ref Tk->Toplevel)
{
	Point: import draw;
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y));
	bd := int cmd(win, ". cget -bd");
	winsize := Point(int cmd(win, ". cget -actwidth") + bd * 2, int cmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		cmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		cmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int cmd(win, ". cget -actx"), int cmd(win, ". cget -acty"));
	actr.max = actr.min.add((int cmd(win, ". cget -actwidth") + bd*2,
				int cmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.max.x - dx, r.max.x);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.max.y - dy, r.max.y);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	cmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
}

killgrp()
{
	fd := sys->open("#p/" + string sys->pctl(0, nil) + "/ctl", sys->OWRITE);
	sys->fprint(fd, "killgrp");
	sys->unmount("#d", "/dev");
	exit;
}

clip(r: Rect, v: Rect): Rect
{
	if(r.min.x > v.max.x)
		r.min.x = v.max.x;
	if(r.max.x < v.min.x)
		r.max.x = v.min.x;
	if(r.min.y > v.max.y)
		r.min.y = v.max.y;
	if(r.min.y < v.min.y)
		r.min.y = v.min.y;
	return r;
}

	
