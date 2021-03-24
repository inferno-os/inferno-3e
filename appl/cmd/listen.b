implement Listen;
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

Listen: module {
	init: fn(nil: ref Draw->Context, argv: list of string);
};

usage()
{
	sys->fprint(stderr(), "usage: listen [-i {initscript}] [-f keyfile] [-a alg]... [addr {command}]...\n");
	sys->raise("fail:usage");
}

badmodule(p: string)
{
	sys->fprint(stderr(), "listen: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

serverkey: ref Keyring->Authinfo;
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
	algs: list of string;
	arg->init(argv);
	keyfile: string;
	initscript: string;
	doauth := 1;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'a' =>
			alg := arg->arg();
			if (alg == nil)
				usage();
			algs = alg :: algs;
		'A' =>
			doauth = 0;
		'f' =>
			keyfile = arg->arg();
			if (keyfile == nil)
				usage();
			if (! (keyfile[0] == '/' || (len keyfile > 2 &&  keyfile[0:2] == "./")))
				keyfile = "/usr/" + user() + "/keyring/" + keyfile;
		'i' =>
			initscript = arg->arg();
			if (initscript == nil)
				usage();
		'v' =>
			verbose = 1;
		* =>
			usage();
		}
	}
	if (doauth && algs == nil)
		algs = getalgs();
	if (algs != nil) {
		if (keyfile == nil)
			keyfile = "/usr/" + user() + "/keyring/default";
		serverkey = keyring->readauthinfo(keyfile);
		if (serverkey == nil) {
			sys->fprint(stderr(), "listen: cannot read %s: %r\n", keyfile);
			sys->raise("fail:bad keyfile");
		}
	}

	argv = arg->argv();
	n := len argv;
	if (n % 2 != 0)
		usage();

	initcmd: ref Sh->Cmd;
	if (initscript != nil) {
		err: string;
		(initcmd, err) = sh->parse(initscript);
		if (initcmd == nil) {
			sys->fprint(stderr(), "listen: %s\n", err);
			sys->raise("fail:errors");
		}
	}

	cmds: list of (string, ref Sh->Cmd);
	for (n = 0; argv != nil; (argv, n) = (tl tl argv, n+2)) {
		(cmd, err) := sh->parse(hd tl argv);
		if (cmd == nil) {
			sys->fprint(stderr(), "listen: arg %d: %s\n", n, err);
			sys->raise("fail:errors");
		}
		cmds = (hd argv, cmd) :: cmds;
	}
	ctxt := Context.new(drawctxt);
	for (; cmds != nil; cmds = tl cmds) {
		sync := chan of int;
		spawn listen(ctxt, hd cmds, algs, initcmd, sync);
		<-sync;
	}
	if (verbose && n > 0)
		sys->fprint(stderr(), "listen: started listeners\n");
}

listen(ctxt: ref Context, a: (string, ref Sh->Cmd),
		algs: list of string, initcmd: ref Sh->Cmd, sync: chan of int)
{
	(addr, cmd) := a;

	sys->pctl(Sys->FORKFD, nil);
	ctxt = ctxt.copy(1);
	sync <-= 1;

	(ok, acon) := sys->announce(addr);
	if (ok == -1) {
		sys->fprint(stderr(), "listen: failed to announce on '%s': %r\n", addr);
		exit;
	}
	if (initcmd != nil) {
		ctxt.setlocal("net", ref Sh->Listnode(nil, acon.dir) :: nil);
		ctxt.run(ref Sh->Listnode(initcmd, nil) :: nil, 0);
		initcmd = nil;
	}
	ctxt.setlocal("user", nil);
	listench := chan of (int, Sys->Connection);
	authch := chan of (string, Sys->Connection);
	spawn listener(listench, acon, addr);
	for (;;) {
		user := "";
		ccon: Sys->Connection;
		alt {
		(ok, c) := <-listench =>
			if (ok == -1)
				exit;
			if (algs != nil) {
				spawn authenticator(authch, c, algs, addr);
				continue;
			}
			ccon = c;
		(user, ccon) = <-authch =>
			;
		}
		if (user != nil)
			ctxt.set("user", sh->stringlist2list(user :: nil));
		ctxt.set("net", ref Sh->Listnode(nil, ccon.dir) :: nil);

		# XXX could do this in a separate process too, to
		# allow new connections to arrive and start authenticating
		# while the shell command is still running.
		sys->dup(ccon.dfd.fd, 0);
		sys->dup(ccon.dfd.fd, 1);
		ccon.dfd = ccon.cfd = nil;
		ctxt.run(ref Sh->Listnode(cmd, nil) :: nil, 0);
		sys->dup(2, 0);
		sys->dup(2, 1);
	}
}

listener(listench: chan of (int, Sys->Connection), c: Sys->Connection, addr: string)
{
	for (;;) {
		(ok, nc) := sys->listen(c);
		if (ok == -1) {
			sys->fprint(stderr(), "listen: listen on '%s' failed: %r\n", addr);
			listench <-= (ok, nc);
			exit;
		}
		if (verbose)
			sys->fprint(stderr(), "listen: got connection on %s from %s",
					addr, readfile(nc.dir + "/remote"));
		nc.dfd = sys->open(nc.dir + "/data", Sys->ORDWR);
		if (nc.dfd == nil)
			sys->fprint(stderr(), "listen: cannot open %s: %r\n", nc.dir + "/data");
		else
			listench <-= (ok, nc);
	}
}

authenticator(authch: chan of (string, Sys->Connection),
		c: Sys->Connection, algs: list of string, addr: string)
{
	err: string;
	(c.dfd, err) = auth->server(algs, serverkey, c.dfd, 0);
	if (c.dfd == nil) {
		sys->fprint(stderr(), "listen: auth on %s failed: %s\n", addr, err);
		return;
	}
	if (verbose)
		sys->fprint(stderr(), "listen: authenticated on %s as %s\n", addr, err);
	authch <-= (err, c);
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

getalgs(): list of string
{
	sslctl := readfile("#D/clone");
	if (sslctl == nil)
		return nil;
	sslctl = "#D/" + sslctl;
	(nil, algs) := sys->tokenize(readfile(sslctl + "/encalgs") + " " + readfile(sslctl + "/hashalgs"), " \t\n");
	return "none" :: algs;
}
