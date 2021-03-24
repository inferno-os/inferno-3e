# Gui implementation for running under wm (tk window manager)
implement Gui;

include "common.m";
include "tk.m";
include "wmlib.m";

sys: Sys;

D: Draw;
	Font,Point, Rect, Image, Context, Screen, Display: import D;

CU: CharonUtils;

E: Events;
	Event: import E;

tk: Tk;

wmlib: Wmlib;

WINDOW, CTLS, PROG, STATUS, BORDER, EXIT: con 1 << iota;
REQD: con ~0;

cfg := array[] of {
	(REQD,	"entry .ctlf.url -bg white -font /fonts/lucidasans/unicode.7.font -height 16"),
	(REQD,	"button .ctlf.back -bd 1 -command {send gctl back} -state disabled -text {back} -font /fonts/lucidasans/unicode.7.font"),
	(REQD,	"button .ctlf.stop -bd 1 -command {send gctl stop} -state disabled -text {stop} -font /fonts/lucidasans/unicode.7.font"),
	(REQD,	"button .ctlf.fwd -bd 1 -command {send gctl fwd} -state disabled -text {next} -font /fonts/lucidasans/unicode.7.font"),
	(REQD,	"label .status -bd 1 -selectborderwidth 0 -font /fonts/lucidasans/unicode.6.font -height 14 -anchor w"),
	(REQD,	"button .ctlf.exit -bd 1 -bitmap exit.bit -command {send wm_title exit}"),
	(REQD,	"frame .f -bd 0"),
	(BORDER,	".f configure -bd 2 -relief sunken"),
	(CTLS|EXIT,	"frame .ctlf"),
	(STATUS,	"frame .statussep -bg black -height 1"),

	(CTLS,	"bind .ctlf.url <Key-\n> {send gctl go}"),
	(CTLS,	"bind .ctlf.url <Key-\u0003> {send gctl copyurl}"),
	(CTLS,	"bind .ctlf.url <Key-\u0016> {send gctl pasteurl}"),

#	(PROG,	"canvas .prog -bd 0 -height 20"),
#	(PROG,	"bind .prog <ButtonPress-1> {send gctl b1p %X %Y}"),
	(CTLS,	"pack .ctlf.back .ctlf.stop .ctlf.fwd -side left -anchor w -fill y"),
	(CTLS,	"pack .ctlf.url -side left -padx 2 -fill x -expand 1"),
	(EXIT,	"pack .ctlf.exit -side right -anchor e"),
	(CTLS|EXIT,	"pack .ctlf -side top -fill x"),
	(REQD,	"pack .f -side top -fill both -expand 1"),
#	(PROG,	"pack .prog -side bottom -fill x"),
	(STATUS,	"pack .statussep -side top -fill x"),
	(STATUS,	"pack .status -side bottom -fill x"),
};

framebinds := array[] of {
	"bind .f <Key> {send gctl k %s}",
	"bind .f <FocusOut> {send gctl focusout}",
	"bind .f <ButtonPress-1> {grab set .f;send gctl b1p %X %Y}",
	"bind .f <Double-ButtonPress-1> {send gctl b1p %X %Y}",
	"bind .f <ButtonRelease-1> {grab release .f;send gctl b1r %X %Y}",
	"bind .f <Motion-Button-1> {send gctl b1d %X %Y}",
	"bind .f <ButtonPress-2> {send gctl b2p %X %Y}",
	"bind .f <Double-ButtonPress-2> {send gctl b2p %X %Y}",
	"bind .f <ButtonRelease-2> {send gctl b2r %X %Y}",
	"bind .f <Motion-Button-2> {send gctl b2d %X %Y}",
	"bind .f <ButtonPress-3> {send gctl b3p %X %Y}",
	"bind .f <Double-ButtonPress-3> {send gctl b3p %X %Y}",
	"bind .f <ButtonRelease-3> {send gctl b3r %X %Y}",
	"bind .f <Motion-Button-3> {send gctl b3d %X %Y}",
	"bind .f <Motion> {send gctl m %X %Y}",
};

tktop : ref Tk->Toplevel;
mousegrabbed := 0;
offset : Point;
p0 := Point(0,0);
popup: ref Popup;
popuptk: ref Tk->Toplevel;
gctl: chan of string;

realwin : ref Draw->Image;
mask : ref Draw->Image;

