#!/usr/bin/perl -w

# Compile-testing for LVAS

use strict;
use lib ();
use File::Spec::Functions ':ALL';
BEGIN {
	$| = 1;
	unless ( $ENV{HARNESS_ACTIVE} ) {
		require FindBin;
		$FindBin::Bin = $FindBin::Bin; # Avoid a warning
		chdir catdir( $FindBin::Bin, updir() );
		lib->import('blib', 'lib');
	}
}

use Test::More tests => 2;

ok( $] > 5.006, 'Perl version is 5.004 or newer' );

use_ok( 'LVAS' );

exit(0);
