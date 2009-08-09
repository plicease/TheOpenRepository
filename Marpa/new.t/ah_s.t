#!perl

# the example grammar in Aycock/Horspool "Practical Earley Parsing",
# _The Computer Journal_, Vol. 45, No. 6, pp. 620-630,
# in source form

use 5.010;
use strict;
use warnings;
use lib 'lib';
use English qw( -no_match_vars );

use Test::More tests => 6;

BEGIN {
    Test::More::use_ok('Marpa');
}

my $source;
{ local ($RS) = undef; $source = <DATA> };

my $grammar = Marpa::Grammar->new(
    {   warnings   => 1,
        code_lines => -1,
    }
);

$grammar->set( { mdl_source => \$source } );

$grammar->precompute();

my $recce = Marpa::Recognizer->new( { grammar => $grammar } );

my $lc_a = Marpa::MDL::get_symbol( $grammar, 'lowercase a' );
$recce->earleme( [ $lc_a, 'lowercase a', 1 ] );
$recce->earleme( [ $lc_a, 'lowercase a', 1 ] );
$recce->earleme( [ $lc_a, 'lowercase a', 1 ] );
$recce->earleme( [ $lc_a, 'lowercase a', 1 ] );
$recce->end_input();

my @answer = (
    q{},
    '(lowercase a;;;)',
    '(lowercase a;lowercase a;;)',
    '(lowercase a;lowercase a;lowercase a;)',
    '(lowercase a;lowercase a;lowercase a;lowercase a)',
);

for my $i ( 0 .. 4 ) {
    my $evaler = Marpa::Evaluator->new(
        {   recce => $recce,
            end   => $i
        }
    );
    my $result = $evaler->value();
    TODO: {
        ## no critic (ControlStructures::ProhibitPostfixControls)
        local $TODO = 'new evaluator not yet written' if $i == 3;
        ## use critic
        Test::More::is( ${$result}, $answer[$i], "parse permutation $i" );
    } ## end TODO:
} ## end for my $i ( 0 .. 4 )

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:

__DATA__
semantics are perl5.  version is 0.001_014.  the start symbol is
S.  the default null value is q{}.  the default action is q{
     my $v_count = scalar @_;
     return q{} if $v_count <= 0;
     return $_[0] if $v_count == 1;
     '(' . join(';', @_) . ')';
}.

S: A, A, A, A.

A: lowercase a.

lowercase a matches /a/.

E: . # empty

A: E.
