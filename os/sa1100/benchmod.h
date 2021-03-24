typedef struct{char *name; long sig; void (*fn)(void*); int size; int np; uchar map[16];} Runtab;
Runtab Benchmodtab[]={
	"disablegc",0x9cd71c5e,Bench_disablegc,32,0,{0},
	"enablegc",0x9cd71c5e,Bench_enablegc,32,0,{0},
	"microsec",0x8bc818ff,Bench_microsec,32,0,{0},
	"read",0x7cfef557,Bench_read,48,2,{0x0,0xc0,},
	"reset",0x9cd71c5e,Bench_reset,32,0,{0},
	0
};
