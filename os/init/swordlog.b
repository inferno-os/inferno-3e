implement Sword;

include "sys.m";
	sys:	Sys;
	stderr: ref Sys->FD;

include "draw.m";

Sword: module
{
	init:	fn();
};

Sh: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Logging		: con 0;
Hostname		: con "sword";				# devices hostname	 	
Startmodule	: con "/dis/wm/tblogon.dis";	# default initial module to load	
Startdir		: con "/usr/inferno";			# directory to start initial DIS code in

init()
{
	sys = load Sys Sys->PATH;
	namespace_init();
	writefile("/dev/sysname", Hostname, 1);
	if(int sysenv("remotedebug"))
		srv();
	shell();
}

namespace_init()
{
	sync := chan of int;
	if (Logging) {
		spawn startlogging(sync, "/dev/log");
		if (<-sync == 0 && (stderr = sys->open("/dev/log", Sys->OWRITE)) != nil) {
			sys->dup(stderr.fd, 2);
			sys->dup(stderr.fd, 1);
		}
	}
	if (stderr == nil)
		stderr = sys->fildes(2);

	ftlfs := 0;
	if (int sysenv("nofs"))
		ftlfs = 1;
	else {
		ftlctlfd := sys->open("#X/ftlctl", sys->OWRITE);
		if (ftlctlfd != nil && sys->fprint(ftlctlfd, "init #W/flash0fs") >= 0) {
			kfscmd("ctl", "filsys fs #X/ftldata flash");
			ftlfs = 1;
		}
		else
			kfscmd("ctl", "filsys fs #W/flash0fs ronly");
	}
	
	if (!failsafe()) {
		sys->print("Found a file system...");
		ebind("#Kfs", "/", sys->MBEFORE|sys->MCREATE);
	}

	ebind(	"#I",		"/net", sys->MAFTER);		# IP
#	bind(	"#J",		"/net", sys->MAFTER);		# i2c
	ebind(	"#p",		"/prog", sys->MREPL);		# prog device
	ebind(	"#d",		"/dev", sys->MBEFORE); 		# draw device
	ebind(	"#t",		"/dev", sys->MAFTER);		# serial line
	ebind("#c", "/dev", sys->MAFTER);				# console device
	sys->bind("#k", "/dev", sys->MBEFORE);			# keyboard device
	if (sys->bind("#m", "/dev", sys->MAFTER) == -1)
		if (sys->bind("#O", "/dev", sys->MAFTER) == -1)
			sys->fprint(stderr, "init: modem device not found\n");
	ebind("#T", "/dev", sys->MAFTER);				# Touchscreen

	ebind("/dis", "/dis", sys->MCREATE);
	ebind("#//dis", "/dis", sys->MAFTER);
	ebind("/dis/wm", "/dis/wm", sys->MCREATE);
	ebind("#//dis/wm", "/dis/wm", sys->MAFTER);
	ebind("/dis/lib", "/dis/lib", sys->MCREATE);
	ebind("#//dis/lib", "/dis/lib", sys->MAFTER);

	if (!ftlfs) {
		hasfs := 1;
		sys->print("init: mounting serial data flash file system\n");
		if (kfscmd("ctl", "filsys sfs #W/flash0datafs flash") == -1) {
			sys->fprint(stderr, "init: failed to mount dataflash: %r\n");
			hasfs = 0;
			sys->fprint(stderr, "init: reaming data flash filesystem\n");
			if (kfscmd("ctl", "ream sfs #W/flash0datafs") == -1) {
				sys->fprint(stderr, "init: cannot initialise data flash fs: %r");
				hasfs = 0;
			}
		}
	 	if (hasfs && kfscmd("cons", "cfs sfs") != -1)
			kfscmd("cons", "flashwrite");
	 	ebind("#Ksfs", "/data", sys->MREPL | sys->MCREATE);
	}
	# ebind("/data", "/usr/inferno", sys->MBEFORE | sys->MCREATE);
	ebind("/data", "/usr/inferno/config", sys->MREPL|sys->MCREATE);
	ebind("/data", "/usr/inferno/charon", sys->MREPL|sys->MCREATE);

	# phone stuff
	ebind("#P/tel", "/tel", sys->MREPL);
	ebind("#P/cons", "/cvt/cons", sys->MREPL);
	ebind("#P/tgen", "/cvt/tgen", sys->MREPL);
	ebind("#R", "/cvt", sys->MAFTER);

	# bind SSL directory back on /n
	ebind("#/n", "/n", sys->MAFTER);

	set_locale();

}


# [DLA] Set up locale from config file

