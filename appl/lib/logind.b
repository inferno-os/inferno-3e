implement Logind;

#
# certification service (signer)
#

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "security.m";
	ssl: SSL;
	password: Password;

include "daytime.m";
	daytime: Daytime;

Logind: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

TimeLimit: con 5*60*1000;	# five minutes

stderr, stdin: ref Sys->FD;
 
init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stderr = sys->open("/dev/cons", sys->OWRITE);

	kr = load Keyring Keyring->PATH;

	ssl = load SSL SSL->PATH;
	if(ssl == nil)
		nomod(SSL->PATH);

	password = load Password Password->PATH;
	if(password == nil)
		nomod(Password->PATH);

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) 
		nomod(Daytime->PATH);

	(err, c) := ssl->connect(stdin);     
	if(c == nil)
		fatal("pushing ssl: " + err);

	# impose time out to ensure dead network connections recovered well before TCP/IP's long time out

	grpid := sys->pctl(Sys->NEWPGRP,nil);
	pidc := chan of int;
	spawn stalker(pidc, grpid);
	tpid := <-pidc;
	err = dologin(c);
	if(err != nil){
		sys->fprint(stderr, "logind: %s\n", err);
		kr->puterror(c.dfd, err);
	}
	kill(tpid, "kill");
}

dologin(c: ref Sys->Connection): string
{
	ivec: array of byte;

	(info, err) := signerkey("/keydb/signerkey");
	if(info == nil)
		return "can't read signer's own key: "+err;

	# get user name; ack
	s: string;
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return err;
	name := s;
	kr->putstring(c.dfd, name);

	# get initialization vector
	(ivec, err) = kr->getbytearray(c.dfd);
	if(err != nil)
		return "can't get initialization vector: "+err;

	# lookup password
	pw := password->get(s);
	if(pw == nil)
		return "no password for "+s;

	# generate our random diffie hellman part
	bits := info.p.bits();
	r0 := kr->IPint.random(bits/4, bits);

	# generate alpha0 = alpha**r0 mod p
	alphar0 := info.alpha.expmod(r0, info.p);

	# start encrypting
	pwbuf := array[8] of byte;
	for(i := 0; i < 8; i++)
		pwbuf[i] = pw.pw[i] ^ pw.pw[8+i];
	for(i = 0; i < 4; i++)
		pwbuf[i] ^= pw.pw[16+i];
	for(i = 0; i < 8; i++)
		pwbuf[i] ^= ivec[i];
	err = ssl->secret(c, pwbuf, pwbuf);
	if(err != nil)
		return "can't set ssl secret: "+err;

	if(sys->fprint(c.cfd, "alg rc4") < 0)
		return sys->sprint("can't push alg rc4: %r");

	# send P(alpha**r0 mod p)
	if(kr->putstring(c.dfd, alphar0.iptob64()) < 0)
		return sys->sprint("can't send (alpha**r0 mod p): %r");

	# stop encrypting
	if(sys->fprint(c.cfd, "alg clear") < 0)
		return sys->sprint("can't clear alg: %r");

	# send alpha, p
	if(kr->putstring(c.dfd, info.alpha.iptob64()) < 0 ||
	   kr->putstring(c.dfd, info.p.iptob64()) < 0)
		return sys->sprint("can't send alpha, p: %r");

	# get alpha**r1 mod p
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return "can't get alpha**r1 mod p:"+err;
	alphar1 := kr->IPint.b64toip(s);

	# compute alpha**(r0*r1) mod p
	alphar0r1 := alphar1.expmod(r0, info.p);

	# turn on digesting
	secret := alphar0r1.iptobytes();
	err = ssl->secret(c, secret, secret);
	if(err != nil)
		return "can't set digest secret: "+err;
	if(sys->fprint(c.cfd, "alg sha") < 0)
		return sys->sprint("can't push alg sha: %r");

	# send our public key
	if(kr->putstring(c.dfd, kr->pktostr(kr->sktopk(info.mysk))) < 0)
		return sys->sprint("can't send signer's public key: %r");

	# get his public key
	(s, err) = kr->getstring(c.dfd);
	if(err != nil)
		return "client public key: "+err;
	hisPKbuf := array of byte s;
	hisPK := kr->strtopk(s);
	if(hisPK.owner != name)
		return "pk name doesn't match user name";

	# sign and return
	state := kr->sha(hisPKbuf, len hisPKbuf, nil, nil);
	cert := kr->sign(info.mysk, 0, state, "sha");

	if(kr->putstring(c.dfd, kr->certtostr(cert)) < 0)
		return sys->sprint("can't send certificate: %r");

	return nil;
}

nomod(mod: string)
{
	fatal(sys->sprint("can't load %s: %r",mod));
}

fatal(msg: string)
{
	sys->fprint(stderr, "logind: %s\n", msg);
	exit;
}

signerkey(filename: string): (ref Keyring->Authinfo, string)
{

	info := kr->readauthinfo(filename);
	if(info == nil)
		return (nil, sys->sprint("readauthinfo %r"));

	# validate signer key
	now := daytime->now();
	if(info.cert.exp != 0 && info.cert.exp < now)
		return (nil, sys->sprint("key expired"));

	return (info, nil);
}

stalker(pidc: chan of int, killpid: int)
{
	pidc <-= sys->pctl(0, nil);
	sys->sleep(TimeLimit);
	sys->fprint(stderr, "logind: login timed out\n");
	kill(killpid, "killgrp");
}

kill(pid: int, how: string)
{
	fd := sys->open("#p/" + string pid + "/ctl", Sys->OWRITE);
	if(fd == nil || sys->fprint(fd, "%s", how) < 0)
		sys->fprint(stderr, "logind: can't %s %d: %r\n", how, pid);
}
