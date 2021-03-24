#include <lib9.h>
#include <image.h>

/*
 * Special version of misc/8x13.0, modified so the rectangle
 * is an integral number of words wide.
 */
uchar
defontdata[] =
{
	0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x30,0x20,0x20,0x20,0x20,0x20,
	0x20,0x20,0x20,0x20,0x20,0x20,0x30,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,
	0x20,0x20,0x30,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x31,0x37,0x39,0x32,0x20,
	0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x31,0x33,0x20,0x90,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x10,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x60,0x06,0x18,0x4c,
	0x00,0x18,0x00,0x00,0x78,0x1f,0x18,0x00,0x70,0x1c,0x38,0x00,0x00,0x32,0x70,0x1c,
	0x18,0x32,0x00,0x00,0x00,0x38,0x1c,0x18,0x00,0x0e,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xd0,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x10,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x54,0x81,0x00,0x10,0x00,
	0x48,0x00,0x00,0x3c,0x44,0x1c,0x70,0x00,0x00,0x00,0x1c,0xf8,0x70,0x20,0x70,0x70,
	0x0e,0x00,0x00,0x00,0x00,0x60,0x30,0x00,0x80,0x80,0xe0,0x00,0x18,0x18,0x24,0x32,
	0x24,0x24,0x00,0x00,0x1e,0x78,0x66,0x24,0x1c,0x70,0x6c,0x28,0x00,0x4c,0x1c,0x70,
	0x24,0x5c,0x24,0x44,0x02,0x0e,0x70,0x66,0x24,0x78,0x00,0x30,0x00,0x00,0x00,0x00,
	0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xb0,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x10,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x24,0x00,
	0x00,0x22,0x00,0x38,0x04,0x20,0x00,0x00,0x00,0x00,0x00,0x02,0x18,0x10,0x3c,0x7e,
	0x04,0x7e,0x1c,0x7e,0x3c,0x3c,0x00,0x00,0x02,0x00,0x40,0x3c,0x3c,0x18,0xfc,0x3c,
	0xfc,0x7e,0x7e,0x3c,0x42,0x7c,0x1e,0x42,0x40,0x82,0x42,0x3c,0x7c,0x3c,0x7c,0x3c,
	0xfe,0x42,0x82,0x82,0x82,0x82,0x7e,0x3c,0x80,0x3c,0x10,0x00,0x38,0x00,0x40,0x00,
	0x02,0x00,0x1c,0x00,0x40,0x00,0x00,0x40,0x30,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x0e,0x10,0x70,0x24,0x2a,0x99,0x10,0x10,0x00,
	0x30,0x82,0x10,0x42,0x00,0x22,0x10,0x00,0x00,0x00,0x22,0x00,0x50,0x20,0x10,0x10,
	0x18,0x00,0x7e,0x00,0x00,0x20,0x48,0x00,0x84,0x88,0x21,0x08,0x06,0x60,0x42,0x00,
	0x00,0x24,0x3f,0x3c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xfc,0x00,0x00,0x00,
	0x00,0x00,0x00,0x28,0x1c,0x00,0x00,0x00,0x00,0x00,0x20,0x48,0x70,0x1c,0x18,0x32,
	0x00,0x28,0x00,0x00,0x70,0x1c,0x18,0x00,0xe0,0x38,0x38,0x00,0x08,0x32,0x38,0x0e,
	0x18,0x32,0x00,0x00,0x00,0x70,0x1c,0x38,0x00,0x1c,0x00,0x00,0x00,0x10,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x00,0x00,0x10,0x10,0xff,0x00,0x00,0x00,
	0x00,0x10,0x10,0x10,0x00,0x10,0x02,0x80,0x00,0x00,0x00,0x00,0x00,0x10,0x24,0x24,
	0x10,0x52,0x00,0x30,0x08,0x10,0x00,0x00,0x00,0x00,0x00,0x02,0x24,0x30,0x42,0x02,
	0x0c,0x40,0x20,0x02,0x42,0x42,0x00,0x00,0x04,0x00,0x20,0x42,0x42,0x24,0x42,0x42,
	0x42,0x40,0x40,0x42,0x42,0x10,0x04,0x44,0x40,0x82,0x42,0x42,0x42,0x42,0x42,0x42,
	0x10,0x42,0x82,0x82,0x82,0x82,0x02,0x20,0x80,0x04,0x28,0x00,0x18,0x00,0x40,0x00,
	0x02,0x00,0x22,0x00,0x40,0x10,0x04,0x40,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x20,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x10,0x08,0x54,0x54,0xa5,0x00,0x3c,0x00,
	0x48,0x82,0x10,0x62,0x00,0x5d,0x70,0x12,0x7e,0x00,0x59,0x00,0x70,0xf8,0x20,0x30,
	0x70,0xc6,0xf4,0x60,0x00,0x20,0x48,0x48,0x88,0x90,0xe2,0x00,0x18,0x18,0x18,0x18,
	0x18,0x18,0x29,0x42,0x7e,0x7e,0x7e,0x7e,0x7c,0x7c,0x7c,0x7c,0x42,0x42,0x3c,0x3c,
	0x3c,0x3c,0x3c,0x10,0x26,0x42,0x42,0x42,0x42,0x82,0x70,0x48,0x1c,0x70,0x66,0x5c,
	0x24,0x28,0x3b,0x00,0x1c,0x70,0x66,0x24,0x38,0xe0,0x6c,0x50,0x3e,0x4c,0x0e,0x38,
	0x66,0x4c,0x24,0x00,0x01,0x1c,0x70,0x6c,0x28,0x70,0xc0,0x24,0x28,0x38,0x92,0x88,
	0xf0,0x78,0x80,0x38,0x00,0x88,0x88,0x10,0x00,0x00,0x10,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x10,0x00,0x10,0x08,0x20,0x00,0x02,0x1c,0x00,0x00,0x10,0x24,0x24,
	0x3c,0x24,0x30,0x40,0x08,0x10,0x24,0x10,0x00,0x00,0x00,0x04,0x42,0x50,0x42,0x04,
	0x14,0x40,0x40,0x04,0x42,0x42,0x10,0x10,0x08,0x00,0x10,0x42,0x42,0x42,0x42,0x40,
	0x42,0x40,0x40,0x40,0x42,0x10,0x04,0x48,0x40,0xc6,0x62,0x42,0x42,0x42,0x42,0x40,
	0x10,0x42,0x44,0x82,0x44,0x44,0x04,0x20,0x40,0x04,0x44,0x00,0x04,0x00,0x40,0x00,
	0x02,0x00,0x20,0x00,0x40,0x00,0x00,0x40,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x20,0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x10,0x08,0x48,0x2a,0xa5,0x10,0x42,0x1c,
	0x48,0x44,0x10,0x50,0x00,0x51,0x90,0x24,0x02,0x00,0x55,0x00,0x00,0x20,0x70,0x10,
	0x00,0x44,0xf4,0x60,0x00,0x70,0x30,0x24,0x90,0xa0,0x24,0x08,0x24,0x24,0x24,0x24,
	0x24,0x24,0x28,0x40,0x40,0x40,0x40,0x40,0x10,0x10,0x10,0x10,0x42,0x62,0x42,0x42,
	0x42,0x42,0x42,0x28,0x4a,0x42,0x42,0x42,0x42,0x82,0x20,0x48,0x00,0x00,0x00,0x00,
	0x00,0x10,0x44,0x3c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x04,0x00,0x00,0x00,
	0x00,0x00,0x00,0x10,0x3e,0x00,0x00,0x00,0x00,0x00,0x40,0x00,0x28,0x7c,0x44,0x88,
	0x80,0x80,0x80,0x44,0x10,0xc8,0x88,0x10,0x00,0x00,0x10,0x10,0x00,0xff,0x00,0x00,
	0x00,0x10,0x10,0x10,0x00,0x10,0x20,0x08,0x00,0x04,0x22,0x00,0x00,0x10,0x00,0x7e,
	0x50,0x08,0x48,0x00,0x10,0x08,0x18,0x10,0x00,0x00,0x00,0x08,0x42,0x10,0x02,0x08,
	0x24,0x5c,0x40,0x08,0x42,0x46,0x38,0x38,0x10,0x7e,0x08,0x02,0x4e,0x42,0x42,0x40,
	0x42,0x40,0x40,0x40,0x42,0x10,0x04,0x50,0x40,0xaa,0x52,0x42,0x42,0x42,0x42,0x40,
	0x10,0x42,0x44,0x82,0x28,0x28,0x08,0x20,0x20,0x04,0x00,0x00,0x00,0x3c,0x5c,0x3c,
	0x3a,0x3c,0x20,0x3a,0x5c,0x30,0x0c,0x44,0x10,0xec,0x5c,0x3c,0x5c,0x3a,0x5c,0x3c,
	0x7c,0x44,0x44,0x82,0x42,0x42,0x7e,0x08,0x10,0x10,0x00,0x54,0x85,0x10,0x40,0x22,
	0x30,0xff,0x00,0x28,0x00,0x51,0x78,0x48,0x00,0x7e,0x59,0x00,0x00,0x20,0x00,0x70,
	0x00,0x44,0xf4,0x00,0x00,0x00,0x00,0x12,0x26,0x4c,0xea,0x08,0x42,0x42,0x42,0x42,
	0x42,0x42,0x28,0x40,0x40,0x40,0x40,0x40,0x10,0x10,0x10,0x10,0x42,0x52,0x42,0x42,
	0x42,0x42,0x42,0x44,0x4a,0x42,0x42,0x42,0x42,0x44,0x20,0x70,0x3c,0x3c,0x3c,0x3c,
	0x3c,0x3c,0x04,0x42,0x3c,0x3c,0x3c,0x3c,0x30,0x30,0x30,0x30,0x3a,0x5c,0x3c,0x3c,
	0x3c,0x3c,0x3c,0x00,0x46,0x44,0x44,0x44,0x44,0x42,0x5c,0x42,0x38,0xfe,0x92,0xf8,
	0xe0,0x80,0x80,0x44,0x10,0xa8,0x50,0x10,0x00,0x00,0x10,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x10,0x00,0x10,0x80,0x02,0xfe,0xfe,0x20,0x00,0x00,0x10,0x00,0x24,
	0x38,0x08,0x48,0x00,0x10,0x08,0x7e,0x7c,0x00,0x7e,0x00,0x10,0x42,0x10,0x04,0x1c,
	0x44,0x62,0x5c,0x08,0x3c,0x3a,0x10,0x10,0x20,0x00,0x04,0x04,0x52,0x42,0x7c,0x40,
	0x42,0x78,0x78,0x40,0x7e,0x10,0x04,0x60,0x40,0x92,0x4a,0x42,0x7c,0x42,0x7c,0x3c,
	0x10,0x42,0x44,0x92,0x10,0x10,0x10,0x20,0x10,0x04,0x00,0x00,0x00,0x02,0x62,0x42,
	0x46,0x42,0x7c,0x44,0x62,0x10,0x04,0x48,0x10,0x92,0x62,0x42,0x62,0x46,0x22,0x42,
	0x20,0x44,0x44,0x82,0x24,0x42,0x04,0x30,0x10,0x0c,0x00,0x2a,0x99,0x10,0x40,0x20,
	0x48,0x38,0x10,0x14,0x00,0x5d,0x00,0x24,0x00,0x00,0x55,0x00,0x00,0x00,0x00,0x00,
	0x00,0x44,0x74,0x00,0x00,0x00,0x00,0x24,0x4a,0x92,0x16,0x04,0x42,0x42,0x42,0x42,
	0x42,0x42,0x4e,0x40,0x78,0x78,0x78,0x78,0x10,0x10,0x10,0x10,0x42,0x4a,0x42,0x42,
	0x42,0x42,0x42,0x00,0x52,0x42,0x42,0x42,0x42,0x28,0x20,0x48,0x02,0x02,0x02,0x02,
	0x02,0x02,0x1f,0x40,0x42,0x42,0x42,0x42,0x10,0x10,0x10,0x10,0x46,0x62,0x42,0x42,
	0x42,0x42,0x42,0x7c,0x4a,0x44,0x44,0x44,0x44,0x42,0x62,0x42,0x04,0x7c,0x44,0x88,
	0x80,0x78,0xf8,0x38,0xfe,0x98,0x20,0xf0,0xf0,0x1f,0x1f,0xff,0x00,0x00,0xff,0x00,
	0x00,0x1f,0xf0,0xff,0xff,0x10,0x20,0x08,0x24,0x10,0xf8,0x10,0x00,0x10,0x00,0x7e,
	0x14,0x10,0x30,0x00,0x10,0x08,0x18,0x10,0x00,0x00,0x00,0x20,0x42,0x10,0x18,0x02,
	0x44,0x02,0x62,0x10,0x42,0x02,0x00,0x00,0x10,0x00,0x08,0x08,0x56,0x7e,0x42,0x40,
	0x42,0x40,0x40,0x4e,0x42,0x10,0x04,0x50,0x40,0x92,0x46,0x42,0x40,0x42,0x50,0x02,
	0x10,0x42,0x28,0x92,0x28,0x10,0x20,0x20,0x08,0x04,0x00,0x00,0x00,0x3e,0x42,0x40,
	0x42,0x7e,0x20,0x44,0x42,0x10,0x04,0x70,0x10,0x92,0x42,0x42,0x42,0x42,0x20,0x30,
	0x20,0x44,0x44,0x92,0x18,0x42,0x08,0x08,0x10,0x10,0x00,0x54,0x91,0x10,0x42,0xf8,
	0x00,0xff,0x10,0x0c,0x00,0x22,0x00,0x12,0x00,0x00,0x22,0x00,0x00,0xf8,0x00,0x00,
	0x00,0x44,0x14,0x00,0x00,0x00,0x00,0x48,0x92,0x04,0x2a,0x02,0x7e,0x7e,0x7e,0x7e,
	0x7e,0x7e,0x78,0x40,0x40,0x40,0x40,0x40,0x10,0x10,0x10,0x10,0xfe,0x46,0x42,0x42,
	0x42,0x42,0x42,0x00,0x52,0x42,0x42,0x42,0x42,0x10,0x20,0x48,0x3e,0x3e,0x3e,0x3e,
	0x3e,0x3e,0x24,0x40,0x7e,0x7e,0x7e,0x7e,0x10,0x10,0x10,0x10,0x42,0x42,0x42,0x42,
	0x42,0x42,0x42,0x00,0x52,0x44,0x44,0x44,0x44,0x42,0x42,0x42,0x04,0x38,0x92,0x88,
	0x9e,0x3c,0x3e,0x00,0x10,0x88,0x3e,0x00,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x00,0x10,0x10,0x08,0x20,0x24,0xfe,0x20,0x00,0x00,0x10,0x00,0x24,
	0x78,0x24,0x4a,0x00,0x08,0x10,0x24,0x10,0x00,0x00,0x00,0x40,0x42,0x10,0x20,0x02,
	0x7e,0x02,0x42,0x10,0x42,0x02,0x00,0x00,0x08,0x7e,0x10,0x08,0x4a,0x42,0x42,0x40,
	0x42,0x40,0x40,0x42,0x42,0x10,0x04,0x48,0x40,0x82,0x42,0x42,0x40,0x52,0x48,0x02,
	0x10,0x42,0x28,0x92,0x44,0x10,0x40,0x20,0x04,0x04,0x00,0x00,0x00,0x42,0x42,0x40,
	0x42,0x40,0x20,0x38,0x42,0x10,0x04,0x48,0x10,0x92,0x42,0x42,0x62,0x46,0x20,0x0c,
	0x20,0x44,0x28,0x92,0x18,0x46,0x10,0x10,0x10,0x08,0x00,0x2a,0x81,0x10,0x3c,0x20,
	0x00,0x10,0x10,0x42,0x00,0x1c,0x00,0x00,0x00,0x00,0x1c,0x00,0x00,0x00,0x00,0x00,
	0x00,0x64,0x14,0x00,0x00,0x00,0x00,0x00,0x1f,0x08,0x4f,0x12,0x42,0x42,0x42,0x42,
	0x42,0x42,0x48,0x42,0x40,0x40,0x40,0x40,0x10,0x10,0x10,0x10,0x42,0x42,0x42,0x42,
	0x42,0x42,0x42,0x00,0x64,0x42,0x42,0x42,0x42,0x10,0x00,0x70,0x42,0x42,0x42,0x42,
	0x42,0x42,0x44,0x42,0x40,0x40,0x40,0x40,0x10,0x10,0x10,0x10,0x42,0x42,0x42,0x42,
	0x42,0x42,0x42,0x10,0x62,0x44,0x44,0x44,0x44,0x46,0x62,0x46,0x04,0x10,0x44,0x3e,
	0x10,0x22,0x20,0x00,0x10,0x20,0x08,0x00,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0xff,
	0x00,0x10,0x10,0x00,0x10,0x10,0x02,0x80,0x24,0x40,0x78,0x00,0x00,0x00,0x00,0x24,
	0x10,0x2a,0x44,0x00,0x08,0x10,0x00,0x00,0x38,0x00,0x10,0x80,0x24,0x10,0x40,0x42,
	0x04,0x42,0x42,0x20,0x42,0x04,0x10,0x38,0x04,0x00,0x20,0x00,0x40,0x42,0x42,0x42,
	0x42,0x40,0x40,0x46,0x42,0x10,0x44,0x44,0x40,0x82,0x42,0x42,0x40,0x4a,0x44,0x42,
	0x10,0x42,0x28,0xaa,0x82,0x10,0x40,0x20,0x02,0x04,0x00,0x00,0x00,0x46,0x62,0x42,
	0x46,0x40,0x20,0x40,0x42,0x10,0x04,0x44,0x10,0x92,0x42,0x42,0x5c,0x3a,0x20,0x42,
	0x22,0x44,0x28,0xaa,0x24,0x3a,0x20,0x10,0x10,0x08,0x00,0x54,0x91,0x10,0x10,0x78,
	0x00,0x10,0x00,0x42,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x5c,0x14,0x00,0x10,0x00,0x00,0x00,0x02,0x1e,0x02,0x0c,0x42,0x42,0x42,0x42,
	0x42,0x42,0x89,0x3c,0x40,0x40,0x40,0x40,0x10,0x10,0x10,0x10,0x42,0x42,0x42,0x42,
	0x42,0x42,0x42,0x00,0x38,0x42,0x42,0x42,0x42,0x10,0x00,0x40,0x46,0x46,0x46,0x46,
	0x46,0x46,0x4c,0x3c,0x40,0x40,0x40,0x40,0x10,0x10,0x10,0x10,0x44,0x42,0x42,0x42,
	0x42,0x42,0x42,0x00,0x7c,0x44,0x44,0x44,0x44,0x3a,0x5c,0x3a,0x07,0x00,0x92,0x08,
	0x1c,0x3c,0x3c,0x00,0xfe,0x20,0x08,0x00,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x00,0x10,0x10,0xfe,0xfe,0x44,0x80,0xa6,0x00,0x00,0x10,0x00,0x00,
	0x00,0x44,0x3a,0x00,0x04,0x20,0x00,0x00,0x30,0x00,0x38,0x80,0x18,0x7c,0x7e,0x3c,
	0x04,0x3c,0x3c,0x20,0x3c,0x38,0x38,0x30,0x02,0x00,0x40,0x08,0x3c,0x42,0xfc,0x3c,
	0xfc,0x7e,0x40,0x3a,0x42,0x7c,0x38,0x42,0x7e,0x82,0x42,0x3c,0x40,0x3c,0x42,0x3c,
	0x10,0x3c,0x10,0x44,0x82,0x10,0x7e,0x3c,0x02,0x3c,0x00,0x00,0x00,0x3a,0x5c,0x3c,
	0x3a,0x3c,0x20,0x3c,0x42,0x7c,0x44,0x42,0x7c,0x82,0x42,0x3c,0x40,0x02,0x20,0x3c,
	0x1c,0x3a,0x10,0x44,0x42,0x02,0x7e,0x0e,0x10,0x70,0x00,0x2a,0x81,0x10,0x10,0xa6,
	0x00,0x10,0x00,0x3c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x42,0x3e,0x00,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x42,0x42,0x42,0x42,
	0x42,0x42,0x9f,0x10,0x7e,0x7e,0x7e,0x7e,0x7c,0x7c,0x7c,0x7c,0xfc,0x42,0x3c,0x3c,
	0x3c,0x3c,0x3c,0x00,0x40,0x3c,0x3c,0x3c,0x3c,0x10,0x00,0x40,0x3a,0x3a,0x3a,0x3a,
	0x3a,0x3a,0x3f,0x10,0x3c,0x3c,0x3c,0x3c,0x7c,0x7c,0x7c,0x7c,0x38,0x42,0x3c,0x3c,
	0x3c,0x3c,0x3c,0x00,0x80,0x3a,0x3a,0x3a,0x3a,0x02,0x40,0x02,0x00,0x00,0x00,0x08,
	0x10,0x22,0x20,0x00,0x00,0x20,0x08,0x00,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0x00,
	0xff,0x10,0x10,0x00,0x10,0x10,0x00,0x00,0x00,0x00,0x40,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x40,0x00,0x10,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x10,0x40,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x02,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xff,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x42,0x00,0x00,0x44,0x00,0x00,0x00,0x00,0x00,0x40,0x02,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x42,0x00,0x00,0x00,0x00,0x00,0x54,0xff,0x00,0x00,0x40,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x40,0x00,0x00,0x08,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x48,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x48,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x42,0x40,0x42,0x00,0x00,0x00,0x08,
	0x10,0x22,0x20,0x00,0x00,0x3e,0x08,0x00,0x10,0x10,0x00,0x10,0x00,0x00,0x00,0x00,
	0x00,0x10,0x10,0x00,0x10,0x10,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x3c,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x40,0x02,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x3c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0xc0,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x38,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
	0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3c,0x40,0x3c,0x20,0x20,0x20,0x20,
	0x20,0x20,0x20,0x20,0x32,0x35,0x36,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,
	0x20,0x31,0x33,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x20,0x31,0x30,0x20,
	0x00,0x00,0x00,0x0b,0x00,0x08,0x08,0x00,0x03,0x0a,0x00,0x08,0x10,0x00,0x04,0x0b,
	0x00,0x08,0x18,0x00,0x04,0x0d,0x00,0x08,0x20,0x00,0x04,0x0d,0x00,0x08,0x28,0x00,
	0x04,0x0d,0x00,0x08,0x30,0x00,0x04,0x0d,0x00,0x08,0x38,0x00,0x04,0x08,0x00,0x08,
	0x40,0x00,0x05,0x0b,0x00,0x08,0x48,0x00,0x04,0x0d,0x00,0x08,0x50,0x00,0x04,0x0d,
	0x00,0x08,0x58,0x00,0x00,0x08,0x00,0x08,0x60,0x00,0x00,0x0d,0x00,0x08,0x68,0x00,
	0x00,0x0d,0x00,0x08,0x70,0x00,0x00,0x0d,0x00,0x08,0x78,0x00,0x00,0x0d,0x00,0x08,
	0x80,0x00,0x00,0x0d,0x00,0x08,0x88,0x00,0x00,0x0d,0x00,0x08,0x90,0x00,0x00,0x0d,
	0x00,0x08,0x98,0x00,0x00,0x0d,0x00,0x08,0xa0,0x00,0x00,0x0d,0x00,0x08,0xa8,0x00,
	0x00,0x0d,0x00,0x08,0xb0,0x00,0x00,0x0d,0x00,0x08,0xb8,0x00,0x00,0x0d,0x00,0x08,
	0xc0,0x00,0x00,0x0d,0x00,0x08,0xc8,0x00,0x00,0x0d,0x00,0x08,0xd0,0x00,0x00,0x0d,
	0x00,0x08,0xd8,0x00,0x00,0x0d,0x00,0x08,0xe0,0x00,0x00,0x0d,0x00,0x08,0xe8,0x00,
	0x00,0x0d,0x00,0x08,0xf0,0x00,0x04,0x0c,0x00,0x08,0xf8,0x00,0x00,0x0d,0x00,0x08,
	0x00,0x01,0x00,0x0d,0x00,0x08,0x08,0x01,0x02,0x0b,0x00,0x08,0x10,0x01,0x00,0x0d,
	0x00,0x08,0x18,0x01,0x00,0x0d,0x00,0x08,0x20,0x01,0x00,0x0d,0x00,0x08,0x28,0x01,
	0x00,0x0d,0x00,0x08,0x30,0x01,0x00,0x0d,0x00,0x08,0x38,0x01,0x00,0x0d,0x00,0x08,
	0x40,0x01,0x00,0x0d,0x00,0x08,0x48,0x01,0x00,0x0d,0x00,0x08,0x50,0x01,0x00,0x0d,
	0x00,0x08,0x58,0x01,0x00,0x0d,0x00,0x08,0x60,0x01,0x00,0x0d,0x00,0x08,0x68,0x01,
	0x00,0x0d,0x00,0x08,0x70,0x01,0x00,0x0d,0x00,0x08,0x78,0x01,0x00,0x0d,0x00,0x08,
	0x80,0x01,0x00,0x0d,0x00,0x08,0x88,0x01,0x00,0x0d,0x00,0x08,0x90,0x01,0x00,0x0d,
	0x00,0x08,0x98,0x01,0x00,0x0d,0x00,0x08,0xa0,0x01,0x00,0x0d,0x00,0x08,0xa8,0x01,
	0x00,0x0d,0x00,0x08,0xb0,0x01,0x00,0x0d,0x00,0x08,0xb8,0x01,0x00,0x0d,0x00,0x08,
	0xc0,0x01,0x00,0x0d,0x00,0x08,0xc8,0x01,0x00,0x0d,0x00,0x08,0xd0,0x01,0x00,0x0d,
	0x00,0x08,0xd8,0x01,0x00,0x0d,0x00,0x08,0xe0,0x01,0x00,0x0d,0x00,0x08,0xe8,0x01,
	0x00,0x0d,0x00,0x08,0xf0,0x01,0x00,0x0d,0x00,0x08,0xf8,0x01,0x00,0x0d,0x00,0x08,
	0x00,0x02,0x00,0x0d,0x00,0x08,0x08,0x02,0x02,0x0b,0x00,0x08,0x10,0x02,0x00,0x0d,
	0x00,0x08,0x18,0x02,0x02,0x0b,0x00,0x08,0x20,0x02,0x02,0x0b,0x00,0x08,0x28,0x02,
	0x02,0x0b,0x00,0x08,0x30,0x02,0x00,0x0d,0x00,0x08,0x38,0x02,0x00,0x0d,0x00,0x08,
	0x40,0x02,0x00,0x0d,0x00,0x08,0x48,0x02,0x02,0x0b,0x00,0x08,0x50,0x02,0x00,0x0d,
	0x00,0x08,0x58,0x02,0x00,0x0d,0x00,0x08,0x60,0x02,0x00,0x0d,0x00,0x08,0x68,0x02,
	0x00,0x0d,0x00,0x08,0x70,0x02,0x02,0x0b,0x00,0x08,0x78,0x02,0x02,0x0b,0x00,0x08,
	0x80,0x02,0x00,0x0d,0x00,0x08,0x88,0x02,0x00,0x0d,0x00,0x08,0x90,0x02,0x00,0x0d,
	0x00,0x08,0x98,0x02,0x00,0x0d,0x00,0x08,0xa0,0x02,0x00,0x0d,0x00,0x08,0xa8,0x02,
	0x02,0x0b,0x00,0x08,0xb0,0x02,0x00,0x0d,0x00,0x08,0xb8,0x02,0x00,0x0d,0x00,0x08,
	0xc0,0x02,0x00,0x0d,0x00,0x08,0xc8,0x02,0x02,0x0b,0x00,0x08,0xd0,0x02,0x00,0x0d,
	0x00,0x08,0xd8,0x02,0x00,0x0d,0x00,0x08,0xe0,0x02,0x00,0x0d,0x00,0x08,0xe8,0x02,
	0x02,0x0b,0x00,0x08,0xf0,0x02,0x02,0x05,0x00,0x08,0xf8,0x02,0x0b,0x0c,0x00,0x08,
	0x00,0x03,0x00,0x0d,0x00,0x08,0x08,0x03,0x05,0x0b,0x00,0x08,0x10,0x03,0x00,0x0d,
	0x00,0x08,0x18,0x03,0x05,0x0b,0x00,0x08,0x20,0x03,0x02,0x0b,0x00,0x08,0x28,0x03,
	0x05,0x0b,0x00,0x08,0x30,0x03,0x00,0x0d,0x00,0x08,0x38,0x03,0x00,0x0d,0x00,0x08,
	0x40,0x03,0x00,0x0d,0x00,0x08,0x48,0x03,0x03,0x0b,0x00,0x08,0x50,0x03,0x00,0x0d,
	0x00,0x08,0x58,0x03,0x00,0x0d,0x00,0x08,0x60,0x03,0x00,0x0d,0x00,0x08,0x68,0x03,
	0x00,0x0d,0x00,0x08,0x70,0x03,0x05,0x0b,0x00,0x08,0x78,0x03,0x05,0x0b,0x00,0x08,
	0x80,0x03,0x05,0x0d,0x00,0x08,0x88,0x03,0x05,0x0d,0x00,0x08,0x90,0x03,0x05,0x0b,
	0x00,0x08,0x98,0x03,0x05,0x0b,0x00,0x08,0xa0,0x03,0x03,0x0b,0x00,0x08,0xa8,0x03,
	0x05,0x0b,0x00,0x08,0xb0,0x03,0x05,0x0b,0x00,0x08,0xb8,0x03,0x05,0x0b,0x00,0x08,
	0xc0,0x03,0x05,0x0b,0x00,0x08,0xc8,0x03,0x05,0x0d,0x00,0x08,0xd0,0x03,0x00,0x0d,
	0x00,0x08,0xd8,0x03,0x00,0x0d,0x00,0x08,0xe0,0x03,0x00,0x0d,0x00,0x08,0xe8,0x03,
	0x00,0x0d,0x00,0x08,0xf0,0x03,0x00,0x0d,0x00,0x08,0xf8,0x03,0x01,0x0c,0x00,0x08,
	0x00,0x04,0x00,0x0c,0x00,0x08,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,
	0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,
	0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,
	0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,
	0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,
	0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,
	0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,
	0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x08,0x08,0x04,0x00,0x00,0x00,0x08,0x08,0x04,
	0x00,0x00,0x00,0x08,0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x00,
	0x08,0x04,0x00,0x00,0x00,0x00,0x08,0x04,0x00,0x00,0x00,0x08,0x08,0x04,0x00,0x00,
	0x00,0x08,0x08,0x04,0x00,0x00,0x00,0x08,0x08,0x04,0x00,0x00,0x00,0x08,0x08,0x04,
	0x00,0x00,0x00,0x08,0x08,0x04,0x00,0x00,0x00,0x08,0x08,0x04,0x00,0x00,0x00,0x08,
	0x08,0x04,0x00,0x00,0x00,0x08,0x08,0x04,0x02,0x0b,0x00,0x08,0x10,0x04,0x01,0x0b,
	0x00,0x08,0x18,0x04,0x04,0x0c,0x00,0x08,0x20,0x04,0x01,0x07,0x00,0x08,0x28,0x04,
	0x02,0x0b,0x00,0x08,0x30,0x04,0x02,0x09,0x00,0x08,0x38,0x04,0x01,0x0b,0x00,0x08,
	0x40,0x04,0x01,0x02,0x00,0x08,0x48,0x04,0x01,0x09,0x00,0x08,0x50,0x04,0x01,0x06,
	0x00,0x08,0x58,0x04,0x03,0x08,0x00,0x08,0x60,0x04,0x03,0x05,0x00,0x08,0x68,0x04,
	0x05,0x06,0x00,0x08,0x70,0x04,0x01,0x09,0x00,0x08,0x78,0x04,0x01,0x02,0x00,0x08,
	0x80,0x04,0x01,0x04,0x00,0x08,0x88,0x04,0x01,0x08,0x00,0x08,0x90,0x04,0x01,0x05,
	0x00,0x08,0x98,0x04,0x01,0x06,0x00,0x08,0xa0,0x04,0x01,0x04,0x00,0x08,0xa8,0x04,
	0x03,0x0d,0x00,0x08,0xb0,0x04,0x02,0x0b,0x00,0x08,0xb8,0x04,0x03,0x05,0x00,0x08,
	0xc0,0x04,0x09,0x0d,0x00,0x08,0xc8,0x04,0x01,0x05,0x00,0x08,0xd0,0x04,0x01,0x05,
	0x00,0x08,0xd8,0x04,0x03,0x08,0x00,0x08,0xe0,0x04,0x01,0x0a,0x00,0x08,0xe8,0x04,
	0x01,0x0a,0x00,0x08,0xf0,0x04,0x01,0x0a,0x00,0x08,0xf8,0x04,0x02,0x0a,0x00,0x08,
	0x00,0x05,0x00,0x0b,0x00,0x08,0x08,0x05,0x00,0x0b,0x00,0x08,0x10,0x05,0x00,0x0b,
	0x00,0x08,0x18,0x05,0x00,0x0b,0x00,0x08,0x20,0x05,0x01,0x0b,0x00,0x08,0x28,0x05,
	0x00,0x0b,0x00,0x08,0x30,0x05,0x02,0x0b,0x00,0x08,0x38,0x05,0x02,0x0d,0x00,0x08,
	0x40,0x05,0x00,0x0b,0x00,0x08,0x48,0x05,0x00,0x0b,0x00,0x08,0x50,0x05,0x00,0x0b,
	0x00,0x08,0x58,0x05,0x01,0x0b,0x00,0x08,0x60,0x05,0x00,0x0b,0x00,0x08,0x68,0x05,
	0x00,0x0b,0x00,0x08,0x70,0x05,0x00,0x0b,0x00,0x08,0x78,0x05,0x01,0x0b,0x00,0x08,
	0x80,0x05,0x02,0x0b,0x00,0x08,0x88,0x05,0x00,0x0b,0x00,0x08,0x90,0x05,0x00,0x0b,
	0x00,0x08,0x98,0x05,0x00,0x0b,0x00,0x08,0xa0,0x05,0x00,0x0b,0x00,0x08,0xa8,0x05,
	0x00,0x0b,0x00,0x08,0xb0,0x05,0x01,0x0b,0x00,0x08,0xb8,0x05,0x01,0x06,0x00,0x08,
	0xc0,0x05,0x01,0x0b,0x00,0x08,0xc8,0x05,0x00,0x0b,0x00,0x08,0xd0,0x05,0x00,0x0b,
	0x00,0x08,0xd8,0x05,0x00,0x0b,0x00,0x08,0xe0,0x05,0x01,0x0b,0x00,0x08,0xe8,0x05,
	0x00,0x0b,0x00,0x08,0xf0,0x05,0x02,0x08,0x00,0x08,0xf8,0x05,0x01,0x0b,0x00,0x08,
	0x00,0x06,0x02,0x0b,0x00,0x08,0x08,0x06,0x02,0x0b,0x00,0x08,0x10,0x06,0x02,0x0b,
	0x00,0x08,0x18,0x06,0x02,0x0b,0x00,0x08,0x20,0x06,0x03,0x0b,0x00,0x08,0x28,0x06,
	0x01,0x0b,0x00,0x08,0x30,0x06,0x03,0x0b,0x00,0x08,0x38,0x06,0x04,0x0d,0x00,0x08,
	0x40,0x06,0x02,0x0b,0x00,0x08,0x48,0x06,0x02,0x0b,0x00,0x08,0x50,0x06,0x02,0x0b,
	0x00,0x08,0x58,0x06,0x03,0x0b,0x00,0x08,0x60,0x06,0x02,0x0b,0x00,0x08,0x68,0x06,
	0x02,0x0b,0x00,0x08,0x70,0x06,0x02,0x0b,0x00,0x08,0x78,0x06,0x03,0x0b,0x00,0x08,
	0x80,0x06,0x01,0x0b,0x00,0x08,0x88,0x06,0x02,0x0b,0x00,0x08,0x90,0x06,0x02,0x0b,
	0x00,0x08,0x98,0x06,0x02,0x0b,0x00,0x08,0xa0,0x06,0x02,0x0b,0x00,0x08,0xa8,0x06,
	0x02,0x0b,0x00,0x08,0xb0,0x06,0x03,0x0b,0x00,0x08,0xb8,0x06,0x04,0x09,0x00,0x08,
	0xc0,0x06,0x03,0x0b,0x00,0x08,0xc8,0x06,0x02,0x0b,0x00,0x08,0xd0,0x06,0x02,0x0b,
	0x00,0x08,0xd8,0x06,0x02,0x0b,0x00,0x08,0xe0,0x06,0x03,0x0b,0x00,0x08,0xe8,0x06,
	0x02,0x0d,0x00,0x08,0xf0,0x06,0x03,0x0d,0x00,0x08,0xf8,0x06,0x03,0x0d,0x00,0x08,
	0x00,0x07,0x00,0x00,0x00,0x08,0x00,
	/* pad */
	0x00,0x00,0x00,0x00,0x00,0x00,0x00
};