init(ctxt: ref Context, cu: CharonUtils)
{
	sys = load Sys Sys->PATH;
	D = load Draw Draw->PATH;
	CU = cu;
	E = cu->E;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if(wmlib == nil)
		CU->raise(sys->sprint("EXInternal: can't load module Wmlib: %r"));
	wmlib->init();

	display = ctxt.display;
	screen = ctxt.screen;

	wmctl: chan of string;
	buttons := parsebuttons((CU->config).buttons);
	winopts := parsewinopts((CU->config).framework);

	(tktop, wmctl) = wmlib->titlebar(screen, "", (CU->config).wintitle, buttons);
	gctl = chan of string;
	tk->namechan(tktop, gctl, "gctl");
	tk->cmd(tktop, "pack propagate . 0");
	filtertkcmds(tktop, winopts, cfg);
	tkcmds(tktop, framebinds);
	w := (CU->config).defaultwidth;
	h := (CU->config).defaultheight;
	tk->cmd(tktop, ". configure -width " + string w + " -height " + string h);
	tk->cmd(tktop, "update");
	makewins();
	mask = display.ones;
	progress = chan of Progressmsg;
	pidc := chan of int;
	spawn progmon(pidc);
	<- pidc;
	spawn evhandle(tktop, wmctl, E->evchan);
}

parsebuttons(s: string): int
{
	b := 0;
	(nil, toks) := sys->tokenize(s, ",");
	for (;toks != nil; toks = tl toks) {
		case hd toks {
		"help" =>
			b |= Wmlib->Help;
		"resize" =>
			b |= Wmlib->Resize;
		"hide" =>
			b |= Wmlib->Hide;
		}
	}
	return b;
}

parsewinopts(s: string): int
{
	b := WINDOW;
	(nil, toks) := sys->tokenize(s, ",");
	for (;toks != nil; toks = tl toks) {
		case hd toks {
		"status" =>
			b |= STATUS;
		"controls" or "ctls" =>
			b |= CTLS;
		"progress" or "prog" =>
			b |= PROG;
		"border" =>
			b |= BORDER;
		"exit" =>
			b |= EXIT;
		"all" =>
			# note: "all" doesn't include 'EXIT' !
			b |= WINDOW | STATUS | CTLS | PROG | BORDER;
		}
	}
	return b;
}

filtertkcmds(top: ref Tk->Toplevel, filter: int, cmds: array of (int, string))
{
	for (i := 0; i < len cmds; i++) {
		(val, cmd) := cmds[i];
		if (val & filter) {
			if ((e := tk->cmd(top, cmd)) != nil && e[0] == '!')
				sys->print("tk error on '%s': %s\n", cmd, e);
		}
	}
}

tkcmds(top: ref Tk->Toplevel, cmds: array of string)
{
	for (i := 0; i < len cmds; i++)
		if ((e := tk->cmd(top, cmds[i])) != nil && e[0] == '!')
			sys->print("tk error on '%s': %s\n", cmds[i], e);
}

# act(x,y) gives top-left, outside the border
# act(width,height) give dimensions inside the border
actr(t: ref Tk->Toplevel, wname: string) : Rect
{
	x := int tk->cmd(t, wname + " cget -actx");
	y := int tk->cmd(t, wname + " cget -acty");
	w := int tk->cmd(t, wname + " cget -actwidth");
	h := int tk->cmd(t, wname + " cget -actheight");
	bd := int tk->cmd(t, wname + " cget -borderwidth");
	return Rect((x,y),(x+w+2*bd,y+h+2*bd));
}

clientr(t: ref Tk->Toplevel, wname: string) : Rect
{
	bd := int tk->cmd(t, wname + " cget -borderwidth");
	x := bd + int tk->cmd(t, wname + " cget -actx");
	y := bd + int tk->cmd(t, wname + " cget -acty");
	w := int tk->cmd(t, wname + " cget -actwidth");
	h := int tk->cmd(t, wname + " cget -actheight");
	return Rect((x,y),(x+w,y+h));
}

progmon(pidc : chan of int)
{
	pidc <-= sys->pctl(0, nil);
	for (;;) {
		msg := <- progress;
		# just handle stop button for now
		if (msg.bsid == -1) {
			case (msg.state) {
			Pstart =>	stopbutton(1);
			* =>		stopbutton(0);
			}
		}
	}
}

