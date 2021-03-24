implement Wmlib;

include "sys.m";
	sys: Sys;
	Dir: import sys;

include "draw.m";
	draw: Draw;
	Screen, Rect, Point: import draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include "string.m";
	str: String;

include "wmlib.m";
	titlefd: ref Sys->FD;

include "workdir.m";

include "readdir.m";
	readdir: Readdir;

include "filepat.m";
	filepat: Filepat;

init()
{
	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	str = load String String->PATH;
}

title_cfg := array[] of {
	"frame .Wm_t -bg #aaaaaa -borderwidth 1",
	"label .Wm_t.title -anchor w -bg #aaaaaa -fg white",
	"button .Wm_t.e -bd 1 -bitmap exit.bit -command {send wm_title exit}",
	"pack .Wm_t.e -side right",
	"bind .Wm_t <Button-1> {send wm_title move}",
	"bind .Wm_t <Double-Button-1> {lower .}",
	"bind .Wm_t <Motion-Button-1> {}",
	"bind .Wm_t <Motion> {}",
	"bind .Wm_t.title <Button-1> {send wm_title move}",
	"bind .Wm_t.title <Double-Button-1> {lower .}",
	"bind .Wm_t.title <Motion-Button-1> {}",
	"bind .Wm_t.title <Motion> {}",
	"bind . <FocusIn> {.Wm_t configure -bg blue;"+
		" .Wm_t.title configure -bg blue;update}",
	"bind . <FocusOut> {.Wm_t configure -bg #aaaaaa;"+
		" .Wm_t.title configure -bg #aaaaaa;update}",
};

readwmgeom(): string
{
	fd := sys->open("/chan/wmgeom", Sys->OREAD);
	if (fd == nil)
		return nil;
	buf := array[100] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	return string buf[0:n];
}

#
# Create a window manager title bar called .Wm_t which is ready
# to pack at the top level
#
titlebar(scr: ref Draw->Screen,
		where: string,
		title: string,
		flags: int): (ref Tk->Toplevel, chan of string)
{
	wm_title := chan of string;
	where = readwmgeom() + " " + where;
	t := tk->toplevel(scr, "-borderwidth 1 -relief raised "+where);

	tk->namechan(t, wm_title, "wm_title");


	for(i := 0; i < len title_cfg; i++)
		cmd(t, title_cfg[i]);
	cmd(t, ".Wm_t.title configure -text " + tkquote(title));

	if(flags & OK)
		cmd(t, "button .Wm_t.ok -bd 1 -bitmap ok.bit"+
			" -command {send wm_title ok}; pack .Wm_t.ok -side right");

	if(flags & Hide)
		cmd(t, "button .Wm_t.t -bd 1 -bitmap task.bit"+
			" -command {send wm_title task}; pack .Wm_t.t -side right");

	if(flags & Resize)
		cmd(t, "button .Wm_t.m -bd 1 -bitmap maxf.bit"+
			" -command {send wm_title size}; pack .Wm_t.m -side right");

	if(flags & Help)
		cmd(t, "button .Wm_t.h -bd 1 -bitmap help.bit"+
			" -command {send wm_title help}; pack .Wm_t.h -side right");

	# pack the title last so it gets clipped first
	cmd(t, "pack .Wm_t.title -side left");
	cmd(t, "pack .Wm_t -fill x");
	return (t, wm_title);
}

#
# titlectl implements the default window behavior for programs
# using title bars
#
titlectl(t: ref Toplevel, request: string)
{
	# cmd(t, "cursor -default");
	(n, toks) := sys->tokenize(request, " \t");
	if (n < 1)
		return;
	case hd toks {
	"move" or "size" =>
		if (hd toks == "move")
			cmd(t, "raise .");
		p := Draw->Point(0,0);
		if (n == 3)
			p = (int hd tl toks, int hd tl tl toks);
		moveresize(t, request[0], p);
	"exit" =>
		pid := sys->pctl(0, nil);
		fd := sys->open("/prog/"+string pid+"/ctl", sys->OWRITE);
		sys->fprint(fd, "killgrp");
		exit;
	"task" =>
		titlefd = sys->open("/chan/wm", sys->ORDWR);
		if(titlefd == nil) {
			sys->print("open wm: %r\n");
			return;
		}
		cmd(t, ". unmap");
		sys->fprint(titlefd, "t%s", cmd(t, ".Wm_t.title cget -text"));
		cmd(t, ". map");
		titlefd = nil;
	}
}

