implement Limbo;

#line	2	"limbo.y"
include "limbo.m";
include "draw.m";

Limbo: module {

	init:		fn(ctxt: ref Draw->Context, argv: list of string);

	YYSTYPE: adt{
		tok:	Tok;
		ids:	ref Decl;
		node:	ref Node;
		ty:	ref Type;
	};

	YYLEX: adt {
		lval: YYSTYPE;
		lex: fn(nil: self ref YYLEX): int;
		error: fn(nil: self ref YYLEX, err: string);
	};
Landeq: con	57346;
Loreq: con	57347;
Lxoreq: con	57348;
Llsheq: con	57349;
Lrsheq: con	57350;
Laddeq: con	57351;
Lsubeq: con	57352;
Lmuleq: con	57353;
Ldiveq: con	57354;
Lmodeq: con	57355;
Ldeclas: con	57356;
Lload: con	57357;
Loror: con	57358;
Landand: con	57359;
Lcons: con	57360;
Leq: con	57361;
Lneq: con	57362;
Lleq: con	57363;
Lgeq: con	57364;
Llsh: con	57365;
Lrsh: con	57366;
Lcomm: con	57367;
Linc: con	57368;
Ldec: con	57369;
Lof: con	57370;
Lref: con	57371;
Lif: con	57372;
Lelse: con	57373;
Lfn: con	57374;
Lmdot: con	57375;
Lto: con	57376;
Lor: con	57377;
Lrconst: con	57378;
Lconst: con	57379;
Lid: con	57380;
Ltid: con	57381;
Lsconst: con	57382;
Llabs: con	57383;
Lnil: con	57384;
Llen: con	57385;
Lhd: con	57386;
Ltl: con	57387;
Ltagof: con	57388;
Limplement: con	57389;
Limport: con	57390;
Linclude: con	57391;
Lcon: con	57392;
Ltype: con	57393;
Lmodule: con	57394;
Lcyclic: con	57395;
Ladt: con	57396;
Larray: con	57397;
Llist: con	57398;
Lchan: con	57399;
Lself: con	57400;
Ldo: con	57401;
Lwhile: con	57402;
Lfor: con	57403;
Lbreak: con	57404;
Lalt: con	57405;
Lcase: con	57406;
Lpick: con	57407;
Lcont: con	57408;
Lreturn: con	57409;
Lexit: con	57410;
Lspawn: con	57411;

};

#line	26	"limbo.y"
	#
	# lex.b
	#
	signdump:	string;			# name of function for sig debugging
	superwarn:	int;
	debug:		array of int;
	noline:		Line;
	nosrc:		Src;
	arrayz:		int;
	emitcode:	string;			# emit stub routines for system module functions
	emitdyn: int;				# emit as above but for dynamic modules
	emitsbl:	string;			# emit symbol file for sysm modules
	emitstub:	int;			# emit type and call frames for system modules
	emittab:	string;			# emit table of runtime functions for this module
	errors:		int;
	mustcompile:	int;
	dontcompile:	int;
	asmsym:		int;			# generate symbols in assembly language?
	bout:		ref Bufio->Iobuf;	# output file
	bsym:		ref Bufio->Iobuf;	# symbol output file; nil => no sym out
	gendis:		int;			# generate dis or asm?
	fixss:		int;
	zeroptrs:		int;

	#
	# decls.b
	#
	scope:		int;
	impmod:		ref Sym;		# name of implementation module
	nildecl:	ref Decl;		# declaration for limbo's nil

	#
	# types.b
	#
	tany:		ref Type;
	tbig:		ref Type;
	tbyte:		ref Type;
	terror:		ref Type;
	tint:		ref Type;
	tnone:		ref Type;
	treal:		ref Type;
	tstring:	ref Type;
	tunknown:	ref Type;
	descriptors:	ref Desc;		# list of all possible descriptors
	tattr:		array of Tattr;

	#
	# nodes.b
	#
	opcommute:	array of int;
	oprelinvert:	array of int;
	isused:		array of int;
	casttab:	array of array of int;	# instruction to cast from [1] to [2]

	nfns:		int;			# functions defined
	nfnexp:		int;
	fns:		array of ref Decl;	# decls for fns defined
	tree:		ref Node;		# root of parse tree

	parset:		int;			# time to parse
	checkt:		int;			# time to typecheck
	gent:		int;			# time to generate code
	writet:		int;			# time to write out code
	symt:		int;			# time to write out symbols
YYEOFCODE: con 1;
YYERRCODE: con 2;
YYMAXDEPTH: con 200;

#line	1302	"limbo.y"


include "keyring.m";

sys:	Sys;
	print, fprint, sprint: import sys;

bufio:	Bufio;
	Iobuf: import bufio;

str:		String;

keyring:Keyring;
	md5: import keyring;

math:	Math;
	import_real, export_real, isnan: import math;

yyctxt: ref YYLEX;

canonnan: real;

debug	= array[256] of {* => 0};

noline	= -1;
nosrc	= Src(-1, -1);

infile:	string;

# front end
include "arg.m";
include "lex.b";
include "types.b";
include "nodes.b";
include "decls.b";

include "typecheck.b";

# back end
include "gen.b";
include "ecom.b";
include "asm.b";
include "dis.b";
include "sbl.b";
include "stubs.b";
include "com.b";

init(nil: ref Draw->Context, argv: list of string)
{
	s: string;

	sys = load Sys Sys->PATH;
	keyring = load Keyring Keyring->PATH;
	math = load Math Math->PATH;
	bufio = load Bufio Bufio->PATH;
	if(bufio == nil){
		sys->print("can't load %s: %r\n", Bufio->PATH);
		sys->raise("fail:bad module");
	}
	str = load String String->PATH;
	if(str == nil){
		sys->print("can't load %s: %r\n", String->PATH);
		sys->raise("fail:bad module");
	}

	stderr = sys->fildes(2);
	yyctxt = ref YYLEX;

	math->FPcontrol(0, Math->INVAL|Math->ZDIV|Math->OVFL|Math->UNFL|Math->INEX);
	na := array[1] of {0.};
	import_real(array[8] of {byte 16r7f, * => byte 16rff}, na);
	canonnan = na[0];
	if(!isnan(canonnan))
		fatal("bad canonical NaN");

	lexinit();
	typeinit();
	optabinit();

	gendis = 1;
	asmsym = 0;
	maxerr = 20;
	ofile := "";
	ext := "";
	zeroptrs = 1;

	arg := Arg.init(argv);
	while(c := arg.opt()){
		case c{
		'Y' =>
			emitsbl = arg.arg();
			if(emitsbl == nil)
				usage();
		'C' =>
			dontcompile = 1;
		'D' =>
			#
			# debug flags:
			#
			# a	alt compilation
			# A	array constructor compilation
			# b	boolean and branch compilation
			# c	case compilation
			# d	function declaration
			# D	descriptor generation
			# e	expression compilation
			# E	addressable expression compilation
			# f	print arguments for compiled functions
			# F	constant folding
			# g	print out globals
			# m	module declaration and type checking
			# n	nil references
			# s	print sizes of output file sections
			# S	type signing
			# t	type checking function bodies
			# T	timing
			# v	global var and constant compilation
			# x	adt verification
			# Y	tuple compilation
			# z Z	bug fixes
			#
			s = arg.arg();
			for(i := 0; i < len s; i++){
				c = s[i];
				if(c < len debug)
					debug[c] = 1;
			}
		'I' =>
			s = arg.arg();
			if(s == "")
				usage();
			addinclude(s);
		'G' =>
			asmsym = 1;
		'S' =>
			gendis = 0;
		'a' =>
			emitstub = 1;
		'A' =>
			emitstub = emitdyn = 1;
		'c' =>
			mustcompile = 1;
		'e' =>
			maxerr = 1000;
		'f' =>
			fabort = 1;
		'g' =>
			dosym = 1;
		'o' =>
			ofile = arg.arg();
		's' =>
			s = arg.arg();
			if(s != nil)
				fixss = int s;
		't' =>
			emittab = arg.arg();
			if(emittab == nil)
				usage();
		'T' =>
			emitcode = arg.arg();
			if(emitcode == nil)
				usage();
		'd' =>
			emitcode = arg.arg();
			if(emitcode == nil)
				usage();
			emitdyn = 1;
		'w' =>
			superwarn = dowarn;
			dowarn = 1;
		'x' =>
			ext = arg.arg();
		'X' =>
			signdump = arg.arg();
		'z' =>
			arrayz = 1;
		'Z' =>
			zeroptrs = 0;
		* =>
			usage();
		}
	}

	addinclude("/module");

	argv = arg.argv;
	arg = nil;

	if(argv == nil){
		usage();
	}else if(ofile != nil){
		if(len argv != 1)
			usage();
		translate(hd argv, ofile, mkfileext(ofile, ".dis", ".sbl"));
	}else{
		pr := len argv != 1;
		if(ext == ""){
			ext = ".s";
			if(gendis)
				ext = ".dis";
		}
		for(; argv != nil; argv = tl argv){
			file := hd argv;
			(nil, s) = str->splitr(file, "/");
			if(pr)
				print("%s:\n", s);
			out := mkfileext(s, ".b", ext);
			translate(file, out, mkfileext(out, ".dis", ".sbl"));
		}
	}
	if (toterrors > 0)
		sys->raise("fail:errors");
}

usage()
{
	fprint(stderr, "usage: limbo [-GSagwe] [-I incdir] [-o outfile] [-{T|t|d} module] [-D debug] file ...\n");
	sys->raise("fail:usage");
}

mkfileext(file, oldext, ext: string): string
{
	n := len file;
	n2 := len oldext;
	if(n >= n2 && file[n-n2:] == oldext)
		file = file[:n-n2];
	return file + ext;
}

translate(in, out, dbg: string)
{
	infile = in;
	outfile = out;
	errors = 0;
	bins[0] = bufio->open(in, Bufio->OREAD);
	if(bins[0] == nil){
		fprint(stderr, "can't open %s: %r\n", in);
		toterrors++;
		return;
	}
	doemit := emitcode != "" || emitstub || emittab != "" || emitsbl != "";
	if(!doemit){
		bout = bufio->create(out, Bufio->OWRITE, 8r666);
		if(bout == nil){
			fprint(stderr, "can't open %s: %r\n", out);
			toterrors++;
			bins[0].close();
			return;
		}
		if(dosym){
			bsym = bufio->create(dbg, Bufio->OWRITE, 8r666);
			if(bsym == nil)
				fprint(stderr, "can't open %s: %r\n", dbg);
		}
	}

	lexstart(in);

	popscopes();
	typestart();
	declstart();
	nfnexp = 0;

	parset = sys->millisec();
	yyparse(yyctxt);
	parset = sys->millisec() - parset;

	checkt = sys->millisec();
	entry := typecheck(!doemit);
	checkt = sys->millisec() - checkt;

	modcom(entry);

	fns = nil;
	nfns = 0;
	descriptors = nil;

	if(debug['T'])
		print("times: parse=%d type=%d: gen=%d write=%d symbols=%d\n",
			parset, checkt, gent, writet, symt);

	if(bout != nil)
		bout.close();
	if(bsym != nil)
		bsym.close();
	toterrors += errors;
	if(errors && bout != nil)
		sys->remove(out);
	if(errors && bsym != nil)
		sys->remove(dbg);
}

