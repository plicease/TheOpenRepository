#!/usr/bin/perl

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More;
if ( $ENV{ADAMK_CHECKOUT} and -d $ENV{ADAMK_CHECKOUT} ) {
	plan( tests => 98 );
} else {
	plan( skip_all => '$ENV{ADAMK_CHECKOUT} is not defined or does not exist' );
}

use File::Spec::Functions ':ALL';
use ADAMK::Repository;

my $root = $ENV{ADAMK_CHECKOUT};






#####################################################################
# Simple Constructor

my $repository = ADAMK::Repository->new( root => $root );
isa_ok( $repository, 'ADAMK::Repository' );
is( $repository->root, $root, '->root ok' );





#####################################################################
# SVN Methods

my $hash = $repository->svn_info( $repository->root );
is( ref($hash), 'HASH', '->svn_info' );
is(
	$hash->{URL},
	'http://svn.ali.as/cpan',
	'svn_info: Repository Root ok',
);
is(
	$hash->{RepositoryUUID},
	'88f4d9cd-8a04-0410-9d60-8f63309c3137',
	'svn_info: Repository UUID ok',
);
is(
	$hash->{NodeKind},
	'directory',
	'svn_info: Node Kind ok',
);





#####################################################################
# Distribution Methods

SCOPE: {
	my @distributions = sort {
		rand() <=> rand()
	} grep {
		-f catfile($_->path, 'Makefile.PL')
	} $repository->distributions;
	foreach my $distribution ( sort @distributions[0 .. 25] ) {
		my $info = $distribution->svn_info;
		is( ref($info), 'HASH', $distribution->name . ': ->svn_info ok' );
	}

	# Check a typical svn_info
	my $first        = $distributions[0];
	my $url          = $first->svn_url;
	my $last_changed = $first->svn_last_changed;
	like( $url,          qr/^http:\/\/svn\.ali\.as\/cpan/, '->svn_url ok' );
	like( $last_changed, qr/^\d+$/, '->last_changed ok' );

	# Export a distribution
	my $export = $first->export( $last_changed );
	isa_ok( $export, 'ADAMK::Distribution::Export' );
	isa_ok( $export->distribution, 'ADAMK::Distribution' );
	isa_ok( $export->repository,   'ADAMK::Repository'   );
	my $name = $export->name;
	my $path = $export->path;
	ok( -d $path, "->export directory '$path' for distribution '$name' exists" );
	ok( -f catfile($path, 'Makefile.PL'), '->export/Makefile.PL exists' );
}





#####################################################################
# Release Methods

SCOPE: {
	my @releases = sort {
		rand() <=> rand()
	} grep {
		-f catfile($_->distribution->path, 'Makefile.PL')
	} $repository->releases_trunk;
	foreach my $release ( sort @releases[0 .. 25] ) {
		my $info = $release->svn_info;
		is( ref($info), 'HASH', $release->file . ': ->svn_info ok' );
		isa_ok( $release->distribution, 'ADAMK::Distribution' );
	}

	# Check a typical svn_info
	my $first    = $releases[0];
	my $revision = $first->svn_revision;
	like( $revision, qr/^\d+$/, '->revision ok ok' );

	# Export a distribution
	my $export = $first->export;
	isa_ok( $export, 'ADAMK::Distribution::Export' );
	ok( -d $export->path, '->path directory exists' );
	ok(
		-f catfile($export->path, 'Makefile.PL'),
		'->path/Makefile.PL exists'
	);
}





#####################################################################
# Find the revision of the latest release for a distribution

SCOPE: {
	my $dist = $repository->distribution('CPAN-Test-Dummy-Perl5-Developer');
	isa_ok( $dist, 'ADAMK::Distribution' );

	my $latest = $dist->latest;
	isa_ok( $latest, 'ADAMK::Release' );

	my $revision = $latest->svn_revision;
	is( $revision, 1370, '->svn_revision returns expected version' );
}
