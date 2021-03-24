implement Styxd;

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";

include "security.m";

stderr: ref Sys->FD;

Styxd: module 
{
	init: fn(ctxt: ref Draw->Context, argv: list of string);
};

# argv is a list of Inferno supported algorithms from Security->Auth
init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stdin := sys->fildes(0);
	stderr = sys->open("/dev/cons", Sys->OWRITE);

	setid := 1;
	if(argv != nil){
		argv = tl argv;
		if(argv != nil && hd argv == "-s"){	# temporary, undocumented option
			setid = 0;
			argv = tl argv;
		}
	}

	auth := load Auth Auth->PATH;
	if(auth == nil)
		err(sys->sprint("can't load %s: %r", Auth->PATH));

	error := auth->init();
	if(error != nil)
		err(sys->sprint("Auth init failed: %s", error));

	user := user();

	kr := load Keyring Keyring->PATH;
	ai := kr->readauthinfo("/usr/"+user+"/keyring/default");
	# let auth->server handle nil ai

	if(argv == nil)
		err("no algorithm list");

	(fd, info_or_err) := auth->server(argv, ai, stdin, setid);
	if(fd == nil )
		err(sys->sprint("server auth failed: %s", info_or_err));

	sys->pctl(Sys->FORKNS|Sys->FORKENV, nil);

	if(sys->export(fd, Sys->EXPASYNC) < 0)
		sys->fprint(sys->fildes(2), "styxd: file export: %r\n");
}

user(): string
{
	fd := sys->open("/dev/user", Sys->OREAD);
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
	sys->fprint(stderr, "styxd: %s\n", s);
	sys->raise("fail:error");
}
