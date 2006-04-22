#!/usr/bin/perl -w

# Unit testing for PPI, generated by Test::Inline

use strict;
use lib ();
use UNIVERSAL 'isa';
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

# Load the API to test
BEGIN { $PPI::XS_DISABLE = 1 }
use PPI;

# Execute the tests
use Test::More tests => 8;

# =begin testing string 8
{
my $Document = PPI::Document->new( \"print q{foo}, q!bar!, q <foo>;" );
isa_ok( $Document, 'PPI::Document' );
my $literal = $Document->find('Token::Quote::Literal');
is( scalar(@$literal), 3, '->find returns three objects' );
isa_ok( $literal->[0], 'PPI::Token::Quote::Literal' );
isa_ok( $literal->[1], 'PPI::Token::Quote::Literal' );
isa_ok( $literal->[2], 'PPI::Token::Quote::Literal' );
is( $literal->[0]->string, 'foo', '->string returns as expected' );
is( $literal->[1]->string, 'bar', '->string returns as expected' );
is( $literal->[2]->string, 'foo', '->string returns as expected' );
}


1;
