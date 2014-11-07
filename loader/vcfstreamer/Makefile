CPP=g++
BOOST_ROOT=/opt/scidb/14.8/3rdparty/boost
CPPFLAGS=-ggdb -Wall -O3 -I$(BOOST_ROOT)/include
LDFLAGS=-L$(BOOST_ROOT)/lib
BOOST_LIBS=-Wl,-R$(BOOST_ROOT)/lib -lboost_program_options 

all: vcfstreamer

vcfstreamer: vcfstreamer.cpp
	$(CPP) $(CPPFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm vcfstreamer
