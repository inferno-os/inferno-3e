# Gui implementation for running under wm (tk window manager)
implement Gui;

include "common.m";
include "tk.m";
include "wmlib.m";

sys: Sys;
draw : Draw;
acme : Acme;
dat : Dat;
utils : Utils;
tk : Tk;
wmlib : Wmlib;

Font, Point, Rect, Image, Context, Screen, Display : import draw;
keyboardpid, mousepid, acmectxt : import acme;
ckeyboard, cmouse, Pointer : import dat;
error : import utils;

screen: ref Screen;

cfg := array[] of {
	"bind . <Key> {send kctl k %s}",
	"bind .Wm_t <Double-Button-1> {send gctl lower}",
	"frame .f",
	"bind .f <Double-Button-1> {send gctl b12 %X %Y %s}",
	"bind .f <ButtonPress-1> {send gctl b1 %X %Y %s}",
	"bind .f <ButtonPress> {send gctl b %X %Y %s}",
	"bind .f <ButtonRelease> {send gctl b %X %Y %s}",
	"bind .f <Motion-Button-1> {send gctl M %X %Y %s}",
	"bind .f <Motion-Button-2> {send gctl M %X %Y %s}",
	"bind .f <Motion-Button-3> {send gctl M %X %Y %s}",
	"bind .f <Motion> {send gctl M %X %Y %s}",
	"pack .f -side top -fill both -expand 1",
};

WMargin : con 0;	# want this much spare screen width
HMargin : con 0;	# want this much spare screen height (allow for titlebar, toolbar)

totalr: Rect;		# toplevel (".") screen coords (includes titlebar)
mainr: Rect;		# browser's main window coords
offset: Point;		# mainr.min-mainwin.r.min (accounts for origin change, due to move)

allwins : array of ref Image;
sp_t : ref Tk->Toplevel;
sp_gctl, sp_kctl, sp_wmctl : chan of string;

init(mods : ref Dat->Mods)
{
	sys = mods.sys;
	draw = mods.draw;
	acme = mods.acme;
	dat = mods.dat;
	utils = mods.utils;

	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if(wmlib == nil)
		error("can't load module Wmlib: %r");
	wmlib->init();

	display = acmectxt.display;
	screen = acmectxt.screen;
	screenw := screen.image.r.dx();
	screenh := screen.image.r.dy();
	yellow = display.color(Draw->Yellow);
	green = display.color(Draw->Green);
	red = display.color(Draw->Red);
	blue = display.color(Draw->Blue);
	black = display.color(Draw->Black);
	white = display.color(Draw->White);

	mainw := screenw - WMargin;
	mainh := screenh  - HMargin - 50;

	(t, wmctl) := wmlib->titlebar(screen, "-x 0 -y 0", "Acme", Wmlib->Resize | Wmlib->Hide);
	# (t, wmctl) := wmlib->titlebar(screen, "-x 0 -y 0", "Acme", Wmlib->Help | Wmlib->Resize | Wmlib->Hide);
	gctl := chan of string;
	kctl := chan of string;
	sp_t = t;
	sp_gctl = gctl;
	sp_kctl = kctl;
	sp_wmctl = wmctl;
	tk->namechan(t, gctl, "gctl");
	tk->namechan(t, kctl, "kctl");
	for(i := 0; i < len cfg; i++)
		if ((e := tk->cmd(t, cfg[i])) != nil && e[0] == '!')
			sys->print("tk error on '%s': %s\n", cfg[i], e);
	tbarh := actr(t, ".Wm_t").dy();
	totalr = Rect(Point(0,0),Point(mainw,tbarh+mainh));
	offset = Point(0,0);
	tk->cmd(t, "pack propagate . 0");
	allwins = array[1] of ref Image;
	makewins(t);
}

