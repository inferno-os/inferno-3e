implement Emuinit;

include "sys.m";
include "draw.m";
include "sh.m";
# include "env.m";
sys: Sys;

USEENV: con 1;

Maxargs: con 8192;

Emuinit: module
{
	init: fn();
};

init()
{
	sys = load Sys Sys->PATH;
	args := getargs();
	if (args != nil)
		args = tl args;	# skip emu
	cmd := Command->PATH;
	for(; args != nil; args = tl args) {
		arg := hd args;
		if (arg[0] != '-') {
			if (arg != "/dis/emuinit.dis" && arg != "/appl/cmd/emuinit.dis")
				break;
		} else if (arg[1] == 'd')
			cmd = "/dis/lib/srv.dis";
	}

	if (USEENV)
		makeenv();
	if (args != nil)
		cmd = hd args;
	sh: Command;
	if (cmd[0] == '/')
		sh = load Command cmd;
	else {
		sh = load Command "/dis/"+cmd;
		if (sh == nil)
			sh = load Command "/"+cmd;
	}
	if (cmd == Command->PATH) {	# add startup option
		if (args == nil)
			args = cmd :: "-l" :: nil;
		else
			args = cmd :: "-l" :: tl args;
	}
	if (sh == nil)
		sys->fprint(sys->fildes(2), "emuinit: unable to load %s: %r\n", cmd);
	else
		sh->init(nil, args);
}

makeenv()
{
	sys->bind("#e", "/env", sys->MREPL|sys->MCREATE);
	# env := load Env Env->PATH;
	# if (env == nil)
	#	sys->fprint(sys->fildes(2), "emuinit: couldn't load env: %r\n");
	# else if ((err := env->new()) != nil)
	#	sys->fprint(sys->fildes(2), "emuinit: couldn't make new env: %s\n", err);
}

getargs(): list of string
{
	buf := array[Maxargs] of byte;
	fd := sys->open("/dev/emuargs", Sys->OREAD);
	if (fd == nil)
		return nil;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	(nil, str) := sys->tokenize(string buf[0:n-1], "\u0001");
	return str;
}
