implement Imageremap;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Display, Image: import draw;

include "bufio.m";

include "imagefile.m";

closest:= array[16*16*16] of {
	byte 255,byte 255,byte 255,byte 254,byte 254,byte 237,byte 220,byte 203,
	byte 253,byte 236,byte 219,byte 202,byte 252,byte 235,byte 218,byte 201,
	byte 255,byte 255,byte 255,byte 254,byte 254,byte 237,byte 220,byte 203,
	byte 253,byte 236,byte 219,byte 202,byte 252,byte 235,byte 218,byte 201,
	byte 255,byte 255,byte 255,byte 250,byte 250,byte 250,byte 220,byte 249,
	byte 249,byte 249,byte 232,byte 248,byte 248,byte 248,byte 231,byte 201,
	byte 251,byte 251,byte 250,byte 250,byte 250,byte 250,byte 249,byte 249,
	byte 249,byte 249,byte 232,byte 248,byte 248,byte 248,byte 231,byte 201,
	byte 251,byte 251,byte 250,byte 250,byte 250,byte 233,byte 233,byte 249,
	byte 249,byte 232,byte 215,byte 215,byte 248,byte 231,byte 214,byte 197,
	byte 234,byte 234,byte 250,byte 250,byte 233,byte 233,byte 216,byte 216,
	byte 249,byte 232,byte 215,byte 198,byte 198,byte 231,byte 214,byte 197,
	byte 217,byte 217,byte 217,byte 246,byte 233,byte 216,byte 216,byte 199,
	byte 199,byte 215,byte 215,byte 198,byte 198,byte 198,byte 214,byte 197,
	byte 200,byte 200,byte 246,byte 246,byte 246,byte 216,byte 199,byte 199,
	byte 245,byte 245,byte 198,byte 244,byte 244,byte 244,byte 227,byte 197,
	byte 247,byte 247,byte 246,byte 246,byte 246,byte 246,byte 199,byte 245,
	byte 245,byte 245,byte 228,byte 244,byte 244,byte 244,byte 227,byte 193,
	byte 230,byte 230,byte 246,byte 246,byte 229,byte 229,byte 212,byte 245,
	byte 245,byte 228,byte 228,byte 211,byte 244,byte 227,byte 210,byte 193,
	byte 213,byte 213,byte 229,byte 229,byte 212,byte 212,byte 212,byte 195,
	byte 228,byte 228,byte 211,byte 211,byte 194,byte 227,byte 210,byte 193,
	byte 196,byte 196,byte 242,byte 242,byte 212,byte 195,byte 195,byte 241,
	byte 241,byte 211,byte 211,byte 194,byte 194,byte 240,byte 210,byte 193,
	byte 243,byte 243,byte 242,byte 242,byte 242,byte 195,byte 195,byte 241,
	byte 241,byte 241,byte 194,byte 194,byte 240,byte 240,byte 239,byte 205,
	byte 226,byte 226,byte 242,byte 242,byte 225,byte 225,byte 195,byte 241,
	byte 241,byte 224,byte 224,byte 240,byte 240,byte 239,byte 239,byte 205,
	byte 209,byte 209,byte 225,byte 225,byte 208,byte 208,byte 208,byte 224,
	byte 224,byte 223,byte 223,byte 223,byte 239,byte 239,byte 222,byte 205,
	byte 192,byte 192,byte 192,byte 192,byte 207,byte 207,byte 207,byte 207,
	byte 206,byte 206,byte 206,byte 206,byte 205,byte 205,byte 205,byte 205,
	byte 255,byte 255,byte 255,byte 254,byte 254,byte 237,byte 220,byte 203,
	byte 253,byte 236,byte 219,byte 202,byte 252,byte 235,byte 218,byte 201,
	byte 255,byte 238,byte 221,byte 221,byte 254,byte 237,byte 220,byte 203,
	byte 253,byte 236,byte 219,byte 202,byte 252,byte 235,byte 218,byte 201,
	byte 255,byte 221,byte 221,byte 221,byte 204,byte 250,byte 220,byte 249,
	byte 249,byte 249,byte 232,byte 248,byte 248,byte 248,byte 231,byte 201,
	byte 251,byte 221,byte 221,byte 204,byte 250,byte 250,byte 249,byte 249,
	byte 249,byte 249,byte 232,byte 248,byte 248,byte 248,byte 231,byte 201,
	byte 251,byte 251,byte 204,byte 250,byte 250,byte 233,byte 233,byte 249,
	byte 249,byte 232,byte 215,byte 215,byte 248,byte 231,byte 214,byte 197,
	byte 234,byte 234,byte 250,byte 250,byte 233,byte 233,byte 216,byte 216,
	byte 249,byte 232,byte 215,byte 198,byte 198,byte 231,byte 214,byte 197,
	byte 217,byte 217,byte 217,byte 246,byte 233,byte 216,byte 216,byte 199,
	byte 199,byte 215,byte 215,byte 198,byte 198,byte 198,byte 214,byte 197,
	byte 200,byte 200,byte 246,byte 246,byte 246,byte 216,byte 199,byte 199,
	byte 245,byte 245,byte 198,byte 244,byte 244,byte 244,byte 227,byte 197,
	byte 247,byte 247,byte 246,byte 246,byte 246,byte 246,byte 199,byte 245,
	byte 245,byte 245,byte 228,byte 244,byte 244,byte 244,byte 227,byte 193,
	byte 230,byte 230,byte 246,byte 246,byte 229,byte 229,byte 212,byte 245,
	byte 245,byte 228,byte 228,byte 211,byte 244,byte 227,byte 210,byte 193,
	byte 213,byte 213,byte 229,byte 229,byte 212,byte 212,byte 212,byte 195,
	byte 228,byte 228,byte 211,byte 211,byte 194,byte 227,byte 210,byte 193,
	byte 196,byte 196,byte 242,byte 242,byte 212,byte 195,byte 195,byte 241,
	byte 241,byte 211,byte 211,byte 194,byte 194,byte 240,byte 210,byte 193,
	byte 243,byte 243,byte 242,byte 242,byte 242,byte 195,byte 195,byte 241,
	byte 241,byte 241,byte 194,byte 194,byte 240,byte 240,byte 239,byte 205,
	byte 226,byte 226,byte 242,byte 242,byte 225,byte 225,byte 195,byte 241,
	byte 241,byte 224,byte 224,byte 240,byte 240,byte 239,byte 239,byte 205,
	byte 209,byte 209,byte 225,byte 225,byte 208,byte 208,byte 208,byte 224,
	byte 224,byte 223,byte 223,byte 223,byte 239,byte 239,byte 222,byte 205,
	byte 192,byte 192,byte 192,byte 192,byte 207,byte 207,byte 207,byte 207,
	byte 206,byte 206,byte 206,byte 206,byte 205,byte 205,byte 205,byte 205,
	byte 255,byte 255,byte 255,byte 191,byte 191,byte 191,byte 220,byte 190,
	byte 190,byte 190,byte 173,byte 189,byte 189,byte 189,byte 172,byte 201,
	byte 255,byte 221,byte 221,byte 221,byte 204,byte 191,byte 220,byte 190,
	byte 190,byte 190,byte 173,byte 189,byte 189,byte 189,byte 172,byte 201,
	byte 255,byte 221,byte 221,byte 204,byte 204,byte 204,byte 186,byte 186,
	byte 186,byte 186,byte 186,byte 185,byte 185,byte 185,byte 168,byte 201,
	byte 188,byte 221,byte 204,byte 204,byte 204,byte 187,byte 186,byte 186,
	byte 186,byte 186,byte 232,byte 185,byte 185,byte 185,byte 168,byte 201,
	byte 188,byte 204,byte 204,byte 204,byte 187,byte 187,byte 186,byte 186,
	byte 186,byte 186,byte 169,byte 185,byte 185,byte 185,byte 168,byte 197,
	byte 188,byte 188,byte 204,byte 187,byte 187,byte 233,byte 216,byte 186,
	byte 186,byte 186,byte 215,byte 185,byte 185,byte 185,byte 168,byte 197,
	byte 217,byte 217,byte 183,byte 183,byte 183,byte 216,byte 216,byte 199,
	byte 182,byte 182,byte 215,byte 198,byte 198,byte 181,byte 214,byte 197,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 183,byte 199,byte 182,
	byte 182,byte 182,byte 182,byte 181,byte 181,byte 181,byte 181,byte 197,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 183,byte 182,byte 182,
	byte 182,byte 182,byte 182,byte 181,byte 181,byte 181,byte 164,byte 193,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 183,byte 182,byte 182,
	byte 182,byte 228,byte 165,byte 181,byte 181,byte 164,byte 164,byte 193,
	byte 167,byte 167,byte 183,byte 229,byte 166,byte 212,byte 212,byte 182,
	byte 182,byte 165,byte 211,byte 211,byte 181,byte 164,byte 210,byte 193,
	byte 180,byte 180,byte 179,byte 179,byte 179,byte 179,byte 195,byte 178,
	byte 178,byte 178,byte 211,byte 194,byte 177,byte 177,byte 177,byte 193,
	byte 180,byte 180,byte 179,byte 179,byte 179,byte 179,byte 195,byte 178,
	byte 178,byte 178,byte 178,byte 177,byte 177,byte 177,byte 177,byte 205,
	byte 180,byte 180,byte 179,byte 179,byte 179,byte 179,byte 178,byte 178,
	byte 178,byte 161,byte 161,byte 177,byte 177,byte 177,byte 160,byte 205,
	byte 163,byte 163,byte 162,byte 162,byte 162,byte 162,byte 208,byte 178,
	byte 161,byte 161,byte 223,byte 177,byte 177,byte 160,byte 160,byte 205,
	byte 192,byte 192,byte 192,byte 192,byte 207,byte 207,byte 207,byte 207,
	byte 206,byte 206,byte 206,byte 206,byte 205,byte 205,byte 205,byte 205,
	byte 176,byte 176,byte 191,byte 191,byte 191,byte 191,byte 190,byte 190,
	byte 190,byte 190,byte 173,byte 189,byte 189,byte 189,byte 172,byte 201,
	byte 176,byte 221,byte 221,byte 204,byte 191,byte 191,byte 190,byte 190,
	byte 190,byte 190,byte 173,byte 189,byte 189,byte 189,byte 172,byte 201,
	byte 188,byte 221,byte 204,byte 204,byte 204,byte 187,byte 186,byte 186,
	byte 186,byte 186,byte 173,byte 185,byte 185,byte 185,byte 168,byte 201,
	byte 188,byte 204,byte 204,byte 204,byte 187,byte 187,byte 186,byte 186,
	byte 186,byte 186,byte 169,byte 185,byte 185,byte 185,byte 168,byte 201,
	byte 188,byte 188,byte 204,byte 187,byte 187,byte 187,byte 186,byte 186,
	byte 186,byte 186,byte 169,byte 185,byte 185,byte 185,byte 168,byte 197,
	byte 188,byte 188,byte 187,byte 187,byte 187,byte 170,byte 170,byte 186,
	byte 186,byte 169,byte 169,byte 185,byte 185,byte 168,byte 168,byte 197,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 170,byte 170,byte 182,
	byte 182,byte 169,byte 152,byte 152,byte 181,byte 168,byte 151,byte 197,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 183,byte 182,byte 182,
	byte 182,byte 182,byte 182,byte 181,byte 181,byte 181,byte 164,byte 197,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 183,byte 182,byte 182,
	byte 182,byte 182,byte 165,byte 181,byte 181,byte 181,byte 164,byte 193,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 166,byte 166,byte 182,
	byte 182,byte 165,byte 165,byte 181,byte 181,byte 164,byte 164,byte 193,
	byte 167,byte 167,byte 167,byte 166,byte 166,byte 166,byte 149,byte 182,
	byte 165,byte 165,byte 165,byte 148,byte 181,byte 164,byte 147,byte 193,
	byte 180,byte 180,byte 179,byte 179,byte 179,byte 179,byte 149,byte 178,
	byte 178,byte 178,byte 148,byte 177,byte 177,byte 177,byte 147,byte 193,
	byte 180,byte 180,byte 179,byte 179,byte 179,byte 179,byte 178,byte 178,
	byte 178,byte 178,byte 178,byte 177,byte 177,byte 177,byte 160,byte 205,
	byte 180,byte 180,byte 179,byte 179,byte 179,byte 162,byte 162,byte 178,
	byte 178,byte 161,byte 161,byte 177,byte 177,byte 160,byte 160,byte 205,
	byte 163,byte 163,byte 162,byte 162,byte 162,byte 162,byte 145,byte 161,
	byte 161,byte 161,byte 144,byte 144,byte 160,byte 160,byte 160,byte 205,
	byte 192,byte 192,byte 192,byte 192,byte 207,byte 207,byte 207,byte 207,
	byte 206,byte 206,byte 206,byte 206,byte 205,byte 205,byte 205,byte 205,
	byte 176,byte 176,byte 191,byte 191,byte 191,byte 174,byte 174,byte 190,
	byte 190,byte 173,byte 156,byte 156,byte 189,byte 172,byte 155,byte 138,
	byte 176,byte 176,byte 204,byte 191,byte 191,byte 174,byte 174,byte 190,
	byte 190,byte 173,byte 156,byte 156,byte 189,byte 172,byte 155,byte 138,
	byte 188,byte 204,byte 204,byte 204,byte 187,byte 187,byte 186,byte 186,
	byte 186,byte 186,byte 169,byte 185,byte 185,byte 185,byte 168,byte 138,
	byte 188,byte 188,byte 204,byte 187,byte 187,byte 187,byte 186,byte 186,
	byte 186,byte 186,byte 169,byte 185,byte 185,byte 185,byte 168,byte 138,
	byte 188,byte 188,byte 187,byte 187,byte 187,byte 170,byte 170,byte 186,
	byte 186,byte 169,byte 169,byte 185,byte 185,byte 168,byte 151,byte 134,
	byte 171,byte 171,byte 187,byte 187,byte 170,byte 170,byte 170,byte 186,
	byte 186,byte 169,byte 152,byte 152,byte 185,byte 168,byte 151,byte 134,
	byte 171,byte 171,byte 183,byte 183,byte 170,byte 170,byte 170,byte 153,
	byte 182,byte 169,byte 152,byte 135,byte 135,byte 168,byte 151,byte 134,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 183,byte 153,byte 182,
	byte 182,byte 182,byte 182,byte 181,byte 181,byte 181,byte 164,byte 134,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 183,byte 182,byte 182,
	byte 182,byte 182,byte 165,byte 181,byte 181,byte 181,byte 164,byte 130,
	byte 167,byte 167,byte 183,byte 183,byte 166,byte 166,byte 166,byte 182,
	byte 182,byte 165,byte 165,byte 181,byte 181,byte 164,byte 147,byte 130,
	byte 150,byte 150,byte 166,byte 166,byte 166,byte 149,byte 149,byte 182,
	byte 165,byte 165,byte 148,byte 148,byte 164,byte 164,byte 147,byte 130,
	byte 150,byte 150,byte 179,byte 179,byte 179,byte 149,byte 132,byte 178,
	byte 178,byte 178,byte 148,byte 131,byte 177,byte 177,byte 147,byte 130,
	byte 180,byte 180,byte 179,byte 179,byte 179,byte 179,byte 132,byte 178,
	byte 178,byte 178,byte 161,byte 177,byte 177,byte 177,byte 160,byte 142,
	byte 163,byte 163,byte 179,byte 179,byte 162,byte 162,byte 162,byte 178,
	byte 178,byte 161,byte 161,byte 177,byte 177,byte 160,byte 160,byte 142,
	byte 146,byte 146,byte 162,byte 162,byte 145,byte 145,byte 145,byte 161,
	byte 161,byte 144,byte 144,byte 144,byte 160,byte 160,byte 159,byte 142,
	byte 129,byte 129,byte 129,byte 129,byte 128,byte 128,byte 128,byte 128,
	byte 143,byte 143,byte 143,byte 143,byte 142,byte 142,byte 142,byte 142,
	byte 175,byte 175,byte 191,byte 191,byte 174,byte 174,byte 157,byte 157,
	byte 190,byte 173,byte 156,byte 139,byte 139,byte 172,byte 155,byte 138,
	byte 175,byte 175,byte 191,byte 191,byte 174,byte 174,byte 157,byte 157,
	byte 190,byte 173,byte 156,byte 139,byte 139,byte 172,byte 155,byte 138,
	byte 188,byte 188,byte 204,byte 187,byte 187,byte 187,byte 157,byte 186,
	byte 186,byte 186,byte 156,byte 185,byte 185,byte 185,byte 168,byte 138,
	byte 188,byte 188,byte 187,byte 187,byte 187,byte 170,byte 170,byte 186,
	byte 186,byte 169,byte 169,byte 185,byte 185,byte 168,byte 168,byte 138,
	byte 171,byte 171,byte 187,byte 187,byte 170,byte 170,byte 170,byte 186,
	byte 186,byte 169,byte 152,byte 152,byte 185,byte 168,byte 151,byte 134,
	byte 171,byte 171,byte 187,byte 170,byte 170,byte 170,byte 170,byte 153,
	byte 169,byte 169,byte 152,byte 135,byte 135,byte 168,byte 151,byte 134,
	byte 154,byte 154,byte 154,byte 170,byte 170,byte 170,byte 153,byte 153,
	byte 169,byte 152,byte 152,byte 135,byte 135,byte 135,byte 151,byte 134,
	byte 154,byte 154,byte 183,byte 183,byte 183,byte 153,byte 153,byte 153,
	byte 182,byte 182,byte 135,byte 135,byte 181,byte 181,byte 164,byte 134,
	byte 184,byte 184,byte 183,byte 183,byte 183,byte 166,byte 166,byte 182,
	byte 182,byte 165,byte 165,byte 181,byte 181,byte 164,byte 164,byte 130,
	byte 167,byte 167,byte 183,byte 166,byte 166,byte 166,byte 149,byte 182,
	byte 165,byte 165,byte 165,byte 148,byte 181,byte 164,byte 147,byte 130,
	byte 150,byte 150,byte 150,byte 166,byte 149,byte 149,byte 149,byte 132,
	byte 165,byte 165,byte 148,byte 148,byte 131,byte 147,byte 147,byte 130,
	byte 133,byte 133,byte 179,byte 179,byte 149,byte 132,byte 132,byte 132,
	byte 178,byte 148,byte 148,byte 131,byte 131,byte 131,byte 130,byte 130,
	byte 133,byte 133,byte 179,byte 179,byte 179,byte 132,byte 132,byte 178,
	byte 178,byte 178,byte 131,byte 131,byte 131,byte 177,byte 160,byte 142,
	byte 163,byte 163,byte 179,byte 162,byte 162,byte 162,byte 132,byte 178,
	byte 161,byte 161,byte 144,byte 131,byte 177,byte 160,byte 160,byte 142,
	byte 146,byte 146,byte 162,byte 162,byte 145,byte 145,byte 145,byte 161,
	byte 161,byte 144,byte 144,byte 143,byte 160,byte 160,byte 159,byte 142,
	byte 129,byte 129,byte 129,byte 129,byte 128,byte 128,byte 128,byte 128,
	byte 143,byte 143,byte 143,byte 143,byte 142,byte 142,byte 142,byte 142,
	byte 158,byte 158,byte 158,byte 112,byte 174,byte 157,byte 157,byte 140,
	byte 140,byte 156,byte 156,byte 139,byte 139,byte 139,byte 155,byte 138,
	byte 158,byte 158,byte 158,byte 112,byte 174,byte 157,byte 157,byte 140,
	byte 140,byte 156,byte 156,byte 139,byte 139,byte 139,byte 155,byte 138,
	byte 158,byte 158,byte 124,byte 124,byte 124,byte 157,byte 157,byte 140,
	byte 123,byte 123,byte 156,byte 139,byte 139,byte 122,byte 155,byte 138,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 170,byte 170,byte 123,
	byte 123,byte 169,byte 152,byte 152,byte 122,byte 168,byte 151,byte 138,
	byte 171,byte 171,byte 124,byte 124,byte 170,byte 170,byte 170,byte 153,
	byte 123,byte 169,byte 152,byte 135,byte 135,byte 168,byte 151,byte 134,
	byte 154,byte 154,byte 154,byte 170,byte 170,byte 170,byte 153,byte 153,
	byte 169,byte 152,byte 152,byte 135,byte 135,byte 135,byte 151,byte 134,
	byte 154,byte 154,byte 154,byte 170,byte 170,byte 153,byte 153,byte 153,
	byte 136,byte 152,byte 135,byte 135,byte 135,byte 135,byte 134,byte 134,
	byte 137,byte 137,byte 137,byte 120,byte 153,byte 153,byte 153,byte 136,
	byte 136,byte 136,byte 135,byte 135,byte 135,byte 118,byte 164,byte 134,
	byte 137,byte 137,byte 120,byte 120,byte 120,byte 166,byte 136,byte 136,
	byte 136,byte 165,byte 165,byte 118,byte 118,byte 164,byte 147,byte 130,
	byte 150,byte 150,byte 120,byte 166,byte 166,byte 149,byte 149,byte 136,
	byte 165,byte 165,byte 148,byte 148,byte 118,byte 164,byte 147,byte 130,
	byte 150,byte 150,byte 150,byte 149,byte 149,byte 149,byte 132,byte 132,
	byte 165,byte 148,byte 148,byte 131,byte 131,byte 147,byte 147,byte 130,
	byte 133,byte 133,byte 133,byte 149,byte 132,byte 132,byte 132,byte 132,
	byte 115,byte 148,byte 131,byte 131,byte 131,byte 131,byte 130,byte 130,
	byte 133,byte 133,byte 133,byte 116,byte 132,byte 132,byte 132,byte 132,
	byte 115,byte 115,byte 131,byte 131,byte 131,byte 131,byte 160,byte 142,
	byte 133,byte 133,byte 116,byte 162,byte 162,byte 132,byte 132,byte 115,
	byte 161,byte 161,byte 144,byte 131,byte 131,byte 160,byte 160,byte 142,
	byte 146,byte 146,byte 146,byte 145,byte 145,byte 145,byte 128,byte 161,
	byte 144,byte 144,byte 144,byte 143,byte 160,byte 160,byte 159,byte 142,
	byte 129,byte 129,byte 129,byte 129,byte 128,byte 128,byte 128,byte 128,
	byte 143,byte 143,byte 143,byte 143,byte 142,byte 142,byte 142,byte 142,
	byte 141,byte 141,byte 112,byte 112,byte 112,byte 157,byte 140,byte 140,
	byte 140,byte 127,byte 139,byte 126,byte 126,byte 126,byte 109,byte 138,
	byte 141,byte 141,byte 112,byte 112,byte 112,byte 157,byte 140,byte 140,
	byte 140,byte 127,byte 139,byte 126,byte 126,byte 126,byte 109,byte 138,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 124,byte 140,byte 123,
	byte 123,byte 123,byte 123,byte 122,byte 122,byte 122,byte 122,byte 138,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 124,byte 123,byte 123,
	byte 123,byte 123,byte 123,byte 122,byte 122,byte 122,byte 105,byte 138,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 124,byte 153,byte 123,
	byte 123,byte 123,byte 152,byte 122,byte 122,byte 122,byte 105,byte 134,
	byte 154,byte 154,byte 124,byte 124,byte 124,byte 153,byte 153,byte 153,
	byte 123,byte 123,byte 135,byte 135,byte 122,byte 122,byte 105,byte 134,
	byte 137,byte 137,byte 137,byte 120,byte 153,byte 153,byte 153,byte 136,
	byte 136,byte 136,byte 135,byte 135,byte 135,byte 118,byte 105,byte 134,
	byte 137,byte 137,byte 120,byte 120,byte 120,byte 153,byte 136,byte 136,
	byte 136,byte 119,byte 119,byte 118,byte 118,byte 118,byte 118,byte 134,
	byte 137,byte 137,byte 120,byte 120,byte 120,byte 120,byte 136,byte 136,
	byte 119,byte 119,byte 119,byte 118,byte 118,byte 118,byte 101,byte 130,
	byte 121,byte 121,byte 120,byte 120,byte 120,byte 120,byte 136,byte 119,
	byte 119,byte 119,byte 102,byte 118,byte 118,byte 118,byte 101,byte 130,
	byte 133,byte 133,byte 120,byte 120,byte 149,byte 132,byte 132,byte 119,
	byte 119,byte 102,byte 148,byte 131,byte 131,byte 101,byte 101,byte 130,
	byte 117,byte 117,byte 116,byte 116,byte 116,byte 132,byte 132,byte 115,
	byte 115,byte 115,byte 131,byte 131,byte 114,byte 114,byte 114,byte 130,
	byte 117,byte 117,byte 116,byte 116,byte 116,byte 116,byte 132,byte 115,
	byte 115,byte 115,byte 131,byte 114,byte 114,byte 114,byte 114,byte 142,
	byte 117,byte 117,byte 116,byte 116,byte 116,byte 116,byte 115,byte 115,
	byte 115,byte 115,byte  98,byte 114,byte 114,byte 114,byte  97,byte 142,
	byte 100,byte 100,byte 116,byte  99,byte  99,byte  99,byte  99,byte 115,
	byte  98,byte  98,byte  98,byte 114,byte 114,byte  97,byte  97,byte 142,
	byte 129,byte 129,byte 129,byte 129,byte 128,byte 128,byte 128,byte 128,
	byte 143,byte 143,byte 143,byte 143,byte 142,byte 142,byte 142,byte 142,
	byte 113,byte 113,byte 112,byte 112,byte 112,byte 112,byte 140,byte 140,
	byte 127,byte 127,byte 110,byte 126,byte 126,byte 126,byte 109,byte  75,
	byte 113,byte 113,byte 112,byte 112,byte 112,byte 112,byte 140,byte 140,
	byte 127,byte 127,byte 110,byte 126,byte 126,byte 126,byte 109,byte  75,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 124,byte 123,byte 123,
	byte 123,byte 123,byte 123,byte 122,byte 122,byte 122,byte 105,byte  75,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 124,byte 123,byte 123,
	byte 123,byte 123,byte 106,byte 122,byte 122,byte 122,byte 105,byte  75,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 124,byte 123,byte 123,
	byte 123,byte 123,byte 106,byte 122,byte 122,byte 122,byte 105,byte  71,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 107,byte 107,byte 123,
	byte 123,byte 106,byte 106,byte 122,byte 122,byte 105,byte 105,byte  71,
	byte 137,byte 137,byte 120,byte 120,byte 120,byte 107,byte 136,byte 136,
	byte 136,byte 106,byte 106,byte 118,byte 118,byte 105,byte  88,byte  71,
	byte 137,byte 137,byte 120,byte 120,byte 120,byte 120,byte 136,byte 136,
	byte 119,byte 119,byte 119,byte 118,byte 118,byte 118,byte 101,byte  71,
	byte 121,byte 121,byte 120,byte 120,byte 120,byte 120,byte 136,byte 119,
	byte 119,byte 119,byte 102,byte 118,byte 118,byte 118,byte 101,byte  67,
	byte 121,byte 121,byte 120,byte 120,byte 120,byte 103,byte 103,byte 119,
	byte 119,byte 102,byte 102,byte 118,byte 118,byte 101,byte 101,byte  67,
	byte 104,byte 104,byte 120,byte 103,byte 103,byte 103,byte 103,byte 119,
	byte 102,byte 102,byte 102,byte 118,byte 118,byte 101,byte  84,byte  67,
	byte 117,byte 117,byte 116,byte 116,byte 116,byte 116,byte 115,byte 115,
	byte 115,byte 115,byte 115,byte 114,byte 114,byte 114,byte 114,byte  67,
	byte 117,byte 117,byte 116,byte 116,byte 116,byte 116,byte 115,byte 115,
	byte 115,byte 115,byte 115,byte 114,byte 114,byte 114,byte  97,byte  79,
	byte 117,byte 117,byte 116,byte 116,byte 116,byte  99,byte  99,byte 115,
	byte 115,byte  98,byte  98,byte 114,byte 114,byte  97,byte  97,byte  79,
	byte 100,byte 100,byte  99,byte  99,byte  99,byte  99,byte  82,byte  98,
	byte  98,byte  98,byte  81,byte 114,byte  97,byte  97,byte  97,byte  79,
	byte  66,byte  66,byte  66,byte  66,byte  65,byte  65,byte  65,byte  65,
	byte  64,byte  64,byte  64,byte  64,byte  79,byte  79,byte  79,byte  79,
	byte  96,byte  96,byte 112,byte 112,byte 111,byte 111,byte  94,byte 127,
	byte 127,byte 110,byte 110,byte  93,byte 126,byte 109,byte  92,byte  75,
	byte  96,byte  96,byte 112,byte 112,byte 111,byte 111,byte  94,byte 127,
	byte 127,byte 110,byte 110,byte  93,byte 126,byte 109,byte  92,byte  75,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 124,byte 123,byte 123,
	byte 123,byte 123,byte 106,byte 122,byte 122,byte 105,byte 105,byte  75,
	byte 125,byte 125,byte 124,byte 124,byte 124,byte 107,byte 107,byte 123,
	byte 123,byte 106,byte 106,byte 122,byte 122,byte 105,byte 105,byte  75,
	byte 108,byte 108,byte 124,byte 124,byte 107,byte 107,byte 107,byte 123,
	byte 123,byte 106,byte 106,byte 122,byte 122,byte 105,byte  88,byte  71,
	byte 108,byte 108,byte 124,byte 107,byte 107,byte 107,byte  90,byte 123,
	byte 106,byte 106,byte 106,byte  89,byte 122,byte 105,byte  88,byte  71,
	byte  91,byte  91,byte 120,byte 107,byte 107,byte  90,byte  90,byte 136,
	byte 106,byte 106,byte  89,byte  89,byte 118,byte 105,byte  88,byte  71,
	byte 121,byte 121,byte 120,byte 120,byte 120,byte 120,byte 136,byte 119,
	byte 119,byte 119,byte 102,byte 118,byte 118,byte 118,byte 101,byte  71,
	byte 121,byte 121,byte 120,byte 120,byte 120,byte 103,byte 103,byte 119,
	byte 119,byte 102,byte 102,byte 118,byte 118,byte 101,byte 101,byte  67,
	byte 104,byte 104,byte 120,byte 103,byte 103,byte 103,byte 103,byte 119,
	byte 102,byte 102,byte 102,byte 118,byte 118,byte 101,byte  84,byte  67,
	byte 104,byte 104,byte 103,byte 103,byte 103,byte 103,byte  86,byte 102,
	byte 102,byte 102,byte  85,byte  85,byte 101,byte 101,byte  84,byte  67,
	byte  87,byte  87,byte 116,byte 116,byte 116,byte  86,byte  86,byte 115,
	byte 115,byte 115,byte  85,byte  85,byte 114,byte 114,byte  84,byte  67,
	byte 117,byte 117,byte 116,byte 116,byte 116,byte 116,byte 115,byte 115,
	byte 115,byte 115,byte  98,byte 114,byte 114,byte 114,byte  97,byte  79,
	byte 100,byte 100,byte  99,byte  99,byte  99,byte  99,byte  99,byte 115,
	byte  98,byte  98,byte  98,byte 114,byte 114,byte  97,byte  97,byte  79,
	byte  83,byte  83,byte  99,byte  99,byte  82,byte  82,byte  82,byte  98,
	byte  98,byte  81,byte  81,byte  81,byte  97,byte  97,byte  80,byte  79,
	byte  66,byte  66,byte  66,byte  66,byte  65,byte  65,byte  65,byte  65,
	byte  64,byte  64,byte  64,byte  64,byte  79,byte  79,byte  79,byte  79,
	byte  95,byte  95,byte 111,byte 111,byte  94,byte  94,byte  94,byte  77,
	byte 110,byte 110,byte  93,byte  93,byte  76,byte 109,byte  92,byte  75,
	byte  95,byte  95,byte 111,byte 111,byte  94,byte  94,byte  94,byte  77,
	byte 110,byte 110,byte  93,byte  93,byte  76,byte 109,byte  92,byte  75,
	byte 108,byte 108,byte 124,byte 111,byte 107,byte  94,byte  94,byte 123,
	byte 123,byte 106,byte  93,byte  93,byte 122,byte 105,byte  92,byte  75,
	byte 108,byte 108,byte 108,byte 107,byte 107,byte 107,byte  90,byte 123,
	byte 106,byte 106,byte 106,byte  89,byte 122,byte 105,byte  88,byte  75,
	byte  91,byte  91,byte 107,byte 107,byte 107,byte  90,byte  90,byte 123,
	byte 106,byte 106,byte  89,byte  89,byte 105,byte 105,byte  88,byte  71,
	byte  91,byte  91,byte  91,byte 107,byte  90,byte  90,byte  90,byte  73,
	byte 106,byte 106,byte  89,byte  89,byte  72,byte  88,byte  88,byte  71,
	byte  91,byte  91,byte  91,byte  90,byte  90,byte  90,byte  73,byte  73,
	byte 106,byte  89,byte  89,byte  72,byte  72,byte  88,byte  88,byte  71,
	byte  74,byte  74,byte 120,byte 120,byte 120,byte  73,byte  73,byte 119,
	byte 119,byte 102,byte  89,byte  72,byte  72,byte 101,byte 101,byte  71,
	byte 104,byte 104,byte 120,byte 103,byte 103,byte 103,byte 103,byte 119,
	byte 102,byte 102,byte 102,byte 118,byte 118,byte 101,byte  84,byte  67,
	byte 104,byte 104,byte 103,byte 103,byte 103,byte 103,byte  86,byte 102,
	byte 102,byte 102,byte  85,byte  85,byte 101,byte 101,byte  84,byte  67,
	byte  87,byte  87,byte  87,byte 103,byte  86,byte  86,byte  86,byte  86,
	byte 102,byte  85,byte  85,byte  85,byte  85,byte  84,byte  84,byte  67,
	byte  87,byte  87,byte  87,byte  86,byte  86,byte  86,byte  69,byte  69,
	byte 115,byte  85,byte  85,byte  85,byte  68,byte  68,byte  67,byte  67,
	byte  70,byte  70,byte 116,byte 116,byte  99,byte  69,byte  69,byte  69,
	byte 115,byte  98,byte  85,byte  68,byte  68,byte  97,byte  97,byte  79,
	byte 100,byte 100,byte  99,byte  99,byte  99,byte  82,byte  82,byte  98,
	byte  98,byte  98,byte  81,byte  68,byte  97,byte  97,byte  97,byte  79,
	byte  83,byte  83,byte  83,byte  82,byte  82,byte  82,byte  82,byte  98,
	byte  81,byte  81,byte  81,byte  64,byte  97,byte  97,byte  80,byte  79,
	byte  66,byte  66,byte  66,byte  66,byte  65,byte  65,byte  65,byte  65,
	byte  64,byte  64,byte  64,byte  64,byte  79,byte  79,byte  79,byte  79,
	byte  78,byte  78,byte  49,byte  49,byte  94,byte  77,byte  77,byte  48,
	byte  48,byte  93,byte  93,byte  76,byte  76,byte  63,byte  92,byte  75,
	byte  78,byte  78,byte  49,byte  49,byte  94,byte  77,byte  77,byte  48,
	byte  48,byte  93,byte  93,byte  76,byte  76,byte  63,byte  92,byte  75,
	byte  62,byte  62,byte  61,byte  61,byte  61,byte  61,byte  77,byte  60,
	byte  60,byte  60,byte  93,byte  76,byte  59,byte  59,byte  59,byte  75,
	byte  62,byte  62,byte  61,byte  61,byte  61,byte  61,byte  90,byte  60,
	byte  60,byte  60,byte  89,byte  59,byte  59,byte  59,byte  88,byte  75,
	byte  91,byte  91,byte  61,byte  61,byte  61,byte  90,byte  73,byte  60,
	byte  60,byte  60,byte  89,byte  72,byte  59,byte  59,byte  88,byte  71,
	byte  74,byte  74,byte  61,byte  61,byte  90,byte  73,byte  73,byte  73,
	byte  60,byte  89,byte  89,byte  72,byte  72,byte  72,byte  71,byte  71,
	byte  74,byte  74,byte  74,byte  90,byte  73,byte  73,byte  73,byte  73,
	byte  56,byte  89,byte  72,byte  72,byte  72,byte  72,byte  71,byte  71,
	byte  58,byte  58,byte  57,byte  57,byte  57,byte  73,byte  73,byte  56,
	byte  56,byte  56,byte  72,byte  72,byte  55,byte  55,byte  55,byte  71,
	byte  58,byte  58,byte  57,byte  57,byte  57,byte  57,byte  56,byte  56,
	byte  56,byte  56,byte  56,byte  55,byte  55,byte  55,byte  55,byte  67,
	byte  87,byte  87,byte  57,byte  57,byte  57,byte  86,byte  86,byte  56,
	byte  56,byte  56,byte  85,byte  85,byte  55,byte  55,byte  84,byte  67,
	byte  87,byte  87,byte  87,byte  86,byte  86,byte  86,byte  69,byte  69,
	byte  56,byte  85,byte  85,byte  85,byte  68,byte  68,byte  67,byte  67,
	byte  70,byte  70,byte  70,byte  53,byte  69,byte  69,byte  69,byte  69,
	byte  52,byte  85,byte  85,byte  68,byte  68,byte  68,byte  67,byte  67,
	byte  70,byte  70,byte  53,byte  53,byte  53,byte  69,byte  69,byte  52,
	byte  52,byte  52,byte  68,byte  68,byte  68,byte  51,byte  51,byte  79,
	byte  54,byte  54,byte  53,byte  53,byte  53,byte  69,byte  69,byte  52,
	byte  52,byte  52,byte  68,byte  68,byte  51,byte  51,byte  80,byte  79,
	byte  83,byte  83,byte  53,byte  82,byte  82,byte  65,byte  65,byte  52,
	byte  52,byte  81,byte  64,byte  64,byte  51,byte  80,byte  80,byte  79,
	byte  66,byte  66,byte  66,byte  66,byte  65,byte  65,byte  65,byte  65,
	byte  64,byte  64,byte  64,byte  64,byte  79,byte  79,byte  79,byte  79,
	byte  50,byte  50,byte  49,byte  49,byte  49,byte  77,byte  77,byte  48,
	byte  48,byte  48,byte  76,byte  76,byte  63,byte  63,byte  46,byte  12,
	byte  50,byte  50,byte  49,byte  49,byte  49,byte  77,byte  77,byte  48,
	byte  48,byte  48,byte  76,byte  76,byte  63,byte  63,byte  46,byte  12,
	byte  62,byte  62,byte  61,byte  61,byte  61,byte  61,byte  77,byte  60,
	byte  60,byte  60,byte  60,byte  59,byte  59,byte  59,byte  59,byte  12,
	byte  62,byte  62,byte  61,byte  61,byte  61,byte  61,byte  60,byte  60,
	byte  60,byte  60,byte  60,byte  59,byte  59,byte  59,byte  42,byte  12,
	byte  62,byte  62,byte  61,byte  61,byte  61,byte  61,byte  73,byte  60,
	byte  60,byte  60,byte  43,byte  59,byte  59,byte  59,byte  42,byte   8,
	byte  74,byte  74,byte  61,byte  61,byte  61,byte  73,byte  73,byte  60,
	byte  60,byte  60,byte  72,byte  72,byte  72,byte  59,byte  42,byte   8,
	byte  74,byte  74,byte  74,byte  57,byte  73,byte  73,byte  73,byte  73,
	byte  56,byte  56,byte  72,byte  72,byte  72,byte  72,byte  42,byte   8,
	byte  58,byte  58,byte  57,byte  57,byte  57,byte  57,byte  73,byte  56,
	byte  56,byte  56,byte  72,byte  55,byte  55,byte  55,byte  55,byte   8,
	byte  58,byte  58,byte  57,byte  57,byte  57,byte  57,byte  56,byte  56,
	byte  56,byte  56,byte  56,byte  55,byte  55,byte  55,byte  38,byte   4,
	byte  58,byte  58,byte  57,byte  57,byte  57,byte  57,byte  56,byte  56,
	byte  56,byte  56,byte  39,byte  55,byte  55,byte  55,byte  38,byte   4,
	byte  70,byte  70,byte  57,byte  57,byte  40,byte  69,byte  69,byte  69,
	byte  56,byte  39,byte  85,byte  68,byte  68,byte  38,byte  38,byte   4,
	byte  70,byte  70,byte  53,byte  53,byte  53,byte  69,byte  69,byte  52,
	byte  52,byte  52,byte  68,byte  68,byte  68,byte  51,byte  51,byte   4,
	byte  54,byte  54,byte  53,byte  53,byte  53,byte  69,byte  69,byte  52,
	byte  52,byte  52,byte  68,byte  68,byte  51,byte  51,byte  51,byte   0,
	byte  54,byte  54,byte  53,byte  53,byte  53,byte  53,byte  69,byte  52,
	byte  52,byte  52,byte  35,byte  51,byte  51,byte  51,byte  34,byte   0,
	byte  37,byte  37,byte  53,byte  36,byte  36,byte  36,byte  36,byte  52,
	byte  35,byte  35,byte  35,byte  51,byte  51,byte  34,byte  34,byte   0,
	byte   3,byte   3,byte   3,byte   3,byte   2,byte   2,byte   2,byte   2,
	byte   1,byte   1,byte   1,byte   1,byte   0,byte   0,byte   0,byte   0,
	byte  33,byte  33,byte  49,byte  49,byte  32,byte  32,byte  77,byte  48,
	byte  48,byte  47,byte  47,byte  63,byte  63,byte  46,byte  46,byte  12,
	byte  33,byte  33,byte  49,byte  49,byte  32,byte  32,byte  77,byte  48,
	byte  48,byte  47,byte  47,byte  63,byte  63,byte  46,byte  46,byte  12,
	byte  62,byte  62,byte  61,byte  61,byte  61,byte  61,byte  60,byte  60,
	byte  60,byte  43,byte  43,byte  59,byte  59,byte  59,byte  42,byte  12,
	byte  62,byte  62,byte  61,byte  61,byte  61,byte  44,byte  44,byte  60,
	byte  60,byte  43,byte  43,byte  59,byte  59,byte  42,byte  42,byte  12,
	byte  45,byte  45,byte  61,byte  61,byte  44,byte  44,byte  44,byte  60,
	byte  60,byte  43,byte  43,byte  59,byte  59,byte  42,byte  42,byte   8,
	byte  45,byte  45,byte  61,byte  44,byte  44,byte  44,byte  73,byte  60,
	byte  43,byte  43,byte  26,byte  72,byte  59,byte  42,byte  42,byte   8,
	byte  74,byte  74,byte  57,byte  44,byte  44,byte  73,byte  73,byte  56,
	byte  43,byte  43,byte  26,byte  72,byte  72,byte  42,byte  42,byte   8,
	byte  58,byte  58,byte  57,byte  57,byte  57,byte  57,byte  56,byte  56,
	byte  56,byte  56,byte  39,byte  55,byte  55,byte  55,byte  38,byte   8,
	byte  58,byte  58,byte  57,byte  57,byte  57,byte  40,byte  40,byte  56,
	byte  56,byte  39,byte  39,byte  55,byte  55,byte  38,byte  38,byte   4,
	byte  41,byte  41,byte  40,byte  40,byte  40,byte  40,byte  40,byte  56,
	byte  39,byte  39,byte  39,byte  55,byte  55,byte  38,byte  38,byte   4,
	byte  41,byte  41,byte  40,byte  40,byte  40,byte  23,byte  23,byte  39,
	byte  39,byte  39,byte  22,byte  68,byte  38,byte  38,byte  38,byte   4,
	byte  54,byte  54,byte  53,byte  53,byte  53,byte  69,byte  69,byte  52,
	byte  52,byte  52,byte  68,byte  68,byte  51,byte  51,byte  21,byte   4,
	byte  54,byte  54,byte  53,byte  53,byte  53,byte  53,byte  69,byte  52,
	byte  52,byte  52,byte  35,byte  51,byte  51,byte  51,byte  34,byte   0,
	byte  37,byte  37,byte  53,byte  36,byte  36,byte  36,byte  36,byte  52,
	byte  35,byte  35,byte  35,byte  51,byte  51,byte  34,byte  34,byte   0,
	byte  37,byte  37,byte  36,byte  36,byte  36,byte  36,byte  36,byte  35,
	byte  35,byte  35,byte  35,byte  18,byte  34,byte  34,byte  34,byte   0,
	byte   3,byte   3,byte   3,byte   3,byte   2,byte   2,byte   2,byte   2,
	byte   1,byte   1,byte   1,byte   1,byte   0,byte   0,byte   0,byte   0,
	byte  16,byte  16,byte  32,byte  32,byte  31,byte  31,byte  31,byte  47,
	byte  47,byte  30,byte  30,byte  30,byte  46,byte  46,byte  29,byte  12,
	byte  16,byte  16,byte  32,byte  32,byte  31,byte  31,byte  31,byte  47,
	byte  47,byte  30,byte  30,byte  30,byte  46,byte  46,byte  29,byte  12,
	byte  45,byte  45,byte  44,byte  44,byte  44,byte  44,byte  31,byte  60,
	byte  43,byte  43,byte  30,byte  59,byte  59,byte  42,byte  42,byte  12,
	byte  45,byte  45,byte  44,byte  44,byte  44,byte  44,byte  27,byte  43,
	byte  43,byte  43,byte  26,byte  26,byte  42,byte  42,byte  42,byte  12,
	byte  28,byte  28,byte  44,byte  44,byte  27,byte  27,byte  27,byte  43,
	byte  43,byte  26,byte  26,byte  26,byte  42,byte  42,byte  25,byte   8,
	byte  28,byte  28,byte  44,byte  44,byte  27,byte  27,byte  27,byte  43,
	byte  43,byte  26,byte  26,byte   9,byte  42,byte  42,byte  25,byte   8,
	byte  28,byte  28,byte  28,byte  27,byte  27,byte  27,byte  10,byte  43,
	byte  26,byte  26,byte  26,byte   9,byte  42,byte  42,byte  25,byte   8,
	byte  41,byte  41,byte  57,byte  40,byte  40,byte  40,byte  40,byte  56,
	byte  39,byte  39,byte  39,byte  55,byte  55,byte  38,byte  38,byte   8,
	byte  41,byte  41,byte  40,byte  40,byte  40,byte  40,byte  23,byte  39,
	byte  39,byte  39,byte  22,byte  55,byte  38,byte  38,byte  38,byte   4,
	byte  24,byte  24,byte  40,byte  40,byte  23,byte  23,byte  23,byte  39,
	byte  39,byte  22,byte  22,byte  22,byte  38,byte  38,byte  21,byte   4,
	byte  24,byte  24,byte  24,byte  23,byte  23,byte  23,byte  23,byte  39,
	byte  22,byte  22,byte  22,byte   5,byte  38,byte  38,byte  21,byte   4,
	byte  24,byte  24,byte  53,byte  23,byte  23,byte   6,byte   6,byte  52,
	byte  52,byte  22,byte   5,byte   5,byte  51,byte  21,byte  21,byte   4,
	byte  37,byte  37,byte  53,byte  36,byte  36,byte  36,byte  36,byte  52,
	byte  35,byte  35,byte  35,byte  51,byte  51,byte  34,byte  34,byte   0,
	byte  37,byte  37,byte  36,byte  36,byte  36,byte  36,byte  36,byte  35,
	byte  35,byte  35,byte  35,byte  18,byte  34,byte  34,byte  34,byte   0,
	byte  20,byte  20,byte  36,byte  36,byte  19,byte  19,byte  19,byte  35,
	byte  35,byte  18,byte  18,byte  18,byte  34,byte  34,byte  17,byte   0,
	byte   3,byte   3,byte   3,byte   3,byte   2,byte   2,byte   2,byte   2,
	byte   1,byte   1,byte   1,byte   1,byte   0,byte   0,byte   0,byte   0,
	byte  15,byte  15,byte  15,byte  15,byte  14,byte  14,byte  14,byte  14,
	byte  13,byte  13,byte  13,byte  13,byte  12,byte  12,byte  12,byte  12,
	byte  15,byte  15,byte  15,byte  15,byte  14,byte  14,byte  14,byte  14,
	byte  13,byte  13,byte  13,byte  13,byte  12,byte  12,byte  12,byte  12,
	byte  15,byte  15,byte  15,byte  15,byte  14,byte  14,byte  14,byte  14,
	byte  13,byte  13,byte  13,byte  13,byte  12,byte  12,byte  12,byte  12,
	byte  15,byte  15,byte  15,byte  15,byte  14,byte  14,byte  14,byte  14,
	byte  13,byte  13,byte  13,byte  13,byte  12,byte  12,byte  12,byte  12,
	byte  11,byte  11,byte  11,byte  11,byte  10,byte  10,byte  10,byte  10,
	byte   9,byte   9,byte   9,byte   9,byte   8,byte   8,byte   8,byte   8,
	byte  11,byte  11,byte  11,byte  11,byte  10,byte  10,byte  10,byte  10,
	byte   9,byte   9,byte   9,byte   9,byte   8,byte   8,byte   8,byte   8,
	byte  11,byte  11,byte  11,byte  11,byte  10,byte  10,byte  10,byte  10,
	byte   9,byte   9,byte   9,byte   9,byte   8,byte   8,byte   8,byte   8,
	byte  11,byte  11,byte  11,byte  11,byte  10,byte  10,byte  10,byte  10,
	byte   9,byte   9,byte   9,byte   9,byte   8,byte   8,byte   8,byte   8,
	byte   7,byte   7,byte   7,byte   7,byte   6,byte   6,byte   6,byte   6,
	byte   5,byte   5,byte   5,byte   5,byte   4,byte   4,byte   4,byte   4,
	byte   7,byte   7,byte   7,byte   7,byte   6,byte   6,byte   6,byte   6,
	byte   5,byte   5,byte   5,byte   5,byte   4,byte   4,byte   4,byte   4,
	byte   7,byte   7,byte   7,byte   7,byte   6,byte   6,byte   6,byte   6,
	byte   5,byte   5,byte   5,byte   5,byte   4,byte   4,byte   4,byte   4,
	byte   7,byte   7,byte   7,byte   7,byte   6,byte   6,byte   6,byte   6,
	byte   5,byte   5,byte   5,byte   5,byte   4,byte   4,byte   4,byte   4,
	byte   3,byte   3,byte   3,byte   3,byte   2,byte   2,byte   2,byte   2,
	byte   1,byte   1,byte   1,byte   1,byte   0,byte   0,byte   0,byte   0,
	byte   3,byte   3,byte   3,byte   3,byte   2,byte   2,byte   2,byte   2,
	byte   1,byte   1,byte   1,byte   1,byte   0,byte   0,byte   0,byte   0,
	byte   3,byte   3,byte   3,byte   3,byte   2,byte   2,byte   2,byte   2,
	byte   1,byte   1,byte   1,byte   1,byte   0,byte   0,byte   0,byte   0,
	byte   3,byte   3,byte   3,byte   3,byte   2,byte   2,byte   2,byte   2,
	byte   1,byte   1,byte   1,byte   1,byte   0,byte   0,byte   0,byte   0,
};

