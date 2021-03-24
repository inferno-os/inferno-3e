#
#	Demo for Habitat.
#
implement InitShell;

include "sys.m";
include "draw.m";

sys: Sys;
FD, Connection, sprint, Dir: import sys;
print, fprint, open, bind, mount, dial, sleep, read: import sys;

stdin:	ref sys->FD;
stderr:	ref sys->FD;

InitShell: module
{
	init:	fn(nil: ref Draw->Context, nil: list of string);
};

Sh: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stderr = sys->fildes(2);

#	mountkfs("#W/flash0fs", "fs", "/n/local", sys->MREPL);

	namespace();

	sys->print("\n\nDemo for Habitat\n\n");
	config();
	netinit();

# someone's busted /dev/rcons???
#	sys->print("redirecting console to serial port at 38400 baud\n");
	spawn errsink();

	sys->print("starting cs\n");
	cs := load Sh "/dis/lib/cs.dis";
	spawn cs->init(nil, nil);

	sys->print("starting Charon\n");
	charon := load Sh "/dis/charon.dis";
	while (1)
		charon->init(nil, "charon" :: "-starturl" :: "http://www.lucent.com/" :: nil);
}

bootp: string;
ipaddr: string;
netmask: string;
ipgw: string;
dns1: string;
dns2: string;

netinit()
{
	sys->bind("#s", "/services/dns", Sys->MBEFORE );
	file := sys->file2chan("/services/dns", "db");
	if(file == nil) {
		sys->print("netinit: failed to make file: /services/dns/db: %r\n");
		return;
	}
	spawn dns(file, dns1, dns2);

	if (sys->bind("#I", "/net", sys->MREPL) < 0) {
		sys->fprint(stderr, "could not bind ip device; %r\n");
		return;
	}
	if (sys->bind("#l", "/net", sys->MAFTER) < 0) {
		sys->fprint(stderr, "could not bind ether device; %r\n");
		return;
	}

	fd := sys->open("/net/ipifc/clone", sys->OWRITE);
	if(fd == nil) {
		sys->print("init: open /net/ipifc: %r");
		return;
	}
	cfg := array of byte "bind ether ether0";
	if(sys->write(fd, cfg, len cfg) != len cfg) {
		sys->fprint(stderr, "could not bind interface: %r\n");
		return;
	}
	if (bootp == "y")
		cfg = array of byte "bootp";
	else
		cfg = array of byte sys->sprint("add %s %s", ipaddr, netmask);
	if (sys->write(fd, cfg, len cfg) != len cfg) {
		sys->print("write cfg: %r\n");
		return;
	}

	if (ipgw != nil)
		echoto("/net/iproute", sys->sprint("add 0 0 %s", ipgw));
}

dns(file: ref Sys->FileIO, dns1, dns2: string)
{
	payload := sys->sprint("%s\n%s\n", dns1, dns2);
	data := array of byte payload;
	for (;;) {
  		alt {
			(nil, nil, nil, wc) := <-file.write =>
				if (wc != nil)
					wc <-= (0, "permission denied");

			(off, nbytes, nil, rc) := <-file.read =>
				if (rc != nil) {
					if (nbytes > len data - off)
						nbytes = len data - off;
					if (nbytes < 0)
						rc <-= (nil, "stupid read request");
					else
						rc <-= (data[off:off+nbytes], nil);
				}
 		   }
	}
}

config()
{
	if (sysenv("configured") == "y" && confval(nil, "Change configuration?", "n") == "n") {
		bootp = defenv("bootp", "y");
		ipaddr = defenv("ipaddr", "0.0.0.0");
		netmask = defenv("netmask", "255.255.255.0");
		ipgw = defenv("ipgw", "0.0.0.0");
		dns1 = defenv("dns1", "0.0.0.0");
		dns2 = defenv("dns2", "0.0.0.0");
		return;
	}

	sys->print("\nQuick Configuration\n\n");

	bootp = confval("bootp", "Use bootp?", "y");
	new := ("configured", "y") :: ("bootp", bootp) :: nil;
	if (bootp != "y") {
		ipaddr = confval("ipaddr", "IP address", "0.0.0.0");
		netmask = confval("netmask", "IP subnet mask", "255.255.255.0");
		new = ("ipaddr", ipaddr) :: ("netmask", netmask) :: new;
	}
	ipgw = confval("ipgw", "IP gateway", "0.0.0.0");
	dns1 = confval("dns1", "DNS server 1", "0.0.0.0");
	dns2 = confval("dns2", "DNS server 2", "0.0.0.0");
	new = ("ipgw", ipgw) :: ("dns1", dns1) :: ("dns2", dns2) :: new;
	saveconfig(new);
}

defenv(var, def: string): string
{
	val := sysenv(var);
	if (val == nil)
		return def;
	return val;
}

