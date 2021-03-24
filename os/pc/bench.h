#pragma hjdicks x4
typedef struct Bench_FD Bench_FD;
struct Bench_FD
{
	WORD	fd;
};
#define Bench_FD_size 4
#define Bench_FD_map {0}
void Bench_disablegc(void*);
typedef struct F_Bench_disablegc F_Bench_disablegc;
struct F_Bench_disablegc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
};
void Bench_enablegc(void*);
typedef struct F_Bench_enablegc F_Bench_enablegc;
struct F_Bench_enablegc
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
};
void Bench_microsec(void*);
typedef struct F_Bench_microsec F_Bench_microsec;
struct F_Bench_microsec
{
	WORD	regs[NREG-1];
	LONG*	ret;
	uchar	temps[12];
};
void Bench_read(void*);
typedef struct F_Bench_read F_Bench_read;
struct F_Bench_read
{
	WORD	regs[NREG-1];
	WORD*	ret;
	uchar	temps[12];
	Bench_FD*	fd;
	Array*	buf;
	WORD	n;
};
void Bench_reset(void*);
typedef struct F_Bench_reset F_Bench_reset;
struct F_Bench_reset
{
	WORD	regs[NREG-1];
	WORD	noret;
	uchar	temps[12];
};
#define Bench_PATH "$Bench"
#pragma hjdicks off