set_locale()
{
	locale_file := "/usr/inferno/config/locale.dat";
	fd := sys->open(locale_file, sys->OREAD);
	if (fd == nil) {
		sys->fprint(stderr, "init: cannot open %s\n", locale_file);
		return;
		}
	buf := array[128] of byte;
	nr := sys->read(fd, buf, len buf);
	if(nr <= 0)
		return;
	(nil, ls) := sys->tokenize(string buf, " \t\n");
	if (ls == nil) return;
	locale := hd ls;
	ebind("/locale/dict/" + locale, "/locale/dict", sys->MBEFORE);
	
}


srv()
{
	sys->fprint(stderr, "init: exporting fs for remote debug\n");
	if(writefile("/dev/eia0ctl", "b38400", 1) == -1)
		return;

	fd := sys->open("/dev/eia0", Sys->ORDWR);
	if (fd == nil)
		sys->fprint(stderr, "init: cannot open /dev/eia0: %r\n");
	else if (sys->export(fd, Sys->EXPASYNC) < 0)
		sys->fprint(stderr, "init: cannot export /dev/eia0: %r\n");
}

startlogging(sync: chan of int, logfile: string)
{
	sys->pctl(Sys->FORKFD, nil);
	logmod := load Sh "/dis/logfile.dis";
	if (logmod == nil)
		sync <-= -1;
	else {
		if (sys->rescue("*", ref Sys->Exception) == Sys->EXCEPTION) {
			sync <-= -1;
		} else {
			logmod->init(nil, "logfile.dis" :: logfile :: nil);
			sync <-= 0;
		}
	}
}

ebind(new, old: string, flags: int)
{
	if (sys->bind(new, old, flags) < 0)
		sys->fprint(stderr, "init: bind '%s' '%s' failed: %r\n", new, old);
}

kfscmd(file, cmd: string) : int
{
	return writefile("#Kcons/kfs" + file, cmd, 1);
}

writefile(fname, cmd: string, report: int): int
{
	fd := sys->open(fname, Sys->OWRITE);
	if (fd == nil) {
		if (report)
			sys->fprint(stderr, "init: cannot open %s: %r\n", fname);
		return -1;
	}
	b := array of byte cmd;
	if (sys->write(fd, b, len b) != len b) {
		if (report)
			sys->fprint(stderr, "init: cannot write '%s' to %s: %r\n", cmd, fname);
		return -1;
	}
	return 0;
}

shell()
{
	sys->print("Starting shell...\n");
	shenv := sysenv("shell");
	if (shenv == nil)
		shenv = Startmodule;

	if (int sysenv("notouch"))
		sys->print("omitting touchscreen calibration\n");
	else {
		psh := load Sh "/dis/config/touchcal.dis";
		if (psh == nil)
			psh = load Sh "/dis/touchcal.dis";
		if (psh == nil)
			psh = load Sh "/dis/wm/sword/touchcal.dis";
		if (psh == nil) {
			sys->print("init: could not load touchcal: %r\n");
		} else {
			spawn psh->init(nil, nil);
		}
	}

	sh := load Sh shenv;
	if (sh == nil) {
		sys->fprint(stderr, "init: could not load %s: %r\n", shenv);
		sys->fprint(stderr, "init: trying shell instead...\n");
		sh = load Sh "/dis/sh.dis";
		if (sh == nil) {
			sys->fprint(stderr, "init: could not load /dis/sh.dis: %r\n");
			hang();
		}
		shenv = nil;
	}
	sys->chdir(Startdir);
	sh->init(nil, "wm" :: nil);
}

sysenv(param: string): string
{
	fd := sys->open("#c/sysenv", sys->OREAD);
	if (fd == nil)
		return nil;
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	if (n <= 0)
		return nil;
	sbuf := string buf[0:n];
	(nil, fl) := sys->tokenize(sbuf,"\n");
	while (fl != nil) {
		pair := hd fl;
		(npl,pl) := sys->tokenize(pair,"=");
		if (npl > 1) {
			if (hd pl == param)
				return hd tl pl;
		}
		fl = tl fl;
	}
	return nil;
}

hang()
{
	<- chan of int;
}

failsafe(): int
{
	fsp := sysenv("failsafe");
	if(fsp != nil && fsp != "0")
		return 1;		# previous system failure: force software download
	sys->print("Bimodal kernel in Kfs mode...\n");
	if (sys->open("#Kfs/"+Startmodule, Sys->OREAD) == nil) {
		sys->print("failed to open #Kfs/%s: %r\n", Startmodule);
		if (sys->open(Startmodule, Sys->OREAD) != nil) {
			sys->print("Incomplete file system - Using failsafe mode\n");
			# TO DO: force fail safe mode (failsafe=1 in plan9.ini)
			return 1;
		}
	}
	return 0;
}
