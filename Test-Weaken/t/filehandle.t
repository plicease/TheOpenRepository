#!/usr/bin/perl

package MyObject;
use strict;
use warnings;
use Scalar::Util;
use Fatal qw(open);

sub new {
    my ($class) = @_;
    ## no critic (InputOutput::RequireBriefOpen)
    open my $out, '<', '/dev/null';
    ## use critic
    return bless { fh => $out }, $class;
} ## end sub new

package main;
use strict;
use warnings;
use Test::Weaken;
use Test::More tests => 2;

{
    my $leak;
    my $test = Test::Weaken::leaks(
        {   constructor => sub {
                my $obj = MyObject->new;
                $leak = $obj->{'fh'}
                    or Carp::croak('MyObject has no fh attribute');
                return $obj;
            },
            tracked_types => ['GLOB'],
        }
    );
    Test::More::ok( $test, 'leaky file handle detection' );
    Test::More::is( $test && $test->unfreed_count, 1, 'one object leaked' );
}

exit 0;