int	sizeofdefont = sizeof defontdata;

Subfont*
getdefont(Display *d)
{
	char *hdr, *p;
	int n;
	Fontchar *fc;
	Subfont *f;
	int ld;
	Rectangle r;
	Image *i;

	/*
	 * make sure data is word-aligned.  this is true with Plan 9 compilers
	 * but not in general.  the byte order is right because the data is
	 * declared as char*, not ulong*.
	 */
	p = (char*)defontdata;
	n = (ulong)p & 3;
	if(n != 0){
		memmove(p+(4-n), p, sizeof defontdata-n);
		p += 4-n;
	}
	ld = atoi(p+0*12);
	r.min.x = atoi(p+1*12);
	r.min.y = atoi(p+2*12);
	r.max.x = atoi(p+3*12);
	r.max.y = atoi(p+4*12);
	/* build image by hand, using existing data. */
	i = allocimage(d, r, ld, 0, 0);
	if(i == 0)
		return 0;

	p += 5*12;
	n = loadimage(i, r, (uchar*)p, (defontdata+sizeof defontdata)-(uchar*)p);
	if(n < 0){
		freeimage(i);
		return 0;
	}

	hdr = p+n;
	n = atoi(hdr);
	p = hdr+3*12;
	fc = malloc(sizeof(Fontchar)*(n+1));
	if(fc == 0){
		freeimage(i);
		return 0;
	}
	_unpackinfo(fc, (uchar*)p, n);
	f = allocsubfont("*default*", n, atoi(hdr+12), atoi(hdr+24), fc, i);
	if(f == 0){
		freeimage(i);
		free(fc);
		return 0;
	}
	return f;
}
