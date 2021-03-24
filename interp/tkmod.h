typedef struct{char *name; long sig; void (*fn)(void*); int size; int np; uchar map[16];} Runtab;
Runtab Tkmodtab[]={
	"cmd",0x3f027a69,Tk_cmd,40,2,{0x0,0xc0,},
	"imageget",0x42ae71f1,Tk_imageget,40,2,{0x0,0xc0,},
	"imageput",0x216b6cbc,Tk_imageput,48,2,{0x0,0xf0,},
	"intop",0x56cbc46e,Tk_intop,48,2,{0x0,0x80,},
	"keyboard",0xaf8ee4de,Tk_keyboard,40,2,{0x0,0x80,},
	"mouse",0x4df18f48,Tk_mouse,48,2,{0x0,0x80,},
	"namechan",0xe4470c15,Tk_namechan,48,2,{0x0,0xe0,},
	"toplevel",0xa4341657,Tk_toplevel,40,2,{0x0,0xc0,},
	"windows",0xa04f48a6,Tk_windows,40,2,{0x0,0x80,},
	0
};