pwd(): string
{
	workdir := load Workdir Workdir->PATH;
	if(workdir == nil)
		cd := "/";
	else
		cd = workdir->init();
	# sys->print("pwd: %s\n", cd);
	return cd;
}

cleanname(s: string): string
{
	ls, path: list of string;

	if(s == nil)
		return nil;
	if(s[0] != '/' && s[0] != '\\')
		(nil, ls) = sys->tokenize(pwd(), "/\\");
	for( ; ls != nil; ls = tl ls)
		path = hd ls :: path;
	(nil, ls) = sys->tokenize(s, "/\\");
	for( ; ls != nil; ls = tl ls){
		n := hd ls;
		if(n == ".")
			;
		else if (n == ".."){
			if(path != nil)
				path = tl path;
		}
		else
			path = n :: path;
	}
	p := "";
	for( ; path != nil; path = tl path)
		p = "/" + hd path + p;
	if(p == nil)
		p = "/";
	# sys->print("cleanname: %s\n", p);
	return p;
}

srcpath(): string
{
	srcp := cleanname(infile);
	# sys->print("srcpath: %s\n", srcp);
	return srcp;
}
yyexca := array[] of {-1, 1,
	1, -1,
	-2, 0,
-1, 3,
	1, 3,
	-2, 0,
-1, 16,
	37, 93,
	48, 55,
	50, 93,
	92, 55,
	-2, 213,
-1, 189,
	55, 26,
	67, 26,
	-2, 0,
-1, 190,
	55, 34,
	67, 34,
	87, 34,
	-2, 0,
-1, 191,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 203,
	1, 2,
	-2, 0,
-1, 284,
	48, 55,
	92, 55,
	-2, 213,
-1, 285,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 324,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 331,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 355,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 371,
	48, 98,
	92, 98,
	-2, 201,
-1, 379,
	67, 230,
	92, 230,
	-2, 130,
-1, 390,
	55, 40,
	67, 40,
	-2, 0,
-1, 399,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 412,
	67, 227,
	-2, 0,
-1, 431,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 437,
	67, 124,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 452,
	52, 52,
	58, 52,
	-2, 55,
-1, 456,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 461,
	67, 127,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 465,
	68, 143,
	-2, 130,
-1, 485,
	67, 135,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 488,
	68, 142,
	81, 120,
	82, 120,
	83, 120,
	85, 120,
	86, 120,
	87, 120,
	-2, 0,
-1, 491,
	48, 55,
	52, 138,
	58, 138,
	92, 55,
	-2, 213,
};
YYNPROD: con 232;
YYPRIVATE: con 57344;
yytoknames: array of string;
yystates: array of string;
yydebug: con 0;
YYLAST:	con 2073;
yyact := array[] of {
 283, 477, 269,  44, 191, 392, 378, 380,  86, 316,
 274, 167, 376, 335,   8,  90,   4, 289,  46, 427,
  21,  98, 371, 255, 248, 105,  43,  70,  71,  72,
 326, 199,  12, 412, 350, 249, 270,  14,  73,   3,
  14, 268,   6, 200, 197,   6,  41,  29, 402, 469,
 467, 149, 150, 151, 152, 153, 154, 155, 156, 157,
 158, 159, 160, 161,  64,  10, 168, 166,  10, 100,
 482,  11, 313, 249, 325,  30, 249, 256, 249, 106,
 323, 322, 321,  39, 314, 177, 185, 180, 188, 471,
  38,  30, 430, 184, 331, 330, 329, 369, 333, 332,
 334,  33,  82, 194, 319, 368, 398, 367, 102, 352,
 340, 204, 205, 206, 207, 208, 209, 210, 211, 212,
 213, 214, 327, 216, 217, 218, 219, 220, 221, 222,
 223, 224, 225, 226, 227, 228, 229, 230, 231, 232,
 233, 234, 235, 236, 168,  14, 313, 241, 203, 187,
   6, 176, 175, 176, 175, 238,  83, 242, 309, 484,
 176, 175,  42, 243, 240, 176, 175,  24, 169,  23,
 397, 202, 448,  10, 247, 251,  22, 174, 201, 445,
 460, 176, 175, 183, 421, 176, 175, 254, 261, 440,
 257, 258,  78, 436, 176, 175,  78, 422, 285,  76,
 416, 411,  81,  76, 259, 349,  81, 288, 291,  92,
  75,  74, 365, 186,  75,  74, 295, 292,   5, 287,
  21, 425, 176, 175, 354,  85, 348,  87,  84,  88,
 100,  89,  79,  80,  77, 246,  79,  80,  77, 290,
  14, 173, 193, 192, 190,   6, 189, 168, 286, 301,
 304, 293,  18,  18,  18, 294, 487, 487, 303,  31,
 144, 414, 495, 486, 245, 307, 305, 483,  10, 102,
 103,  16,  40,  91, 104,  17,  17, 324, 312,  78,
 454, 339, 414, 168, 391,   2,  76,  13, 474,  81,
 338, 480, 337, 414, 341, 394, 426,  75,  74, 462,
 311,  96, 318, 452, 414,  18,  78, 456,   5, 346,
 438, 414, 372,  76, 385, 384,  81, 415,  89,  79,
  80,  77, 479, 103,  75,  74, 366, 104, 355, 359,
 336, 253, 252, 364, 362, 358, 239, 394, 142,  85,
 107,  87,  84,  18, 478,  93,  79,  80,  77, 379,
  20, 304, 345, 176, 175, 468, 374,  36, 168, 403,
 383,  16, 388, 344, 353,  17, 408, 351, 363, 396,
  34, 400, 401, 407, 320, 298, 379,  13, 143, 198,
 146,  94, 147, 148,  32, 153, 418, 419, 410, 347,
 145, 144, 300, 417, 162, 182, 420, 181, 163, 428,
 178, 165, 429, 164, 373, 408, 123, 124, 125, 121,
 439, 437, 435, 379, 442, 408, 444, 488, 472, 441,
 431, 343, 443, 126, 127, 123, 124, 125, 121, 450,
 453, 296,  65, 449, 458, 196, 363, 195, 465, 461,
 432, 457,  66, 459, 361, 463, 360, 357,  69,  68,
  40, 328,  67,  36,  17,  18, 121, 409, 215, 470,
 451,  27, 465,  25, 424, 266, 264, 250, 363, 473,
 273, 108,  28,   1,  26, 423, 271, 388, 317, 390,
 389, 485, 481, 476, 475,  15, 265, 489, 315, 493,
  45, 494, 263, 363, 310,   9, 153, 129, 128, 126,
 127, 123, 124, 125, 121,  47,  48,  51, 434, 433,
  54, 282, 406, 405,   7,  52,  53, 377,  58, 275,
  37,  66, 302, 237, 393, 363, 276,  69,  68, 284,
  63,  67,  97,  17,  49,  50,  57,  55,  56,  59,
 272, 395, 271,  95, 179,  13, 101,  99,  19,  35,
  78,  60,  61,  62,   0,   0,  45,  76, 277,   0,
  81,   0, 278, 279, 281, 280,   0,   0,  75,  74,
   0,  47,  48,  51,   0,   0,  54, 282,   0,   0,
   0,  52,  53,   0,  58, 275,   0,  66, 387,   0,
  79,  80,  77,  69,  68, 284,  63,  67,   0,  17,
  49,  50,  57,  55,  56,  59, 272, 356, 271,   0,
   0,  13,   0,   0,   0,   0,  78,  60,  61,  62,
   0,   0,  45,  76, 277,   0,  81,   0, 278, 279,
 281, 280,   0,   0,  75,  74,   0,  47,  48,  51,
   0,   0,  54, 282,   0, 375,   0,  52,  53,   0,
  58, 275,   0,  66,   0,   0,  79,  80,  77,  69,
  68, 284,  63,  67,   0,  17,  49,  50,  57,  55,
  56,  59, 272, 342, 271,   0,   0,  13,   0,   0,
   0,   0,  78,  60,  61,  62,   0,   0,  45,  76,
 277,   0,  81,   0, 278, 279, 281, 280,   0,   0,
  75,  74,   0,  47,  48,  51,   0,   0,  54, 282,
   0,   0,   0,  52,  53,   0,  58, 275,   0,  66,
   0,   0,  79,  80,  77,  69,  68, 284,  63,  67,
   0,  17,  49,  50,  57,  55,  56,  59, 272, 267,
 490,   0,   0,  13,   0,   0,   0,   0,   0,  60,
  61,  62,   0,   0,  45,   0, 277,   0,   0,   0,
 278, 279, 281, 280,   0,   0,   0,   0,   0,  47,
  48, 492,   0,   0,  54, 282,   0,   0,   0,  52,
  53,   0,  58, 275,   0,  66,   0,   0,   0,   0,
   0,  69,  68, 491,  63,  67,   0,  17,  49,  50,
  57,  55,  56,  59, 272, 464,   0,   0,   0,  13,
   0,   0,   0,   0,   0,  60,  61,  62,   0,  45,
   0,   0, 277,   0,   0,   0, 278, 279, 281, 280,
   0,   0,   0,   0,  47,  48, 381,   0,   0,  54,
 282,   0,   0,   0,  52,  53,   0,  58, 275,   0,
  66,   0,   0,   0,   0,   0,  69,  68, 284,  63,
  67,   0,  17,  49,  50,  57,  55,  56,  59, 272,
 271,   0,   0,   0,  13,   0,   0,   0,   0,   0,
  60,  61,  62,   0,  45,   0,   0, 277,   0,   0,
   0, 278, 279, 281, 280,   0,   0,   0,   0,  47,
  48,  51,   0,   0,  54, 282,   0,   0,   0,  52,
  53,   0,  58, 275,   0,  66,   0,   0,   0,   0,
   0,  69,  68, 284,  63,  67,   0,  17,  49,  50,
  57,  55,  56,  59, 272, 382,   0,   0,   0,   0,
   0,   0,   0,  78,   0,  60,  61,  62,   0,  45,
  76,   0, 277,  81,   0,   0, 278, 279, 281, 280,
   0,  75,  74,   0,  47,  48, 381,   0,   0,  54,
  65,   0,   0,   0,  52,  53,   0,  58, 386,   0,
  66, 387,   0,  79,  80,  77,  69,  68,  40,  63,
  67,   0,  17,  49,  50,  57,  55,  56,  59,  45,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
  60,  61,  62,   0,  47,  48,  51,   0,   0,  54,
  65,   0,   0, 244,  52,  53,   0,  58,   0,   0,
  66,   0,   0,   0,   0,   0,  69,  68,  40,  63,
  67,   0,  17,  49,  50,  57,  55,  56,  59,  45,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
  60,  61,  62,   0,  47,  48,  51,   0,   0,  54,
  65,   0,   0,   0,  52,  53,   0,  58,   0,   0,
  66,   0,   0,   0,   0,   0,  69,  68,  40,  63,
  67,   0,  17,  49,  50,  57,  55,  56,  59,   0,
   0,   0,   0,  47,  48,  51,   0,   0,  54,  65,
  60,  61,  62,  52,  53,   0,  58,   0,   0,  66,
   0,   0,   0,   0,   0,  69,  68,  40,  63,  67,
   0,  17,  49,  50,  57,  55,  56,  59,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,  60,
  61,  62, 110, 111, 112, 113, 114, 115, 116, 117,
 118, 119, 120, 122,   0, 141, 140, 139, 138, 137,
 136, 134, 135, 130, 131, 132, 133, 129, 128, 126,
 127, 123, 124, 125, 121, 140, 139, 138, 137, 136,
 134, 135, 130, 131, 132, 133, 129, 128, 126, 127,
 123, 124, 125, 121, 110, 111, 112, 113, 114, 115,
 116, 117, 118, 119, 120, 122, 455, 141, 140, 139,
 138, 137, 136, 134, 135, 130, 131, 132, 133, 129,
 128, 126, 127, 123, 124, 125, 121, 139, 138, 137,
 136, 134, 135, 130, 131, 132, 133, 129, 128, 126,
 127, 123, 124, 125, 121,   0, 110, 111, 112, 113,
 114, 115, 116, 117, 118, 119, 120, 122, 447, 141,
 140, 139, 138, 137, 136, 134, 135, 130, 131, 132,
 133, 129, 128, 126, 127, 123, 124, 125, 121, 137,
 136, 134, 135, 130, 131, 132, 133, 129, 128, 126,
 127, 123, 124, 125, 121,   0,   0,   0, 110, 111,
 112, 113, 114, 115, 116, 117, 118, 119, 120, 122,
 446, 141, 140, 139, 138, 137, 136, 134, 135, 130,
 131, 132, 133, 129, 128, 126, 127, 123, 124, 125,
 121, 136, 134, 135, 130, 131, 132, 133, 129, 128,
 126, 127, 123, 124, 125, 121,   0,   0,   0,   0,
 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
 120, 122, 370, 141, 140, 139, 138, 137, 136, 134,
 135, 130, 131, 132, 133, 129, 128, 126, 127, 123,
 124, 125, 121, 134, 135, 130, 131, 132, 133, 129,
 128, 126, 127, 123, 124, 125, 121,   0,   0,   0,
   0,   0, 110, 111, 112, 113, 114, 115, 116, 117,
 118, 119, 120, 122, 308, 141, 140, 139, 138, 137,
 136, 134, 135, 130, 131, 132, 133, 129, 128, 126,
 127, 123, 124, 125, 121, 130, 131, 132, 133, 129,
 128, 126, 127, 123, 124, 125, 121,   0,   0,   0,
   0,   0,   0,   0, 110, 111, 112, 113, 114, 115,
 116, 117, 118, 119, 120, 122, 306, 141, 140, 139,
 138, 137, 136, 134, 135, 130, 131, 132, 133, 129,
 128, 126, 127, 123, 124, 125, 121,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0, 110, 111, 112, 113,
 114, 115, 116, 117, 118, 119, 120, 122, 262, 141,
 140, 139, 138, 137, 136, 134, 135, 130, 131, 132,
 133, 129, 128, 126, 127, 123, 124, 125, 121,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0, 110, 111,
 112, 113, 114, 115, 116, 117, 118, 119, 120, 122,
 260, 141, 140, 139, 138, 137, 136, 134, 135, 130,
 131, 132, 133, 129, 128, 126, 127, 123, 124, 125,
 121,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
 120, 122, 172, 141, 140, 139, 138, 137, 136, 134,
 135, 130, 131, 132, 133, 129, 128, 126, 127, 123,
 124, 125, 121,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0, 110, 111, 112, 113, 114, 115, 116, 117,
 118, 119, 120, 122, 171, 141, 140, 139, 138, 137,
 136, 134, 135, 130, 131, 132, 133, 129, 128, 126,
 127, 123, 124, 125, 121,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0, 110, 111, 112, 113, 114, 115,
 116, 117, 118, 119, 120, 122, 170, 141, 140, 139,
 138, 137, 136, 134, 135, 130, 131, 132, 133, 129,
 128, 126, 127, 123, 124, 125, 121,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0, 110, 111, 112, 113,
 114, 115, 116, 117, 118, 119, 120, 122, 109, 141,
 140, 139, 138, 137, 136, 134, 135, 130, 131, 132,
 133, 129, 128, 126, 127, 123, 124, 125, 121,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0, 110, 111, 112, 113,
 114, 115, 116, 117, 118, 119, 120, 122, 466, 141,
 140, 139, 138, 137, 136, 134, 135, 130, 131, 132,
 133, 129, 128, 126, 127, 123, 124, 125, 121,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0, 110, 111, 112, 113,
 114, 115, 116, 117, 118, 119, 120, 122, 404, 141,
 140, 139, 138, 137, 136, 134, 135, 130, 131, 132,
 133, 129, 128, 126, 127, 123, 124, 125, 121,   0,
   0, 110, 111, 112, 113, 114, 115, 116, 117, 118,
 119, 120, 122, 413, 141, 140, 139, 138, 137, 136,
 134, 135, 130, 131, 132, 133, 129, 128, 126, 127,
 123, 124, 125, 121,   0,   0,   0, 299, 110, 111,
 112, 113, 114, 115, 116, 117, 118, 119, 120, 122,
   0, 141, 140, 139, 138, 137, 136, 134, 135, 130,
 131, 132, 133, 129, 128, 126, 127, 123, 124, 125,
 121,   0,   0,   0, 297, 110, 111, 112, 113, 114,
 115, 116, 117, 118, 119, 120, 122,   0, 141, 140,
 139, 138, 137, 136, 134, 135, 130, 131, 132, 133,
 129, 128, 126, 127, 123, 124, 125, 121,   0, 399,
 110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
 120, 122,   0, 141, 140, 139, 138, 137, 136, 134,
 135, 130, 131, 132, 133, 129, 128, 126, 127, 123,
 124, 125, 121, 141, 140, 139, 138, 137, 136, 134,
 135, 130, 131, 132, 133, 129, 128, 126, 127, 123,
 124, 125, 121,
};
yypact := array[] of {
 216,-1000, 295, 306,-1000, 108,-1000,-1000, 101,  99,
 459, 457,  -1, 202, 336, 320,-1000,-1000, 217, -46,
  94,-1000,-1000,-1000,-1000,1033,1033,1033,1033, 645,
 418,  88, 155, 207, 290, 333, 268, -13,-1000,-1000,
-1000, 285,-1000,1720,-1000, 283, 341,1072,1072,1072,
1072,1072,1072,1072,1072,1072,1072,1072,1072,1072,
 355, 360, 358,1072,-1000,1033, 416,-1000,-1000,-1000,
1668,1616,1564, 173,-1000,-1000, 645, 357, 645, 354,
 352, 416,-1000,-1000, 645,1033, 145,1033, 180, 178,
-1000,-1000, 176,-1000, 645, 399, 397, -48,-1000, 331,
 -17, -49,-1000,-1000,-1000,-1000, 217,-1000, 306,-1000,
1033,1033,1033,1033,1033,1033,1033,1033,1033,1033,
1033, 454,1033,1033,1033,1033,1033,1033,1033,1033,
1033,1033,1033,1033,1033,1033,1033,1033,1033,1033,
1033,1033,1033,1033, 281, 395,1033,-1000,-1000,-1000,
-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,-1000,
-1000,-1000, 983, 208, 169, 645,-1000, -14,2016,-1000,
-1000,-1000,-1000,-1000,1033, 277, 276, 304, 645, -15,
 304, 645, 645,-1000, 136,1512,-1000,1033,1460, 464,
 463, 672,-1000,-1000, 304,-1000,-1000, 215, 159, 159,
 196,-1000,-1000, 306,2016,2016,2016,2016,2016,2016,
2016,2016,2016,2016,2016,1033,2016, 420, 420, 420,
 373, 373, 392, 392, 468, 468, 468, 468,1420,1420,
1370,1319,1268,1218,1218,1167,2036, 393, -57,-1000,
 210,1944, 327,1907, 349,1072,1033, 304,-1000,1033,
 207,1408,-1000,-1000, 304,-1000, 645, 304, 304,-1000,
-1000,1356,-1000,  91,-1000,  17,-1000,-1000,-1000,-1000,
 326,  14,-1000, -18,  54, 414,  13, 275, 275,1033,
1033,  42,1033,2016,-1000, 606, 383,-1000, 304,-1000,
 308, 304,-1000,-1000,-1000,2016,-1000,-1000,1033, 346,
 160,-1000, 138, -58,2016,-1000,-1000, 304,-1000,-1000,
-1000, 319,  41,-1000,-1000,-1000,-1000,-1000, 316, 158,
 269,-1000,-1000,-1000, 540, 410, 645,-1000,1033, 409,
 407, 868,1033, 146, 271,  39,-1000,  37,  29,1304,
-1000, -16,-1000,-1000,-1000, 257, 364, 579, 933,-1000,
1033, 242,-1000, 906, 282, 474,-1000,1033, 102,1981,
1033,1033, -34, 311,1822, 933, 442,-1000,-1000,-1000,
-1000,-1000,-1000,-1000, 304, 933, 134, -59,-1000,1872,
 259,1072,-1000, 132, 645,1033,1033, 645, 116, 130,
 462,-1000, 163, 244,-1000,-1000, -19,-1000,1033, 868,
  24, 382, 403,-1000, 933, 126,-1000, 252,1872,1033,
 122,-1000, 933,1033, 933,1033,-1000, 111,1252,1200,
 104,-1000,-1000, 248, 240,-1000, 225,-1000,1148, 261,
1033, 868,1033, 113,-1000, 241,-1000, 803,-1000,1772,
-1000,-1000,2016,-1000,2016,-1000,-1000,-1000,-1000,-1000,
  -8, 307,-1000,  -9,-1000,-1000, 868,  21,-1000, 380,
-1000, 803,-1000, 230,  14,1872, 289,-1000, 513,-1000,
-1000,1033,   2, 209,-1000,  92,-1000, 205,-1000,-1000,
-1000, 379,-1000,-1000,-1000, 738,-1000, 289, 868, 204,
  14,-1000,1072,-1000,-1000,-1000,
};
yypgo := array[] of {
   0,   8, 549, 101,  17,  36, 548, 547, 546, 544,
 543, 532,  21, 526,  13,   5, 524,  10,   0,   3,
  18,  11, 523, 522,  64,  32,  71, 520,  12, 517,
   6,   7,  41,  39,  16, 514,  15,   2,   4, 513,
 512, 509, 508, 495,  14, 494, 492, 488, 486, 485,
 484, 483,   1, 480, 479, 478,   9, 475, 473, 471,
 470, 467,
};
yyr1 := array[] of {
   0,  59,  58,  58,  33,  33,  34,  34,  34,  34,
  34,  34,  34,  34,  34,  34,  34,  25,  25,  32,
  32,  32,  32,  32,  32,  43,  46,  46,  46,  45,
  45,  45,  45,  44,  48,  48,  48,  47,  47,  47,
  57,  57,  56,  56,  55,  53,  53,  53,  54,  54,
  54,  15,  16,  16,   5,   6,   6,   1,   1,   1,
   1,   1,   1,   1,   1,   1,   1,   9,   9,   2,
   2,   2,   3,   3,  10,  10,  11,  11,  12,  12,
  12,  12,   7,   8,   8,   8,   8,   4,   4,  35,
  36,  36,  36,  49,  49,  38,  38,  38,  60,  60,
  37,  37,  37,  37,  37,  37,  37,  37,  37,  37,
  37,  37,  37,  37,  37,  37,  37,  37,  37,  37,
  13,  13,  14,  14,  39,  40,  40,  41,  42,  42,
  31,  31,  31,  31,  31,  50,  51,  51,  52,  52,
  52,  52,  17,  17,  18,  18,  18,  18,  18,  18,
  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,
  18,  18,  18,  18,  18,  18,  18,  18,  18,  18,
  18,  18,  18,  18,  18,  18,  18,  18,  19,  19,
  19,  19,  19,  19,  19,  19,  19,  19,  19,  19,
  19,  19,  19,  19,  19,  19,  19,  19,  19,  20,
  20,  20,  61,  20,  20,  20,  20,  20,  20,  20,
  20,  20,  20,  24,  24,  26,  27,  27,  27,  27,
  22,  22,  23,  23,  21,  21,  28,  28,  29,  29,
  30,  30,
};
yyr2 := array[] of {
   0,   0,   5,   1,   1,   2,   2,   1,   1,   2,
   2,   4,   4,   4,   4,   4,   6,   1,   3,   3,
   5,   5,   4,   6,   5,   6,   0,   2,   1,   4,
   2,   5,   5,   6,   0,   2,   1,   1,   1,   5,
   0,   2,   5,   4,   4,   2,   2,   1,   2,   4,
   4,   1,   1,   3,   1,   1,   3,   1,   1,   3,
   3,   2,   3,   3,   3,   3,   2,   1,   3,   3,
   3,   5,   1,   3,   0,   1,   1,   3,   3,   3,
   3,   3,   1,   1,   1,   3,   3,   2,   3,   3,
   3,   2,   4,   1,   3,   0,   2,   2,   3,   5,
   2,   2,   4,   3,   4,   6,   2,   5,   7,  10,
   6,   8,   3,   3,   3,   3,   6,   5,   8,   2,
   0,   2,   0,   1,   2,   2,   4,   2,   2,   4,
   1,   3,   1,   3,   1,   2,   2,   4,   1,   1,
   3,   1,   0,   1,   1,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   4,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   1,   2,
   2,   2,   2,   2,   2,   2,   2,   2,   2,   2,
   2,   2,   6,   8,   7,   5,   3,   4,   2,   1,
   4,   3,   0,   4,   3,   3,   4,   6,   2,   2,
   1,   1,   1,   1,   1,   3,   1,   1,   3,   3,
   0,   1,   1,   2,   1,   3,   1,   2,   1,   3,
   1,   3,
};
yychk := array[] of {
-1000, -58,  69, -33, -34,   2, -32, -35, -44, -43,
 -24, -26, -25,  71,  -5, -49,  55,  59,  37,  -6,
  55, -34,  68,  68,  68,   4,  15,   4,  15,  48,
  92,  57,  48,  -3,  50,  -2,  37, -27, -26, -24,
  55,  92,  68, -18, -19,  16, -20,  31,  32,  60,
  61,  33,  41,  42,  36,  63,  64,  62,  44,  65,
  77,  78,  79,  56, -24,  37,  47,  57,  54,  53,
 -18, -18, -18,  -1,  56,  55,  44,  79,  37,  77,
  78,  47, -26,  68,  73,  70,  -1,  72,  74,  76,
 -36,  66,   2,  55,  48, -10,  33, -11, -12,  -7,
 -25,  -8, -26,  55,  59,  38,  92,  55, -59,  68,
   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,
  14,  36,  15,  33,  34,  35,  31,  32,  30,  29,
  25,  26,  27,  28,  23,  24,  22,  21,  20,  19,
  18,  17,  55,  37,  50,  49,  39,  41,  42, -19,
 -19, -19, -19, -19, -19, -19, -19, -19, -19, -19,
 -19, -19,  39,  43,  43,  43, -19, -21, -18,  -3,
  68,  68,  68,  68,   4,  50,  49,  -1,  43,  -9,
  -1,  43,  43,  -3,  -1, -18,  68,   4, -18,  66,
  66, -38,  67,  66,  -1,  38,  38,  92,  48,  48,
  92, -26, -24, -33, -18, -18, -18, -18, -18, -18,
 -18, -18, -18, -18, -18,   4, -18, -18, -18, -18,
 -18, -18, -18, -18, -18, -18, -18, -18, -18, -18,
 -18, -18, -18, -18, -18, -18, -18, -22, -21,  55,
 -20, -18, -17, -18,  40,  56,  66,  -1,  38,  92,
 -61, -18,  55,  55,  -1,  38,  92,  -1,  -1,  68,
  68, -18,  68, -46,   2, -48,   2,  67, -32, -37,
  -5,   2,  66, -60, -17,  45, -13,  84,  88,  89,
  91,  90,  37, -18,  55, -38,  33, -12,  -1,  -4,
  80,  -1,  -4,  55,  59, -18,  38,  40,  48,  40,
  43, -19, -23, -21, -18, -36,  68,  -1,  68,  67,
 -45,  -5, -44,  55,  67, -47, -56, -55,  -5,  87,
  48,  68,  67,  66, -38,  92,  48,  68,  37,  83,
  82,  81,  86,  85,  87, -14,  55, -14, -17, -18,
  68, -21,  67,  38,  55,  44, -17,  43,  66,  67,
  92,  48,  68,  48,  66, -38,  67,  37,  -1, -18,
  37,  37, -37,  -5, -18,  66,  55,  68,  68,  68,
  68,  38,  55,  40,  -1,  66, -28, -29, -30, -18,
 -31,  33,   2,  -1,  73,  72,  72,  75,  -1, -53,
 -54,   2, -15, -16,  55,  67, -21,  68,   4,  38,
 -17, -17,  82,  48,  66, -39, -40, -31, -18,  15,
 -28,  67,  92,  51,  52,  58,  68,  -1, -18, -18,
  -1,  68,  67, -57,   2,  58,  52,  38, -18, -37,
  68,  38,  37, -41, -42, -31,  67, -38,  58, -18,
  67, -30, -18, -31, -18,  68,  68,  68,  68, -56,
 -15,  -5,  55, -15,  55,  68,  46, -17, -37, -17,
  67, -38,  58, -31,   2, -18,  66,  58,  48,  58,
 -37,  68,  38, -31,  58, -50, -51, -52,  55,  33,
   2, -17,  68,  58,  67, -38,  58,  52,  38, -52,
   2,  55,  33, -52, -37,  58,
};
yydef := array[] of {
   0,  -2,   0,  -2,   4,   0,   7,   8,   0,   0,
   0,  17,   0,   0,   0,   0,  -2, 214,   0,  54,
   0,   5,   6,   9,  10,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,  72,  74,   0, 216, 217,
 213,   0,   1,   0, 144,   0, 178,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0, 199,   0,   0, 210, 211, 212,
   0,   0,   0,   0,  57,  58,   0,   0,   0,   0,
   0,   0,  18,  19,   0,   0,   0,   0,   0,   0,
  89,  95,   0,  94,   0,   0,   0,  75,  76,   0,
   0,  82,  17,  83,  84, 215,   0,  56,   0,  11,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
   0,   0,   0, 220,   0,   0, 142, 208, 209, 179,
 180, 181, 182, 183, 184, 185, 186, 187, 188, 189,
 190, 191,   0,   0,   0,   0, 198,   0, 224, 202,
  13,  12,  14,  15,   0,   0,   0,  61,   0,   0,
  67,   0,   0,  66,   0,   0,  22,   0,   0,  -2,
  -2,  -2,  91,  95,  73,  69,  70,   0,   0,   0,
   0, 218, 219,  -2, 145, 146, 147, 148, 149, 150,
 151, 152, 153, 154, 155,   0, 157, 159, 160, 161,
 162, 163, 164, 165, 166, 167, 168, 169, 170, 171,
 172, 173, 174, 175, 176, 177, 158,   0, 221, 204,
 205, 143,   0,   0,   0,   0,   0, 196, 201,   0,
   0,   0,  59,  60,  62,  63,   0,  64,  65,  20,
  21,   0,  24,   0,  28,   0,  36,  90,  96,  97,
   0,   0,  95,   0,   0,   0,   0, 122, 122, 142,
   0,   0,   0, 143,  -2,  -2,   0,  77,  78,  79,
   0,  80,  81,  85,  86, 156, 200, 206, 142,   0,
   0, 197,   0, 222, 225, 203,  16,  68,  23,  25,
  27,   0,   0,  55,  33,  35,  37,  38,   0,   0,
 121, 100, 101,  95,  -2,   0,   0, 106,   0,   0,
   0,  -2,   0,   0,   0,   0, 123,   0,   0,   0,
 119,   0,  92,  71,  87,   0,   0,   0,   0, 195,
 223,   0,  30,   0,   0,  -2, 103,   0,   0,   0,
 142, 142,   0,   0,   0,   0,   0, 112, 113, 114,
 115,  -2,  88, 207, 192,   0,   0, 226, 228,  -2,
   0, 132, 134,   0,   0,   0,   0,   0,   0,   0,
  -2,  47,   0,  51,  52, 102,   0, 104,   0,  -2,
   0,   0,   0, 121,   0,   0,  95,   0, 130,   0,
   0, 194,  -2,   0,   0,   0,  29,   0,   0,   0,
   0,  43,  44,  45,  46,  48,   0,  99,   0, 107,
 142,  -2, 142,   0,  95,   0, 117,  -2, 125,   0,
 193, 229, 131, 133, 231,  31,  32,  39,  42,  41,
   0,   0,  -2,   0,  53, 105,  -2,   0, 110,   0,
 116,  -2, 128,   0, 134,  -2,   0,  49,   0,  50,
 108, 142,   0,   0, 126,   0,  95,   0, 138, 139,
 141,   0, 111, 129, 118,  -2, 136,   0,  -2,   0,
 141,  -2, 139, 140, 109, 137,
};
yytok1 := array[] of {
   1,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,  60,   3,   3,   3,  35,  22,   3,
  37,  38,  33,  31,  92,  32,  50,  34,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,  48,  68,
  25,   4,  26,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,  39,   3,  40,  21,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,   3,   3,   3,   3,   3,   3,   3,
   3,   3,   3,  66,  20,  67,  61,
};
yytok2 := array[] of {
   2,   3,   5,   6,   7,   8,   9,  10,  11,  12,
  13,  14,  15,  16,  17,  18,  19,  23,  24,  27,
  28,  29,  30,  36,  41,  42,  43,  44,  45,  46,
  47,  49,  51,  52,  53,  54,  55,  56,  57,  58,
  59,  62,  63,  64,  65,  69,  70,  71,  72,  73,
  74,  75,  76,  77,  78,  79,  80,  81,  82,  83,
  84,  85,  86,  87,  88,  89,  90,  91,
};
yytok3 := array[] of {
   0
};

