implement Bounce;

# bouncing balls demo.  it uses tk and multiple processes to animate a
# number of balls bouncing around the screen.  each ball has its own
# process.  processes are linked together with a circular linked list of
# channels, which ensures that time is doled out fairly to each process
# without letting the unpredictable host OS scheduling arbitrate.  (an
# earlier version used sys->sleep(), which had unpredictable results
# because of this).

include "sys.m";
	sys: Sys;
include "draw.m";
	draw: Draw;
	Point, Rect: import draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "math.m";
	math: Math;
include "rand.m";

Bounce: module {
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

BALLSIZE: con 5;
ZERO: con 1e-6;
π: con Math->Pi;

Line: adt {
	p1, p2: Point;
};

Realpoint: adt {
	x, y: real;
};

gamecmds := array[] of {
"canvas .c",
"bind .c <ButtonRelease-1> {send cmd 0 %x %y}",
"bind .c <ButtonRelease-2> {send cmd 0 %x %y}",
"bind .c <Button-1> {send cmd 1 %x %y}",
"bind .c <Button-2> {send cmd 2 %x %y}",
"pack .c -fill both -expand 1",
"update",
};

randch: chan of int;
lines: list of (int, Line);
lineid := 0;
lineversion := 0;

NBALLS: con 20;

addline(win: ref Tk->Toplevel, v: Line)
{
	lines = (++lineid, v) :: lines;
	cmd(win, ".c create line " + pt2s(v.p1) + " " + pt2s(v.p2) + " -width 3 -fill black" +
			" -tags l" + string lineid);
	lineversion++;
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	math = load Math Math->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil)
		nomod(Wmlib->PATH);
	wmlib->init();
	sys->pctl(Sys->NEWPGRP, nil);
	(win, wmctl) := wmlib->titlebar(ctxt.screen, nil, "Bounce", 0);
	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	for (i := 0; i < len gamecmds; i++)
		cmd(win, gamecmds[i]);
	cmd(win, ".c configure -width [.c cget -actwidth] -height [.c cget -actheight]");

	mch := chan of (int, Point);
	randch = chan of int;
	spawn randgenproc(randch);
	csz := Point(int cmd(win, ".c cget -actwidth"), int cmd(win, ".c cget -actheight"));
	addline(win, ((-1, -1), (csz.x, -1)));
	addline(win, ((csz.x, -1), csz));
	addline(win, (csz, (-1, csz.y)));
	addline(win, ((-1, csz.y), (-1, -1)));
	spawn makelinesproc(win, mch);

	# spawn a process for each ball, and link 'em all together
	# with a circular list of channels.
	firstc := c1 := chan of int;
	c2 := chan of int;
	for (i = 0; i < NBALLS; i++) {
		if (i == NBALLS - 1)
			c2 = firstc;
		spawn animproc(c1, c2, win,
			(50.0 + real i * 2.7, 100.0), makeunit(((0, 0), (-10 + i, 35))));
		(c1, c2) = (c2, chan of int);
	}
	# inject the token to be passed around the ring.
	firstc <-= 1;
	for (;;) alt {
	c := <-wmctl =>
		wmlib->titlectl(win, c);
	c := <-cmdch =>
		(nil, toks) := sys->tokenize(c, " ");
		mch <-= (int hd toks, Point(int hd tl toks, int hd tl tl toks));
	}
}

nomod(s: string)
{
	sys->fprint(sys->fildes(2), "bounce: cannot load %s: %r\n", s);
	sys->raise("fail:bad module");
}

