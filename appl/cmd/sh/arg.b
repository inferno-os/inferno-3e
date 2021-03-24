implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;
	myself = load Shellbuiltin "$self";
	if (myself == nil)
		ctxt.fail("bad module", sys->sprint("arg: cannot load self: %r"));
	ctxt.addbuiltin("arg", myself);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runbuiltin(ctxt: ref Context, nil: Sh,
			argv: list of ref Listnode, last: int): string
{
	case (hd argv).word {
	"arg" =>
		return builtin_arg(ctxt, argv, last);
	}
	return nil;
}

runsbuiltin(nil: ref Sh->Context, nil: Sh,
			nil: list of ref Listnode): list of ref Listnode
{
	return nil;
}

argusage(ctxt: ref Context)
{
	ctxt.fail("usage", "usage: arg [opts {command}]... - args");
}

builtin_arg(ctxt: ref Context, argv: list of ref Listnode, nil: int): string
{
	for (args := tl argv; args != nil; args = tl tl args) {
		if ((hd args).word == "-")
			break;
		if ((hd args).cmd != nil && (hd args).word == nil)
			argusage(ctxt);
		if (tl args == nil)
			argusage(ctxt);
		if ((hd tl args).cmd == nil)
			argusage(ctxt);
	}
	if (args == nil)
		args = ctxt.get("*");
	else
		args = tl args;
	laststatus := "";
	ctxt.push();
	e := ref Sys->Exception;
	if (sys->rescue("fail:*", e) == Sys->EXCEPTION) {
		sys->rescued(Sys->ONCE, nil);
		ctxt.pop();
		if (e.name[5:] == "break")
			return laststatus;
		sys->raise(e.name);
	}
	arg := Arg.init(args);
	while ((opt := arg.opt()) != 0) {
		for (argt := tl argv; argt != nil && (hd argt).word != "-"; argt = tl tl argt) {
			w := (hd argt).word;
			if (w == nil)
				continue;
			needarg := 0;
			if (w[len w - 1] == '+') {
				needarg = 1;
				w = w[0:len w - 1];
			}
			for (i := 0; i < len w; i++)
				if (w[i] == opt || w[i] == '*')
					break;
			if (i < len w) {
				optstr := ""; optstr[0] = opt;
				ctxt.setlocal("opt", ref Listnode(nil, optstr) :: nil);
				if (needarg)
					ctxt.setlocal("arg", arg.arg());
				else
					ctxt.setlocal("arg", nil);
				laststatus = ctxt.run(hd tl argt :: nil, 0);
				break;
			}
		}
		if (argt == nil || (hd argt).word == "-")
			ctxt.fail("usage", sys->sprint("unknown option -%c", opt));
	}
	ctxt.pop();
	ctxt.set("args", arg.args);		# XXX backward compatibility - should go
	ctxt.set("*", arg.args);
	return laststatus;
}


Arg: adt {
	args: list of ref Listnode;
	curropt: string;
	init: fn(argv: list of ref Listnode): ref Arg;
	arg: fn(ctxt: self ref Arg): list of ref Listnode;
	opt: fn(ctxt: self ref Arg): int;
};
	

Arg.init(argv: list of ref Listnode): ref Arg
{
	return ref Arg(argv, nil);
}

# get next option argument (nil list if no argument found)
Arg.arg(ctxt: self ref Arg): list of ref Listnode
{
	if (ctxt.curropt != "") {
		ret := ctxt.curropt;
		ctxt.curropt = nil;
		return ref Listnode(nil, ret) :: nil;
	}

	if (ctxt.args == nil)
		return nil;

	ret := hd ctxt.args :: nil;
	ctxt.args = tl ctxt.args;
	return ret;
}

# get next option letter
# return 0 at end of options
Arg.opt(ctxt: self ref Arg): int
{
	if (ctxt.curropt != "") {
		opt := ctxt.curropt[0];
		ctxt.curropt = ctxt.curropt[1:];
		return opt;
	}

	if (ctxt.args == nil)
		return 0;

	nextarg := (hd ctxt.args).word;
	if (len nextarg < 2 || nextarg[0] != '-')
		return 0;

	if (nextarg == "--") {
		ctxt.args = tl ctxt.args;
		return 0;
	}

	opt := nextarg[1];
	if (len nextarg > 2)
		ctxt.curropt = nextarg[2:];
	ctxt.args = tl ctxt.args;
	return opt;
}