YYSys: module
{
	FD: adt
	{
		fd:	int;
	};
	fildes:		fn(fd: int): ref FD;
	fprint:		fn(fd: ref FD, s: string, *): int;
};

yysys: YYSys;
yystderr: ref YYSys->FD;

YYFLAG: con -1000;

# parser for yacc output

yytokname(yyc: int): string
{
	if(yyc > 0 && yyc <= len yytoknames && yytoknames[yyc-1] != nil)
		return yytoknames[yyc-1];
	return "<"+string yyc+">";
}

yystatname(yys: int): string
{
	if(yys >= 0 && yys < len yystates && yystates[yys] != nil)
		return yystates[yys];
	return "<"+string yys+">\n";
}

yylex1(yylex: ref YYLEX): int
{
	c : int;
	yychar := yylex.lex();
	if(yychar <= 0)
		c = yytok1[0];
	else if(yychar < len yytok1)
		c = yytok1[yychar];
	else if(yychar >= YYPRIVATE && yychar < YYPRIVATE+len yytok2)
		c = yytok2[yychar-YYPRIVATE];
	else{
		n := len yytok3;
		c = 0;
		for(i := 0; i < n; i+=2) {
			if(yytok3[i+0] == yychar) {
				c = yytok3[i+1];
				break;
			}
		}
		if(c == 0)
			c = yytok2[1];	# unknown char
	}
	if(yydebug >= 3)
		yysys->fprint(yystderr, "lex %.4ux %s\n", yychar, yytokname(c));
	return c;
}