evhandle(t: ref Tk->Toplevel, wmctl: chan of string, evchan: chan of ref Event)
{
	for(;;) {
		ev : ref Event = nil;
		dismisspopup := 1;
		alt {
		s := <-gctl =>
			(nil, l) := sys->tokenize(s, " ");
			case hd l {
			"focusout" =>
				ev = ref Event.Elostfocus;
			"b1p" or "b1r" or "b1d" or 
			"b2p" or "b2r" or "b2d" or 
			"b3p" or "b3r" or "b3d" or 
			"m" =>
				l = tl l;
				pt := Point(int hd l, int hd tl l);
				pt = pt.sub(offset);
				mtype := s2mtype(s);
				dismisspopup = 0;
				if(mtype == E->Mlbuttondown) {
					tk->cmd(t, "focus .f");
					pu := popup;
					if (pu != nil && !pu.r.contains(pt))
						dismisspopup = 1;
					pu = nil;
				}
				ev = ref Event.Emouse(pt, mtype);
			"k" =>
				dismisspopup = 0;
				k := int hd tl l;
				if(k != 0)
					ev = ref Event.Ekey(k);
			"back" =>
				ev = ref Event.Eback;
			"stop" =>
				ev = ref Event.Estop;
			"fwd" =>
				ev = ref Event.Efwd;
			"go" =>
				url := tk->cmd(tktop, ".ctlf.url get");
				if (url != nil)
					ev = ref Event.Ego(url, nil, 0, E->EGnormal);
			"copyurl" =>
				url := tk->cmd(tktop, ".ctlf.url get");
				snarfput(url);
			"pasteurl" =>
				url := wmlib->tkquote(wmlib->snarfget());
				tk->cmd(tktop, ".ctlf.url delete 0 end");
				tk->cmd(tktop, ".ctlf.url insert end " + url);
				tk->cmd(tktop, "update");
			}
		s := <-wmctl =>
			case s {
			"move" =>
				r := clientr(t, ".f");
				t.image.draw(r, realwin, display.ones, realwin.r.min);
				offscreen := screen.image.r.max;
				realwin.origin(p0, offscreen);
	
				if (cancelpopup())
					evchan <-= ref Event.Edismisspopup;
				wmlib->titlectl(t, "move");

				r = clientr(t, ".f");
				offset = r.min;
				realwin.origin(p0, r.min);
#				screen.top(allwins);
			"exit" =>
				hidewins();
				ev = ref Event.Equit(0);
			"help" =>
				ev = ref Event.Ego((CU->config).helpurl, nil, 0, E->EGnormal); 
			"size" =>
				if (cancelpopup())
					evchan <-= ref Event.Edismisspopup;
				wmlib->titlectl(t, "size 355 335");
				makewins();
#				screen.top(allwins);
				ev = ref Event.Ereshape(mainwin.r);
			"task" =>
				# move the browser windows off the screen to hide them
				# Tell browser about dismissal of popup after "task" completed
				# but move off screen before hand
				if (cancelpopup())
					evchan <-= ref Event.Edismisspopup;
				r := clientr(t, ".f");
				hidewins();

				wmlib->titlectl(t, "task");
				# restore position of the offscreen windows
				realwin.origin(p0, r.min);
#				screen.top(allwins);
			"raise" =>
				# no guarantee that we can get this right
				screen.top(array [] of {realwin});
			* =>
				wmlib->titlectl(t, s);
			}
		}
		if (dismisspopup) {
			if (cancelpopup()) {
				evchan <-= ref Event.Edismisspopup;
			}
		}
		if (ev != nil)
			evchan <-= ev;
	}
}

s2mtype(s: string): int
{
	mtype := E->Mmove;
	if(s[0] == 'm')
		mtype = E->Mmove;
	else {
		case s[1] {
		'1' =>
			case s[2] {
			'p' => mtype = E->Mlbuttondown;
			'r' => mtype = E->Mlbuttonup;
			'd' => mtype = E->Mldrag;
			}
		'2' =>
			case s[2] {
			'p' => mtype = E->Mmbuttondown;
			'r' => mtype = E->Mmbuttonup;
			'd' => mtype = E->Mmdrag;
			}
		'3' =>
			case s[2] {
			'p' => mtype = E->Mrbuttondown;
			'r' => mtype = E->Mrbuttonup;
			'd' => mtype = E->Mrdrag;
			}
		}
	}
	return mtype;
}


