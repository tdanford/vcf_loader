CPP=g++
BOOST_ROOT=/opt/scidb/14.8/3rdparty/boost
CPPFLAGS=-ggdb -Wall -O3 -I$(BOOST_ROOT)/include
LDFLAGS=-L$(BOOST_ROOT)/lib
BOOST_LIBS=-Wl,-R$(BOOST_ROOT)/lib -lboost_program_options 
GTEST_DIR=/home/bio/tdanford/googletest

all: vcfstreamer

libgtest.a: 
	g++ -isystem ${GTEST_DIR}/include -I${GTEST_DIR} \
      -pthread -c ${GTEST_DIR}/src/gtest-all.cc
	ar -rv libgtest.a gtest-all.o

vcfstreamer_test: vcfstreamer_test.cpp libgtest.a
	g++ -isystem ${GTEST_DIR}/include -pthread vcfstreamer_test.cpp libgtest.a \
      -o vcfstreamer_test

vcfstreamer: vcfstreamer.cpp
	$(CPP) $(CPPFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm vcfstreamer vcfstreamer_test *.a *.o
