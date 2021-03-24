Arg : module
{
	PATH: con "/dis/lib/arg.dis";

	init: fn(argv: list of string);
	arg: fn(): string;
	opt: fn(): int;

	progname: fn(): string;
	argv: fn(): list of string;
};
