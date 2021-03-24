Shell: module
{
	PATH: con "/dis/shell.dis";
	init: fn(ctxt: ref Draw->Context, argv: list of string);
	system: fn(drawctxt: ref Draw->Context, cmd: string): string;
	parse: fn(s: string): (ref Cmd, string);
	cmd2string: fn(c: ref Cmd): string;

	Context: adt {
		new: fn(drawcontext: ref Draw->Context): ref Context;
		get: fn(c: self ref Context, name: string): list of ref Listnode;
		set: fn(c: self ref Context, name: string, val: list of ref Listnode);
		env: fn(c: self ref Context): list of (string, list of ref Listnode);
		push, pop: fn(c: self ref Context);
		setlocal: fn(c: self ref Context, name: string, val: list of ref Listnode);
		run: fn(c: self ref Context, args: list of ref Listnode, last: int): string;
		addmodule: fn(c: self ref Context, name: string, mod: Shellbuiltin);
		addbuiltin: fn(c: self ref Context, name: string, mod: Shellbuiltin);
		removebuiltin: fn(c: self ref Context, name: string, mod: Shellbuiltin);
		addsbuiltin: fn(c: self ref Context, name: string, mod: Shellbuiltin);
		removesbuiltin: fn(c: self ref Context, name: string, mod: Shellbuiltin);
		fail: fn(c: self ref Context, ename, msg: string);
		options: fn(c: self ref Context): int;
		setoptions: fn(c: self ref Context, flags, on: int): int;
		INTERACTIVE, VERBOSE, EXECPRINT, ERROREXIT: con 1 << iota;

		localenv: ref Localenv;		# locally held environment variables
		waitfd: ref Sys->FD;
		drawcontext: ref Draw->Context;
		sbuiltins: ref Builtins;
		builtins: ref Builtins;
		bmods: list of (string, Shellbuiltin);
	};

	list2stringlist: fn(nl: list of ref Listnode): list of string;
	stringlist2list: fn(sl: list of string): list of ref Listnode;

	initbuiltin: fn(c: ref Context, sh: Shell): string;
	runbuiltin: fn(c: ref Context, sh: Shell, cmd: list of ref Listnode, last: int): string;
	runsbuiltin: fn(c: ref Context, sh: Shell, cmd: list of ref Listnode): list of ref Listnode;
	getself: fn(): Shellbuiltin;
	Cmd: type Node;
	Node: adt {
		ntype: int;
		left, right: ref Node;
		word: string;
		redir: ref Redir;
	};
	Redir: adt {
		rtype: int;
		fd1, fd2: int;
	};
	Var: adt {
		name: string;
		val: list of ref Listnode;
		flags: int;
		CHANGED, NOEXPORT: con (1 << iota);
	};
	Localenv: adt {
		vars: array of list of ref Var;
		pushed: ref Localenv;
		flags: int;
	};
	Listnode: adt {
		cmd: ref Node;
		word: string;
	};
	Builtins: adt {
		ba: array of (string, list of Shellbuiltin);
		n: int;
	};
};

Shellbuiltin: module {
	initbuiltin: fn(c: ref Shell->Context, sh: Shell): string;
	runbuiltin: fn(c: ref Shell->Context, sh: Shell,
			cmd: list of ref Shell->Listnode, last: int): string;
	runsbuiltin: fn(c: ref Shell->Context, sh: Shell,
			cmd: list of ref Shell->Listnode): list of ref Shell->Listnode;
	getself: fn(): Shellbuiltin;
};
