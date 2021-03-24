#
# ipaq
#

implement Init;

include "sys.m";
	sys:	Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;

include "security.m";
	auth: Auth;

include "keyboard.m";

Init: module
{
	init:	fn();
};

Sh: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

SHELL: con "/dis/sh.dis";

Bootpreadlen: con 128;

usertc := 0;
ethername := "ether0";

#
# initialise flash translation
# mount flash file system
# add devices
# start a shell or window manager
#

init()
{
	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if(auth != nil)
		auth->init();

	lightup();

	localok := 0;
	if(lfs() >= 0){
		# let's just take a closer look
		sys->bind("/n/local/nvfs", "/nvfs", Sys->MREPL|Sys->MCREATE);
		(rc, nil) := sys->stat("/n/local/dis/sh.dis");
		if(rc >= 0)
			localok = 1;
		else
			err("local file system unusable");
	}
	netok := sys->bind("#l", "/net", Sys->MREPL) >= 0;
	if(!netok){
		netok = sys->bind("#l1", "/net", Sys->MREPL) >= 0;
		if(netok)
			ethername = "ether1";
	}
	if(netok)
		configether();
	dobind("#I", "/net", sys->MAFTER);	# IP
	dobind("#p", "/prog", sys->MREPL);	# prog device
	dobind("#d", "/dev", sys->MREPL); 	# draw device
	dobind("#t", "/dev", sys->MAFTER);	# serial line
#	dobind("#J", "/dev", sys->MAFTER);	# i2c
	dobind("#c", "/dev", sys->MAFTER); 	# console device
	sys->bind("#e", "/env", sys->MREPL|sys->MCREATE);	# optional environment device
	sys->bind("#A", "/dev", Sys->MAFTER);	# optional audio device
	dobind("#T","/dev",sys->MAFTER);	# touch screen and other ipaq devices
	timefile: string;
	rootsource: string;
	cfd := sys->open("/dev/consctl", Sys->OWRITE);
	if(cfd != nil)
		sys->fprint(cfd, "rawon");
	for(;;){
		(rootsource, timefile) = askrootsource(localok, netok);
		if(rootsource == nil)
			break;	# internal
		(rc, nil) := sys->stat(rootsource+"/dis/sh.dis");
		if(rc < 0)
			err("%s has no shell");
		else if(sys->bind(rootsource, "/", Sys->MAFTER) < 0)
			sys->print("can't bind %s on /: %r\n", rootsource);
		else{
			sys->bind(rootsource+"/dis", "/dis", Sys->MBEFORE|Sys->MCREATE);
			break;
		}
	}
	cfd = nil;

	setsysname("ipaq");			# set system name

	setclock(timefile, rootsource);

	sys->chdir("/");
	if(netok){
		(ok, nil) := sys->stat("/dis/lib/cs.dis");
		if(ok >= 0){
			cs := load Sh "/dis/lib/cs.dis";
			if(cs == nil)
				sys->print("ipaqinit: can't load cs: %r\n");
			else
				spawn cs->init(nil, "cs" :: nil);
		}
	}
	calibrate();
	user := username("inferno");
	(ok, nil) := sys->stat("/dis/wm/logon.dis");
	if(ok >= 0 && userok(user)){
		wm := load Sh "/dis/wm/logon.dis";
		if(wm != nil){
			fd := sys->open("/nvfs/user", Sys->OWRITE);
			if(fd != nil){
				sys->fprint(fd, "%s", user);
				fd = nil;
			}
			spawn wm->init(ref Draw->Context, "wm/logon" :: "-u" :: user :: nil);
			exit;
		}
		sys->print("ipaqinit: can't load wm/logon: %r");
	}
	sh := load Sh SHELL;
	if(sh == nil){
		err(sys->sprint("can't load %s: %r", SHELL));
		hang();
	}
	spawn sh->init(nil, "sh" :: nil);
}

dobind(f, t: string, flags: int)
{
	if(sys->bind(f, t, flags) < 0)
		err(sys->sprint("can't bind %s on %s: %r", f, t));
}

