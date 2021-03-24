opname := array[Oend+1] of
{
			"unknown",

	Oadd =>		"+",
	Oaddas =>	"+=",
	Oadr =>		"adr",
	Oadtdecl =>	"adtdecl",
	Oalt =>		"alt",
	Oand =>		"&",
	Oandand =>	"&&",
	Oandas =>	"&=",
	Oarray =>	"array",
	Oas =>		"=",
	Obreak =>	"break",
	Ocall =>	"call",
	Ocase =>	"case",
	Ocast =>	"cast",
	Ochan =>	"chan",
	Ocomp =>	"~",
	Ocondecl =>	"condecl",
	Ocons =>	"::",
	Oconst =>	"const",
	Ocont =>	"continue",
	Odas =>		":=",
	Odec =>		"--",
	Odiv =>		"/",
	Odivas =>	"/=",
	Odo =>		"do",
	Odot =>		".",
	Oelem =>	"elem",
	Oeq =>		"==",
	Oexit =>	"exit",
	Ofielddecl =>	"fielddecl",
	Ofor =>		"for",
	Ofunc =>	"fn(){}",
	Ogeq =>		">=",
	Ogt =>		">",
	Ohd =>		"hd",
	Oif =>		"if",
	Oimport =>	"import",
	Oinc =>		"++",
	Oind =>		"*",
	Oindex =>	"index",
	Oinds =>	"inds",
	Oindx =>	"indx",
	Ojmp =>		"jmp",
	Olabel =>	"label",
	Olen =>		"len",
	Oleq =>		"<=",
	Oload =>	"load",
	Olsh =>		"<<",
	Olshas =>	"<<=",
	Olt =>		"<",
	Omdot =>	"->",
	Omod =>		"%",
	Omodas =>	"%=",
	Omoddecl =>	"moddecl",
	Omul =>		"*",
	Omulas =>	"*=",
	Oname =>	"name",
	Oneg =>		"-",
	Oneq =>		"!=",
	Onot =>		"!",
	Onothing =>	"nothing",
	Oor =>		"|",
	Ooras =>	"|=",
	Ooror =>	"||",
	Opick =>	"pick",
	Opickdecl =>	"pickdec",
	Opredec =>	"--",
	Opreinc =>	"++",
	Orange =>	"range",
	Orcv =>		"<-",
	Oref =>		"ref",
	Oret =>		"return",
	Orsh =>		">>",
	Orshas =>	">>=",
	Oscope =>	"scope",
	Oseq =>		"seq",
	Oslice =>	"slice",
	Osnd =>		"<-=",
	Ospawn =>	"spawn",
	Osub =>		"-",
	Osubas =>	"-=",
	Otagof =>	"tagof",
	Otl =>		"tl",
	Otuple =>	"tuple",
	Otypedecl =>	"typedecl",
	Oused =>	"used",
	Ovardecl =>	"vardecl",
	Ovardecli =>	"vardecli",
	Owild =>	"*",
	Oxor =>		"^",
	Oxoras =>	"^=",

	Oend =>	"unknown"
};
