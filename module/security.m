#
#  security routines implemented in limbo
#


Virgil: module
{
	PATH:	con "/dis/lib/virgil.dis";

	virgil:	fn(args: list of string): string;
};

Random: module
{
	PATH:	con "/dis/lib/random.dis";

	ReallyRandom:	con 0;
	NotQuiteRandom:	con 1;

	randomint: fn(which: int): int;
	randombuf: fn(which, n: int): array of byte;
};

#
#  read and write password entries in the password file
#
Password: module
{
	PATH:	con "/dis/lib/password.dis";

	PW: adt {
		id:	string;			# user id
		pw:	array of byte;	# password hashed by SHA
		expire:	int;		# expiration time (epoch seconds)
		other:	string;		# about the account	
	};

	setpwfile:	fn(name: string): string;
	get: fn(id: string): ref PW;
	put: fn(pass: ref PW): int;
};

#
#  secure socket layer emulator
#
SSL: module
{
	# Caller is expected to bind the security device to /n/ssl.

	PATH:	con "/dis/lib/ssl.dis";

	connect: fn(fd: ref Sys->FD): (string, ref Sys->Connection);
	secret: fn(c: ref Sys->Connection, secretin, secretout: array of byte): string;
};


#
#  Encrypted Key Exchange protocol
#
Login: module 
{
	PATH:	con "/dis/lib/login.dis";

	login:	fn(id, password, dest: string): (string, ref Keyring->Authinfo);
};

#
#  Station To Station protocol
#
Auth: module
{
	PATH:	con "/dis/lib/auth.dis";

	init: fn(): string;
	server: fn(algs: list of string, ai: ref Keyring->Authinfo, fd: ref Sys->FD, setid: int): (ref Sys->FD, string);
	client: fn(alg: string, ai: ref Keyring->Authinfo, fd: ref Sys->FD): (ref Sys->FD, string);
};
