implement Gamelogind;

#
# certification service (signer)
#
# modified for the game server in the following ways:
#	no password is required to acquire a certificate
#	i.e. no shared secret.
# 	however, i believe that the protocol in this case
#	only falls to a man-in-the-middle attack
#	where the man in the middle changes the public keys
#	visible to either party. so after a certificate has been
#	granted, it's easy for the party at the other end to check
#	through out of band channels that the server has the
#	same public key.
#
#	a certificate is only granted once.
#	at that point, a user entry is created for the user, which
#	will stop another certificate being issued.
#
# there should really be locking on the password directory,
# because it's quite possible that two identical user ids
# are created for different clients at the same time.

include "sys.m";
	sys: Sys;

include "draw.m";

include "keyring.m";
	kr: Keyring;
	IPint: import kr;

include "security.m";
	rand: Random;
	ssl: SSL;
	password: Password;

include "daytime.m";
	daytime: Daytime;

include "string.m";
	str: String;

include "lib/base64.m";
	base64: Base64;

Gamelogind: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

TimeLimit: con 5*60*1000;	# five minutes

Knownpassword: con "gameserver";
Passwordfile: con "/keydb/gamepassword";
Signerkey: con "/keydb/gamesignerkey";

stderr, stdin: ref Sys->FD;
 
init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys->PATH;
	stdin = sys->fildes(0);
	stderr = sys->open("/dev/cons", sys->OWRITE);

	sys->fprint(stderr, "game logind executing\n");

	kr = load Keyring Keyring->PATH;

	ssl = load SSL SSL->PATH;
	if(ssl == nil) nomod(SSL->PATH);

	rand = load Random Random->PATH;
	if(rand == nil) nomod(Random->PATH);

	password = load Password Password->PATH;
	if(password == nil) nomod(Password->PATH);

	daytime = load Daytime Daytime->PATH;
	if(daytime == nil) nomod(Daytime->PATH);

	str = load String String->PATH;
	if (str == nil) nomod(String->PATH);

	base64 = load Base64 Base64->PATH;
	if (base64 == nil) nomod(Base64->PATH);

	# push ssl, leave in clear mode
	if(sys->bind("#D", "/n/ssl", Sys->MREPL) < 0)
		fatal("cannot bind #D", 1);

	password->setpwfile(Passwordfile);

	(err, c) := ssl->connect(stdin);     
	if(c == nil)
		fatal("pushing ssl: " + err, 0);

	# impose time out to ensure dead network connections recovered well before TCP/IP's long time out

	grpid := sys->pctl(Sys->NEWPGRP,nil);
	pidc := chan of int;
	spawn stalker(pidc, grpid);
	tpid := <-pidc;
	err = dologin(c);
	if(err != nil){
		sys->fprint(stderr, "logind: %s\n", err);
		kr->puterror(c.dfd, err);
		#fatal(err, 0);
	}
	kill(tpid, "kill");
}
blankpw: Password->PW;

dologin(c: ref Sys->Connection): string
{
	ivec: array of byte;

	(info, err) := signerkey(Signerkey);
	if(info == nil)
		return "can't read signer's own key: "+err;

	# get user name; ack
	name: string;
	(name, err) = kr->getstring(c.dfd);
	if(err != nil)
		return err;
	# lookup password
	pw := password->get(name);
	if (pw != nil)
		return "that username already exists";

	if (!validusername(name))
		return "invalid user name";

	pw = makeuser(name);
	if (pw == nil)
		return "failed to create password entry";
	kr->putstring(c.dfd, name);

	# get initialization vector
	(ivec, err) = kr->getbytearray(c.dfd);
	if(err != nil)
		return "can't get initialization vector: "+err;

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
	s: string;
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
	pw.other = base64->encode(hisPKbuf);
	password->put(pw);
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

makeuser(name: string): ref Password->PW
{
	bpw := array of byte Knownpassword;
	pw := ref blankpw;
	pw.id = name;
	pw.pw = array[Keyring->SHAdlen] of byte;
	kr->sha(bpw, len bpw, pw.pw, nil);
	pw.expire = 16r7fffffff;
	if (password->put(pw) == -1)
		return nil;
	return pw;
}

Notok: con "\0-\u0020:/\u007f";
validusername(name: string): int
{
	for (i := 0; i < len name; i++)
		if (str->in(name[i], Notok))
			return 0;
	return 1;
}

nomod(mod: string)
{
	fatal(sys->sprint("can't load %s",mod), 1);
}

fatal(msg: string, prsyserr: int)
{
	if(prsyserr)
		sys->fprint(stderr, "logind: %s: %r\n", msg);
	else
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