# deprecated, awaiting removal.
untaskbar()
{
	if(titlefd != nil)
		sys->fprint(titlefd, "r");
}

unhide()
{
	if(titlefd != nil)
		sys->fprint(titlefd, "r");
}

#
# find upper left corner for new child window
#
gx, gy: int;
ix, iy: int;
STEP: con 20;

geom(t: ref Toplevel): string
{
	# always want to be relative to current position of parent
	tx := int cmd(t, ". cget x");
	ty := int cmd(t, ". cget y");

	if ( tx != gx || ty != gy ) {		# reset if parent moved
		gx = tx;
		gy = ty;
		ix = iy = 0;
	}
	else
	if ( ix + iy >= STEP * 20 ) {		# don't march off indefinitely
		ix = ix - iy + STEP;		# offset new series
		iy = 0;
		if ( ix >= STEP * 10 )
			ix = 0;
	}
	ix += STEP;
	iy += STEP;
	return "-x " + string (gx+ix) +" -y " + string (gy+iy);
}

#
# find upper left corner for subsidiary child window (always at constant
# position relative to parent)
#
localgeom(t: ref Toplevel): string
{
	if (t == nil)
		return nil;

	tx := int cmd(t, ". cget x");
	ty := int cmd(t, ". cget y");

	return "-x " + string (tx+STEP) + " -y " + string (ty+STEP);
}

centre(t: ref Toplevel)
{
	org: Point;
	org.x = t.image.screen.image.r.dx() / 2 - t.image.r.dx() / 2;
	org.y = t.image.screen.image.r.dy() / 3 - t.image.r.dy() / 2;
	if (org.y < 0)
		org.y = 0;
	cmd(t, ". configure -x " + string org.x + " -y " + string org.y);
}

#
# Set the name that will be displayed on the task bar
#
taskbar(t: ref Toplevel, name: string): string
{
	old := cmd(t, ".Wm_t.title cget -text");
	cmd(t, ".Wm_t.title configure -text '"+name);
	return old;
}

#
# Dialog with wm to rubberband the window and return a new position
# or size
#
moveresize(t: ref Toplevel, mode: int, min: Draw->Point)
{
	ox := int cmd(t, ". cget -x");
	oy := int cmd(t, ". cget -y");
	w := int cmd(t, ". cget -width");
	h := int cmd(t, ". cget -height");
	bw := int cmd(t, ". cget -borderwidth");

	h += 2*bw;
	w += 2*bw;
	fd := sys->open("/chan/wm", sys->ORDWR);
	if(fd == nil) {
		sys->print("open wm: %r\n");
		return;
	}
	sys->fprint(fd, "%c%5d %5d %5d %5d", mode, ox, oy, ox+w, oy+h);

	reply := array[128] of byte;
	n := sys->read(fd, reply, len reply);
	if(n <= 0)
		return;

	s := string reply[0:n];
	if( len s < 18 )
		return;
	x := int s;
	y := int s[6:];
	if(mode == 'm') {
		if(ox != x || oy != y)
			cmd(t, ". configure -x "+string x+" -y "+string y+"; update");
		return;
	}
	w = int s[12:] - x - 2*bw;
	h = int s[18:] - y - 2*bw;

	if (w < min.x)
		w = min.x;
	if (h < min.y)
		h = min.y;
	cmd(t, ". configure -x "+ string x +
		   " -y "+string y+
		   " -width "+string w+
		   " -height "+string h+
		   "; update");
}

