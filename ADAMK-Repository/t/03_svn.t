#!/usr/bin/perl

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More;
if ( $ENV{ADAMK_CHECKOUT} ) {
	plan( tests => 208 );
} else {
	plan( skip_all => '$ENV{ADAMK_CHECKOUT} is not defined' );
}

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
	$hash->{RepositoryRoot},
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

my @distributions = $repository->distributions;
@distributions = sort { rand() <=> rand() } @distributions;
foreach my $distribution ( sort @distributions[0 .. 100] ) {
	my $info = $distribution->svn_info;
	is( ref($info), 'HASH', $distribution->name . ': ->svn_info ok' );
}





#####################################################################
# Release Methods

my @releases = $repository->releases;
@releases = sort { rand() <=> rand() } @releases;
foreach my $release ( sort @releases[0 .. 100] ) {
	my $info = $release->svn_info;
	is( ref($info), 'HASH', $release->file . ': ->svn_info ok' );
}
