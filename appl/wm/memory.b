implement WmMemory;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image, Rect: import draw;

include "tk.m";
	tk: Tk;
	t: ref Tk->Toplevel;

include	"wmlib.m";
	wmlib: Wmlib;

WmMemory: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Arena: adt
{
	name:	string;
	limit:	int;
	size:	int;
	hw:	int;
	y:	int;
	tag:	string;
	tagsz: string;
	taghw:	string;
};
a := array[10] of Arena;

mem_cfg := array[] of {
	"canvas .c -width 240 -height 45",
	"pack .c",
	"update",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	spawn realinit(ctxt);
}

realinit(ctxt: ref Draw->Context)
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;

	wmlib->init();

	menubut := chan of string;
	(t, menubut) = wmlib->titlebar(ctxt.screen, "", "Memory", 0);
	wmlib->tkcmds(t, mem_cfg);

	tick := chan of int;
	spawn ticker(tick);

	mfd := sys->open("/dev/memory", sys->OREAD);

	n := getmem(mfd);
	maxx := initdraw(n);

	pid: int;
	for(;;) alt {
	menu := <-menubut =>
		if(menu == "exit"){
			kill(pid);
			return;
		}
		wmlib->titlectl(t, menu);
	pid = <-tick =>
		update(mfd);
		for(i := 0; i < n; i++) {
			x := int ((big a[i].size * big (230-maxx)) / big a[i].limit);
			s := sys->sprint(".c coords %s %d %d %d %d",
				a[i].tag,
				maxx,
				a[i].y + 4,
				maxx + x,
				a[i].y + 8);
			cmd(t, s);
			x = int ((big a[i].hw * big (230-maxx)) / big a[i].limit);
			s = sys->sprint(".c coords %s %d %d %d %d",
				a[i].taghw,
				maxx,
				a[i].y + 4,
				maxx+x,
				a[i].y + 8);
			cmd(t, s);
			s = sys->sprint(".c itemconfigure %s -text '%s", a[i].tagsz, sizestr(a[i].size));
			cmd(t, s);
		}
		cmd(t, "update");
	}
}

ticker(c: chan of int)
{
	pid := sys->pctl(0, nil);
	for(;;) {
		c <-= pid;
		sys->sleep(1000);
	}
}

initdraw(n: int): int
{
	y := 15;
	maxx := 0;
	for (i := 0; i < n; i++) {
		id := cmd(t, ".c create text 5 "+string y+" -anchor w -text "+a[i].name);
		r := s2r(cmd(t, ".c bbox " + id));
		if (r.max.x > maxx)
			maxx = r.max.x;
		y += 20;
	}
	maxx += 5;
	y = 15;
	for(i = 0; i < n; i++) {
		s := sys->sprint(".c create rectangle %d %d 230 %d -fill white", maxx, y+4, y+8);
		cmd(t, s);
		s = sys->sprint(".c create rectangle %d %d 230 %d -fill white", maxx, y+4, y+8);
		a[i].taghw = cmd(t, s);
		s = sys->sprint(".c create rectangle %d %d 230 %d -fill red", maxx, y+4, y+8);
		a[i].tag = cmd(t, s);
		s = sys->sprint(".c create text 230 %d -anchor e -text '%s", y - 2, sizestr(a[i].limit));
		cmd(t, s);
		s = sys->sprint(".c create text %d %d -anchor w -text '%s", maxx, y - 2, sizestr(a[i].size));
		a[i].tagsz = cmd(t, s);
		a[i].y = y;
		y += 20;
	}
	cmd(t, ".c configure -height "+string y);
	cmd(t, "update");
	return maxx;
}

sizestr(n: int): string
{
	if ((n / 1024) % 1024 == 0)
		return string (n / (1024 * 1024)) + "M";
	return string (n / 1024) + "K";
}

buf := array[8192] of byte;

update(mfd: ref Sys->FD): int
{
	sys->seek(mfd, 0, Sys->SEEKSTART);
	n := sys->read(mfd, buf, len buf);
	if(n <= 0)
		exit;
	(nil, l) := sys->tokenize(string buf[0:n], "\n");
	i := 0;
	while(l != nil) {
		s := hd l;
		a[i].size = int s[0:];
		a[i++].hw = int s[24:];
		l = tl l;
	}
	return i;
}

getmem(mfd: ref Sys->FD): int
{
	n := sys->read(mfd, buf, len buf);
	if(n <= 0)
		exit;
	(nil, l) := sys->tokenize(string buf[0:n], "\n");
	i := 0;
	while(l != nil) {
		s := hd l;
		a[i].size = int s[0:];
		a[i].limit = int s[12:];
		a[i].hw = int s[24:];
		a[i].name = s[7*12:];
		i++;
		l = tl l;
	}
	return i;
}

s2r(s: string): Rect
{
	(n, toks) := sys->tokenize(s, " ");
	if (n != 4) {
		sys->print("'%s' is not a rectangle!\n", s);
		sys->raise("bad conversion");
	}
	r: Rect;
	(r.min.x, toks) = (int hd toks, tl toks);
	(r.min.y, toks) = (int hd toks, tl toks);
	(r.max.x, toks) = (int hd toks, tl toks);
	(r.max.y, toks) = (int hd toks, tl toks);
	return r;
}

kill(pid: int)
{
	fd := sys->open("#p/"+string pid+"/ctl", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "kill");
}


cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->print("mand: tk error on '%s': %s\n", s, e);
	return e;
}