snarfget(): string
{
	fd := sys->open("/chan/snarf", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[8192] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return "";

	return string buf[0:n];
}

snarfput(buf: string)
{
	fd := sys->open("/chan/snarf", sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "%s", buf);
}

tkquote(s: string): string
{
	r := "{";

	j := 0;
	for(i:=0; i < len s; i++) {
		if(s[i] == '{' || s[i] == '}' || s[i] == '\\') {
			r = r + s[j:i] + "\\";
			j = i;
		}
	}
	r = r + s[j:i] + "}";
	return r;
}

tkcmds(top: ref Tk->Toplevel, a: array of string)
{
	n := len a;
	for(i := 0; i < n; i++)
		tk->cmd(top, a[i]);
}

topopts := array[] of {
	"font"
#	, "bd"			# Wait for someone to ask for these
#	, "relief"		# Note: colors aren't inherited, it seems
};

opts(top: ref Tk->Toplevel) : string
{
	if (top == nil)
		return nil;
	opts := "";
	for ( i := 0; i < len topopts; i++ ) {
		cfg := tk->cmd(top, ". cget " + topopts[i]);
		if ( cfg != "" && cfg[0] != '!' )
			opts += " -" + topopts[i] + " " + tkquote(cfg);
	}
	return opts;
}

dialog_config := array[] of {
	"label .top.ico",
	"label .top.msg",
	"frame .top -relief raised -bd 1",
	"frame .bot -relief raised -bd 1",
	"pack .top.ico -side left -padx 10 -pady 10",
	"pack .top.msg -side left -expand 1 -fill both -padx 10 -pady 10",
	"pack .Wm_t .top .bot -side top -fill both",
	"focus ."
};

dialog(parent: ref Tk->Toplevel,
	ico: string,
	title:string,
	msg: string,
	dflt: int,
	labs : list of string): int
{
	where := localgeom(parent) + " " + opts(parent);

	(t, tc) := titlebar(parent.image.screen, where, title, 0);

	d := chan of string;
	tk->namechan(t, d, "d");

	tkcmds(t, dialog_config);
	cmd(t, ".top.msg configure -text '" + msg);
	if (ico != nil)
		cmd(t, ".top.ico configure -bitmap " + ico);

	n := len labs;
	for(i := 0; i < n; i++) {
		cmd(t, "button .bot.button" +
				string(i) + " -command {send d " +
				string(i) + "} -text '" + hd labs);

		if(i == dflt) {
			cmd(t, "frame .bot.default -relief sunken -bd 1");
			cmd(t, "pack .bot.default -side left -expand 1 -padx 10 -pady 8");
			cmd(t, "pack .bot.button" + string i +
				" -in .bot.default -side left -padx 10 -pady 8 -ipadx 8 -ipady 4");
		}
		else
			cmd(t, "pack .bot.button" + string i +
				" -side left -expand 1 -padx 10 -pady 10 -ipadx 8 -ipady 4");
		labs = tl labs;
	}

	if(dflt >= 0)
		cmd(t, "bind . <Key-\n> {send d " + string dflt + "}");
	cmd(t, "update");

	e := cmd(t, "variable lasterror");
	if(e != "") {
		sys->fprint(sys->fildes(2), "Wmlib.dialog error: %s\n", e);
		return dflt;
	}

	for(;;) alt {
	ans := <-d =>
		return int ans;
	tcs := <-tc =>
		if(tcs == "exit")
			return dflt;
		titlectl(t, tcs);
	}

}

getstring_config := array[] of {
	"label .lab",
	"entry .ent -relief sunken -bd 2 -width 200",
	"pack .lab .ent -side left",
	"bind .ent <Key-\n> {send f 1}",
	"focus .ent"
};

getstring(parent: ref Tk->Toplevel, msg: string): string
{
	where := localgeom(parent) + " " + opts(parent);

	t := tk->toplevel(parent.image.screen, where + " -borderwidth 2 -relief raised");
	f := chan of string;
	tk->namechan(t, f, "f");

	tkcmds(t, getstring_config);
	cmd(t, ".lab configure -text '" + msg + ":   ");
	cmd(t, "update");

	e := tk->cmd(t, "variable lasterror");
	if(e != "") {
		sys->print("getstring error: %s\n", e);
		return "";
	}

	<-f;

	ans := cmd(t, ".ent get");
	if(len ans > 0 && ans[0] == '!')
		return "";

	cmd(t, "destroy .");

	return ans;
}

TABSXdelta : con 2;
TABSXslant : con 5;
TABSXoff : con 5;
TABSYheight : con 35;
TABSYtop : con 10;
TABSBord : con 3;

# pseudo-widget for folder tab selections
mktabs(t: ref Tk->Toplevel, dot: string, tabs: array of (string, string), dflt: int): chan of string
{
	lab, widg: string;
	cmd(t, "canvas "+dot+" -height "+string TABSYheight);
	cmd(t, "pack propagate "+dot+" 0");
	c := chan of string;
	tk->namechan(t, c, dot[1:]);
	xpos := 2*TABSXdelta;
	top := 10;
	ypos := TABSYheight - 3;
	back := cmd(t, dot+" cget -background");
	dark := "#999999";
	light := "#ffffff";
	w := 20;
	h := 30;
	last := "";
	for(i := 0; i < len tabs; i++){
		(lab, widg) = tabs[i];
		tag := "tag" + string i;
		sel := "sel" + string i;
		xs := xpos;
		xpos += TABSXslant + TABSXoff;
		v := cmd(t, dot+" create text "+string xpos+" "+string ypos+" -text "+tkquote(lab)+" -anchor sw -tags "+tag);
		bbox := tk->cmd(t, dot+" bbox "+tag);
		if(bbox[0] == '!')
			break;
		(r, nil) := parserect(bbox);
		r.max.x += TABSXoff;
		x1 := " "+string xs;
		x2 := " "+string(xs + TABSXslant);
		x3 := " "+string r.max.x;
		x4 := " "+string(r.max.x + TABSXslant);
		y1 := " "+string(TABSYheight - 2);
		y2 := " "+string TABSYtop;
		cmd(t, dot+" create polygon " + x1+y1 + x2+y2 + x3+y2 + x4+y1 +
			" -fill "+back+" -tags "+tag);
		cmd(t, dot+" create line " + x3+y2 + x4+y1 +
			" -fill "+dark+" -width 3 -tags "+tag);
		cmd(t, dot+" create line " + x1+y1 + x2+y2 + x3+y2 +
			" -fill "+light+" -width 3 -tags "+tag);

		x1 = " "+string(xs+2);
		x4 = " "+string(r.max.x + TABSXslant - 2);
		y1 = " "+string(TABSYheight);
		cmd(t, dot+" create line " + x1+y1 + x4+y1 +
			" -fill "+back+" -width 5 -tags "+sel);

		cmd(t, dot+" raise "+v);
		cmd(t, dot+" bind "+tag+" <ButtonRelease-1> 'send "+
			dot[1:]+" "+string i);

		cmd(t, dot+" lower "+tag+" "+last);
		last = tag;

		xpos = r.max.x;
		ww := int cmd(t, widg+" cget -width");
		wh := int cmd(t, widg+" cget -height");
		if(wh > h)
			h = wh;
		if(ww > w)
			w = ww;
	}
	xpos += 4*TABSXslant;
	if(w < xpos)
		w = xpos;

	for(i = 0; i < len tabs; i++){
		(nil, widg) = tabs[i];
		cmd(t, "pack propagate "+widg+" 0");
		cmd(t, widg+" configure -width "+string w+" -height "+string h);
	}

	w += 2*TABSBord;
	h += 2*TABSBord + TABSYheight;

	cmd(t, dot+" create line 0 "+string TABSYheight+
		" "+string w+" "+string TABSYheight+" -width 3 -fill "+light);
	cmd(t, dot+" create line 1 "+string TABSYheight+
		" 1 "+string(h-1)+" -width 3 -fill "+light);
	cmd(t, dot+" create line  0 "+string(h-1)+
		" "+string w+" "+string(h-1)+" -width 3 -fill "+dark);
	cmd(t, dot+" create line "+string(w-1)+" "+string TABSYheight+
		" "+string(w-1)+" "+string(h-1)+" -width 3 -fill "+dark);

	cmd(t, dot+" configure -width "+string w+" -height "+string h);
	cmd(t, dot+" configure -scrollregion {0 0 "+string w+" "+string h+"}");
	tabsctl(t, dot, tabs, -1, string dflt);
	return c;
}

tabsctl(t: ref Tk->Toplevel,
	dot: string,
	tabs: array of (string, string),
	id: int,
	s: string): int
{
	lab, widg: string;

	nid := int s;
	if(id == nid)
		return id;
	if(id >= 0){
		(lab, widg) = tabs[id];
		tag := "tag" + string id;
		cmd(t, dot+" lower sel" + string id);
		pos := cmd(t, dot+" coords " + tag);
		if(len pos >= 1 && pos[0] != '!'){
			(p, nil) := parsept(pos);
			cmd(t, dot+" coords "+tag+" "+string(p.x+1)+
				" "+string(p.y+1));
		}
		if(id > 0)
			cmd(t, dot+" lower "+ tag + " tag"+string (id - 1));
		cmd(t, dot+" delete win" + string id);
	}
	id = nid;
	(lab, widg) = tabs[id];
	pos := tk->cmd(t, dot+" coords tag" + string id);
	if(len pos >= 1 && pos[0] != '!'){
		(p, nli) := parsept(pos);
		cmd(t, dot+" coords tag"+string id+" "+string(p.x-1)+" "+string(p.y-1));
	}
	cmd(t, dot+" raise tag"+string id);
	cmd(t, dot+" raise sel"+string id);
	cmd(t, dot+" create window "+string TABSBord+" "+
		string(TABSYheight+TABSBord)+" -window "+widg+" -anchor nw -tags win"+string id);
	cmd(t, "update");
	return id;
}

parsept(s: string): (Draw->Point, string)
{
	p: Draw->Point;

	(p.x, s) = str->toint(s, 10);
	(p.y, s) = str->toint(s, 10);
	return (p, s);
}

parserect(s: string): (Draw->Rect, string)
{
	r: Draw->Rect;

	(r.min, s) = parsept(s);
	(r.max, s) = parsept(s);
	return (r, s);
}

Browser: adt {
	top:		ref Tk->Toplevel;
	ncols:	int;
	colwidth:	int;
	w:		string;
	init:		fn(top: ref Tk->Toplevel, w: string, colwidth, height: string, maxcols: int): (ref Browser, chan of string);

	addcol:	fn(c: self ref Browser, t: string, d: array of string);
	delete:	fn(c: self ref Browser, colno: int);
	selection:	fn(c: self ref Browser, cno: int): string;
	select:	fn(b: self ref Browser, cno: int, e: string);
	entries:	fn(b: self ref Browser, cno: int): array of string;
	resize:	fn(c: self ref Browser);
};

BState: adt {
	b:			ref Browser;
	bpath:		string;		# path currently displayed in browser
	epath:		string;		# path entered by user
	dirfetchpid:	int;
	dirfetchpath:	string;
};

filename_config := array[] of {
	"entry .e -bg white",
	"frame .pf",
	"entry .pf.e",
	"label .pf.t -text {Filter:}",
	"entry .pats",
	"bind .e <Key> +{send ech key}",
	"bind .e <Key-\n> {send ech enter}",
	"bind .e {<Key-\t>} {send ech expand}",
	"bind .pf.e <Key-\n> {send ech setpat}",
	"bind . <Configure> {send ech config}",
	"pack .b -side top -fill both -expand 1",
	"pack .pf.t -side left",
	"pack .pf.e -side top -fill x",
	"pack .pf -side top -fill x",
	"pack .e -side top -fill x",
	"pack propagate . 0",
};

debugging := 0;

filename(scr: ref Screen, otop: ref Toplevel,
		title: string,
		pats: list of string,
		dir: string): string
{
	patstr: string;
	if(readdir == nil) {
		readdir = load Readdir Readdir->PATH;
		filepat = load Filepat Filepat->PATH;
	}

	if (dir == nil || dir == ".") {
		wd := load Workdir Workdir->PATH;
		if ((dir = wd->init()) != nil) {
			(ok, nil) := sys->stat(dir);
			if (ok == -1)
				dir = nil;
		}
		wd = nil;
	}
	if (dir == nil)
		dir = "/";
	(pats, patstr) = makepats(pats);
	where := localgeom(otop) + " " + opts(otop);
	if (title == nil)
		title = "Open";
	(top, wch) := titlebar(scr, where+" -bd 1 -font /fonts/misc/latin1.6x13", 
			title, Wmlib->Resize|Wmlib->OK);
	(b, colch) := Browser.init(top, ".b", "16w", "20h", 3);
	entrych := chan of string;
	tk->namechan(top, entrych, "ech");
	tkcmds(top, filename_config);	
	cmd(top, ".e insert 0 '" + dir);
	cmd(top, ".pf.e insert 0 '" + patstr);
	s := ref BState(b, nil, dir, -1, nil);
	s.b.resize();
	dfch := chan of (string, array of ref Sys->Dir);
	if (otop == nil)
		centre(top);
	fittoscreen(top);
loop: for (;;) {
		if (debugging) {
			sys->print("filename: before sync, bpath: '%s'; epath: '%s'\n",
				s.bpath, s.epath);
		}
		bsync(s, dfch, pats);
		if (debugging) {
			sys->print("filename: after sync, bpath: '%s'; epath: '%s'", s.bpath, s.epath);
			if (s.dirfetchpid == -1)
				sys->print("\n");
			else
				sys->print("; fetching '%s' (pid %d)\n", s.dirfetchpath, s.dirfetchpid);
		}
		cmd(top, "focus .e");
		cmd(top, "update");
		alt {
		c := <-colch =>
			double := c[0] == 'd';
			c = c[1:];
			(bpath, nbpath, elem) := (s.bpath, "", "");
			for (cno := 0; cno <= int c; cno++) {
				(elem, bpath) = nextelem(bpath);
				nbpath = pathcat(nbpath, elem);
			}
			nsel := s.b.selection(int c);
			if (nsel != nil)
				nbpath = pathcat(nbpath, nsel);
			s.epath = nbpath;
			cmd(top, ".e delete 0 end");
			cmd(top, ".e insert 0 '" + s.epath);
			if (double)
				break loop;
		c := <-entrych =>
			case c {
			"enter" =>
				break loop;
			"config" =>
				s.b.resize();
			"key" =>
				s.epath = cmd(top, ".e get");
			"expand" =>
				cmd(top, ".e delete 0 end");
				cmd(top, ".e insert 0 '" + s.bpath);
				s.epath = s.bpath;
			"setpat" =>
				patstr = cmd(top, ".pf.e get");
				if (patstr == "  debug  ")
					debugging = !debugging;
				else {
					(nil, pats) = sys->tokenize(patstr, " ");
					s.b.delete(0);
					s.bpath = nil;
				}
			}
		c := <-wch =>
			if (c == "ok")
				break loop;
			if (c == "exit") {
				s.epath = nil;
				break loop;
			}
			titlectl(top, c);
		(t, d) := <-dfch =>
			ds := array[len d] of string;
			for (i := 0; i < len d; i++) {
				n := d[i].name;
				if ((d[i].mode & Sys->CHDIR) != 0)
					n[len n] = '/';
				ds[i] = n;
			}
			s.b.addcol(t, ds);
			ds = nil;
			d = nil;
			s.bpath = s.dirfetchpath;
			s.dirfetchpid = -1;
		}
	}
	if (s.dirfetchpid != -1)
		kill(s.dirfetchpid);
	return s.epath;
}

bsync(s: ref BState, dfch: chan of (string, array of ref Sys->Dir), pats: list of string)
{
	(epath, bpath) := (s.epath, s.bpath);
	cno := 0;
	prefix, e1, e2: string = "";

	# find maximal prefix of epath and bpath.
	for (;;) {
		p1, p2: string;
		(e1, p1) = nextelem(epath);
		(e2, p2) = nextelem(bpath);
		if (e1 == nil || e1 != e2)
			break;
		prefix = pathcat(prefix, e1);
		(epath, bpath) = (p1, p2);
		cno++;
	}

	if (epath == nil) {
		if (bpath != nil) {
			s.b.delete(cno);
			s.b.select(cno - 1, nil);
			s.bpath = prefix;
		}
		return;
	}

	# if the paths have no prefix in common then we're starting
	# at a different root - don't do anything until
	# we know we have at least one full element.
	# even then, if it's not a directory, we have to ignore it.
	if (cno == 0 && islastelem(epath))
		return;

	if (e1 != nil && islastelem(epath)) {
		# find first prefix-matching entry.
		match := "";
		for ((i, ents) := (0, s.b.entries(cno - 1)); i < len ents; i++) {
			m := ents[i];
			if (len m >= len e1 && m[0:len e1] == e1) {
				match = deslash(m);
				break;
			}
		}
		if (match != nil) {
			if (match == e2 && islastelem(bpath))
				return;

			epath = pathcat(match,  epath[len e1:]);
			e1 = match;
			if (e1 == e2)
				cno++;
		} else {
			s.b.delete(cno);
			s.bpath = prefix;
			return;
		}
	}

	s.b.delete(cno);
	s.b.select(cno - 1, e1);
	np := pathcat(prefix, e1);
	if (s.dirfetchpid != -1) {
		if (np == s.dirfetchpath)
			return;
		kill(s.dirfetchpid);
		s.dirfetchpid = -1;
	}
	(ok, dir) := sys->stat(np);
	if (ok != -1 && (dir.mode & Sys->CHDIR) != 0) {
		sync := chan of int;
		spawn dirfetch(np, e1, sync, dfch, pats);
		s.dirfetchpid = <-sync;
		s.dirfetchpath = np;
	} else if (ok != -1)
		s.bpath = np;
	else
		s.bpath = prefix;
}

dirfetch(p: string, t: string, sync: chan of int,
		dfch: chan of (string, array of ref Sys->Dir),
		pats: list of string)
{
	sync <-= sys->pctl(0, nil);
	(a, e) := readdir->init(p, Readdir->NAME|Readdir->COMPACT);
	if (e != -1) {
		j := 0;
		for (i := 0; i < len a; i++) {
			pl := pats;
			if ((a[i].mode & Sys->CHDIR) == 0) {
				for (; pl != nil; pl = tl pl)
					if (filepat->match(hd pl, a[i].name))
						break;
			}
			if (pl != nil || pats == nil)
				a[j++] = a[i];
		}
		a = a[0:j];
	}
	dfch <-= (t, a);
}

dist(top: ref Tk->Toplevel, s: string): int
{
	cmd(top, "frame .xxxx -width " + s);
	d := int cmd(top, ".xxxx cget -width");
	cmd(top, "destroy .xxxx");
	return d;
}

Browser.init(top: ref Tk->Toplevel, w: string, colwidth, height: string, maxcols: int): (ref Browser, chan of string)
{
	b := ref Browser;
	b.top = top;
	b.ncols = 0;
	b.colwidth = dist(top, colwidth);
	h := dist(top, height);
	b.w = w;
	cmd(b.top, "frame " + b.w);
	cmd(b.top, "canvas " + b.w + ".c -height " + string h +
		" -width " + string (maxcols * b.colwidth) +
		" -xscrollcommand {" + b.w + ".s set}");
	cmd(b.top, "frame " + b.w + ".c.f -bd 0");
	cmd(b.top, "pack propagate " + b.w + ".c.f 0");
	cmd(b.top, b.w + ".c create window 0 0 -tags win -window " + b.w + ".c.f -anchor nw -height " + string h);
	cmd(b.top, "scrollbar "+b.w+".s -command {"+b.w+".c xview} -orient horizontal");
	cmd(b.top, "pack "+b.w+".c -side top -fill both -expand 1");
	cmd(b.top, "pack "+b.w+".s -side top -fill x");
	ch := chan of string;
	tk->namechan(b.top, ch, "colch");
	return (b, ch);
}

xview(top: ref Tk->Toplevel, w: string): (real, real)
{
	s := tk->cmd(top, w + " xview");
	if (s != nil && s[0] != '!') {
		(n, v) := sys->tokenize(s, " ");
		if (n == 2)
			return (real hd v, real hd tl v);
	}
	return (0.0, 0.0);
}

setscrollregion(b: ref Browser)
{
	(w, h) := (b.colwidth * (b.ncols + 1), int cmd(b.top, b.w + ".c cget -actheight"));
	cmd(b.top, b.w+".c.f configure -width " + string w + " -height " + string h);
#	w := int cmd(b.top, b.w+".c.f cget -actwidth");
#	w += int cmd(b.top, b.w+".c cget -actwidth") - b.colwidth;
#	h := int cmd(b.top, b.w+".c.f cget -actheight");
	if (w > 0 && h > 0)
		cmd(b.top, b.w + ".c configure -scrollregion {0 0 " + string w + " " + string h + "}");
	(start, end) := xview(b.top, b.w+".c");
	if (end > 1.0)
		cmd(b.top, b.w+".c xview scroll left 0 units");
}

Browser.addcol(b: self ref Browser, title: string, d: array of string)
{
	ncol := string b.ncols++;

	f := b.w + ".c.f.d" + ncol;
	cmd(b.top, "frame " + f + " -bg green -width " + string b.colwidth);

	t := f + ".t";
	cmd(b.top, "label " + t + " -text " + tkquote(title) + " -bg black -fg white");

	sb := f + ".s";
	lb := f + ".l";
	cmd(b.top, "scrollbar " + sb +
		" -command {" + lb + " yview}");

	cmd(b.top, "listbox " + lb +
		" -selectmode browse" +
		" -yscrollcommand {" + sb + " set}" +
		" -bd 2");

	cmd(b.top, "bind " + lb + " <ButtonRelease-1> +{send colch s " + ncol + "}");
	cmd(b.top, "bind " + lb + " <Double-Button-1> +{send colch d " + ncol + "}");
	cmd(b.top, "pack propagate " + f + " 0");
	cmd(b.top, "pack " + t + " -side top -fill x");
	cmd(b.top, "pack " + sb + " -side left -fill y");
	cmd(b.top, "pack " + lb + " -side left -fill y");
	cmd(b.top, "pack " + f + " -side left -fill y");
	for (i := 0; i < len d; i++)
		cmd(b.top, lb + " insert end '" + d[i]);
	setscrollregion(b);
	seecol(b, b.ncols - 1);
}

Browser.resize(b: self ref Browser)
{
	if (b.ncols == 0)
		return;
	setscrollregion(b);
}

seecol(b: ref Browser, cno: int)
{
	w := b.w + ".c.f.d" + string cno;
	min := int cmd(b.top, w + " cget -actx");
	max := min + int cmd(b.top, w + " cget -actwidth") +
			2 * int cmd(b.top, w + " cget -bd");
	min = int cmd(b.top, b.w+".c canvasx " + string min);
	max = int cmd(b.top, b.w +".c canvasx " + string max);

	# see first the right edge; then the left edge, to ensure
	# that the start of a column is visible, even if the window
	# is narrower than one column.
	cmd(b.top, b.w + ".c see " + string max + " 0");
	cmd(b.top, b.w + ".c see " + string min + " 0");
}

Browser.delete(b: self ref Browser, colno: int)
{
	while (b.ncols > colno)
		cmd(b.top, "destroy " + b.w+".c.f.d" + string --b.ncols);
	setscrollregion(b);
}

Browser.selection(b: self ref Browser, cno: int): string
{
	if (cno >= b.ncols || cno < 0)
		return nil;
	l := b.w+".c.f.d" + string cno + ".l";
	sel := cmd(b.top, l + " curselection");
	if (sel == nil)
		return nil;
	return cmd(b.top, l + " get " + sel);
}

Browser.select(b: self ref Browser, cno: int, e: string)
{
	if (cno < 0 || cno >= b.ncols)
		return;
	l := b.w+".c.f.d" + string cno + ".l";
	cmd(b.top, l + " selection clear 0 end");
	if (e == nil)
		return;
	ents := b.entries(cno);
	for (i := 0; i < len ents; i++) {
		if (deslash(ents[i]) == e) {
			cmd(b.top, l + " selection set " + string i);
			cmd(b.top, l + " see " + string i);
			return;
		}
	}
}

Browser.entries(b: self ref Browser, cno: int): array of string
{
	if (cno < 0 || cno >= b.ncols)
		return nil;
	l := b.w+".c.f.d" + string cno + ".l";
	nent := int cmd(b.top, l + " index end") + 1;
	ents := array[nent] of string;
	for (i := 0; i < len ents; i++)
		ents[i] = cmd(b.top, l + " get " + string i);
	return ents;
}

# turn each pattern of the form "*.b (Limbo files)" into "*.b".
# ignore '*' as it's a hangover from a past age.
makepats(pats: list of string): (list of string, string)
{
	np: list of string;
	s := "";
	for (; pats != nil; pats = tl pats) {
		p := hd pats;
		for (i := 0; i < len p; i++)
			if (p[i] == ' ')
				break;
		pat := p[0:i];
		if (p != "*") {
			np = p[0:i] :: np;
			s += hd np;
			if (tl pats != nil)
				s[len s] = ' ';
		}
	}
	return (np, s);
}

widgetwidth(top: ref Tk->Toplevel, w: string): int
{
	return int cmd(top, w + " cget -width") + 2 * int cmd(top, w + " cget -bd");
}

skipslash(path: string): string
{
	for (i := 0; i < len path; i++)
		if (path[i] != '/')
			return path[i:];
	return nil;
}

nextelem(path: string): (string, string)
{
	if (path == nil)
		return (nil, nil);
	if (path[0] == '/')
		return ("/", skipslash(path));
	for (i := 0; i < len path; i++)
		if (path[i] == '/')
			break;
	return (path[0:i], skipslash(path[i:]));
}

islastelem(path: string): int
{
	for (i := 0; i < len path; i++)
		if (path[i] == '/')
			return 0;
	return 1;
}

pathcat(path, elem: string): string
{
	if (path != nil && path[len path - 1] != '/')
		path[len path] = '/';
	return path + elem;
}

# remove a possible trailing slash
deslash(s: string): string
{
	if (len s > 0 && s[len s - 1] == '/')
		s = s[0:len s - 1];
	return s;
}

kill(pid: int): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}
Showtk: con 0;

cmd(top: ref Tk->Toplevel, s: string): string
{
	if (Showtk)
		sys->print("%s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "wmlib: tk error %s on '%s'\n", e, s);
	return e;
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
