#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 3;

BEGIN {
	use_ok( 'POE' ); # 1
	use_ok( 'PITA::POE::SupportServer' ); # 2
};

ok( $] > 5.005, 'Perl version is 5.005 or newer' ); # 4

exit(0);