lightup()
{
	# backlight
	fd := sys->open("#T/ipaqctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "light 1 1 0x80");
}

#
# Set system name from nvram if possible
#
setsysname(def: string)
{
	v := array of byte def;
	fd := sys->open("/nvfs/ID", sys->OREAD);
	if(fd != nil){
		buf := array[128] of byte;
		nr := sys->read(fd, buf, len buf);
		while(nr > 0 && buf[nr-1] == byte '\n')
			nr--;
		if(nr > 0)
			v = buf[0:nr];
	}
	fd = sys->open("/dev/sysname", sys->OWRITE);
	if(fd != nil)
		sys->write(fd, v, len v);
}

setclock(timefile: string, timedir: string)
{
	now := big 0;
	if(timefile != nil){
		fd := sys->open(timefile, Sys->OREAD);
		if(fd != nil){
			b := array[64] of byte;
			n := sys->read(fd, b, len b-1);
			if(n > 0){
				now = big string b[0:n];
				if(now <= big 16r20000000)
					now = big 0;	# remote itself is not initialised
			}
		}
	}
	if(now == big 0){
		if(timedir != nil){
			(ok, dir) := sys->stat(timedir);
			if (ok < 0) {
				sys->print("init: stat %s: %r", timedir);
				return;
			}
			now = big dir.atime * big 1000000;
		}else{
			now = big 993826747000000;
			sys->print("time warped\n");
		}
	}
	fd := sys->open("/dev/time", sys->OWRITE);
	if (fd == nil) {
		sys->print("init: can't open /dev/time: %r");
		return;
	}

	b := sys->aprint("%ubd", now);
	if (sys->write(fd, b, len b) != len b)
		sys->print("init: can't write to /dev/time: %r");
}

srv()
{
	sys->print("remote debug srv...");
	fd := sys->open("/dev/eia0ctl", Sys->OWRITE);
	if(fd != nil)
		sys->fprint(fd, "b115200");

	fd = sys->open("/dev/eia0", Sys->ORDWR);
	if (fd == nil){
		err(sys->sprint("can't open /dev/eia0: %r"));
		return;
	}
	if (sys->export(fd, Sys->EXPASYNC) < 0){
		err(sys->sprint("can't export on serial port: %r"));
		return;
	}
}

err(s: string)
{
	sys->fprint(sys->fildes(2), "ipaqinit: %s\n", s);
}

hang()
{
	<-(chan of int);
}

askrootsource(localok: int, netok: int): (string, string)
{
	stdin := sys->fildes(0);
	sources := "kernel" :: nil;
	if(netok)
		sources = "remote" :: sources;
	if(localok){
		sources = "local" :: sources;
		if(netok)
			sources = "local+remote" :: sources;
	}
Query:
	for(;;) {
		sys->print("root from (");
		cm := "";
		for(l := sources; l != nil; l = tl l){
			sys->print("%s%s", cm, hd l);
			cm = ",";
		}
		sys->print(")[%s] ", hd sources);

		s := getline(stdin, hd sources);	# default
		case s[0] {
		Keyboard->Right or Keyboard->Left =>
			sources = append(hd sources, tl sources);
			sys->print("\n");
			continue Query;
		Keyboard->Down =>
			s = hd sources;
			sys->print(" %s\n", s);
		}
		(nil, choice) := sys->tokenize(s, "\t ");
		if(choice == nil)
			choice = sources;
		opt := hd choice;
		case opt {
		* =>
			sys->print("\ninvalid boot option: '%s'\n", opt);
		"kernel" =>
			return (nil, nil);
		"local" =>
			return ("/n/local", nil);
		"local+remote" =>
			if(netfs("/n/remote") >= 0)
				return ("/n/local", "/n/remote/dev/time");
		"remote" =>
			if(netfs("/n/remote") >= 0)
				return ("/n/remote", "/n/remote/dev/time");
		}
	}
}

getline(fd: ref Sys->FD, default: string): string
{
	result := "";
	buf := array[10] of byte;
	i := 0;
	for(;;) {
		n := sys->read(fd, buf[i:], len buf - i);
		if(n < 1)
			break;
		i += n;
		while(i >0 && (nutf := sys->utfbytes(buf, i)) > 0){
			s := string buf[0:nutf];
			for (j := 0; j < len s; j++)
				case s[j] {
				'\b' =>
					if(result != nil)
						result = result[0:len result-1];
				'u'&16r1F =>
					sys->print("^U\n");
					result = "";
				'\r' =>
					;
				* =>
					sys->print("%c", s[j]);
					if(s[j] == '\n' || s[j] >= 16r80){
						if(s[j] != '\n')
							result[len result] = s[j];
						if(result == nil)
							return default;
						return result;
					}
					result[len result] = s[j];
				}
			buf[0:] = buf[nutf:i];
			i -= nutf;
		}
	}
	return default;
}

append(v: string, l: list of string): list of string
{
	if(l == nil)
		return v :: nil;
	return hd l :: append(v, tl l);
}

#
# serve local DOS file system using flash translation layer
#
lfs(): int
{
	if(!flashinit("#F/flash", 16r140000, 16rE00000))
		return -1;
	dos := load Sh "/dis/svc/dossrv/dossrv.dis";
	if(dos == nil){
		sys->print("can't load dossrv: %r\n");
		return -1;
	}
	dos->init(nil, "dossrv" :: "-f" :: "#X/ftldata" :: "-m" :: "/n/local" :: nil);
	return 0;
}

#
# set up flash translation layer
#
flashdone := 0;

flashinit(flashmem: string, offset: int, length: int): int
{
	if(flashdone)
		return 1;
	sys->print("Set flash translation of %s at offset %d (%d bytes)\n", flashmem, offset, length);
	fd := sys->open("#X/ftlctl", Sys->OWRITE);
	if(fd == nil){
		sys->print("can't open #X/ftlctl: %r\n");
		return 0;
	}
	if(sys->fprint(fd, "init %s %ud %ud", flashmem, offset, length) <= 0){
		sys->print("can't init flash translation: %r");
		return 0;
	}
	flashdone = 1;
	return 1;
}

configether()
{
	if(ethername == nil)
		return;
	fd := sys->open("/nvfs/etherparams", Sys->OREAD);
	if(fd == nil)
		return;
	ctl := sys->open("/net/"+ethername+"/clone", Sys->OWRITE);
	if(ctl == nil){
		sys->print("init: can't open %s's clone: %r\n", ethername);
		return;
	}
	b := array[1024] of byte;
	n := sys->read(fd, b, len b);
	if(n <= 0)
		return;
	for(i := 0; i < n;){
		for(e := i; e < n && b[e] != byte '\n'; e++)
			;
		s := string b[i:e];
		if(sys->fprint(ctl, "%s", s) < 0)
			sys->print("init: ctl write to %s: %s: %r\n", ethername, s);
		i = e+1;
	}
}

donebind := 0;

#
# set up network mount
#
netfs(mountpt: string): int
{
	sys->print("bootp ...");

	fd: ref Sys->FD;
	if(!donebind){
		fd = sys->open("/net/ipifc/clone", sys->OWRITE);
		if(fd == nil) {
			sys->print("init: open /net/ipifc/clone: %r\n");
			return -1;
		}
		if(sys->fprint(fd, "bind ether %s", ethername) < 0) {
			sys->print("could not bind ether0 interface: %r\n");
			return -1;
		}
		donebind = 1;
	}else{
		fd = sys->open("/net/ipifc/0/ctl", Sys->OWRITE);
		if(fd == nil){
			sys->print("init: can't reopen /net/ipifc/0/ctl: %r\n");
			return -1;
		}
	}
	if(sys->fprint(fd, "bootp") < 0) {
		sys->print("could not bootp: %r\n");
		return -1;
	}

	server := bootp();
	if(server == nil || server == "0.0.0.0")
		return -1;

	net := "tcp";	# how to specify il?
	svcname := net + "!" + server + "!6666";

	sys->print("dial %s...", svcname);

	(ok, c) := sys->dial(svcname, nil);
	if(ok < 0){
		sys->print("can't dial %s: %r\n", svcname);
		return -1;
	}

	sys->print("\nConnected ...\n");
	if(kr != nil){
		err: string;
		sys->print("Authenticate ...");
		ai := kr->readauthinfo("/nvfs/default");
		if(ai == nil){
			sys->print("readauthinfo /nvfs/default failed: %r\n");
			sys->print("trying mount as `nobody'\n");
		}
		(c.dfd, err) = auth->client("none", ai, c.dfd);
		if(c.dfd == nil){
			sys->print("authentication failed: %s\n", err);
			return -1;
		}
	}

	sys->print("mount %s...", mountpt);

	c.cfd = nil;
	n := sys->mount(c.dfd, mountpt, sys->MREPL, "");
	if(n > 0)
		return 0;
	if(n < 0)
		sys->print("%r");
	return -1;
}

bootp(): string
{
	fd := sys->open("/net/bootp", sys->OREAD);
	if(fd == nil) {
		sys->print("init: can't open /net/bootp: %r");
		return nil;
	}

	buf := array[Bootpreadlen] of byte;
	nr := sys->read(fd, buf, len buf);
	fd = nil;
	if(nr <= 0) {
		sys->print("init: read /net/bootp: %r");
		return nil;
	}

	(ntok, ls) := sys->tokenize(string buf, " \t\n");
	while(ls != nil) {
		if(hd ls == "fsip"){
			ls = tl ls;
			break;
		}
		ls = tl ls;
	}
	if(ls == nil) {
		sys->print("init: server address not in bootp read");
		return nil;
	}

	srv := hd ls;

	sys->print("%s\n", srv);

	return srv;
}

calibrate()
{
	val := rf("/nvfs/calibrate", nil);
	if(val != nil){
		fd := sys->open("/dev/touchctl", Sys->OWRITE);
		if(fd != nil && sys->fprint(fd, "%s", val) >= 0)
			return;
	}
	done := chan of int;
	spawn docal(done);
	<-done;
}

docal(done: chan of int)
{
	sys->pctl(Sys->FORKFD, nil);
	ofd := sys->create("/nvfs/calibrate", Sys->OWRITE, 8r644);
	if(ofd != nil)
		sys->dup(ofd.fd, 1);
	cal := load Sh "/dis/touchcal.dis";
	if(cal != nil){
		e := ref Sys->Exception;
		if(sys->rescue("fail:*", e) != Sys->EXCEPTION)
			cal->init(nil, "touchcal" :: nil);
	}
	done <-= 1;
}
	
username(def: string): string
{
	return rf("/nvfs/user", def);
}

userok(user: string): int
{
	(ok, d) := sys->stat("/usr/"+user);
	return ok >= 0 && (d.mode & Sys->CHDIR) != 0;
}

rf(file: string, default: string): string
{
	fd := sys->open(file, Sys->OREAD);
	if(fd != nil){
		buf := array[128] of byte;
		nr := sys->read(fd, buf, len buf);
		if(nr > 0)
			return string buf[0:nr];
	}
	return default;
}
