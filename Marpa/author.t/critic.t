#!/usr/bin/perl

use 5.010;
use strict;
use warnings;
use English qw( -no_match_vars );
use Fatal qw( open close );

# Test that the module passes perlcritic
BEGIN {
	$|  = 1;
	$^W = 1;
}

my @MODULES = (
	'Perl::Critic 1.098',
	'Test::Perl::Critic 1.01',
);

# Don't run tests during end-user installs
use Test::More;

# Load the testing modules
foreach my $MODULE ( @MODULES ) {
        ## no critic (BuiltinFunctions::ProhibitStringyEval)
	eval "use $MODULE";
        ## use critic
	if ( $@ ) {
		$ENV{RELEASE_TESTING}
		? die( "Failed to load required release-testing module $MODULE" )
		: plan( skip_all => "$MODULE not available for testing" );
	}
}

my %exclude = map { ( $_, 1 ) } qw(
    Makefile.PL
    bootstrap/bootstrap.pl
    bootstrap/bootstrap_header.pl
    bootstrap/bootstrap_trailer.pl
    lib/Marpa/Raw_Source.pm
    lib/Marpa/header_Raw_Source.pm
    lib/Marpa/trailer_Raw_Source.pm
    inc/Test/Weaken.pm
);

open my $manifest, '<', 'MANIFEST'
    or Marpa::Exception("open of MANIFEST failed: $ERRNO");

my @test_files = ();
FILE: while ( my $file = <$manifest> ) {
    chomp $file;
    $file =~ s/\s*[#].*\z//xms;
    next FILE if -d $file;
    next FILE if $exclude{$file};
    my ($ext) = $file =~ / [.] ([^.]+) \z /xms;
    next FILE if not defined $ext;
    $ext = lc $ext;
    next FILE
        if $ext ne 'pl'
            and $ext ne 'pm'
            and $ext ne 't';

    push @test_files, $file;
}    # FILE
close $manifest;

all_critic_ok(@test_files);

1;
