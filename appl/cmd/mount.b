implement Mount;

include "sys.m";
	sys: Sys;

include "draw.m";
include "keyring.m";
include "security.m";

Mount: module
{
	init:	 fn(ctxt: ref Draw->Context, argv: list of string);
};

vflag := 0;

usage()
{
	sys->fprint(sys->fildes(2), "Usage: mount [-rabcA] [-C cryptoalg] [-f keyring] net!addr|file mountpoint [spec]\n");
	sys->raise("fail:usage");
}

fail(e, m: string)
{
	sys->fprint(sys->fildes(2), "mount: %s\n", m);
	sys->raise("fail:"+e);
}

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	
	# dump module name
	argv = tl argv;

	# process arguments
	(doauth, keyfile, flags, alg, addr, mountpoint, spec) := getargs(argv);

	# open stream
	fd := do_connect(addr);

	# authenticate if necessary
	if (doauth)
		fd = do_auth(keyfile, alg, fd, addr);

	# add to namespace
	do_mount(fd, mountpoint, flags, spec);
}

# process arguments
getargs(argv: list of string): (int, string, int, string, string, string, string)
{

	copt := 0;
	vflag = 0;
	doauth := 1;
	flags := sys->MREPL;
	alg := "none";
	# keyfile := "default";
	keyfile := string nil;
	spec: string;
	while(argv != nil) {
		s := hd argv;
		if(s[0] != '-')
			break;
	opt:    for(i := 1; i < len s; i++) {
			case s[i] {
			'a' =>
				flags = sys->MAFTER;
			'b' =>
				flags = sys->MBEFORE;
			'r' =>
				flags = sys->MREPL;
			'c' =>
				copt++;
			'C' =>
				alg = s[i+1:];
				if(alg == nil) {
					argv = tl argv;
					if(argv != nil) {
						alg = hd argv;
						if(alg[0] == '-')
							usage();
					} else
						usage();
				}
				break opt;
			'f' =>
				keyfile = s[i+1:];
				if(keyfile == nil) {
					argv = tl argv;
					if(argv != nil) {
						keyfile = hd argv;
						if(keyfile[0] == '-')
							usage();
					} else
						usage();
				}
				break opt;
			'A' =>
				doauth = 0;
			'v' =>
				vflag = 1;
			*   =>
				usage();
			}
		}
		argv = tl argv;
	}
	if(copt)
		flags |= sys->MCREATE;
	if(len argv != 2){
		if(len argv != 3)
			usage();
		spec = hd tl tl argv;
	}

	return (doauth, keyfile, flags, alg, hd argv, hd tl argv, spec);
}

# either make network connection or open file
do_connect(dest: string): ref Sys->FD
{
	(n, nil) := sys->tokenize(dest, "!");
	if(n == 1){
		fd := sys->open(dest, Sys->ORDWR);
		if(fd != nil)
			return fd;
		if(dest[0] == '/')
			fail("open failed", sys->sprint("can't open %s: %r", dest));
	}
	(ok, c) := sys->dial(netmkaddr(dest, "tcp", "styx"), nil);
	if(ok < 0)
			fail("dial failed",  sys->sprint("can't dial %s: %r", dest));
	return c.dfd;
}

# authenticate if necessary
do_auth(keyfile, alg: string, dfd: ref Sys->FD, addr: string): ref Sys->FD
{
	cert : string;

	kr := load Keyring Keyring->PATH;
	if(kr == nil)
		fail("load Keyring", sys->sprint("cannot load %s: %r", Keyring->PATH));

	kd := "/usr/" + user() + "/keyring/";
	if (keyfile == nil) {
		cert = kd + netmkaddr(addr, "tcp", "");
		(ok, nil) := sys->stat(cert);
		if (ok < 0)
			cert = kd + "default";
	}
	else if (len keyfile > 0 && keyfile[0] != '/')
		cert = kd + keyfile;
	else
		cert = keyfile;
	ai := kr->readauthinfo(cert);
	if (ai == nil)
		fail("readauthinfo failed", sys->sprint("cannot read %s: %r", cert));

	au := load Auth Auth->PATH;
	if(au == nil)
		fail("load Auth", sys->sprint("cannot load %s: %r", Auth->PATH));

	err := au->init();
	if(err != nil)
		fail("auth init failed", sys->sprint("cannot init Auth: %s", err));

	fd: ref Sys->FD;
	(fd, err) = au->client(alg, ai, dfd);
	if(fd == nil)
		fail("auth failed", sys->sprint("authorisation failed: %s", err));
	if(vflag)
		sys->print("remote username is %s\n", err);

	return fd;
}

user(): string
{
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		return "";

	buf := array[Sys->NAMELEN] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return "";

	return string buf[0:n]; 
}

# do the actual mount
do_mount(fd: ref Sys->FD, dir: string, flags: int, spec: string)
{
	# check connection with TNOP's
	c := chan of string;
	pid := chan of int;

	spawn rx(pid, fd, c);
	rx_pid := <- pid;
	spawn timer(pid, c);
	timer_pid := <- pid;
	spawn tx(pid, fd, c);
	tx_pid := <- pid;

	rc := <- c;

	kill(rx_pid);
	kill(tx_pid);
	kill(timer_pid);

	if (rc != nil)
		fail("error", "mount error: " + rc);

	# all ok so mount it
	ok := sys->mount(fd, dir, flags, spec);
	if(ok < 0)
		fail("mount failed", sys->sprint("mount failed: %r"));
}

kill(pid: int)
{
	fd := sys->open("#p/" + string pid + "/ctl", sys->OWRITE);
	if (fd == nil)
		return;

	msg := array of byte "kill";
        sys->write(fd, msg, len msg);
}

Tnop: con 0;
Rnop: con 1;

# send TNOP to chack that other end is alive
tx(pid: chan of int, fd: ref Sys->FD, c: chan of string)
{
	pid <-= sys->pctl(0, nil);

	tnop := array[] of { byte Tnop, byte 16rff, byte 16rff };
	n := sys->write(fd, tnop, len tnop);
	if (n < 0)
		c <-= "write: " + sys->sprint("%r");
}

# listen for RNOP message
rx(pid: chan of int, fd: ref Sys->FD, c: chan of string)
{
	pid <-= sys->pctl(0, nil);

	buf := array[1] of byte;
	pat := array[] of { byte Rnop, byte 16rff, byte 16rff };
	i := 0;
	for(;;) {
		# wait for RNOP
		n := sys->read(fd, buf, 1);
		if (n <= 0) {
			if (n < 0)
				c <-= "read: " + sys->sprint("%r");
			else
				c <-= "read: remote hangup";
			break;
		}
		if (buf[0] != pat[i]) {
			sys->print("Read unknown data [%x] %c\n", int buf[0], int buf[0]);
			i = 0;
			continue;
		}
		if(++i == len pat) {
			c <-= nil;
			return;
		}
	}
}

# timeout for trying TNOP/RNOP
timer(pid: chan of int, c: chan of string)
{
	pid <-= sys->pctl(0, nil);

	# sleep 10 sec.
	sys->sleep(10000);

	# send timeout
	c <-= "timed out";
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
