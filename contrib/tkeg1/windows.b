implement Windows;

include "sys.m";
	sys: Sys;
include "draw.m";
include "tk.m";
	tk: Tk;

Windows: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	
	t:= tk->intop(ctxt.screen, -1, -1);
	
	wins:= tk->windows(ctxt.screen);
	if(t == nil)
		sys->print("nil t\n");
	else
		wins = t::wins;
	
	while(wins != nil) {
		w:= hd wins;
		wins = tl wins;
		if(w.image == nil)
			sys->print("%d: nil image\n", w.id);
		else
			sys->print("%d: (%d %d), (%d %d)\n",
				w.id,
				w.image.r.min.x, w.image.r.min.y,
				w.image.r.max.x, w.image.r.max.y);
	}
}

