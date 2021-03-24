implement Dial;
include "sys.m";
	sys: Sys;
include "draw.m";
include "arg.m";
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;
include "sh.m";
	sh: Sh;
	Context: import sh;

Dial: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr(), "usage: dial [-f keyfile] [-a alg] addr {command}\n");
	sys->raise("fail:usage");
}

badmodule(p: string)
{
	sys->fprint(stderr(), "dial: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

DEFAULTALG := "none";

verbose := 0;

init(drawctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmodule(Arg->PATH);
	sh = load Sh Sh->PATH;
	if (sh == nil)
		badmodule(Sh->PATH);

	auth->init();
	alg: string;
	keyfile: string;
	doauth := 1;
	arg->init(argv);
	while ((opt := arg->opt()) != 0) {
		case opt {
		'A' =>
			doauth = 1;
		'a' =>
			if ((a := arg->arg()) == nil)
				usage();
			found := 0;
			alg = a;
			for (i := 0; i < len alg; i++)
				if (alg[i] == '/')
					(alg[i], found) = (' ', found+1);
			if (found > 1) {
				sys->fprint(stderr(), "dial: invalid algorithm '%s'\n", a);
				sys->raise("fail:errors");
			}
		'f' =>
			keyfile = arg->arg();
			if (keyfile == nil)
				usage();
			if (! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		'v' =>
			verbose = 1;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	if (len argv != 2)
		usage();
	(addr, shcmd) := (hd argv, hd tl argv);

	if (doauth && alg == nil)
		alg = DEFAULTALG;

	if (alg != nil && keyfile == nil) {
		kd := "/usr/" + user() + "/keyring/";
		if (exists(kd + addr))
			keyfile = kd + addr;
		else
			keyfile = kd + "default";
	}
	cert: ref Keyring->Authinfo;
	if (alg != nil) {
		cert = keyring->readauthinfo(keyfile);
		if (cert == nil) {
			sys->fprint(stderr(), "dial: cannot read %s: %r\n", keyfile);
			sys->raise("fail:bad keyfile");
		}
	}

	(cmd, err) := sh->parse(shcmd);
	if (cmd == nil) {
		sys->fprint(stderr(), "dial: %s\n", err);
		sys->raise("fail:bad command");
	}


	(ok, c) := sys->dial(addr, nil);
	if (ok == -1) {
		sys->fprint(stderr(), "dial: cannot dial %s:: %r\n", addr);
		sys->raise("fail:errors");
	}
	user: string;
	if (alg != nil) {
		(c.dfd, err) = auth->client(alg, cert, c.dfd);
		if (c.dfd == nil) {
			sys->fprint(stderr(), "dial: authentication failed: %s\n", err);
			sys->raise("fail:errors");
		}
		user = err;
	}
	sys->dup(c.dfd.fd, 0);
	sys->dup(c.dfd.fd, 1);
	c.dfd = c.cfd = nil;
	ctxt := Context.new(drawctxt);
	if (user != nil)
		ctxt.set("user", sh->stringlist2list(user :: nil));
	else
		ctxt.set("user", nil);
	ctxt.set("net", ref Sh->Listnode(nil, c.dir) :: nil);
	ctxt.run(ref Sh->Listnode(cmd, nil) :: nil, 1);
}

exists(f: string): int
{
	(ok, nil) := sys->stat(f);
	return ok != -1;
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

user(): string
{
	u := readfile("/dev/user");
	if (u == nil)
		return "nobody";
	return u;
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}
