CFLAGS?=-std=c89 -ansi -pedantic -O4 -Wall -fPIC 

default: multipart_parser.o

multipart_parser.o: multipart_parser.c multipart_parser.h

solib: multipart_parser.o
	$(CC) -shared -Wl,-soname,libmultipart.so -o libmultipart.so multipart_parser.o
	cp -f libmultipart.so /home/cyi/cloudac/application/lib/fcgi/

clean:
	rm -f *.o *.so