clamp: array of int;
rgbvmap: array of int;

init(d: ref Display)
{
	# initialise in a way that make races slightly wasteful but benign
	if(sys == nil)
		sys = load Sys Sys->PATH;
	if(draw == nil)
		draw = load Draw Draw->PATH;
	if(clamp == nil){
		m := array[64+256+64] of int;
		for(j:=0; j<64; j++)
			m[j] = 0;
		for(j=0; j<256; j++)
			m[64+j] = (j>>4);
		for(j=0; j<64; j++)
			m[64+256+j] = (255>>4);
		clamp = m;
	}
	if(rgbvmap == nil){
		m := array[3*256] of int;
		for(j:=0; j<256; j++)
			(m[3*j+0], m[3*j+1], m[3*j+2]) = d.cmap2rgb(j);
		rgbvmap = m;
	}
}

remap(i: ref RImagefile->Rawimage, d: ref Display, errdiff: int): (ref Image, string)
{
	if(sys == nil || draw == nil || clamp == nil || rgbvmap == nil)
		init(d);	# temporarily do this here until all clients change
	j: int;
	im := d.newimage(i.r, 3, 0, 0);
	dx := i.r.max.x-i.r.min.x;
	dy := i.r.max.y-i.r.min.y;
	cmap := i.cmap;

	pic := i.chans[0];

	case i.chandesc{
	RImagefile->CRGB1 =>
		if(cmap == nil)
			return (nil, sys->sprint("image has no color map"));
		if(i.nchans != 1)
			return (nil, sys->sprint("can't handle nchans %d", i.nchans));
		for(j=1; j<=8; j++)
			if(len cmap == 3*(1<<j))
				break;
		if(j > 8)
			return (nil, sys->sprint("can't understand colormap size 3*%d", len cmap/3));
		if(len cmap != 3*256){
			# to avoid a range check in inner loop below, make a full-size cmap
			cmap1 := array[3*256] of byte;
			cmap1[0:] = cmap[0:];
			cmap = cmap1;
			errdiff = 0;	# why not?
		}
		if(errdiff == 0){
			map := array[256] of byte;
			k := 0;
			for(j=0; j<256; j++){
				r := int cmap[k]>>4;
				g := int cmap[k+1]>>4;
				b := int cmap[k+2]>>4;
				k += 3;
				map[j] = byte closest[b+16*(g+16*r)];
			}
			for(j=0; j<len pic; j++)
				pic[j] = map[int pic[j]];
		}else{
			# modified floyd steinberg, coefficients (1 0) 3/16, (0, 1) 3/16, (1, 1) 7/16
			ered := array[dx+1] of int;
			egrn := array[dx+1] of int;
			eblu := array[dx+1] of int;
			for(j=0; j<=dx; j++)
				ered[j] = 0;
			egrn[0:] = ered[0:];
			eblu[0:] = ered[0:];
			p := 0;
			for(y:=0; y<dy; y++){
				er := 0;
				eg := 0;
				eb := 0;
				for(x:=0; x<dx; x++){
					in := 3*int pic[p];
					r := int cmap[in+0]+ered[x];
					g := int cmap[in+1]+egrn[x];
					b := int cmap[in+2]+eblu[x];
					r1 := clamp[r+64];
					g1 := clamp[g+64];
					b1 := clamp[b+64];
					col := int closest[b1+16*(g1+16*r1)];
					pic[p++] = byte col;

					col *= 3;
					r -= rgbvmap[col+0];
					t := (3*r)>>4;
					ered[x] = t+er;
					ered[x+1] += t;
					er = r-3*t;

					g -= rgbvmap[col+1];
					t = (3*g)>>4;
					egrn[x] = t+eg;
					egrn[x+1] += t;
					eg = g-3*t;

					b -= rgbvmap[col+2];
					t = (3*b)>>4;
					eblu[x] = t+eb;
					eblu[x+1] += t;
					eb = b-3*t;
				}
			}
		}
	RImagefile->CRGB =>
		if(i.nchans != 3)
			return (nil, sys->sprint("RGB image has %d channels", i.nchans));
		rpic := i.chans[0];
		gpic := i.chans[1];
		bpic := i.chans[2];
		if(errdiff == 0){
			for(j=0; j<len rpic; j++){
				r := int rpic[j]>>4;
				g := int gpic[j]>>4;
				b := int bpic[j]>>4;
				pic[j] = byte closest[b+16*(g+16*r)];
			}
		}else{
			# modified floyd steinberg, coefficients (1 0) 3/16, (0, 1) 3/16, (1, 1) 7/16
			ered := array[dx+1] of int;
			egrn := array[dx+1] of int;
			eblu := array[dx+1] of int;
			for(j=0; j<=dx; j++)
				ered[j] = 0;
			egrn[0:] = ered[0:];
			eblu[0:] = ered[0:];
			p := 0;
			for(y:=0; y<dy; y++){
				er := 0;
				eg := 0;
				eb := 0;
				for(x:=0; x<dx; x++){
					r := int rpic[p]+ered[x];
					g := int gpic[p]+egrn[x];
					b := int bpic[p]+eblu[x];
					r1 := clamp[r+64];
					g1 := clamp[g+64];
					b1 := clamp[b+64];
					col := int closest[b1+16*(g1+16*r1)];
					pic[p++] = byte col;

					col *= 3;
					r -= rgbvmap[col+0];
					t := (3*r)>>4;
					ered[x] = t+er;
					ered[x+1] += t;
					er = r-3*t;

					g -= rgbvmap[col+1];
					t = (3*g)>>4;
					egrn[x] = t+eg;
					egrn[x+1] += t;
					eg = g-3*t;

					b -= rgbvmap[col+2];
					t = (3*b)>>4;
					eblu[x] = t+eb;
					eblu[x+1] += t;
					eb = b-3*t;
				}
			}
		}
	RImagefile->CY =>
		if(i.nchans != 1)
			return (nil, sys->sprint("Y image has %d chans", i.nchans));
		rpic := i.chans[0];
		if(errdiff == 0){
			for(j=0; j<len pic; j++){
				r := int rpic[j]>>4;
				pic[j] = byte closest[r+16*(r+16*r)];
			}
		}else{
			# modified floyd steinberg, coefficients (1 0) 3/16, (0, 1) 3/16, (1, 1) 7/16
			ered := array[dx+1] of int;
			for(j=0; j<=dx; j++)
				ered[j] = 0;
			p := 0;
			for(y:=0; y<dy; y++){
				er := 0;
				for(x:=0; x<dx; x++){
					r := int rpic[p]+ered[x];
					r1 := clamp[r+64];
					col := int closest[r1+16*(r1+16*r1)];
					pic[p++] = byte col;

					col *= 3;
					r -= rgbvmap[col+0];
					t := (3*r)>>4;
					ered[x] = t+er;
					ered[x+1] += t;
					er = r-3*t;
				}
			}
		}
	}
	im.writepixels(im.r, pic);
	return (im, "");
}
