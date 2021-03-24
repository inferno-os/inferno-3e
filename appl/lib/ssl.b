implement SSL;

include "sys.m";
include "keyring.m";
include "draw.m";
include "security.m";

connect(fd: ref Sys->FD): (string, ref Sys->Connection)
{
	c := ref Sys->Connection;

	sys := load Sys Sys->PATH;

	c.dir = "#D";	# only the local device will work, because local file descriptors are used
	(rc, nil) := sys->stat(c.dir);
	if(rc < 0){
		(rc, nil) = sys->stat(c.dir+"/ssl");	# alternative version
		if(rc >= 0)
			c.dir += "/ssl";
	}
	c.cfd = sys->open(c.dir + "/clone", Sys->ORDWR);
	if(c.cfd == nil)
		return (sys->sprint("cannot open clone: %r"), nil);

	buf := array[128] of byte;
	if((n := sys->read(c.cfd, buf, len buf)) < 0)
		return (sys->sprint("cannot read ctl: %r"), nil);

	c.dir += "/" + string buf[0:n];
	
	c.dfd = sys->open(c.dir + "/data", Sys->ORDWR);
	if(c.dfd == nil)
		return (sys->sprint("cannot open data: %r"), nil);

	if(sys->fprint(c.cfd, "fd %d", fd.fd) < 0)
		return (sys->sprint("cannot push fd: %r"), nil);

	return (nil, c);
}

secret(c: ref Sys->Connection, secretin, secretout: array of byte): string
{
	sys := load Sys Sys->PATH;

	if(secretin != nil){
		fd := sys->open(c.dir + "/secretin", Sys->ORDWR);
		if(fd == nil)
			return sys->sprint("cannot open %s: %r", c.dir + "/secretin");
		if(sys->write(fd, secretin, len secretin) < 0)
			return sys->sprint("cannot write %s: %r", c.dir + "/secretin");
	}

	if(secretout != nil){
		fd := sys->open(c.dir + "/secretout", Sys->ORDWR);
		if(fd == nil)
			return sys->sprint("cannot open %s: %r", c.dir + "/secretout");
		if(sys->write(fd, secretout, len secretout) < 0)
			return sys->sprint("cannot open %s: %r", c.dir + "/secretout");
	}
	return nil;
}
