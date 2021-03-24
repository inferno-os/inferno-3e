implement Rstyxd;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
include "security.m";

include "sh.m";

include "string.m";
	str: String;

stderr: ref Sys->FD;

Rstyxd: module
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

#
# argv is a list of Inferno supported algorithms from Security->Auth
#
init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdin := sys->fildes(0);
	stderr = sys->open("/dev/cons", Sys->OWRITE);

	if(argv != nil)
		argv = tl argv;
	if(argv == nil)
		err("no algorithm list");

	auth := load Auth Auth->PATH;
	if(auth == nil)
		err(sys->sprint("can't load %s: %r", Auth->PATH));

	str = load String String->PATH;
	if (str == nil)
		err(sys->sprint("can't load %s: %r", String->PATH));

	error := auth->init();
	if(error != nil)
		err(sys->sprint("Auth init failed: %s", error));

	user := getuser();
	kr := load Keyring Keyring->PATH;
	ai := kr->readauthinfo("/usr/"+user+"/keyring/default");

	(fd, info_or_err) := auth->server(argv, ai, stdin, 1);
	if(fd == nil)
		err(sys->sprint("server auth failed: %s", info_or_err));

	dorstyx(fd);
}

dorstyx(fd: ref Sys->FD)
{
	sys->pctl(sys->FORKFD, fd.fd :: nil);

	args := readargs(fd);
	if(args == nil)
		err(sys->sprint("error reading arguments: %r"));

	cmd := hd args;
	s := "";
	for (a := args; a != nil; a = tl a)
		s += hd a + " ";
	sys->fprint(stderr, "rstyxd: cmd: %s\n", s);
	s = nil;
	file: string;
	if(cmd == "sh")
		file = "/dis/sh.dis";
	else
		file = cmd + ".dis";
	mod := load Command file;
	if(mod == nil){
		mod = load Command "/dis/"+file;
		if(mod == nil)
			err(sys->sprint("can't load %s: %r", cmd));
	}

	sys->pctl(Sys->FORKNS|Sys->FORKENV, nil);

	if(sys->mount(fd, "/n/client", Sys->MREPL, "") < 0)
		err(sys->sprint("cannot mount connection on /n/client: %r"));

	if(sys->bind("/n/client/dev", "/dev", Sys->MBEFORE) < 0)
		err(sys->sprint("cannot bind /n/client/dev to /dev: %r"));

	fd = sys->open("/dev/cons", sys->OREAD);
	sys->dup(fd.fd, 0);
	fd = sys->open("/dev/cons", sys->OWRITE);
	sys->dup(fd.fd, 1);
	sys->dup(fd.fd, 2);
	fd = nil;

	mod->init(nil, args);
}

readargs(fd: ref Sys->FD): list of string
{
	buf := array[15] of byte;
	c := array[1] of byte;
	for(i:=0; ; i++){
		if(i>=len buf || sys->read(fd, c, 1)!=1)
			return nil;
		buf[i] = c[0];
		if(c[0] == byte '\n')
			break;
	}
	nb := int string buf[0:i];
	if(nb <= 0)
		return nil;
	args := readn(fd, nb);
	if (args == nil)
		return nil;
	return str->unquoted(string args[0:nb]);
}

readn(fd: ref Sys->FD, nb: int): array of byte
{
	buf:= array[nb] of byte;
	for(n:=0; n<nb;){
		m := sys->read(fd, buf[n:], nb-n);
		if(m <= 0)
			return nil;
		n += m;
	}
	return buf;
}

getuser(): string
{
	fd := sys->open("/dev/user", sys->OREAD);
	if(fd == nil)
		err(sys->sprint("can't open /dev/user: %r"));

	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0)
		err(sys->sprint("error reading /dev/user: %r"));

	return string buf[0:n];	
}

err(s: string)
{
	sys->fprint(stderr, "rstyxd: %s\n", s);
	sys->raise("fail:error");
}
