implement Createsignerkey;

include "sys.m";
	sys: Sys;

include "draw.m";

include "daytime.m";

include "keyring.m";
	kr: Keyring;

include "arg.m";

# signer key never expires
SKexpire:       con 0;

# size in bits of modulus for public keys
PKmodlen:		con 512;

# size in bits of modulus for diffie hellman
DHmodlen:		con 512;

algs := array[] of {"elgamal", "rsa"};	# first entry is default

Createsignerkey: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	err: string;

	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	if(kr == nil)
		loaderr(Keyring->PATH);
	arg := load Arg Arg->PATH;
	if(arg == nil)
		loaderr(Arg->PATH);

	arg->init(argv);
	alg := algs[0];
	filename := "/keydb/signerkey";
	expire := SKexpire;
	bits := PKmodlen;
	while((c := arg->opt()) != 0){
		case c {
		'a' =>
			alg = arg->arg();
			if(alg == nil)
				usage();
			for(i:=0;; i++){
				if(i >= len algs)
					error(sys->sprint("unknown algorithm: %s", alg));
				else if(alg == algs[i])
					break;
			}
		'f' =>
			filename = arg->arg();
			if(filename == nil)
				usage();
		'e' =>
			s := arg->arg();
			if(s == nil)
				usage();
			(err, expire) = checkdate(s);
			if(err != nil)
				error(err);
		'b' =>
			s := arg->arg();
			if(s == nil)
				usage();
			bits = int s;
			if(bits < 32 || bits > 4096)
				error("modulus must be in the range of 32 to 4096 bits");
		}
	}
	argv = arg->argv();
	arg = nil;

	if(argv == nil)
		usage();
	owner := hd argv;
	argv = tl argv;

	# compatibility with original version
	if(argv != nil){
		if(len hd argv == 8){
			 (err, expire) = checkdate(hd argv);
			 if(err != nil)
				error(err);
			argv = tl argv;
		}
	}

	# compatibility with original version
	if(argv != nil){
		bits = int hd argv;
		argv = tl argv;
		if(bits < 32 || bits > 4096)
			error("modulus must be in the range of 32 to 4096 bits");
	}

	# compatibility with original version
	if(argv != nil){
		filename = hd argv;
		argv = tl argv;
	}

	# generate a local key
	info := ref Keyring->Authinfo;
	info.mysk = kr->genSK(alg, owner, bits);
	if(info.mysk == nil)
		error(sys->sprint("algorithm %s not configured in system", alg));
	info.mypk = kr->sktopk(info.mysk);
	info.spk = kr->sktopk(info.mysk);
	myPKbuf := array of byte kr->pktostr(info.mypk);
	state := kr->sha(myPKbuf, len myPKbuf, nil, nil);
	info.cert = kr->sign(info.mysk, expire, state, "sha");
	(info.alpha, info.p) = kr->dhparams(DHmodlen);

	if(kr->writeauthinfo(filename, info) < 0)
		error(sys->sprint("can't write signerkey file %s: %r", filename));
}

usage()
{
	sys->fprint(sys->fildes(2), "usage: createsignerkey [-a algorithm] [-f keyfile] [-e ddmmyyyy] [-b size-in-bits] name-of-owner\n");
	sys->raise("fail:usage");
}

loaderr(s: string)
{
	error(sys->sprint("can't load %s: %r", s));
}

error(s: string)
{
	sys->fprint(sys->fildes(2), "createsignerkey: %s\n", s);
	sys->raise("fail:error");
}

checkdate(word: string): (string, int)
{
	if(len word != 8)
		return ("!date must be in form ddmmyyyy", 0);

	daytime := load Daytime Daytime->PATH;
	if(daytime == nil)
		loaderr(Daytime->PATH);

	now := daytime->now();

	tm := daytime->local(now);
	tm.sec = 59;
	tm.min = 59;
	tm.hour = 24;

	tm.mday = int word[0:2];
	if(tm.mday > 31 || tm.mday < 1)
		return ("!bad day of month", 0);

	tm.mon = int word[2:4] - 1;
	if(tm.mon > 11 || tm.mday < 0)
		return ("!bad month", 0);

	tm.year = int word[4:8] - 1900;
	if(tm.year < 70)
		return ("!bad year", 0);

	newdate := daytime->tm2epoch(tm);
	if(newdate < now)
		return ("!expiration date must be in the future", 0);

	return (nil, newdate);
}
