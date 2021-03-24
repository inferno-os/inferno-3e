implement Server;

include "sys.m";
	sys: Sys;

include "bufio.m";
	Iobuf: import Bufio;

include "draw.m";

include "newns.m";

include "arg.m";

include "sh.m";

Service: adt
{
	ptype: string;	# S for normal listened-for services, M for command spawned at start up
	port:	string;
	pid:	int;
	net:	string;
	cmd:	list of string;
};

Server: module
{
	init: fn(ctxt: ref Draw->Context, args: list of string);
};

#logfile := "/services/logs/log";
logfile: string;
nsfile := "/services/namespace";
srvfile := "/services/server/config";
chatty := 0;
stderr: ref Sys->FD;

usage()
{
	sys->fprint(stderr, "usage: lib/srv [-v] [-s] [-n nsfile] [-c configfile] [-l logfile]\n");
	sys->raise("fail:usage");
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	# bind #I, if not bound already
	if (sys->open("/net/tcp", Sys->OREAD) == nil && sys->bind("#I", "/net", Sys->MREPL) < 0) {
		sys->fprint(stderr, "srv: can't bind #I: %r\n");
		sys->raise("fail:bind #I");
	}

	spawnit := 1;
	arg := load Arg Arg->PATH;
	if(arg == nil){
		sys->fprint(stderr, "srv: can't load %s: %r\n", Arg->PATH);
		sys->raise("fail:load");
	}
	arg->init(args);
	while((c := arg->opt()) != 0)
		case c {
		'v' =>
			chatty = 1;
		's' =>
			spawnit = 0;
		'n' =>
			nsfile = arg->arg();
			if(nsfile == nil)
				usage();
		'c' =>
			srvfile = arg->arg();
			if(srvfile == nil)
				usage();
		'l' =>
			logfile = arg->arg();
			if(logfile == nil)
				usage();
		* =>
			usage();
		}
	arg = nil;

	if(spawnit == 0)
		server();
	else
		spawn server();
}

server()
{
	(ok, nil) := sys->stat(nsfile);
	if(ok >= 0) {
		ns := load Newns Newns->PATH;
		if(ns == nil)
			fatal(sys->sprint("can't load %s: %r", Newns->PATH));
		nserr := ns->newns(nil, nsfile);
		if(nserr != nil)
			fatal(sys->sprint("user namespace file %s:  %s", nsfile, nserr));
	}

	#
	# cs must be started before listen
	#
	cs := load Command "/dis/lib/cs.dis";
	if(cs == nil)
		fatal(sys->sprint("can't load /dis/lib/cs.dis: %r"));
	cs->init(nil, "cs" :: nil);

	sys->pctl(Sys->NEWPGRP|Sys->FORKFD,nil);

	#
	# open and parse service configuration file
	#

	(srvlist, err) := opensrv(srvfile);
	if (srvlist == nil)
		fatal(sys->sprint("%s", err));

	waitfile := "#p/" + string sys->pctl(0, nil) + "/wait";
	wait := sys->open(waitfile, Sys->OREAD);
	if(wait == nil)
		fatal(sys->sprint("can't open %s: %r", waitfile));

	if(logfile != nil)
		setuplog();

	#
	# start all services in the services file
	#

	pidc := chan of int;
	for(slist := srvlist; slist != nil; slist = tl slist){
		p := hd slist;
		if(p.ptype == "M")
			spawn startcmd(p, pidc);
		else
			spawn startlistener(p, pidc);
		p.pid = <-pidc;
		if(chatty || logfile != nil)
			sys->fprint(stderr, "srv: %s is pid %d\n", p.port, p.pid);
	}

	#
	# watch and wait (not that much is done with the result)
	#

	buf := array[128] of byte;
	for(;;) {
		got := sys->read(wait, buf, len buf);
		if(got < 0)
			sys->fprint(stderr, "srv: wait error: %r\n");
		else
			sys->fprint(stderr, "%d %s\n", got, string buf[0:got]);
	}
}

startcmd(sv: ref Service, pidc: chan of int)
{
	pidc <-= sys->pctl(Sys->NEWFD|Sys->NEWPGRP, list of {0, 1, 2});	# can't FORKNS because of lockm/SDS

	cmd := load Command hd sv.cmd;
	if(cmd == nil){
		sys->fprint(stderr, "srv: can't load command %s: %r\n", hd sv.cmd);
		exit;
	}
	if (sys->rescue("fail:*", ref Sys->Exception) == Sys->EXCEPTION)
		exit;

	cmd->init(nil, sv.cmd);
}

startlistener(sv: ref Service, pidc: chan of int)
{
	pidc <-= sys->pctl(Sys->FORKFD, nil);
	if(sv.net == "udp"){
		startsrvudp(sv.cmd, stderr);
	}else{
		(ok, c) := sys->announce(sv.net+"!*!"+sv.port);
		if(ok < 0){
			sys->fprint(stderr, "srv: can't announce %s: %r\n", hd sv.cmd);
			exit;
		}
		for(;;)
			gendoer(sv.cmd, c);
	}
}