saveconfig(new: list of (string, string))
{
	fd := sys->open("#W/flash0plan9.ini", sys->ORDWR);
	if (fd == nil) {
		sys->print("saveconfig: can't open #W/flash0plan9.ini for writing: %r\n");
		return;
	}
	buf := array[4096] of byte;
	n := sys->read(fd, buf, len buf);
	(nfl,fl) := sys->tokenize(string buf, "\n");
	merge, merged: list of (string, string);
	while (fl != nil) {
		pair := hd fl;
		(npl, pl) := sys->tokenize(pair, "=");
		if (npl > 1) {
			ok := 1;
			for (no := new; no != nil; no = tl no) {
				(name, nil) := hd no;
				if ((hd pl) == name) {
					ok = 0;
					break;
				}
			}
			if (ok)
				merge = (hd pl, hd tl pl) :: merge;
		}
		fl = tl fl;
	}
	while (new != nil) {
		merge = hd new :: merge;
		new = tl new;
	}
	while (merge != nil) {
		merged = hd merge :: merged;
		merge = tl merge;
	}

	s := "";
	while (merged != nil) {
		(var, val) := hd merged;
		merged = tl merged;
		s += sys->sprint("%s=%s\n", var, val);
	}
	newini := array of byte s;
	newbuf := array[4096] of { * => byte '\0' };
	newbuf[0:] = newini;
	sys->seek(fd, 0, Sys->SEEKSTART);
	if (sys->write(fd, newbuf, len newbuf) != len newbuf)
		sys->print("saveconfig: error writing #W/flash0plan9.ini: %r\n");
}

confval(var, prompt, def: string): string
{
	val := sysenv(var);
	if (val == nil)
		val = def;
	sys->print("%s [%s]: ", prompt, val);
	buf := array[80] of byte;
	n := sys->read(stdin, buf, len buf);
	if (n > 0 && buf[n-1] == byte '\n')
		n--;
	if (n <= 0)
		return val;
	buf[n] = byte '\0';
	return string buf;
}

errsink()
{
	echoto("/dev/eia0ctl", "b38400");
	errs := sys->open("/dev/rcons", Sys->OREAD);
	out := sys->open("/dev/eia0", Sys->OWRITE);
	sys->stream(errs, out, 8192);
}

namespace()
{
	# Bind anything useful we can get our hands on.  Ignore errors.
	sys->print("namespace...\n");
	sys->bind("#I", "/net", sys->MAFTER);	# IP
	sys->bind("#p", "/prog", sys->MREPL);	# prog device
	sys->bind("#d", "/dev", sys->MREPL); 	# draw device
	sys->bind("#t", "/dev", sys->MAFTER);	# serial line
	sys->bind("#c", "/dev", sys->MAFTER); 	# console device
	sys->bind("#W", "/dev", sys->MAFTER);	# Flash
	sys->bind("#O", "/dev", sys->MAFTER);	# Modem
	sys->bind("#T", "/dev", sys->MAFTER);	# Touchscreen
}

mountkfs(devname: string, fsname: string, where: string, flags: int): int
{
	sys->print("mount kfs...\n");
	fd := sys->open("#Kcons/kfsctl", sys->OWRITE);
	if (fd == nil) {
		sys->fprint(stderr, "could not open #Kcons/kfsctl: %r\n");
		return 0;
	}
	b := array of byte ("filsys " + fsname + " " + devname);
	if (sys->write(fd, b, len b) < 0) {
		sys->fprint(stderr, "could not write #Kcons/kfsctl: %r\n");
		return 0;
	}
	if (sys->bind("#K" + fsname, where, flags) < 0) {
		sys->fprint(stderr, "could not bind %s to %s: %r\n", "#K" + fsname, where);
		return 0;
	}
	return 1;
}

sysenv(param: string): string
{
	if (param == nil)
		return nil;
	fd := sys->open("#c/sysenv", sys->OREAD);
	if (fd == nil)
		return(nil);
	buf := array[4096] of byte;
	nb := sys->read(fd, buf, len buf);
	(nfl,fl) := sys->tokenize(string buf, "\n");
	while (fl != nil) {
		pair := hd fl;
		(npl, pl) := sys->tokenize(pair, "=");
		if (npl > 1) {
			if ((hd pl) == param)
				return hd tl pl;
		}
		fl = tl fl;
	}
	return nil;
}

echoto(fname, str: string): int
{
	fd := sys->open(fname, Sys->OWRITE);
	if(fd == nil) {
		sys->print("%s: %r\n", fname);
		return -1;
	}
	x := array of byte str;
	if(sys->write(fd, x, len x) == -1) {
		sys->print("write: %r\n");
		return -1;
	}
	return 0;
}

hang()
{
	c := chan of int;
	<- c;
}

#
# Set system name from nvram
#
setsysname()
{
	fd := open("/nvfs/ID", sys->OREAD);
	if(fd == nil)
		return;
	fds := open("/dev/sysname", sys->OWRITE);
	if(fds == nil)
		return;
	buf := array[128] of byte;
	nr := sys->read(fd, buf, len buf);
	if(nr <= 0)
		return;
	sys->write(fds, buf, nr);
}
