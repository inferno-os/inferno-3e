implement WmAbout;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image: import draw;

include "tk.m";
	tk: Tk;

include	"wmlib.m";
	wmlib: Wmlib;

WmAbout: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

tkcfg(version: string): array of string
{
	return  array[] of {
	"frame .f -bg black -borderwidth 2 -relief ridge",
	"label .b -bg black -bitmap @/icons/inferno.bit",
	"label .l1 -bg black -fg #ff5500  -text {Inferno "+ version + "}",
	"pack .b .l1 -in .f",
	"pack .f -ipadx 4 -ipady 2",
	"pack propagate . 0",
	"update",
	};
}

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	wmlib= load Wmlib Wmlib->PATH;

	wmlib->init();
	(t, menubut) := wmlib->titlebar(ctxt.screen, "", "About Inferno", 0);

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");
	wmlib->tkcmds(t, tkcfg(rf("/dev/sysctl")));

	for(;;) alt {
	menu := <-menubut =>
		if(menu == "exit")
			return;
		wmlib->titlectl(t, menu);
	}
}

rf(name: string): string
{
	fd := sys->open(name, Sys->OREAD);
	if(fd == nil)
		return nil;
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		n = 0;
	return string buf[0:n];
}