# animate one ball. initial position and unit-velocity are
# given by p and v.
animproc(c1, c2: chan of int, win: ref Tk->Toplevel, p, v: Realpoint)
{
	velocity := 0.1 + real (<-randch % 40) / 100.0;
	ballid := cmd(win, sys->sprint(".c create oval 0 0 1 1 -fill #%.6x", <-randch & 16rffffff));
	hitlineid := -1;
	smallcount := 0;
	version := lineversion;
loop:	for (;;) {
		hitline: Line;
		hitp: Realpoint;

		dist := 1000000.0;
		oldid := hitlineid;
		for (l := lines; l != nil; l = tl l) {
			(id, line) := hd l;
			(ok, hp, hdist) := intersect(p, v, line);
			if (ok && hdist < dist && id != oldid && (smallcount < 10 || hdist > 1.5)) {
				(hitp, hitline, hitlineid, dist) = (hp, line, id, hdist);
			}
		}
		if (dist > 10000.0) {
			sys->print("no intersection!\n");
			for (;;)
				c2 <-= <-c1;		# exiting would halt all processes!
		}
		if (dist < 0.0001)
			smallcount++;
		else
			smallcount = 0;
		bouncev := boing(v, hitline);
		t0 := sys->millisec();
		dt := int (dist / velocity);
		t := 0;
		do {
			s := real t * velocity;
			currp := Realpoint(p.x + s * v.x,  p.y + s * v.y);
			bp := Point(int currp.x, int currp.y);
			cmd(win, ".c coords " + ballid + " " +
				string (bp.x-BALLSIZE)+" "+string (bp.y-BALLSIZE)+" "+
				string (bp.x+BALLSIZE)+" "+string (bp.y+BALLSIZE));
			cmd(win, "update");
			if (lineversion > version) {
				(p, hitlineid, version) = (currp, oldid, lineversion);
				continue loop;
			}
			# pass the token around the ring.
			c2 <-= <-c1;
			t = sys->millisec() - t0;
		} while (t < dt);
		p = hitp;
		v = bouncev;
	}
}

# thread-safe access to the Rand module
randgenproc(ch: chan of int)
{
	rand := load Rand Rand->PATH;
	for (;;)
		ch <-= rand->rand(16r7fffffff);
}

makelinesproc(win: ref Tk->Toplevel, mch: chan of (int, Point))
{
	for (;;) {
		(down, p1) := <-mch;
		addline(win, (p1, p1));
		(id, nil) := hd lines;
		p2 := p1;
		do {
			(down, p2) = <-mch;
			cmd(win, ".c coords l" + string id + " " + pt2s(p1) + " " + pt2s(p2));
			cmd(win, "update");
			lines = (id, (p1, p2)) :: tl lines;
			lineversion++;
			if (down > 1) {
				dp := p2.sub(p1);
				if (dp.x*dp.x + dp.y+dp.y > 5) {
					p1 = p2;
					addline(win, (p2, p2));
					(id, nil) = hd lines;
				}
			}
		} while (down);
	}
}

makeunit(v: Line): Realpoint
{
	fg := v.p2.sub(v.p1);
	mag := math->sqrt(real (fg.x * fg.x + fg.y * fg.y));
	return (real fg.x / mag, real fg.y / mag);
}

# bounce ball travelling in direction av off line b.
# return the new unit vector.
boing(av: Realpoint, b: Line): Realpoint
{
	f := b.p2.sub(b.p1);
	d := math->atan2(real f.y, real f.x) * 2.0 - math->atan2(av.y, av.x);
	return (math->cos(d), math->sin(d));
}

# compute the intersection of lines a and b.
# b is assumed to be fixed, and a is indefinitely long
# but doesn't extend backwards from its starting point.
# a is defined by the starting point p and the unit vector v.
intersect(p, v: Realpoint, b: Line): (int, Realpoint, real)
{
	w := Realpoint(real (b.p2.x - b.p1.x), real (b.p2.y - b.p1.y));
	det := w.x * v.y - v.x * w.y;
	if (det > -ZERO && det < ZERO)
		return (0, (0.0, 0.0), 0.0);

	y21 := real b.p1.y - p.y;
	x21 := real b.p1.x - p.x;
	s := (w.x * y21 - w.y * x21) / det;
	if (s < 0.0)
		return (0, (0.0, 0.0), 0.0);

	hp := Realpoint(p.x+v.x*s, p.y+v.y*s);
	if (b.p1.x > b.p2.x)
		(b.p1.x, b.p2.x) = (b.p2.x, b.p1.x);
	if (b.p1.y > b.p2.y)
		(b.p1.y, b.p2.y) = (b.p2.y, b.p1.y);

	return (int hp.x >= b.p1.x && int hp.x <= b.p2.x
			&& int hp.y >= b.p1.y && int hp.y <= int b.p2.y, hp, s);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->print("tk error %s on '%s'\n", e, s);
	return e;
}

pt2s(p: Point): string
{
	return string p.x + " " + string p.y;
}
