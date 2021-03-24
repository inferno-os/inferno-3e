implement EScroll;

include "sys.m";
	sys: Sys;
include "tk.m";
	tk: Tk;
include "draw.m";

include "wmlib.m";
	wmlib: Wmlib;

EScroll: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

config:= array[] of {
"entry .e",
"bind .e <Button-1> +{send cmd b%x}",
"bind .e <Motion-Button-1> {send cmd %x}",
"bind .e <ButtonRelease-1> +{send cmd b%x}",
"pack .e",
"pack propagate . 0",
"update",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	wmlib->init();
	
	sys->pctl(Sys->NEWPGRP, nil);
	
	(t, ctl):= wmlib->titlebar(ctxt.screen, "", "EScroll", Wmlib->Appl);
	cmd:= chan of string;
	tk->namechan(t, cmd, "cmd");
	tk->cmd(t, "update");
	
	spawn winctl(t, ctl, cmd);
	
	wmlib->tkcmds(t, config);
	
	last:= -1;
	s:= "";
	
	for(;;) {
		c:= <- cmd;
		if(c == nil)
		break;
		
		if(c[0] == 'b') {
			last = int c[1:];
			continue;
		}
		
		p:= int c;
		if(p < last)
		s = "-1u";
		else
		s = "1u";
		last = p;
		tk->cmd(t, ".e xview scroll "+s+"; update");
		
	}
}

winctl(t: ref Tk->Toplevel, ctl, cmd: chan of string)
{
	for(;;) {
		c:= <- ctl;
		if(c[0] == 'e') {
			cmd <-= nil;
			return;
		}
		wmlib->titlectl(t, c);
	}
}

