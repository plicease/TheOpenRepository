#!/usr/bin/perl

# I've disabled warnings, so theoretically warnings shouldn't be printed

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

my $have_nowarnings;
BEGIN{ eval 'use Test::NoWarnings; $have_nowarnings = 1;' };
use Test::More tests => 5+($have_nowarnings || 0);
use t::lib::Test;

SCOPE: {
	my $dbh = connect_ok( RaiseError => 1, PrintWarn => 0 );
	ok( ! $dbh->{PrintWarn}, '->{PrintWarn} is false' );
	ok( $dbh->do("CREATE TABLE f (f1, f2, f3)"), 'CREATE TABLE ok' );
	ok( $dbh->begin_work, '->begin_work' );
	ok(
		$dbh->do("INSERT INTO f VALUES (?, ?, ?)", {}, 'foo', 'bar', 1),
		'INSERT ok',
	);
}
