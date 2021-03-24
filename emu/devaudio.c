#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	"devaudio.h"

static int debug = 0;

#define OPEN_MASK 0x7

Dirtab audiotab[] =
{
	"audio",	{Qaudio},	0,	0777,
	"audioctl",	{Qaudioctl},	0,	0777
};

void
audioinit(void)
{
	audio_file_init();
	audio_ctl_init();
}

Chan*
audioattach(char *spec)
{
	return devattach('A', spec);
}

int
audiowalk(Chan *c, char *name)
{
	return devwalk(c, name, audiotab, nelem(audiotab), devgen);
}

void
audiostat(Chan *c, char *db)
{
	devstat(c, db, audiotab, nelem(audiotab), devgen);
}

Chan*
audioopen(Chan *c, int omode)
{
	switch(c->qid.path & ~CHDIR) {
	default:
		error(Eperm);
		break;
	case Qdir:
		break;
	case Qaudio:
		audio_file_open(c, omode&OPEN_MASK);
		break;
	case Qaudioctl:
		audio_ctl_open(c, omode&OPEN_MASK);
		break;
	}
	c = devopen(c, omode, audiotab, nelem(audiotab), devgen);
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

void
audioclose(Chan *c)
{
	if((c->flag & COPEN) == 0)
		return;

	switch(c->qid.path & ~CHDIR) {
	default:
		error(Eperm);
		break;
	case Qdir:
		break;
	case Qaudio:
		audio_file_close(c);
		break;
	case Qaudioctl:
		audio_ctl_close(c);
		break;
	}
}

long
audioread(Chan *c, void *va, long count, ulong offset)
{
	if (c->qid.path & CHDIR)
		return devdirread(c, va, count, audiotab, nelem(audiotab), devgen);
	switch(c->qid.path) {
	case Qaudio:
		return(audio_file_read(c, va, count, offset));
	case Qaudioctl:
		return(audio_ctl_read(c, va, count, offset));
	default:
		error(Egreg);
	}
	return 0;
}

long
audiowrite(Chan *c, void *va, long count, ulong offset)
{
	switch(c->qid.path) {
	case Qaudio:
		return(audio_file_write(c, va, count, offset));
	case Qaudioctl:
		return(audio_ctl_write(c, va, count, offset));
	default:
		error(Egreg);
	}
	return 0;
}

int
audioparse(char* args, int len, Audio_t *t)
{
int i;
int n;
ulong v;
char *argv[AUDIO_CMD_MAXNUM];
char buf[AUDIO_INFO_MAXBUF+1];
ulong tf = AUDIO_IN_FLAG|AUDIO_OUT_FLAG;
Audio_t info = *t;

  if(len > sizeof(buf)-1)
    len = sizeof(buf)-1;
  memmove(buf, args, len);
  buf[len] = '\0';

  if(debug) print("buf = <<%s>>\n", buf);

  n = getfields(buf, argv, AUDIO_CMD_MAXNUM, 1, " =,\t\n");

  if(debug) print("%d args\n", n);

  for(i = 0; i < n - 1; i++) {

    if(debug) print("arg[%d] = %s\n", i, argv[i]);

    if(strcmp(argv[i], "in") == 0) {
	tf &= ~AUDIO_OUT_FLAG;
	tf |= AUDIO_IN_FLAG;
	continue;
    }
    if(strcmp(argv[i], "out") == 0) {
	tf &= ~AUDIO_IN_FLAG;
	tf |= AUDIO_OUT_FLAG;
	continue;
    }
    if(strcmp(argv[i], "bits") == 0) {
	if(! svpmatchs(audio_bits_tbl, argv[i+1], &v))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_BITS_FLAG|AUDIO_MOD_FLAG;
	  info.in.bits = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_BITS_FLAG|AUDIO_MOD_FLAG;
	  info.out.bits = v;
	}

	continue;
    }
    else if(strcmp(argv[i], "buf") == 0) {
	if(! sval(argv[i+1], &v, Audio_Max_Val, Audio_Min_Val))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_BUF_FLAG|AUDIO_MOD_FLAG;
	  info.in.buf = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_BUF_FLAG|AUDIO_MOD_FLAG;
	  info.out.buf = v;
	}

	continue;
    }
    else if(strcmp(argv[i], "chans") == 0) {
	if(! svpmatchs(audio_chan_tbl, argv[i+1], &v))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_CHAN_FLAG|AUDIO_MOD_FLAG;
	  info.in.chan = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_CHAN_FLAG|AUDIO_MOD_FLAG;
	  info.out.chan = v;
	}

	continue;
    }
    else if(strcmp(argv[i], "indev") == 0) {
	if(! svpmatchs(audio_indev_tbl, argv[i+1], &v))
        	break;
	i++;
	info.in.flags |= AUDIO_DEV_FLAG|AUDIO_MOD_FLAG;
	info.in.dev = v;
    }
    else if(strcmp(argv[i], "outdev") == 0) {
	if(! svpmatchs(audio_outdev_tbl, argv[i+1], &v))
         	break;
	i++;
	info.out.flags |= AUDIO_DEV_FLAG|AUDIO_MOD_FLAG;
	info.out.dev = v;
	continue;
    }
    else if(strcmp(argv[i], "enc") == 0) {
	if(! svpmatchs(audio_enc_tbl, argv[i+1], &v))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_ENC_FLAG|AUDIO_MOD_FLAG;
	  info.in.enc = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_ENC_FLAG|AUDIO_MOD_FLAG;
	  info.out.enc = v;
	}

	continue;
    }
    else if(strcmp(argv[i], "rate") == 0) {
	if(! svpmatchs(audio_rate_tbl, argv[i+1], &v))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_RATE_FLAG|AUDIO_MOD_FLAG;
	  info.in.rate = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_RATE_FLAG|AUDIO_MOD_FLAG;
	  info.out.rate = v;
	}

	continue;
    }
    else if(strcmp(argv[i], "vol") == 0) {
	if(! sval(argv[i+1], &v, Audio_Max_Val, Audio_Min_Val))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_VOL_FLAG|AUDIO_MOD_FLAG;
	  info.in.left = v;
	  info.in.right = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_VOL_FLAG|AUDIO_MOD_FLAG;
	  info.out.left = v;
	  info.out.right = v;
	}

	continue;
    }
    else if(strcmp(argv[i], "left") == 0) {
	if(! sval(argv[i+1], &v, Audio_Max_Val, Audio_Min_Val))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_LEFT_FLAG|AUDIO_MOD_FLAG;
	  info.in.left = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_LEFT_FLAG|AUDIO_MOD_FLAG;
	  info.out.left = v;
	}

	continue;
    }
    else if(strcmp(argv[i], "right") == 0) {
	if(! sval(argv[i+1], &v, Audio_Max_Val, Audio_Min_Val))
        	break;

	i++;
	if(tf & AUDIO_IN_FLAG) {
	  info.in.flags |= AUDIO_RIGHT_FLAG|AUDIO_MOD_FLAG;
	  info.in.right = v;
	}
	if(tf & AUDIO_OUT_FLAG) {
	  info.out.flags |= AUDIO_RIGHT_FLAG|AUDIO_MOD_FLAG;
	  info.out.right = v;
	}

	continue;
    }
    else
	continue;
  }

  if(i < n - 1)
	return 0;

  *t = info;	/* set information back */
  return n;	/* return number of affected fields */
}