YYS: adt
{
	yyv: YYSTYPE;
	yys: int;
};

yyparse(yylex: ref YYLEX): int
{
	if(yydebug >= 1 && yysys == nil) {
		yysys = load YYSys "$Sys";
		yystderr = yysys->fildes(2);
	}

	yys := array[YYMAXDEPTH] of YYS;

	yyval: YYSTYPE;
	yystate := 0;
	yychar := -1;
	yynerrs := 0;		# number of errors
	yyerrflag := 0;		# error recovery flag
	yyp := -1;
	yyn := 0;

yystack:
	for(;;){
		# put a state and value onto the stack
		if(yydebug >= 4)
			yysys->fprint(yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));

		yyp++;
		if(yyp >= YYMAXDEPTH) {
			yylex.error("yacc stack overflow");
			yyn = 1;
			break yystack;
		}
		yys[yyp].yys = yystate;
		yys[yyp].yyv = yyval;

		for(;;){
			yyn = yypact[yystate];
			if(yyn > YYFLAG) {	# simple state
				if(yychar < 0)
					yychar = yylex1(yylex);
				yyn += yychar;
				if(yyn >= 0 && yyn < YYLAST) {
					yyn = yyact[yyn];
					if(yychk[yyn] == yychar) { # valid shift
						yychar = -1;
						yyp++;
						if(yyp >= YYMAXDEPTH) {
							yylex.error("yacc stack overflow");
							yyn = 1;
							break yystack;
						}
						yystate = yyn;
						yys[yyp].yys = yystate;
						yys[yyp].yyv = yylex.lval;
						if(yyerrflag > 0)
							yyerrflag--;
						if(yydebug >= 4)
							yysys->fprint(yystderr, "char %s in %s", yytokname(yychar), yystatname(yystate));
						continue;
					}
				}
			}
		
			# default state action
			yyn = yydef[yystate];
			if(yyn == -2) {
				if(yychar < 0)
					yychar = yylex1(yylex);
		
				# look through exception table
				for(yyxi:=0;; yyxi+=2)
					if(yyexca[yyxi] == -1 && yyexca[yyxi+1] == yystate)
						break;
				for(yyxi += 2;; yyxi += 2) {
					yyn = yyexca[yyxi];
					if(yyn < 0 || yyn == yychar)
						break;
				}
				yyn = yyexca[yyxi+1];
				if(yyn < 0){
					yyn = 0;
					break yystack;
				}
			}

			if(yyn != 0)
				break;

			# error ... attempt to resume parsing
			if(yyerrflag == 0) { # brand new error
				yylex.error("syntax error");
				yynerrs++;
				if(yydebug >= 1) {
					yysys->fprint(yystderr, "%s", yystatname(yystate));
					yysys->fprint(yystderr, "saw %s\n", yytokname(yychar));
				}
			}

			if(yyerrflag != 3) { # incompletely recovered error ... try again
				yyerrflag = 3;
	
				# find a state where "error" is a legal shift action
				while(yyp >= 0) {
					yyn = yypact[yys[yyp].yys] + YYERRCODE;
					if(yyn >= 0 && yyn < YYLAST) {
						yystate = yyact[yyn];  # simulate a shift of "error"
						if(yychk[yystate] == YYERRCODE)
							continue yystack;
					}
	
					# the current yyp has no shift onn "error", pop stack
					if(yydebug >= 2)
						yysys->fprint(yystderr, "error recovery pops state %d, uncovers %d\n",
							yys[yyp].yys, yys[yyp-1].yys );
					yyp--;
				}
				# there is no state on the stack with an error shift ... abort
				yyn = 1;
				break yystack;
			}

			# no shift yet; clobber input char
			if(yydebug >= 2)
				yysys->fprint(yystderr, "error recovery discards %s\n", yytokname(yychar));
			if(yychar == YYEOFCODE) {
				yyn = 1;
				break yystack;
			}
			yychar = -1;
			# try again in the same state
		}
	
		# reduction by production yyn
		if(yydebug >= 2)
			yysys->fprint(yystderr, "reduce %d in:\n\t%s", yyn, yystatname(yystate));
	
		yypt := yyp;
		yyp -= yyr2[yyn];
#		yyval = yys[yyp+1].yyv;
		yym := yyn;
	
		# consult goto table to find next state
		yyn = yyr1[yyn];
		yyg := yypgo[yyn];
		yyj := yyg + yys[yyp].yys + 1;
	
		if(yyj >= YYLAST || yychk[yystate=yyact[yyj]] != -yyn)
			yystate = yyact[yyg];
		case yym {
			
1=>
#line	141	"limbo.y"
{
		impmod = yys[yypt-1].yyv.tok.v.idval;
	}
2=>
#line	144	"limbo.y"
{
		tree = rotater(yys[yypt-0].yyv.node);
	}
3=>
#line	148	"limbo.y"
{
		impmod = nil;
		tree = rotater(yys[yypt-0].yyv.node);
	}
4=>
yyval.node = yys[yyp+1].yyv.node;
5=>
#line	156	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil)
			yyval.node = yys[yypt-0].yyv.node;
		else if(yys[yypt-0].yyv.node == nil)
			yyval.node = yys[yypt-1].yyv.node;
		else
			yyval.node = mkbin(Oseq, yys[yypt-1].yyv.node, yys[yypt-0].yyv.node);
	}
6=>
#line	167	"limbo.y"
{
		yyval.node = nil;
	}
7=>
yyval.node = yys[yyp+1].yyv.node;
8=>
yyval.node = yys[yyp+1].yyv.node;
9=>
yyval.node = yys[yyp+1].yyv.node;
10=>
yyval.node = yys[yyp+1].yyv.node;
11=>
#line	175	"limbo.y"
{
		yyval.node = mkbin(Oas, yys[yypt-3].yyv.node, yys[yypt-1].yyv.node);
	}
12=>
#line	179	"limbo.y"
{
		yyval.node = mkbin(Oas, yys[yypt-3].yyv.node, yys[yypt-1].yyv.node);
	}
13=>
#line	183	"limbo.y"
{
		yyval.node = mkbin(Odas, yys[yypt-3].yyv.node, yys[yypt-1].yyv.node);
	}
14=>
#line	187	"limbo.y"
{
		yyval.node = mkbin(Odas, yys[yypt-3].yyv.node, yys[yypt-1].yyv.node);
	}
15=>
#line	191	"limbo.y"
{
		yyerror("illegal declaration");
		yyval.node = nil;
	}
16=>
#line	196	"limbo.y"
{
		yyerror("illegal declaration");
		yyval.node = nil;
	}
17=>
yyval.node = yys[yyp+1].yyv.node;
18=>
#line	204	"limbo.y"
{
		yyval.node = mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
19=>
#line	210	"limbo.y"
{
		includef(yys[yypt-1].yyv.tok.v.idval);
		yyval.node = nil;
	}
20=>
#line	215	"limbo.y"
{
		yyval.node = typedecl(yys[yypt-4].yyv.ids, yys[yypt-1].yyv.ty);
	}
21=>
#line	219	"limbo.y"
{
		yyval.node = importdecl(yys[yypt-1].yyv.node, yys[yypt-4].yyv.ids);
		yyval.node.src.start = yys[yypt-4].yyv.ids.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
22=>
#line	225	"limbo.y"
{
		yyval.node = vardecl(yys[yypt-3].yyv.ids, yys[yypt-1].yyv.ty);
	}
23=>
#line	229	"limbo.y"
{
		yyval.node = mkbin(Ovardecli, vardecl(yys[yypt-5].yyv.ids, yys[yypt-3].yyv.ty), varinit(yys[yypt-5].yyv.ids, yys[yypt-1].yyv.node));
	}
24=>
#line	233	"limbo.y"
{
		yyval.node = condecl(yys[yypt-4].yyv.ids, yys[yypt-1].yyv.node);
	}
25=>
#line	239	"limbo.y"
{
		yys[yypt-5].yyv.ids.src.stop = yys[yypt-0].yyv.tok.src.stop;
		yyval.node = moddecl(yys[yypt-5].yyv.ids, rotater(yys[yypt-1].yyv.node));
	}
26=>
#line	246	"limbo.y"
{
		yyval.node = nil;
	}
27=>
#line	250	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil)
			yyval.node = yys[yypt-0].yyv.node;
		else if(yys[yypt-0].yyv.node == nil)
			yyval.node = yys[yypt-1].yyv.node;
		else
			yyval.node = mkn(Oseq, yys[yypt-1].yyv.node, yys[yypt-0].yyv.node);
	}
28=>
#line	259	"limbo.y"
{
		yyval.node = nil;
	}
29=>
#line	265	"limbo.y"
{
		yyval.node = fielddecl(Dglobal, typeids(yys[yypt-3].yyv.ids, yys[yypt-1].yyv.ty));
	}
30=>
yyval.node = yys[yyp+1].yyv.node;
31=>
#line	270	"limbo.y"
{
		yyval.node = typedecl(yys[yypt-4].yyv.ids, yys[yypt-1].yyv.ty);
	}
32=>
#line	274	"limbo.y"
{
		yyval.node = condecl(yys[yypt-4].yyv.ids, yys[yypt-1].yyv.node);
	}
33=>
#line	280	"limbo.y"
{
		yys[yypt-5].yyv.ids.src.stop = yys[yypt-0].yyv.tok.src.stop;
		yyval.node = adtdecl(yys[yypt-5].yyv.ids, rotater(yys[yypt-1].yyv.node));
	}
34=>
#line	287	"limbo.y"
{
		yyval.node = nil;
	}
35=>
#line	291	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil)
			yyval.node = yys[yypt-0].yyv.node;
		else if(yys[yypt-0].yyv.node == nil)
			yyval.node = yys[yypt-1].yyv.node;
		else
			yyval.node = mkn(Oseq, yys[yypt-1].yyv.node, yys[yypt-0].yyv.node);
	}
36=>
#line	300	"limbo.y"
{
		yyval.node = nil;
	}
37=>
yyval.node = yys[yyp+1].yyv.node;
38=>
yyval.node = yys[yyp+1].yyv.node;
39=>
#line	308	"limbo.y"
{
		yyval.node = condecl(yys[yypt-4].yyv.ids, yys[yypt-1].yyv.node);
	}
40=>
#line	314	"limbo.y"
{
		yyval.node = nil;
	}
41=>
#line	318	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil)
			yyval.node = yys[yypt-0].yyv.node;
		else if(yys[yypt-0].yyv.node == nil)
			yyval.node = yys[yypt-1].yyv.node;
		else
			yyval.node = mkn(Oseq, yys[yypt-1].yyv.node, yys[yypt-0].yyv.node);
	}
