#define	AUDIO_BITS_FLAG		0x00000001
#define	AUDIO_BUF_FLAG		0x00000002
#define	AUDIO_CHAN_FLAG		0x00000004
#define	AUDIO_COUNT_FLAG	0x00000008
#define	AUDIO_DEV_FLAG		0x00000010
#define	AUDIO_ENC_FLAG		0x00000020
#define	AUDIO_RATE_FLAG		0x00000040
#define	AUDIO_VOL_FLAG		0x00000080
#define	AUDIO_LEFT_FLAG		0x00000100
#define	AUDIO_RIGHT_FLAG	0x00000200
#define	AUDIO_IN_FLAG		0x00000400
#define	AUDIO_OUT_FLAG		0x00000800
#define	AUDIO_MOD_FLAG		0x10000000

#define		Audio_Min_Val		0
#define		Audio_Max_Val		100

#define 	Audio_No_Val		0
#define 	Audio_In_Val		1
#define 	Audio_Out_Val		2

#define		Audio_Max_Buf		32768
#define		Bits_Per_Byte		8

typedef struct Audio_d {
	ulong	flags;		/* bit flag for fields */
	ulong	bits;		/* bits per sample */
	ulong	buf;		/* buffer size */
	ulong	chan;		/* number of channels */
	ulong	dev;		/* device */
	ulong	enc;		/* encoding format */
	ulong	rate;		/* samples per second */
	ulong	left;		/* left channel gain */
	ulong	right;		/* right channel gain */
} Audio_d;

typedef struct Audio_t {
	Audio_d	in;		/* input device */
	Audio_d	out;		/* output device */
} Audio_t;

#define AUDIO_CMD_MAXNUM 32
#define AUDIO_INFO_MAXBUF 512

void audio_info_init(Audio_t*);
int audio_get_info(char*, Audio_d*, Audio_d*);
int audioparse(char*, int n, Audio_t*);

enum
{
	Qdir = 0,		/* must start at 0 representing a directory */
	Qaudio,
	Qaudioctl
};

/* required external platform specific functions */
void	audio_file_init(void);
void	audio_ctl_init(void);
void	audio_file_open(Chan*, int);
void	audio_ctl_open(Chan*, int);
long	audio_file_read(Chan*, void*, long, ulong);
long	audio_ctl_read(Chan*, void*, long, ulong);
long	audio_file_write(Chan*, void*, long, ulong);
long	audio_ctl_write(Chan*, void*, long, ulong);
void	audio_file_close(Chan*);
void	audio_ctl_close(Chan*);

typedef struct _svp_t {
	char*		s;	/* string */
	unsigned long	v;	/* value */
} svp_t;

#define SVP_SZ(a) (sizeof(a)/sizeof(svp_t))

extern int sval(char*, unsigned long*, unsigned long, unsigned long);
extern int svpmatchs(svp_t*, char*, unsigned long*);
extern int svpmatchv(svp_t*, char**, unsigned long);

/* string value pairs for default audio values */
extern svp_t audio_bits_tbl[];
extern svp_t audio_chan_tbl[];
extern svp_t audio_indev_tbl[];
extern svp_t audio_outdev_tbl[];
extern svp_t audio_enc_tbl[];
extern svp_t audio_rate_tbl[];
extern svp_t audio_val_tbl[];

extern Audio_d Default_Audio_Format;
extern int Default_Audio_Input, Default_Audio_Output;