gendoer(cmd: list of string, c: Sys->Connection)
{
	cmdname := hd cmd;
	(ok, nc) := sys->listen(c);
	if(ok < 0) {
		sys->fprint(stderr, "srv: can't listen (%s): %r\n", cmdname);
		return;
	}
	remote: string;
	lbuf := array[64] of byte;
	l := sys->open(nc.dir+"/remote", sys->OREAD);
	if (l != nil){
		n := sys->read(l, lbuf, len lbuf);
		if(n >= 0){
			if(n > 0 && lbuf[n-1] == byte '\n')
				n--;
			remote = string lbuf[0:n];
		}else
			sys->fprint(stderr, "srv: can't read %s for %s: %r\n", nc.dir+"/remote", cmdname);
		l = nil;
	}else
		sys->fprint(stderr, "srv: can't open %s for %s: %r\n", nc.dir+"/remote", cmdname);

	if(len remote > 0)
		sys->fprint(stderr, "New client (%s): %s %s\n", cmdname, nc.dir, remote);
	else
		sys->fprint(stderr, "New client (%s): %s unknown\n", cmdname, nc.dir);

	sync := chan of int;
	spawn startsrv(cmd, nc.dir, remote, sync);
	<- sync;
}

startsrvudp(args: list of string, fd: ref Sys->FD)
{
	cmd := load Command hd args;
	if(cmd == nil){
		sys->fprint(stderr, "srv: can't load %s: %r\n", hd args);
		exit;
	}

	sys->pctl(Sys->NEWFD|Sys->FORKNS|Sys->NEWPGRP|Sys->FORKENV, stderr.fd :: fd.fd :: nil);
	sys->dup(fd.fd, 0);
	sys->dup(fd.fd, 1);
	if(stderr.fd != 2)
		sys->dup(stderr.fd, 2);

	if (sys->rescue("fail:*", ref Sys->Exception) == Sys->EXCEPTION)
		exit;
	cmd->init(nil, args);
}

startsrv(args: list of string, dir: string, remote: string, sync: chan of int)
{
	cmd := load Command hd args;
	if(cmd == nil){
		sys->fprint(stderr, "srv: can't load %s: %r\n", hd args);
		sync <-= 0;
		exit;
	}

	sys->pctl(Sys->NEWFD|Sys->FORKNS|Sys->NEWPGRP|Sys->FORKENV, stderr.fd :: nil);
	fd := sys->open(dir+"/data", sys->ORDWR);
	sync <-= 0;
	if(fd == nil) {
		sys->fprint(stderr, "srv: can't open %s for %s: %r\n", hd args, dir);
		exit;
	}
	#sys->bind(dir+"/data", "/dev/cons");
	sys->dup(fd.fd, 0);
	sys->dup(fd.fd, 1);
	if(stderr.fd != 2)
		sys->dup(stderr.fd, 2);

	if (sys->rescue("fail:*", ref Sys->Exception) == Sys->EXCEPTION)
		exit;
	if (hd args == "/dis/lib/logind.dis")
		cmd->init(nil, hd args :: remote :: tl args);
	else
		cmd->init(nil, args);
}

opensrv(srvfile: string) : (list of ref Service, string)
{
	bufio := load Bufio Bufio->PATH;

	if ((srvbuf := bufio->open(srvfile, Bufio->OREAD)) == nil)
		return (nil, sys->sprint("can't open %s: %r", srvfile));

	srvlist: list of ref Service;
	line := 0;
	while((srvstr := bufio->srvbuf.gets('\n')) != nil){
		if(srvstr[0] == '#'){   # comment
			line++;
			continue;
		}
		(n, slist) := sys->tokenize(srvstr, " \t\r\n");
		if (n == 0){    # blank line
			line++;
			continue;
		}

		if(n < 4){
			line++;
			return (nil, sys->sprint("config file %s:%d: record with %d fields", 
				srvfile, line, n));
		}

		if((s := hd slist)[0] >= '0' && s[0] <= '9')
			slist = tl slist;	# skip unused `restart' count
		# [MS] service protocol command ...
		srvlist = ref Service(hd slist, hd tl slist, -1, hd tl tl slist, tl tl tl slist) :: srvlist;
		line++;
	}
	return (srvlist, nil);
}

setuplog()
{
	fd: ref Sys->FD;
	(ok, nil) := sys->stat(logfile);
	if (ok < 0) {
		fd = sys->create(logfile, sys->ORDWR, 8r640);
		if (fd == nil)
			fatal(sys->sprint("srv: can't create %s: %r\n", logfile));
	} else {
		fd = sys->open(logfile, sys->ORDWR);
		if (fd == nil)
			fatal(sys->sprint("srv: can't open %s: %r\n", logfile));
	}
	sys->seek(fd, 0, Sys->SEEKEND);	# BUG: not good enough
	stderr = fd;
}

fatal(s: string)
{
	sys->fprint(stderr, "srv: %s\n", s);
	sys->raise("fail:error");
}