spawnprocs()
{
	spawn evhandle(sp_t, sp_gctl, sp_wmctl);
	spawn khandle(sp_kctl);
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

khandle(kctl: chan of string)
{
	keyboardpid = sys->pctl(0, nil);
	sys->pctl(Sys->FORKFD, nil);
	for(;;){
		s := <- kctl;
		(nil, l) := sys->tokenize(s, " ");
		case hd l{
			"k" =>
				k := int hd tl l;
				if(k != 0)
					ckeyboard <-= k;
			* =>
				error(sys->sprint("received %s on kctl", s));
		}
	}
}

evhandle(t: ref Tk->Toplevel, gctl, wmctl: chan of string)
{
	m : Pointer;
	s : string;
	QSZ : con 8;	# a power of two

	F := R := 0;
	q := array[QSZ] of string;
	mousepid = sys->pctl(0, nil);
	sys->pctl(Sys->FORKFD, nil);
	for(;;) {
		if (F != R) {
			alt {
				s = <- gctl or
				s = <- wmctl =>
					if (s[0] != 'M') {
						R = (R+1)&(QSZ-1);
						q[R] = s;
					}
				* =>
					;
			}
			F = (F+1)&(QSZ-1);
			s = q[F];
			q[F] = nil;
			sys->sleep(1);
		}
		else {
			alt {
				s = <- gctl or
				s = <- wmctl =>
					;
			}
		}
		(nil, l) := sys->tokenize(s, " ");
		case hd l {
			"b12" or "b1" or "b" or "M" =>
				l = tl l;
				x := int hd l;
				y := int hd tl l;
				but := int hd tl tl l;
				if (s[1] == '1') {
					if (s[2] == '2')
						but |= Acme->M_DOUBLE;
					else
						tk->cmd(t, "focus .");
				}
				p := Point(x,y);
				m.xy = p.sub(offset);
				m.buttons = but;
				m.msec = sys->millisec();
			# "k" =>
			#	k := int hd tl l;
			#	if(k != 0)
			#		ckeyboard <-= k;
			#	continue;
			"exit" =>
				m.buttons = Acme->M_QUIT;
			"help" =>
				m.buttons = Acme->M_HELP;
			"move" =>
				wmlib->titlectl(t, "move");
				r := actr(t, ".");
				if(totalr.min.x != r.min.x || totalr.min.y != r.min.y) {
					p := r.min;
					diff := p.sub(totalr.min);
					newmainr := mainr.addpt(diff);
					mainwin.origin(mainwin.r.min, newmainr.min);
					totalr = totalr.addpt(diff);
					mainr = newmainr;
					offset = mainr.min.sub(mainwin.r.min);
				}
				screen.top(allwins);
				continue;
			"size" =>
				wmlib->titlectl(t, "size 0 0");
				totalr  = actr(t, ".");
				makewins(t);
				screen.top(allwins);
				m.buttons = Acme->M_RESIZE;
			"task" =>
				# move the browser windows off the screen to hide them
                       		mainwin.origin(mainwin.r.min, (-3000, -3000));
				wmlib->titlectl(t, "task");
				# restore position of the offscreen windows
                 			mainwin.origin(mainwin.r.min, mainr.min);
				screen.top(allwins);
				continue;
			"raise" =>
				screen.top(allwins);
				continue;
			"lower" =>
				mainwin.bottom();
				tk->cmd(t, "lower .");
		}
		alt {
			cmouse <-= m =>
				;
			* =>
				if (s[0] != 'M') {
					q[F] = s;
					F = (F-1)&(QSZ-1);
				}
		}
	}
}

# Use tbarh, totalr to calculate mainr,
# reconfigure "." to cover totalr,
# and make (or remake) mainwin.
makewins(t: ref Tk->Toplevel)
{
	bd := int tk->cmd(t, ". cget -borderwidth");
	tk->cmd(t, ". configure -x " + string totalr.min.x
				+ " -y "+ string totalr.min.y
				+ " -width " + string (totalr.dx() - bd*2)
				+ " -height " + string (totalr.dy() - bd*2));
	tk->cmd(t, "update");
	mainr = actr(t, ".f");
	offset = Point(0,0);
	mainwin = screen.newwindow(mainr, Draw->White);
	if(mainwin == nil)
		error("can't initialize windows: %r");
	# mainwin.flush(D->Flushoff);
	allwins[0] = mainwin;
	screen.top(allwins);
}

setcursor(p : Point)
{
	display.cursorset(p.add(offset));
	# tk->cmd(sp_t, "cursor -x " + string p.x + " -y " + string p.y);
}

killwins()
{
	mainwin.origin(mainwin.r.min, (-3000, -3000));
	tk->cmd(sp_t, ". unmap");
}