42=>
#line	329	"limbo.y"
{
		for(d := yys[yypt-4].yyv.ids; d != nil; d = d.next)
			d.cyc = byte 1;
		yyval.node = fielddecl(Dfield, typeids(yys[yypt-4].yyv.ids, yys[yypt-1].yyv.ty));
	}
43=>
#line	335	"limbo.y"
{
		yyval.node = fielddecl(Dfield, typeids(yys[yypt-3].yyv.ids, yys[yypt-1].yyv.ty));
	}
44=>
#line	341	"limbo.y"
{
		yyval.node = yys[yypt-1].yyv.node;
	}
45=>
#line	347	"limbo.y"
{
		yys[yypt-1].yyv.node.right.right = yys[yypt-0].yyv.node;
		yyval.node = yys[yypt-1].yyv.node;
	}
46=>
#line	352	"limbo.y"
{
		yyval.node = nil;
	}
47=>
#line	356	"limbo.y"
{
		yyval.node = nil;
	}
48=>
#line	362	"limbo.y"
{
		yyval.node = mkn(Opickdecl, nil, mkn(Oseq, fielddecl(Dtag, yys[yypt-1].yyv.ids), nil));
		typeids(yys[yypt-1].yyv.ids, mktype(yys[yypt-1].yyv.ids.src.start, yys[yypt-1].yyv.ids.src.stop, Tadtpick, nil, nil));
	}
