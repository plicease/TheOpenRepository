#!/usr/bin/perl

# Tests for the HTTP server component of the support server only

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More tests => 7;
use File::Spec::Functions ':ALL';
use PITA::SupportServer::HTTP ();
use POE;

# Test event firing order
my $order = 0;
sub order {
	my $position = shift;
	my $message  = shift;
	is( $order++, $position, "$message ($position)" );
}

my $minicpan = rel2abs( catdir( 't', 'minicpan' ), );
ok( -d $minicpan, 'Found minicpan directory' );

# Create the web server
my $server = PITA::SupportServer::HTTP->new(
	Hostname => '127.0.0.1',
	Port     => 12345,
	Mirrors  => {
		'/cpan/' => $minicpan,
	},
);
isa_ok( $server, 'PITA::SupportServer::HTTP' );

# Set up the test session
POE::Session->create(
	inline_states => {

		_start => sub {
			# Start the server
			order( 0, 'Fired main::_start' );
			ok( $server->start, '->start ok' );

			# Start the timeout
			$_[KERNEL]->delay_set( timeout => 2 );
		},

		timeout => sub {
			order( 1, 'Fired main::timeout' );
			ok( $server->stop, '->stop ok' );
		},

		_stop => sub {
			order( 2, 'Fired main::_stop' );
		},

	},
);

# Run the web server
$server->run;
