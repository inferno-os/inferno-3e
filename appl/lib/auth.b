# Inferno authentication protocol
implement Auth;

include "sys.m";
	sys: Sys;

include "keyring.m";
	kr: Keyring;

include "security.m";
	ssl: SSL;

init(): string
{
	if(sys == nil)
		sys = load Sys Sys->PATH;

	if(kr == nil)
		kr = load Keyring Keyring->PATH;

	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		return sys->sprint("can't load ssl: %r");

	return nil;	
}

server(algs: list of string, ai: ref Keyring->Authinfo, fd: ref Sys->FD, setid: int): (ref Sys->FD, string)
{
	# mutual authentication
	(id_or_err, secret) := kr->auth(fd, ai, setid); 

	nobody := 0;
	for(sl := algs; sl != nil; sl = tl sl)
		if(hd sl == "nobody")
			nobody = 1;	# server allows unauthenticated mount as `nobody' (security hole)

	if(secret == nil){
		if(nobody && id_or_err == "remote: no authentication information")
			return (fd, id_or_err);
		if(ai == nil && id_or_err == "no authentication information")
			id_or_err = "no server certificate";
		return (nil, id_or_err);
	}

	# have got a secret, get algorithm from client
	# check if the client algorithm is in the server algorithm list
	# client algorithm ::= ident (' ' ident)*
	# where ident is defined by ssl(3)
	algbuf := string kr->getmsg(fd);
	if(algbuf == nil)
		return (nil, sys->sprint("can't read client ssl algorithm: %r"));
	alg := "";
	(nil, calgs) := sys->tokenize(algbuf, " /");
	for(; calgs != nil; calgs = tl calgs){
		calg := hd calgs;
		if(algs != nil){	# otherwise we suck it and see
			for(sl = algs; sl != nil; sl = tl sl)
				if(hd sl == calg)
					break;
			if(sl == nil)
				return (nil, "unsupported client algorithm: " + calg);
		}
		alg += calg + " ";
	}
	if(alg != nil)
		alg = alg[0:len alg - 1];

	# don't push ssl if server supports nossl
	if(alg == nil || alg == "nossl" || alg == "none")
		return (fd, id_or_err);

	# push ssl and turn on algorithms
	(c, err) := pushssl(fd, secret, secret, alg);
	if(c == nil)
		return (nil, "push ssl: " + err);
	return (c, id_or_err);
}

client(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD): (ref Sys->FD, string)
{
	if(alg == nil)
		alg = "none";

	# mutual authentication
	(id_or_err, secret) := kr->auth(fd, ai, 0);

	if(secret == nil){
		if(ai == nil)
			return (fd, sys->sprint("%s; running as nobody", id_or_err));
		return (nil, id_or_err);
	}

	# send algorithm
	buf := array of byte alg;
	if(kr->sendmsg(fd, buf, len buf) < 0)
		return (nil, sys->sprint("can't send ssl algorithm: %r"));

	# don't push ssl if server supports no ssl connection
	if(alg == "nossl" || alg == "none")
		return (fd, id_or_err);

	# push ssl and turn on algorithm
	(c, err) := pushssl(fd, secret, secret, alg);
	if(c == nil)
		return (nil, "push ssl: " + err);
	return (c, id_or_err);
}

# push an SSLv2 Record Layer onto the fd
pushssl(fd: ref Sys->FD, secretin, secretout: array of byte, alg: string): (ref Sys->FD, string)
{
	(err, c) := ssl->connect(fd);
	if(err != nil)
		return (nil, "can't connect ssl: " + err);

	err = ssl->secret(c, secretin, secretout);
	if(err != nil)
		return (nil, "can't write secret: " + err);

	if(sys->fprint(c.cfd, "alg %s", alg) < 0)
		return (nil, sys->sprint("can't push algorithm %s: %r", alg));

	return (c.dfd, nil);
}