49=>
#line	367	"limbo.y"
{
		yys[yypt-3].yyv.node.right.right = yys[yypt-2].yyv.node;
		yyval.node = mkn(Opickdecl, yys[yypt-3].yyv.node, mkn(Oseq, fielddecl(Dtag, yys[yypt-1].yyv.ids), nil));
		typeids(yys[yypt-1].yyv.ids, mktype(yys[yypt-1].yyv.ids.src.start, yys[yypt-1].yyv.ids.src.stop, Tadtpick, nil, nil));
	}
50=>
#line	373	"limbo.y"
{
		yyval.node = mkn(Opickdecl, nil, mkn(Oseq, fielddecl(Dtag, yys[yypt-1].yyv.ids), nil));
		typeids(yys[yypt-1].yyv.ids, mktype(yys[yypt-1].yyv.ids.src.start, yys[yypt-1].yyv.ids.src.stop, Tadtpick, nil, nil));
	}
51=>
#line	380	"limbo.y"
{
		yyval.ids = revids(yys[yypt-0].yyv.ids);
	}
52=>
#line	386	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval, nil, nil);
	}
53=>
#line	390	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval, nil, yys[yypt-2].yyv.ids);
	}
54=>
#line	396	"limbo.y"
{
		yyval.ids = revids(yys[yypt-0].yyv.ids);
	}
55=>
#line	402	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval, nil, nil);
	}
56=>
#line	406	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval, nil, yys[yypt-2].yyv.ids);
	}
57=>
#line	412	"limbo.y"
{
		yyval.ty = mkidtype(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval);
	}
58=>
#line	416	"limbo.y"
{
		yyval.ty = mkidtype(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval);
	}
59=>
#line	420	"limbo.y"
{
		yyval.ty = mkdottype(yys[yypt-2].yyv.ty.src.start, yys[yypt-0].yyv.tok.src.stop, yys[yypt-2].yyv.ty, yys[yypt-0].yyv.tok.v.idval);
	}
60=>
#line	424	"limbo.y"
{
		yyval.ty = mkarrowtype(yys[yypt-2].yyv.ty.src.start, yys[yypt-0].yyv.tok.src.stop, yys[yypt-2].yyv.ty, yys[yypt-0].yyv.tok.v.idval);
	}
61=>
#line	428	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-1].yyv.tok.src.start, yys[yypt-0].yyv.ty.src.stop, Tref, yys[yypt-0].yyv.ty, nil);
	}
62=>
#line	432	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-2].yyv.tok.src.start, yys[yypt-0].yyv.ty.src.stop, Tchan, yys[yypt-0].yyv.ty, nil);
	}
63=>
#line	436	"limbo.y"
{
		if(yys[yypt-1].yyv.ids.next == nil)
			yyval.ty = yys[yypt-1].yyv.ids.ty;
		else
			yyval.ty = mktype(yys[yypt-2].yyv.tok.src.start, yys[yypt-0].yyv.tok.src.stop, Ttuple, nil, revids(yys[yypt-1].yyv.ids));
	}
64=>
#line	443	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-2].yyv.tok.src.start, yys[yypt-0].yyv.ty.src.stop, Tarray, yys[yypt-0].yyv.ty, nil);
	}
65=>
#line	447	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-2].yyv.tok.src.start, yys[yypt-0].yyv.ty.src.stop, Tlist, yys[yypt-0].yyv.ty, nil);
	}
66=>
#line	451	"limbo.y"
{
		yys[yypt-0].yyv.ty.src.start = yys[yypt-1].yyv.tok.src.start;
		yyval.ty = yys[yypt-0].yyv.ty;
	}
67=>
#line	458	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.ty.src, nil, yys[yypt-0].yyv.ty, nil);
	}
68=>
#line	462	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-2].yyv.ids.src, nil, yys[yypt-0].yyv.ty, yys[yypt-2].yyv.ids);
	}
69=>
#line	468	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-2].yyv.tok.src.start, yys[yypt-0].yyv.tok.src.stop, Tfn, tnone, yys[yypt-1].yyv.ids);
	}
70=>
#line	472	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-2].yyv.tok.src.start, yys[yypt-0].yyv.tok.src.stop, Tfn, tnone, nil);
		yyval.ty.varargs = byte 1;
	}
71=>
#line	477	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-4].yyv.tok.src.start, yys[yypt-0].yyv.tok.src.stop, Tfn, tnone, yys[yypt-3].yyv.ids);
		yyval.ty.varargs = byte 1;
	}
72=>
yyval.ty = yys[yyp+1].yyv.ty;
73=>
#line	485	"limbo.y"
{
		yys[yypt-2].yyv.ty.tof = yys[yypt-0].yyv.ty;
		yys[yypt-2].yyv.ty.src.stop = yys[yypt-0].yyv.ty.src.stop;
		yyval.ty = yys[yypt-2].yyv.ty;
	}
74=>
#line	493	"limbo.y"
{
		yyval.ids = nil;
	}
75=>
yyval.ids = yys[yyp+1].yyv.ids;
76=>
yyval.ids = yys[yyp+1].yyv.ids;
77=>
#line	501	"limbo.y"
{
		yyval.ids = appdecls(yys[yypt-2].yyv.ids, yys[yypt-0].yyv.ids);
	}
78=>
#line	507	"limbo.y"
{
		yyval.ids = typeids(yys[yypt-2].yyv.ids, yys[yypt-0].yyv.ty);
	}
79=>
#line	511	"limbo.y"
{
		yyval.ids = typeids(yys[yypt-2].yyv.ids, yys[yypt-0].yyv.ty);
		for(d := yyval.ids; d != nil; d = d.next)
			d.implicit = byte 1;
	}
80=>
#line	517	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-2].yyv.node.src, enter("junk", 0), yys[yypt-0].yyv.ty, nil);
		yyval.ids.store = Darg;
		yyerror("illegal argument declaraion");
	}
81=>
#line	523	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-2].yyv.node.src, enter("junk", 0), yys[yypt-0].yyv.ty, nil);
		yyval.ids.store = Darg;
		yyerror("illegal argument declaraion");
	}
82=>
#line	531	"limbo.y"
{
		yyval.ids = revids(yys[yypt-0].yyv.ids);
	}
83=>
#line	537	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval, nil, nil);
		yyval.ids.store = Darg;
	}
84=>
#line	542	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, nil, nil, nil);
		yyval.ids.store = Darg;
	}
85=>
#line	547	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval, nil, yys[yypt-2].yyv.ids);
		yyval.ids.store = Darg;
	}
86=>
#line	552	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, nil, nil, yys[yypt-2].yyv.ids);
		yyval.ids.store = Darg;
	}
87=>
#line	559	"limbo.y"
{
		yyval.ty = mkidtype(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval);
	}
88=>
#line	563	"limbo.y"
{
		yyval.ty = mktype(yys[yypt-1].yyv.tok.src.start, yys[yypt-0].yyv.tok.src.stop, Tref, mkidtype(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval), nil);
	}
89=>
#line	569	"limbo.y"
{
		yyval.node = fndecl(yys[yypt-2].yyv.node, yys[yypt-1].yyv.ty, yys[yypt-0].yyv.node);
		nfns++;
		yyval.node.src = yys[yypt-2].yyv.node.src;
	}
90=>
#line	577	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil){
			yys[yypt-1].yyv.node = mkn(Onothing, nil, nil);
			yys[yypt-1].yyv.node.src.start = curline();
			yys[yypt-1].yyv.node.src.stop = yys[yypt-1].yyv.node.src.start;
		}
		yyval.node = rotater(yys[yypt-1].yyv.node);
		yyval.node.src.start = yys[yypt-2].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
