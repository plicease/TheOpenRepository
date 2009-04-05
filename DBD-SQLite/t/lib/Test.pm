package t::lib::Test;

# Support code for DBD::SQLite tests

use strict;
use Exporter   ();
use File::Spec ();
use Test::More ();

use vars qw{$VERSION @ISA @EXPORT};
BEGIN {
	$VERSION = '1.19_09';
	@ISA     = qw{ Exporter };
	@EXPORT  = qw{ connect_ok };
}

# Always load the DBI module
use DBI ();

# Delete temporary files
sub clean {
	unlink( 'foo'         );
	unlink( 'foo-journal' );
}

# Clean up temporary test files both at the beginning and end of the
# test script.
BEGIN { clean() }
END   { clean() }

# A simplified connect function for the most common case
sub connect_ok {
	my @params = ( 'dbi:SQLite:dbname=foo', '', '' );
	if ( @_ ) {
		push @params, { @_ };
	}
	my $dbh = DBI->connect( @params );
	Test::More::isa_ok( $dbh, 'DBI::db' );
	return $dbh;
}

1;
