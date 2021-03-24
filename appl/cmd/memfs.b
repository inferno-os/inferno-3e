implement memfs;

include "sys.m";
include "draw.m";
include "memfs.m";

memfs : module {
	init : fn(ctxt : ref Draw->Context, args : list of string);
};

usage : con "memfs [-rab] [size] mountpoint";

init(nil : ref Draw->Context, args : list of string)
{
	sys := load Sys Sys->PATH;
	maxsz := 1024 * 1024;
	amode := Sys->MREPL;

	args = tl args;
	for (; args != nil; args = tl args) {
		arg := hd args;
		if (arg == nil)
			continue;
		if (arg[0] != '-')
			break;
		if (len arg != 2) {
			sys->print("%s\n", usage);
			return;
		}
		case arg[1] {
		'r' =>
			amode = Sys->MREPL;
		'a' =>
			amode = Sys->MAFTER;
		'b' =>
			amode = Sys->MBEFORE;
		'*' =>
			sys->print("%s\n", usage);
			return;
		}
	}
	nargs := len args;
	if (nargs != 1 && nargs != 2) {
		sys->print("%s\n", usage);
		return;
	}
	if (nargs == 2)
		(maxsz, args) = (int hd args, tl args);

	mountpt := hd args;
	(ok, dir) := sys->stat(mountpt);
	if (ok == -1) {
		sys->print("stat failed: %r\n");
		return;
	}
	if (!(dir.qid.path & Sys->CHDIR)) {
		sys->print("mountpoint %s is not a directory\n", mountpt);
		return;
	}

	mfs := load MemFS MemFS->PATH;
	if (mfs == nil) {
		sys->print("cannot load MemFS: %r\n");
		return;
	}

	mfs->init();
	mfd := mfs->newfs(maxsz);
	if (mfd == nil) {
		sys->print("failed to start filesystem: %r\n");
		return;
	}
	sys->mount(mfd, mountpt, amode | Sys->MCREATE, nil);
}