int
audio_get_info(char *p, Audio_d *in, Audio_d *out)
{
  char *s;
  int l = 0;
  Audio_d tmpin = *in;
  Audio_d tmpout = *out;
  svp_t *sv;

  /* in device */
  if(! svpmatchv(audio_indev_tbl, &s, in->dev))
    return 0;
  else
    sprint(p, "indev %s", s);

  /* rest of input devices */
  for(sv = audio_indev_tbl; sv->s != nil; sv++)
    if(sv->v != in->dev)
      sprint(p+strlen(p), " %s", sv->s);
  sprint(p+strlen(p), "\n");
    

  /* out device */
  if(! svpmatchv(audio_outdev_tbl, &s, out->dev))
    return 0;
  else
    sprint(p+strlen(p), "outdev %s", s);

  /* rest of output devices */
  for(sv = audio_outdev_tbl; sv->s != nil; sv++)
    if(sv->v != out->dev)
      sprint(p+strlen(p), " %s", sv->s);
  sprint(p+strlen(p), "\n");

  tmpin.flags = 0;
  tmpout.flags = 0;
  tmpin.dev = 0;
  tmpout.dev = 0;

  if(memcmp(&tmpin, &tmpout, sizeof(Audio_d)) != 0) {

    sprint(p+strlen(p), "out\n");

    if(! svpmatchv(audio_enc_tbl, &s, out->enc))
      return 0;
    else
      sprint(p+strlen(p), "enc %s", s);
    
    /* rest of encoding */
    for(sv = audio_enc_tbl; sv->s != nil; sv++)
      if(sv->v != out->enc)
        sprint(p+strlen(p), " %s", sv->s);
    sprint(p+strlen(p), "\n");

    if(! svpmatchv(audio_rate_tbl, &s, out->rate))
      return 0;
    else
      sprint(p+strlen(p), "rate %s", s);

    /* rest of rates */
     for(sv = audio_rate_tbl; sv->s != nil; sv++)
      if(sv->v != out->rate)
        sprint(p+strlen(p), " %s", sv->s);
    sprint(p+strlen(p), "\n");

    /* bits */
    if(! svpmatchv(audio_bits_tbl, &s, out->bits))
      return 0;
    else
      sprint(p+strlen(p), "bits %s", s);

    /* rest of bits */
    for(sv = audio_bits_tbl; sv->s != nil; sv++)
      if(sv->v != out->bits)
        sprint(p+strlen(p), " %s", sv->s);
    sprint(p+strlen(p), "\n");

    if(! svpmatchv(audio_chan_tbl, &s, out->chan))
      return 0;
    else
      sprint(p+strlen(p), "chans %s", s);

    /* rest of channels */
    for(sv = audio_chan_tbl; sv->s != nil; sv++)
      if(sv->v != out->chan)
        sprint(p+strlen(p), " %s", sv->s);
    sprint(p+strlen(p), "\n");
    sprint(p+strlen(p), "left %d %d %d\n", out->left, Audio_Min_Val, Audio_Max_Val);
    sprint(p+strlen(p), "right %d %d %d\n", out->right, Audio_Min_Val, Audio_Max_Val);
    sprint(p+strlen(p), "buf %d %d %d\n", out->buf, Audio_Min_Val, Audio_Max_Val);
    sprint(p+strlen(p), "in\n");
  }

  /* encode */
  if(! svpmatchv(audio_enc_tbl, &s, in->enc))
    return 0;
  else
    sprint(p+strlen(p), "enc %s", s);
  
  /* rest of encoding */
  for(sv = audio_enc_tbl; sv->s != nil; sv++) 
    if(sv->v != in->enc)
      sprint(p+strlen(p), " %s", sv->s);
  sprint(p+strlen(p), "\n");

  /* rate */
  if(! svpmatchv(audio_rate_tbl, &s, in->rate))
    return 0;
  else
    sprint(p+strlen(p), "rate %s", s);

  /* rest of rates */
  for(sv = audio_rate_tbl; sv->s != nil; sv++)
    if(sv->v != in->rate)
      sprint(p+strlen(p), " %s", sv->s);
  sprint(p+strlen(p), "\n");

  /* bits */
  if(! svpmatchv(audio_bits_tbl, &s, in->bits))
    return 0;
  else
    sprint(p+strlen(p), "bits %s", s);

  /* rest of bits */
  for(sv = audio_bits_tbl; sv->s != nil; sv++)
    if(sv->v != in->bits)
      sprint(p+strlen(p), " %s", sv->s);
  sprint(p+strlen(p), "\n");

  /* channels */
  if(! svpmatchv(audio_chan_tbl, &s, in->chan))
    return 0;
  else
    sprint(p+strlen(p), "chans %s", s);

  /* rest of channels */
  for(sv = audio_chan_tbl; sv->s != nil; sv++)
    if(sv->v != in->chan)
      sprint(p+strlen(p), " %s", sv->s);
  sprint(p+strlen(p), "\n");

  sprint(p+strlen(p), "left %d %d %d\n", in->left, Audio_Min_Val, Audio_Max_Val);
  sprint(p+strlen(p), "right %d %d %d\n", in->right, Audio_Min_Val, Audio_Max_Val);
  sprint(p+strlen(p), "buf %d %d %d\n", in->buf, Audio_Min_Val, Audio_Max_Val);

  return strlen(p)+1;
}

