#!/usr/bin/perl

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More tests => 1;
use Alien::BatToExeConverter ();

my $path = Alien::BatToExeConverter::bat2exe_path();
ok(    $path, 'bat2exe_path is defined'    );
ok( -f $path, 'bat2exe_path exists'        );
ok( -x $path, 'bat2exe_path is executable' );
