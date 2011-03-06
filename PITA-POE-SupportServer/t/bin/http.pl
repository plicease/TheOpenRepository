#!/usr/bin/perl

# Test launcher for the HTTP server component of the support server

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use File::Spec::Functions ':ALL';
use PITA::SupportServer::HTTP ();

my $minicpan = rel2abs( catdir( 't', 'minicpan' ), );
unless ( -d $minicpan ) {
	die "Failed to find t/minicpan directory";
}

# Create the web server
my $server = PITA::SupportServer::HTTP->new(
	Hostname => '127.0.0.1',
	Port     => 12345,
	Mirrors  => {
		'/cpan/' => $minicpan,
	},
) or die "Failed to create HTTP support server";

# Run the web server
$server->run;