91=>
#line	588	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
	}
92=>
#line	592	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
	}
93=>
#line	598	"limbo.y"
{
		yyval.node = mkname(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval);
	}
94=>
#line	602	"limbo.y"
{
		yyval.node = mkbin(Odot, yys[yypt-2].yyv.node, mkname(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval));
	}
95=>
#line	608	"limbo.y"
{
		yyval.node = nil;
	}
96=>
#line	612	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil)
			yyval.node = yys[yypt-0].yyv.node;
		else if(yys[yypt-0].yyv.node == nil)
			yyval.node = yys[yypt-1].yyv.node;
		else
			yyval.node = mkbin(Oseq, yys[yypt-1].yyv.node, yys[yypt-0].yyv.node);
	}
97=>
#line	621	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil)
			yyval.node = yys[yypt-0].yyv.node;
		else
			yyval.node = mkbin(Oseq, yys[yypt-1].yyv.node, yys[yypt-0].yyv.node);
	}
100=>
#line	634	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
101=>
#line	640	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
102=>
#line	646	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
103=>
#line	652	"limbo.y"
{
		if(yys[yypt-1].yyv.node == nil){
			yys[yypt-1].yyv.node = mkn(Onothing, nil, nil);
			yys[yypt-1].yyv.node.src.start = curline();
			yys[yypt-1].yyv.node.src.stop = yys[yypt-1].yyv.node.src.start;
		}
		yyval.node = mkscope(rotater(yys[yypt-1].yyv.node));
	}
104=>
#line	661	"limbo.y"
{
		yyerror("illegal declaration");
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
105=>
#line	668	"limbo.y"
{
		yyerror("illegal declaration");
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
106=>
#line	675	"limbo.y"
{
		yyval.node = yys[yypt-1].yyv.node;
	}
107=>
#line	679	"limbo.y"
{
		yyval.node = mkn(Oif, yys[yypt-2].yyv.node, mkunary(Oseq, yys[yypt-0].yyv.node));
		yyval.node.src.start = yys[yypt-4].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.node.src.stop;
	}
108=>
#line	685	"limbo.y"
{
		yyval.node = mkn(Oif, yys[yypt-4].yyv.node, mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node));
		yyval.node.src.start = yys[yypt-6].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.node.src.stop;
	}
109=>
#line	691	"limbo.y"
{
		yyval.node = mkunary(Oseq, yys[yypt-0].yyv.node);
		if(yys[yypt-2].yyv.node.op != Onothing)
			yyval.node.right = yys[yypt-2].yyv.node;
		yyval.node = mkbin(Ofor, yys[yypt-4].yyv.node, yyval.node);
		yyval.node.decl = yys[yypt-9].yyv.ids;
		if(yys[yypt-6].yyv.node.op != Onothing)
			yyval.node = mkbin(Oseq, yys[yypt-6].yyv.node, yyval.node);
	}
110=>
#line	701	"limbo.y"
{
		yyval.node = mkn(Ofor, yys[yypt-2].yyv.node, mkunary(Oseq, yys[yypt-0].yyv.node));
		yyval.node.src.start = yys[yypt-4].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.node.src.stop;
		yyval.node.decl = yys[yypt-5].yyv.ids;
	}
111=>
#line	708	"limbo.y"
{
		yyval.node = mkn(Odo, yys[yypt-2].yyv.node, yys[yypt-5].yyv.node);
		yyval.node.src.start = yys[yypt-6].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-1].yyv.tok.src.stop;
		yyval.node.decl = yys[yypt-7].yyv.ids;
	}
112=>
#line	715	"limbo.y"
{
		yyval.node = mkn(Obreak, nil, nil);
		yyval.node.decl = yys[yypt-1].yyv.ids;
		yyval.node.src = yys[yypt-2].yyv.tok.src;
	}
113=>
#line	721	"limbo.y"
{
		yyval.node = mkn(Ocont, nil, nil);
		yyval.node.decl = yys[yypt-1].yyv.ids;
		yyval.node.src = yys[yypt-2].yyv.tok.src;
	}
114=>
#line	727	"limbo.y"
{
		yyval.node = mkn(Oret, yys[yypt-1].yyv.node, nil);
		yyval.node.src = yys[yypt-2].yyv.tok.src;
		if(yys[yypt-1].yyv.node.op == Onothing)
			yyval.node.left = nil;
		else
			yyval.node.src.stop = yys[yypt-1].yyv.node.src.stop;
	}
115=>
#line	736	"limbo.y"
{
		yyval.node = mkn(Ospawn, yys[yypt-1].yyv.node, nil);
		yyval.node.src.start = yys[yypt-2].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-1].yyv.node.src.stop;
	}
116=>
#line	742	"limbo.y"
{
		yyval.node = mkn(Ocase, yys[yypt-3].yyv.node, caselist(yys[yypt-1].yyv.node, nil));
		yyval.node.src = yys[yypt-3].yyv.node.src;
		yyval.node.decl = yys[yypt-5].yyv.ids;
	}
117=>
#line	748	"limbo.y"
{
		yyval.node = mkn(Oalt, caselist(yys[yypt-1].yyv.node, nil), nil);
		yyval.node.src = yys[yypt-3].yyv.tok.src;
		yyval.node.decl = yys[yypt-4].yyv.ids;
	}
118=>
#line	754	"limbo.y"
{
		yyval.node = mkn(Opick, mkbin(Odas, mkname(yys[yypt-5].yyv.tok.src, yys[yypt-5].yyv.tok.v.idval), yys[yypt-3].yyv.node), caselist(yys[yypt-1].yyv.node, nil));
		yyval.node.src.start = yys[yypt-5].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-3].yyv.node.src.stop;
		yyval.node.decl = yys[yypt-7].yyv.ids;
	}
119=>
#line	761	"limbo.y"
{
		yyval.node = mkn(Oexit, nil, nil);
		yyval.node.src = yys[yypt-1].yyv.tok.src;
	}
120=>
#line	768	"limbo.y"
{
		yyval.ids = nil;
	}
121=>
#line	772	"limbo.y"
{
		if(yys[yypt-1].yyv.ids.next != nil)
			yyerror("only one identifier allowed in a label");
		yyval.ids = yys[yypt-1].yyv.ids;
	}
122=>
#line	780	"limbo.y"
{
		yyval.ids = nil;
	}
123=>
#line	784	"limbo.y"
{
		yyval.ids = mkids(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval, nil, nil);
	}
124=>
#line	790	"limbo.y"
{
		yys[yypt-1].yyv.node.left.right.right = yys[yypt-0].yyv.node;
		yyval.node = yys[yypt-1].yyv.node;
	}
125=>
#line	797	"limbo.y"
{
		yyval.node = mkunary(Oseq, mkscope(mkunary(Olabel, rotater(yys[yypt-1].yyv.node))));
	}
126=>
#line	801	"limbo.y"
{
		yys[yypt-3].yyv.node.left.right.right = yys[yypt-2].yyv.node;
		yyval.node = mkbin(Oseq, mkscope(mkunary(Olabel, rotater(yys[yypt-1].yyv.node))), yys[yypt-3].yyv.node);
	}
127=>
#line	808	"limbo.y"
{
		yys[yypt-1].yyv.node.left.right = mkscope(yys[yypt-0].yyv.node);
		yyval.node = yys[yypt-1].yyv.node;
	}
128=>
#line	815	"limbo.y"
{
		yyval.node = mkunary(Oseq, mkunary(Olabel, rotater(yys[yypt-1].yyv.node)));
	}
129=>
#line	819	"limbo.y"
{
		yys[yypt-3].yyv.node.left.right = mkscope(yys[yypt-2].yyv.node);
		yyval.node = mkbin(Oseq, mkunary(Olabel, rotater(yys[yypt-1].yyv.node)), yys[yypt-3].yyv.node);
	}
