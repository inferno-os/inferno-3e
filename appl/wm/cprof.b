implement Wmcprof;

include "sys.m";
	sys: Sys;
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "draw.m";
	draw: Draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "arg.m";
	arg: Arg;
include "profile.m";

Prof: module{
	init0: fn(ctxt: ref Draw->Context, argv: list of string): Profile->Coverage;
};

prof: Prof;

Wmcprof: module{
	init: fn(ctxt: ref Draw->Context, argl: list of string);
};

usage(s: string)
{
	sys->fprint(sys->fildes(2), "wm/cprof: %s\n", s);
	sys->fprint(sys->fildes(2), "usage: wm/cprof [-er] [-m modname]... cmd [arg ... ]");
	exit;
}

TXTBEGIN: con 3;

init(ctxt: ref Draw->Context, argl: list of string)
{
	sys = load Sys Sys->PATH;
	bufio = load Bufio Bufio->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	arg = load Arg Arg->PATH;
	
	if(ctxt == nil)
		fatal("wm not running");
	sys->pctl(Sys->NEWPGRP, nil);

	arg->init(argl);
	while((o := arg->opt()) != 0){
		case(o){
			'e' or 'r' => ;
			'm' =>
				if((s := arg->arg()) == nil)
					usage("missing module/file");
			* => 
				usage(sys->sprint("unknown option -%c", o));
		}
	}

	cover := execprof(ctxt, argl);

	wmlib->init();
	(win, wmc) := wmlib->titlebar(ctxt.screen, nil, hd argl, Wmlib->Resize|Wmlib->Hide);
	tkc := chan of string;
	tk->namechan(win, tkc, "tkc");
	for(i := 0; i < len wincfg; i++)
		cmd(win, wincfg[i]);
	createmenu(win, cover);
	curc := 0;
	curm := newprint(win, cover, curc);
	
	for(;;){
		alt{
			c := <- wmc =>
				wmlib->titlectl(win, c);
				case(c){
					"move" =>
						;
					"size" =>
						;
					"task" =>
						;
					"raise" =>
						;
					"exit" =>
						;
				}
			c := <- tkc =>
				(n, toks) := sys->tokenize(c, " ");
				case(hd toks){
					"b" =>
						if(curc > 0)
							curm = newprint(win, cover, --curc);
					"f" =>
						if(curc < len cover - 1)
							curm = newprint(win, cover, ++curc);
					"s" =>
						if(curm != nil)
							scroll(win, curm);
					"m" =>
						x := cmd(win, ".f cget actx");
						y := cmd(win, ".f cget acty");
						cmd(win, ".f.menu post " + x + " " + y);
					* =>
						curc = int hd toks;
						curm = newprint(win, cover, curc);
				}
		}
	}
}

execprof(ctxt: ref Draw->Context, argl: list of string): Profile->Coverage
{
	e := ref Sys->Exception;
	if (sys->rescue("fail:*", e) == Sys->EXCEPTION){
		sys->rescued(Sys->ONCE, "");
		return nil;
	}
	prof = load Prof "/dis/cprof.dis";
	if(prof == nil)
		fatal("cannot load profiler");
	return prof->init0(ctxt, hd argl :: "-g" :: tl argl);
}

print(win: ref Tk->Toplevel, cvr: Profile->Coverage, i: int, c: chan of Profile->Coverage)
{
	cmd(win, ".f.t delete 1.0 end");
	cmd(win, "update");
	m0, m1: Profile->Coverage;
	for(m := cvr; m != nil && --i >= 0; m = tl m)
		m0 = m;
	if(m == nil){
		c <- = nil;
		return;
	}
	m1 = tl m;	
	(name, cvd, ls) := hd m;
	name0 := name1 := "nil";
	if(m0 != nil)
		(name0, nil, nil) = hd m0;
	if(m1 != nil)
		(name1, nil, nil) = hd m1;
	name += sys->sprint(" (%d%% coverage) ", cvd);
	cmd(win, ".f.t insert end {" + name + "        <- " + name0 + "        -> " + name1 + "}");
	cmd(win, ".f.t insert end \n\n");
	cmd(win, "update");
	line := TXTBEGIN;
	for(l := ls; l != nil; l = tl l){
		(rs, s) := hd l;
		cmd(win, ".f.t insert end " + wmlib->tkquote(s));
		for(r := rs; r != nil; r = tl r){
			(a, b, e) := hd r;
			if(int e)	# partly executed
				tag := "halfexec";
			else
				tag = "notexec";
			cmd(win, ".f.t tag add " + tag + " " + string line + "." + string a + " " + string line + "." + string b);
		}
		cmd(win, "update");
		line++;
	}
	c <- = m;
}

