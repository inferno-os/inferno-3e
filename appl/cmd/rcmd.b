implement Rcmd;

include "sys.m";
	sys: Sys;
	stderr: ref Sys->FD;

include "draw.m";

include "keyring.m";

include "security.m";
	auth: Auth;

Rcmd: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	argv = tl argv;

	alg := "none";
	while(argv != nil) {
		s := hd argv;
		if(s[0] != '-')
			break;
		case s[1] {
		'C' =>
			alg = s[2:];
			if(alg == nil || alg == "") {
				argv = tl argv;
				if(argv != nil)
					alg = hd argv;
				else
					usage();
			}
		*   =>
			usage();
		}
		argv = tl argv;
	}

	if(argv == nil)
		usage();

	addr := hd argv;
	argv = tl argv;

	args := "";
	while(argv != nil){
		args += " " + hd argv;
		argv = tl argv;
	}
	if(args == "")
		args = "sh";

	kr := load Keyring Keyring->PATH;
	if(kr == nil){
		sys->fprint(stderr, "rcmd: can't load module Keyring %r\n");
		sys->raise("fail:bad module");
	}
	au := load Auth Auth->PATH;
	if(au == nil){
		sys->fprint(stderr, "rcmd: can't load module Login %r\n");
		sys->raise("fail:bad module");
	}


	user := user();
	kd := "/usr/" + user + "/keyring/";
	cert := kd + netmkaddr(addr, "tcp", "");
	if(!exists(cert)){
		cert = kd + "default";
		if(!exists(cert))
			sys->fprint(stderr, "Warning: no certificate found in %s; use getauthinfo\n", kd);
	}

	# To make visible remotely (withdrawn as questionable)
	#if(!exists("/dev/draw/new"))
	#	sys->bind("#d", "/dev", sys->MBEFORE);

	(ok, c) := sys->dial(netmkaddr(addr, "tcp", "rstyx"), nil);
	if(ok < 0){
		sys->fprint(stderr, "rcmd: dial server failed: %r\n");
		sys->raise("fail:bad module");
	}

	ai := kr->readauthinfo(cert);
	#
	# let auth->client handle nil ai
	# if(ai == nil){
	#	sys->fprint(stderr, "rcmd: certificate for %s not found\n", addr);
	#	sys->raise("fail:no certificate");
	# }
	#

	err := au->init();
	if(err != nil){
		sys->fprint(stderr, "rcmd: %s\n", err);
		sys->raise("fail:auth init failed");
	}

	fd: ref Sys->FD;
	(fd, err) = au->client(alg, ai, c.dfd);
	if(fd == nil){
		sys->fprint(stderr, "rcmd: authentication failed: %s\n", err);
		sys->raise("fail:auth failed");
	}

	t := array of byte sys->sprint("%d\n%s\n", len (array of byte args)+1, args);
	if(sys->write(fd, t, len t) != len t){
		sys->fprint(stderr, "rcmd: cannot write arguments: %r\n");
		sys->raise("fail:bad arg write");
	}

	if(sys->export(fd, sys->EXPWAIT) < 0) {
		sys->fprint(stderr, "rcmd: export: %r\n");
		sys->raise("fail:export failed");
	}
}

usage()
{
	sys->fprint(stderr, "Usage: rcmd [-C cryptoalg] tcp!mach cmd\n");
	sys->raise("fail:usage");
}

exists(f: string): int
{
	(ok, nil) := sys->stat(f);
	return ok >= 0;
}

user(): string
{
	sys = load Sys Sys->PATH;

	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n];	
}

netmkaddr(addr, net, svc: string): string
{
	if(net == nil)
		net = "net";
	(n, l) := sys->tokenize(addr, "!");
	if(n <= 1){
		if(svc== nil)
			return sys->sprint("%s!%s", net, addr);
		return sys->sprint("%s!%s!%s", net, addr, svc);
	}
	if(svc == nil || n > 2)
		return addr;
	return sys->sprint("%s!%s", addr, svc);
}
