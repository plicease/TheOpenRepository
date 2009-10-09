#!perl
# A grammar with cycles

use 5.010;
use strict;
use warnings;
use English qw( -no_match_vars );
use Fatal qw(open close chdir);

use Test::More tests => 8;
use lib 'lib';
use t::lib::Marpa::Test;

BEGIN {
    Test::More::use_ok('Marpa');
    Test::More::use_ok('Marpa::MDLex');
}

## no critic (Subroutines::RequireArgUnpacking)
sub default_action {
    return join q{ }, grep { defined $_ } @_;
}
## use critic

my $mdl_header = <<'EOF';
semantics are perl5.  version is 0.001_019.
start symbol is S.
default action is 'main::default_action'.

EOF

my $cycle1_mdl = $mdl_header . <<'EOF';
S: S.

S matches /./.

EOF

my $cycle2_mdl = $mdl_header . <<'EOF';
S: A.

A: S.

A matches /./.

EOF

my $cycle8_mdl = $mdl_header . <<'EOF';
S: A.

A: B, T, U.

B: V, C.

C: W, D, X.

D: E.

E: S.

E matches /./.

T matches /./.

T: .

U matches /./.

U: .

V matches /./.

V: .

W matches /./.

W: .

X matches /./.

X: .

EOF

my $cycle1_test = [
    'cycle1',
    \$cycle1_mdl,
    \('1'),
    '1',
    <<'EOS'
Cycle found involving rule: 0: s -> s
EOS
];

my $cycle2_test = [
    'cycle2',
    \$cycle2_mdl,
    \('1'),
    '1',
    <<'EOS'
Cycle found involving rule: 1: a -> s
Cycle found involving rule: 0: s -> a
EOS
];

my $cycle8_test = [
    'cycle8',
    \$cycle8_mdl,
    \('123456'),
    '1 2 3 4 5 6',
    <<'EOS'
Cycle found involving rule: 3: c -> w d x
Cycle found involving rule: 2: b -> v c
Cycle found involving rule: 1: a -> b t u
Cycle found involving rule: 5: e -> s
Cycle found involving rule: 4: d -> e
Cycle found involving rule: 0: s -> a
EOS
];

my @test_data = ( $cycle1_test, $cycle2_test, $cycle8_test );

for my $test_data (@test_data) {
    my ( $test_name, $grammar_source, $input, $expected, $expected_trace ) =
        @{$test_data};
    my $trace = q{};
    open my $MEMORY, '>', \$trace;
    my $grammar = Marpa::Grammar->new(
        {   mdl_source        => $grammar_source,
            cycle_action      => 'warn',
            trace_file_handle => $MEMORY,
        }
    );
    my $lexer_args = $grammar->lexer_args();

    my $recce = Marpa::Recognizer->new( { grammar => $grammar } );
    my $lexer = Marpa::MDLex->new( { recce => $recce, %{$lexer_args} } );
    my $fail_offset = $lexer->text($input);
    my $result;
    given ($fail_offset) {
        when ( $_ < 0 ) {
            $recce->end_input();
            my $evaler =
                Marpa::Evaluator->new( { recce => $recce, clone => 0 } );
            $result = $evaler->value();
        } ## end when ( $_ < 0 )
        default {
            $result = \"Parse failed at offset $fail_offset";
        }
    };

    close $MEMORY;

    Marpa::Test::is( ${$result}, $expected,       "$test_name result" );
    Marpa::Test::is( $trace,     $expected_trace, "$test_name trace" );

} ## end for my $test_data (@test_data)

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