void
audio_info_init(Audio_t *t)
{
	t->in = Default_Audio_Format;
	t->in.dev = Default_Audio_Input;
	t->out = Default_Audio_Format;
	t->out.dev = Default_Audio_Output;
}

int
svpmatchs(svp_t* t, char* s, ulong *v)
{
	if(t == nil || s == nil)
		return 0;
	for(; t->s != nil; t++) {
		if(strncmp(t->s, s, strlen(t->s)) == 0) {
			*v = t->v;
			return 1;
		}
	}
	return 0;
}

int
svpmatchv(svp_t* t, char** s, ulong v)
{
	if(t == nil)
		return 0;
	for(; t->s != nil; t++) {
		if(t->v == v) {
			*s = t->s;
			return 1;
		}
	}
	return 0;
}

int 
sval(char* buf, ulong* v, ulong max, ulong min)
{
	unsigned long val = strtoul(buf, 0, 10);

	if(val > max || val < min)
		return 0;
	*v = val;
	return 1;
}

Dev audiodevtab = {
        'A',
        "audio",

        audioinit,
        audioattach,
        devclone,
        audiowalk,
        audiostat,
        audioopen,
        devcreate,
        audioclose,
        audioread,
        devbread,
        audiowrite,
        devbwrite,
        devremove,
        devwstat
};