newprint(win: ref Tk->Toplevel, cvr: Profile->Coverage, i: int): Profile->Coverage
{
	c := chan of Profile->Coverage;
	spawn print(win, cvr, i, c);
	return <- c;
}

index(win: ref Tk->Toplevel, x: int, y: int): int
{
	t := cmd(win, ".f.t index @" + string x + "," + string y);
	(nil, l) := sys->tokenize(t, ".");
# sys->print("%d,%d -> %s\n", x, y, t);
	return int hd l;
}

winextent(win: ref Tk->Toplevel): (int, int)
{
	w := int cmd(win, ".f.t cget -actwidth");
	h := int cmd(win, ".f.t cget -actheight");
	lw := index(win, 0, 0);
	uw := index(win, w-1, h-1);
	return (lw, uw);
}

see(win: ref Tk->Toplevel, line: int)
{
	cmd(win, ".f.t see " + string line + ".0");
	cmd(win, "update");	
}
	
scroll(win: ref Tk->Toplevel, m: Profile->Coverage)
{
	(nil, cvd, ls) := hd m;
	(nil, uw) := winextent(win);
	line := TXTBEGIN;
	for(l := ls; l != nil; l = tl l){
		(rs, nil) := hd l;
		if(rs != nil && line > uw){
			see(win, line);
			return;
		}
		line++;
	}
	if(cvd < 100){
		line = TXTBEGIN;
		for(l = ls; l != nil; l = tl l){
			(rs, nil) := hd l;
			if(rs != nil){
				see(win, line);
				return;
			}
			line++;
		}
	}
	return;
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	# sys->print("%s\n", s);
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(sys->fildes(2), "tk error on '%s': %s\n", s, e);
	return e;
}

fatal(s: string)
{
	sys->fprint(sys->fildes(2), "%s\n", s);
	exit;
}

MENUMAX: con 20;

createmenu(top: ref Tk->Toplevel, cvr: Profile->Coverage )
{
	mn := ".f.menu";
	cmd(top, "menu " + mn);
	i := j := 0;
	for(m := cvr; m != nil; m = tl m){
		(name, nil, nil) := hd m;
		cmd(top, mn + " add command -label " + name + " -command {send tkc " + string i + "}");
		i++;
		j++;
		if(j == MENUMAX && tl m != nil){
			cmd(top, mn + " add cascade -label MORE -menu " + mn + ".menu");
			mn += ".menu";
			cmd(top, "menu " + mn);
			j = 0;
		}
	}
}

wincfg := array[] of {
	"frame .f",
	"text .f.t -width 809 -height 500 -state disabled -wrap char -bg white -yscrollcommand {.f.s set}",
	"scrollbar .f.s -orient vertical -command {.f.t yview}",
	"frame .i",
	"button .i.b -bitmap small_color_left.bit -command {send tkc b}",
	"button .i.f -bitmap small_color_right.bit -command {send tkc f}",
	"button .i.s -bitmap small_find.bit -command {send tkc s}",
	"button .i.m -bitmap small_reload.bit -command {send tkc m}",

	"pack .i.b -side left",
	"pack .i.f -side left",
	"pack .i.s -side left",
	"pack .i.m -side left",

	"pack .f.s -fill y -side left",
	"pack .f.t -fill both -expand 1",

	"pack .i -fill x",
	"pack .f -fill both -expand 1",
	"pack propagate . 0",

	".f.t tag configure notexec -fg white -bg red",
	".f.t tag configure halfexec -fg red -bg white",

	"update",
};