130=>
yyval.node = yys[yyp+1].yyv.node;
131=>
#line	827	"limbo.y"
{
		yyval.node = mkbin(Orange, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
132=>
#line	831	"limbo.y"
{
		yyval.node = mkn(Owild, nil, nil);
		yyval.node.src = yys[yypt-0].yyv.tok.src;
	}
133=>
#line	836	"limbo.y"
{
		yyval.node = mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
134=>
#line	840	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
135=>
#line	848	"limbo.y"
{
		yys[yypt-1].yyv.node.left.right = mkscope(yys[yypt-0].yyv.node);
		yyval.node = yys[yypt-1].yyv.node;
	}
136=>
#line	855	"limbo.y"
{
		yyval.node = mkunary(Oseq, mkunary(Olabel, rotater(yys[yypt-1].yyv.node)));
	}
137=>
#line	859	"limbo.y"
{
		yys[yypt-3].yyv.node.left.right = mkscope(yys[yypt-2].yyv.node);
		yyval.node = mkbin(Oseq, mkunary(Olabel, rotater(yys[yypt-1].yyv.node)), yys[yypt-3].yyv.node);
	}
138=>
#line	866	"limbo.y"
{
		yyval.node = mkname(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval);
	}
139=>
#line	870	"limbo.y"
{
		yyval.node = mkn(Owild, nil, nil);
		yyval.node.src = yys[yypt-0].yyv.tok.src;
	}
140=>
#line	875	"limbo.y"
{
		yyval.node = mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
141=>
#line	879	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
142=>
#line	887	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = curline();
		yyval.node.src.stop = yyval.node.src.start;
	}
143=>
yyval.node = yys[yyp+1].yyv.node;
144=>
yyval.node = yys[yyp+1].yyv.node;
145=>
#line	897	"limbo.y"
{
		yyval.node = mkbin(Oas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
146=>
#line	901	"limbo.y"
{
		yyval.node = mkbin(Oandas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
147=>
#line	905	"limbo.y"
{
		yyval.node = mkbin(Ooras, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
148=>
#line	909	"limbo.y"
{
		yyval.node = mkbin(Oxoras, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
149=>
#line	913	"limbo.y"
{
		yyval.node = mkbin(Olshas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
150=>
#line	917	"limbo.y"
{
		yyval.node = mkbin(Orshas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
151=>
#line	921	"limbo.y"
{
		yyval.node = mkbin(Oaddas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
152=>
#line	925	"limbo.y"
{
		yyval.node = mkbin(Osubas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
153=>
#line	929	"limbo.y"
{
		yyval.node = mkbin(Omulas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
154=>
#line	933	"limbo.y"
{
		yyval.node = mkbin(Odivas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
155=>
#line	937	"limbo.y"
{
		yyval.node = mkbin(Omodas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
156=>
#line	941	"limbo.y"
{
		yyval.node = mkbin(Osnd, yys[yypt-3].yyv.node, yys[yypt-0].yyv.node);
	}
157=>
#line	945	"limbo.y"
{
		yyval.node = mkbin(Odas, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
158=>
#line	949	"limbo.y"
{
		yyval.node = mkn(Oload, yys[yypt-0].yyv.node, nil);
		yyval.node.src.start = yys[yypt-2].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.node.src.stop;
		yyval.node.ty = mkidtype(yys[yypt-1].yyv.tok.src, yys[yypt-1].yyv.tok.v.idval);
	}
159=>
#line	956	"limbo.y"
{
		yyval.node = mkbin(Omul, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
160=>
#line	960	"limbo.y"
{
		yyval.node = mkbin(Odiv, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
161=>
#line	964	"limbo.y"
{
		yyval.node = mkbin(Omod, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
162=>
#line	968	"limbo.y"
{
		yyval.node = mkbin(Oadd, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
163=>
#line	972	"limbo.y"
{
		yyval.node = mkbin(Osub, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
164=>
#line	976	"limbo.y"
{
		yyval.node = mkbin(Orsh, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
165=>
#line	980	"limbo.y"
{
		yyval.node = mkbin(Olsh, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
166=>
#line	984	"limbo.y"
{
		yyval.node = mkbin(Olt, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
167=>
#line	988	"limbo.y"
{
		yyval.node = mkbin(Ogt, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
168=>
#line	992	"limbo.y"
{
		yyval.node = mkbin(Oleq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
169=>
#line	996	"limbo.y"
{
		yyval.node = mkbin(Ogeq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
170=>
#line	1000	"limbo.y"
{
		yyval.node = mkbin(Oeq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
171=>
#line	1004	"limbo.y"
{
		yyval.node = mkbin(Oneq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
172=>
#line	1008	"limbo.y"
{
		yyval.node = mkbin(Oand, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
173=>
#line	1012	"limbo.y"
{
		yyval.node = mkbin(Oxor, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
174=>
#line	1016	"limbo.y"
{
		yyval.node = mkbin(Oor, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
175=>
#line	1020	"limbo.y"
{
		yyval.node = mkbin(Ocons, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
176=>
#line	1024	"limbo.y"
{
		yyval.node = mkbin(Oandand, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
177=>
#line	1028	"limbo.y"
{
		yyval.node = mkbin(Ooror, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
178=>
yyval.node = yys[yyp+1].yyv.node;
179=>
#line	1035	"limbo.y"
{
		yys[yypt-0].yyv.node.src.start = yys[yypt-1].yyv.tok.src.start;
		yyval.node = yys[yypt-0].yyv.node;
	}
180=>
#line	1040	"limbo.y"
{
		yyval.node = mkunary(Oneg, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
181=>
#line	1045	"limbo.y"
{
		yyval.node = mkunary(Onot, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
182=>
#line	1050	"limbo.y"
{
		yyval.node = mkunary(Ocomp, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
183=>
#line	1055	"limbo.y"
{
		yyval.node = mkunary(Oind, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
184=>
#line	1060	"limbo.y"
{
		yyval.node = mkunary(Opreinc, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
185=>
#line	1065	"limbo.y"
{
		yyval.node = mkunary(Opredec, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
186=>
#line	1070	"limbo.y"
{
		yyval.node = mkunary(Orcv, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
187=>
#line	1075	"limbo.y"
{
		yyval.node = mkunary(Ohd, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
188=>
#line	1080	"limbo.y"
{
		yyval.node = mkunary(Otl, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
189=>
#line	1085	"limbo.y"
{
		yyval.node = mkunary(Olen, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
190=>
#line	1090	"limbo.y"
{
		yyval.node = mkunary(Oref, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
191=>
#line	1095	"limbo.y"
{
		yyval.node = mkunary(Otagof, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
	}
192=>
#line	1100	"limbo.y"
{
		yyval.node = mkn(Oarray, yys[yypt-3].yyv.node, nil);
		yyval.node.ty = mktype(yys[yypt-5].yyv.tok.src.start, yys[yypt-0].yyv.ty.src.stop, Tarray, yys[yypt-0].yyv.ty, nil);
		yyval.node.src = yyval.node.ty.src;
	}
193=>
#line	1106	"limbo.y"
{
		yyval.node = mkn(Oarray, yys[yypt-5].yyv.node, yys[yypt-1].yyv.node);
		yyval.node.src.start = yys[yypt-7].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
194=>
#line	1112	"limbo.y"
{
		yyval.node = mkn(Onothing, nil, nil);
		yyval.node.src.start = yys[yypt-5].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-4].yyv.tok.src.stop;
		yyval.node = mkn(Oarray, yyval.node, yys[yypt-1].yyv.node);
		yyval.node.src.start = yys[yypt-6].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
195=>
#line	1121	"limbo.y"
{
		yyval.node = etolist(yys[yypt-1].yyv.node);
		yyval.node.src.start = yys[yypt-4].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
196=>
#line	1127	"limbo.y"
{
		yyval.node = mkn(Ochan, nil, nil);
		yyval.node.ty = mktype(yys[yypt-2].yyv.tok.src.start, yys[yypt-0].yyv.ty.src.stop, Tchan, yys[yypt-0].yyv.ty, nil);
		yyval.node.src = yyval.node.ty.src;
	}
197=>
#line	1133	"limbo.y"
{
		yyval.node = mkunary(Ocast, yys[yypt-0].yyv.node);
		yyval.node.ty = mktype(yys[yypt-3].yyv.tok.src.start, yys[yypt-0].yyv.node.src.stop, Tarray, mkidtype(yys[yypt-1].yyv.tok.src, yys[yypt-1].yyv.tok.v.idval), nil);
		yyval.node.src = yyval.node.ty.src;
	}
198=>
#line	1139	"limbo.y"
{
		yyval.node = mkunary(Ocast, yys[yypt-0].yyv.node);
		yyval.node.src.start = yys[yypt-1].yyv.tok.src.start;
		yyval.node.ty = mkidtype(yyval.node.src, yys[yypt-1].yyv.tok.v.idval);
	}
199=>
yyval.node = yys[yyp+1].yyv.node;
200=>
#line	1148	"limbo.y"
{
		yyval.node = mkn(Ocall, yys[yypt-3].yyv.node, yys[yypt-1].yyv.node);
		yyval.node.src.start = yys[yypt-3].yyv.node.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
201=>
#line	1154	"limbo.y"
{
		yyval.node = yys[yypt-1].yyv.node;
		if(yys[yypt-1].yyv.node.op == Oseq)
			yyval.node = mkn(Otuple, rotater(yys[yypt-1].yyv.node), nil);
		else
			yyval.node.parens = byte 1;
		yyval.node.src.start = yys[yypt-2].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
202=>
#line	1164	"limbo.y"
{
#		n := mkdeclname($1, mkids($1, enter(".fn"+string nfnexp++, 0), nil, nil));
#		$<node>$ = fndef(n, $2);
#		nfns++;
	}
203=>
#line	1169	"limbo.y"
{
#		$$ = fnfinishdef($<node>3, $4);
#		$$ = mkdeclname($1, $$.left.decl);
		yyerror("urt unk");
		yyval.node = nil;
	}
204=>
#line	1176	"limbo.y"
{
		yyval.node = mkbin(Odot, yys[yypt-2].yyv.node, mkname(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval));
	}
205=>
#line	1180	"limbo.y"
{
		yyval.node = mkbin(Omdot, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
206=>
#line	1184	"limbo.y"
{
		yyval.node = mkbin(Oindex, yys[yypt-3].yyv.node, yys[yypt-1].yyv.node);
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
207=>
#line	1189	"limbo.y"
{
		if(yys[yypt-3].yyv.node.op == Onothing)
			yys[yypt-3].yyv.node.src = yys[yypt-2].yyv.tok.src;
		if(yys[yypt-1].yyv.node.op == Onothing)
			yys[yypt-1].yyv.node.src = yys[yypt-2].yyv.tok.src;
		yyval.node = mkbin(Oslice, yys[yypt-5].yyv.node, mkbin(Oseq, yys[yypt-3].yyv.node, yys[yypt-1].yyv.node));
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
208=>
#line	1198	"limbo.y"
{
		yyval.node = mkunary(Oinc, yys[yypt-1].yyv.node);
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
209=>
#line	1203	"limbo.y"
{
		yyval.node = mkunary(Odec, yys[yypt-1].yyv.node);
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
210=>
#line	1208	"limbo.y"
{
		yyval.node = mksconst(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval);
	}
211=>
#line	1212	"limbo.y"
{
		yyval.node = mkconst(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.ival);
		if(yys[yypt-0].yyv.tok.v.ival > big 16r7fffffff || yys[yypt-0].yyv.tok.v.ival < big -16r7fffffff)
			yyval.node.ty = tbig;
	}
212=>
#line	1218	"limbo.y"
{
		yyval.node = mkrconst(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.rval);
	}
213=>
#line	1224	"limbo.y"
{
		yyval.node = mkname(yys[yypt-0].yyv.tok.src, yys[yypt-0].yyv.tok.v.idval);
	}
214=>
#line	1228	"limbo.y"
{
		yyval.node = mknil(yys[yypt-0].yyv.tok.src);
	}
215=>
#line	1234	"limbo.y"
{
		yyval.node = mkn(Otuple, rotater(yys[yypt-1].yyv.node), nil);
		yyval.node.src.start = yys[yypt-2].yyv.tok.src.start;
		yyval.node.src.stop = yys[yypt-0].yyv.tok.src.stop;
	}
216=>
yyval.node = yys[yyp+1].yyv.node;
217=>
yyval.node = yys[yyp+1].yyv.node;
218=>
#line	1244	"limbo.y"
{
		yyval.node = mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
219=>
#line	1248	"limbo.y"
{
		yyval.node = mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
220=>
#line	1254	"limbo.y"
{
		yyval.node = nil;
	}
221=>
#line	1258	"limbo.y"
{
		yyval.node = rotater(yys[yypt-0].yyv.node);
	}
222=>
yyval.node = yys[yyp+1].yyv.node;
223=>
yyval.node = yys[yyp+1].yyv.node;
224=>
yyval.node = yys[yyp+1].yyv.node;
225=>
#line	1269	"limbo.y"
{
		yyval.node = mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
226=>
#line	1275	"limbo.y"
{
		yyval.node = rotater(yys[yypt-0].yyv.node);
	}
227=>
#line	1279	"limbo.y"
{
		yyval.node = rotater(yys[yypt-1].yyv.node);
	}
228=>
yyval.node = yys[yyp+1].yyv.node;
229=>
#line	1286	"limbo.y"
{
		yyval.node = mkbin(Oseq, yys[yypt-2].yyv.node, yys[yypt-0].yyv.node);
	}
230=>
#line	1292	"limbo.y"
{
		yyval.node = mkn(Oelem, nil, yys[yypt-0].yyv.node);
		yyval.node.src = yys[yypt-0].yyv.node.src;
	}
231=>
#line	1297	"limbo.y"
{
		yyval.node = mkbin(Oelem, rotater(yys[yypt-2].yyv.node), yys[yypt-0].yyv.node);
	}
		}
	}

	return yyn;
}
