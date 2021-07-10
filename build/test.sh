#!/bin/bash
# shellcheck disable=SC2154,SC2120,SC2119,SC2034,SC1090,SC1117,SC2030,SC2031
#source /local64/etc/profile2.local
source ./media-suite_helper.sh

do_simple_print "Hello world !"
:<<!
do_wget \
            -h ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e \
            "http://10.1.1.43:8001/archive/lame-3.100.tar.gz"
!
			
RUSTUP_HOME="/opt/cargo"	
CARCH=x86_64
do_rust		