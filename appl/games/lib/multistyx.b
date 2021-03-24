implement Multistyx;
include "sys.m";
	sys: Sys;
include "styxlib.m";
	styxlib: Styxlib;
	Styxserver, Tmsg: import styxlib;
include "keyring.m";
	keyring: Keyring;
include "security.m";
	auth: Auth;
include "multistyx.m";

badmodule(p: string)
{
	sys->fprint(stderr(), "multistyx: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

Verbose: con 1;
MAXCONN: con 10;

init(): Styxlib
{
	sys = load Sys Sys->PATH;
	styxlib = load Styxlib Styxlib->PATH;
	if (styxlib == nil)
		badmodule(Styxlib->PATH);
	auth = load Auth Auth->PATH;
	if (auth == nil)
		badmodule(Auth->PATH);
	if ((e := auth->init()) != nil) {
		sys->fprint(stderr(), "multistyx: cannot init auth module: %s\n", e);
		sys->raise("fail:auth init failed");
	}
	keyring = load Keyring Keyring->PATH;
	if (keyring == nil)
		badmodule(Keyring->PATH);
	return styxlib;
}

srv(addr: string, doauth: int, algs: list of string):
	(chan of (int, ref Styxserver, string), chan of (int, ref Styxserver, ref Tmsg), string)
{
	if (addr == nil)
		doauth = 0;		# no authentication necessary for local mount
	authinfo: ref Keyring->Authinfo;
	if (doauth) {
		authinfo = keyring->readauthinfo("/usr/" + user() + "/keyring/default");
		if (authinfo == nil)
			return (nil, nil, sys->sprint("cannot read certificate: %r"));
	}

	newsrvch := chan of (int, ref Styxserver, string);
	tmsgch := chan of (int, ref Styxserver, ref Tmsg);
	if (doauth && algs == nil)
		algs = "none" :: nil;		# XXX is this default a bad idea?
	srvrq := chan of (ref Sys->FD, string);
	srvsync := chan of (int, string);
	spawn listener(addr, authinfo, srvrq, srvsync, algs);
	(srvpid, err) := <-srvsync;
	srvsync = nil;
	if (srvpid == -1)
		return (nil, nil, sys->sprint("failed to start listener: %s", err));
	sync := chan of int;
	spawn srvproc(srvrq, sync, newsrvch, tmsgch);
	<-sync;
	return (newsrvch, tmsgch, nil);
}

# buffer one message to avoid the deadlock on a local
# mount as we try to mount the connection synchronously
# while srvproc tries to inform the called about the
# new connection.
buf1(in, out: chan of (int, ref Styxserver, string))
{
	out <-= <-in;
}

# srvrq gets incoming connections; the tuple is (datafd, username).
srvproc(srvrq: chan of (ref Sys->FD, string), sync: chan of int,
		newsrvch: chan of (int, ref Styxserver, string),
		tmsgch: chan of (int, ref Styxserver, ref Tmsg))
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	down := 0;
	nclient := 0;
	tchans := array[MAXCONN] of chan of ref Tmsg;
	srv := array[MAXCONN] of ref Styxserver;
loop:  for (;;) alt {
	(fd, name) := <-srvrq =>
		if (fd == nil) {
			if (Verbose && name != nil)
				sys->fprint(stderr(), "multistyx: listener going down: %s\n", name);
			down = 1;
		} else {
			if (Verbose)
				sys->fprint(stderr(), "multistyx: got new connection, username: %s\n", name);
			for (i := 0; i < len tchans; i++)
				if (tchans[i] == nil)
					break;
			if (i == len tchans) {
				tchans = (array[len tchans +10] of chan of ref Tmsg)[0:] = tchans;
				srv = (array[len srv +10] of ref Styxserver)[0:] = srv;
			}
			(tchans[i], srv[i]) = Styxserver.new(fd);	
			newsrvch <-= (i, srv[i], name);
			nclient++;
		}
	(n, gm) := <-tchans =>
		tmsgch <-= (n, srv[n], gm);
		if (gm == nil || tagof(gm) == tagof(Tmsg.Readerror)) {
			tchans[n] = nil;
			srv[n] = nil;
			if (nclient-- <= 1 && down)
				break loop;
		}
	}
	if (Verbose)
		sys->fprint(stderr(), "multistyx: finished\n");
}

# addr should be, e.g. tcp!*!2345
listener(addr: string, authinfo: ref Keyring->Authinfo, ch: chan of (ref Sys->FD, string),
		sync: chan of (int, string), algs: list of string)
{
	(n, c) := sys->announce(addr);
	if (n == -1) {
		sync <-= (-1, sys->sprint("cannot anounce on %s: %r", addr));
		return;
	}
	sync <-= (sys->pctl(0, nil), nil);
	for (;;) {
		(n, nc) := sys->listen(c);
		if (n == -1) {
			ch <-= (nil, sys->sprint("listen failed: %r"));
			return;
		}
		if (Verbose)
			sys->fprint(stderr(), "multistyx: got connection from %s\n",
					readfile(nc.dir + "/remote"));
		dfd := sys->open(nc.dir + "/data", Sys->ORDWR);
		if (dfd != nil) {
			if (algs == nil)
				ch <-= (dfd, nil);
			else
				spawn authenticator(dfd, authinfo, ch, algs);
		}
	}
}

# authenticate a connection; we don't bother setting the user id.
authenticator(dfd: ref Sys->FD, authinfo: ref Keyring->Authinfo,
		ch: chan of (ref Sys->FD, string), algs: list of string)
{
	(fd, err) := auth->server(algs, authinfo, dfd, 0);
	if (fd == nil) {
		if (Verbose)
			sys->fprint(stderr(), "multistyx: authentication failed: %s\n", err);
		return;
	}
	if (Verbose)
		sys->fprint(stderr(), "multistyx: authenticated as %s\n", err);
	ch <-= (fd, err);
}

stderr(): ref Sys->FD
{
	return sys->fildes(2);
}

user(): string
{
	if ((s := readfile("/dev/user")) == nil)
		return "nobody";
	return s;
}

readfile(f: string): string
{
	fd := sys->open(f, sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		return nil;

	return string buf[0:n];	
}