makewins()
{
	mainr := clientr(tktop, ".f");
	offset = mainr.min;
	realwin = screen.newwindow(mainr, D->White);
	realwin.origin(p0,mainr.min);
	if(realwin == nil)
		CU->raise(sys->sprint("EXFatal: can't initialize windows: %r"));
	r := Rect(p0, Point(mainr.dx(), mainr.dy()));
	mainwin = display.newimage(r, realwin.ldepth, 0, D->White);
#	mainwin = screen.newwindow(r, D->White);
	if(mainwin == nil)
		CU->raise(sys->sprint("EXFatal: can't initialize windows: %r"));
}

hidewins()
{
	realwin.origin(p0, (-3000, -3000));
	tk->cmd(tktop, ". unmap");
}

snarfput(s: string)
{
	wmlib->snarfput(s);
}

setstatus(s : string)
{
	tk->cmd(tktop, ".status configure -text " + wmlib->tkquote(s));
	tk->cmd(tktop, "update");
}

seturl(s: string)
{
	tk->cmd(tktop, ".ctlf.url delete 0 end");
	tk->cmd(tktop, ".ctlf.url insert 0 " + wmlib->tkquote(s));
	tk->cmd(tktop, "update");
}

auth(realm: string) : (int, string, string)
{
	return (-1, "", "");
}

alert(msg: string)
{
sys->print("ALERT:%s\n", msg);
	return;
}

confirm(msg: string) : int
{
sys->print("CONFIRM:%s\n", msg);
	return -1;
}

prompt(msg, dflt: string) : (int, string)
{
	return (-1, "");
}

stopbutton(enable : int)
{
	state : string;
	if (enable) {
		tk->cmd(tktop, ".ctlf.stop configure -bg red -activebackground red -activeforeground white");
		state = "normal";
	} else {
		tk->cmd(tktop, ".ctlf.stop configure -bg #dddddd");
		state = "disabled";
	}
	tk->cmd(tktop, ".ctlf.stop configure -state " + state + ";update");
}

backbutton(enable : int)
{
	state : string;
	if (enable) {
		tk->cmd(tktop, ".ctlf.back configure -bg lime -activebackground lime -activeforeground red");
		state = "normal";
	} else {
		tk->cmd(tktop, ".ctlf.back configure -bg #dddddd");
		state = "disabled";
	}
	tk->cmd(tktop, ".ctlf.back configure -state " + state + ";update");
}

fwdbutton(enable : int)
{
	state : string;
	if (enable) {
		tk->cmd(tktop, ".ctlf.fwd  configure -bg lime -activebackground lime -activeforeground red");
		state = "normal";
	} else {
		tk->cmd(tktop, ".ctlf.fwd configure -bg #dddddd");
		state = "disabled";
	}
	tk->cmd(tktop, ".ctlf.fwd configure -state " + state + ";update");
}

flush(r : Rect)
{
	realwin.draw(r, mainwin, display.ones, r.min);
}

clientfocus()
{
	tk->cmd(tktop, "focus .f");
	tk->cmd(tktop, "update");
}

exitcharon()
{
	hidewins();
	E->evchan <-= ref Event.Equit(0);
}

kill(pid : int)
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	sys->write(fd, array of byte "kill", 4);
}

getpopup(r: Rect): ref Popup
{
	cancelpopup();
#	img := screen.newwindow(r, D->White);
	img := display.newimage(r, screen.image.ldepth, 0, D->White);
	if (img == nil)
		return nil;
	winr := r.addpt(offset);	# race for offset

	pos := "-x " + string winr.min.x + " -y " + string winr.min.y;
	top := tk->toplevel(screen, pos);
	if (top == nil)
		return nil;
	tk->namechan(top, gctl, "gctl");
	tk->cmd(top, "frame .f -bd 0 -bg white -width " + string r.dx() + " -height " + string r.dy());
	tkcmds(top, framebinds);
	tk->cmd(top, "pack .f; update");
	win := screen.newwindow(winr, D->White);
	if (win == nil)
		return nil;
	win.origin(r.min, winr.min);

	popuptk = top;
	popup = ref Popup(r, img, win);
	return popup;
}

cancelpopup(): int
{
	popuptk = nil;
	pu := popup;
	if (pu == nil)
		return 0;
	pu.image = nil;
	pu.window = nil;
	pu = nil;
	popup = nil;
	return 1;
}

Popup.flush(p: self ref Popup, r: Rect)
{
	win := p.window;
	img := p.image;
	if (win != nil && img != nil)
		win.draw(r, img, display.ones, r.min);
}
