#!perl
# Ensure various coding errors are caught

use 5.010_000;
use strict;
use warnings;

use Test::More tests => 22;

use lib 'lib';
use lib 't/lib';
use Marpa::Test;
use Carp;
use English qw( -no_match_vars );

BEGIN {
	use_ok( 'Parse::Marpa' );
}

# Need also to test null actions
# and lexing routines

# Errors in evaluation of raw grammars?
# in unstringifying grammars?
# in unstringifying recognizers?

my @features = qw(
    preamble lex_preamble
    e_op_action default_action
);

my @tests = (
    'compile phase warning',
    'compile phase fatal',
    'run phase warning',
    'run phase error',
    'run phase die',
);

my %good_code = (
    'e op action' => 'my $error =',
    'e number action' => 'my $error =',
    'default action' => 'my $error =',
);

my %test_code;
my %expected;
for my $test (@tests) {
    $test_code{$test} = '1;';
    for my $feature (@features) {
        $expected{$test}{$feature} = q{};
    }
}

my $getting_headers = 1;
my @headers;
my $data = q{};

LINE: while (my $line = <DATA>)
{

    if ($getting_headers)
    {
        next LINE if $line =~ m/ \A \s* \Z/xms;
        if ($line =~ s/ \A [|] \s+ //xms)
        {
            chomp $line;
            push(@headers, $line);
            next LINE;
        } else {
            $getting_headers = 0;
            $data = q{};
        }
    }
    
    # getting data

    if ($line =~ /\A__END__\Z/xms) {
        HEADER: while (my $header = pop @headers) {
            if ($header =~ s/\A expected \s //xms) {
                my ($feature, $test) = ($header =~ m/\A ([^\s]*) \s+ (.*) \Z/xms);
                croak("expected result given for unknown test, feature: $test, $feature")
                    unless defined $expected{$test}{$feature};
                $expected{$test}{$feature} = $data;
                next HEADER;
            }
            if ($header =~ s/\A good \s code \s //xms) {
                chomp $header;
                $good_code{$header} = $data;
                next HEADER;
            }
            if ($header =~ s/\A bad \s code \s //xms) {
                chomp $header;
                croak("test code given for unknown test: $header")
                    unless defined $test_code{$header};
                $test_code{$header} = $data;
                next HEADER;
            }
            croak("Bad header: $header");
        } # HEADER
        $getting_headers = 1;
        $data = q{};
    } # if $line

    $data .= $line;
}

sub canonical {
    my $template = shift;
    my $where = shift;
    my $long_where = shift;
    $long_where //= $where;
    $template =~ s/ \b package \s Parse [:][:] Marpa [:][:] [EP] _ [0-9a-fA-F]+ [;] $
        /package Parse::Marpa::<PACKAGE>;/xms;
    $template =~ s/ \s* at \s [^\s]* code_diag[.]t \s line  \s \d+\Z//xms;
    $template =~ s/[<]WHERE[>]/$where/xmsg;
    $template =~ s/[<]LONG_WHERE[>]/$long_where/xmsg;
    $template =~ s/ \s [<]DATA[>] \s line \s \d+
            / <DATA> line <LINE_NO>/xmsg;
    $template
        =~ s/
            \s at \s [(] eval \s \d+ [)] \s line \s
            / at (eval <LINE_NO>) line /xmsg;
    return $template;
}

sub run_test {
    my $args = shift;

    my $E_Op_action = $good_code{e_op_action};
    my $E_Number_action = $good_code{e_number_action};
    my $preamble = q{1};
    my $lex_preamble = q{1};
    my $default_action = $good_code{default_action};

    while (my ($arg, $value) = each %{$args})
    {
      given(lc $arg) {
        when ('e_op_action') { $E_Op_action = $value }
        when ('e_number_action') { $E_Number_action = $value }
        when ('default_action') { $default_action = $value }
        when ('lex_preamble') { $lex_preamble = $value }
        when ('preamble') { $preamble = $value }
        default { croak("unknown argument to run_test: $arg"); }
      }
    }

    my $grammar = new Parse::Marpa::Grammar({
        start => 'S',
        rules => [
            [ 'S', [qw/E trailer optional_trailer/], ],
            [ 'E', [qw/E Op E/], $E_Op_action, ],
            [ 'E', [qw/Number/], $E_Number_action, ],
            [ 'optional_trailer', [qw/trailer/], ],
            [ 'optional_trailer', [], ],
            [ 'trailer', [qw/Text/], ],
        ],
        terminals => [
            [ 'Number' => { regex => qr/\d+/xms } ],
            [ 'Op' => { regex => qr/[-+*]/xms } ],
            [ 'Text' => { action => 'lex_q_quote' } ],
        ],
        default_action => $default_action,
        preamble => $preamble,
        lex_preamble => $lex_preamble,
        default_lex_prefix => '\s*',
    });

    $grammar->precompute();

    my $recce = new Parse::Marpa::Recognizer({grammar => $grammar});

    my $fail_offset = $recce->text( '2 - 0 * 3 + 1 q{trailer}' );
    if ( $fail_offset >= 0 ) {
        croak("Parse failed at offset $fail_offset");
    }

    $recce->end_input();

    my $expected = '((((2-0)*3)+1)==7; q{trailer};undef)';
    my $evaler = new Parse::Marpa::Evaluator( { recce => $recce } );
    my $value = $evaler->value();
    Marpa::Test::is(${$value}, $expected, 'Ambiguous Equation Value');

    return 1;

} # sub run_test

run_test({});

my %where = (
    preamble => 'evaluating preamble',
    lex_preamble => 'evaluating lex preamble',
    e_op_action => 'compiling action',
    default_action => 'compiling action',
);

my %long_where = (
    preamble => 'evaluating preamble',
    lex_preamble => 'evaluating lex preamble',
    e_op_action => 'compiling action for 1: E -> E Op E',
    default_action => 'compiling action for 3: optional_trailer -> trailer',
);

for my $test (@tests)
{
    for my $feature (@features)
    {
        my $test_name = "$test in $feature";
        if (eval {
            run_test({
                $feature => $test_code{$test},
            });
        })
        {
           fail("$test_name did not fail -- that shouldn't happen");
        } else {
            my $eval_error = $EVAL_ERROR;
            my $where = $where{$feature};
            my $long_where = $long_where{$feature};
            Marpa::Test::is(
                canonical($eval_error, $where, $long_where),
                canonical($expected{$test}{$feature}, $where, $long_where),
                $test_name
            );
        }
    }
}

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:

__DATA__
| bad code compile phase warning
# this should be a compile phase warning
my $x = 0;
my $x = 1;
my $x = 2;
$x++;
1;
__END__

| expected preamble compile phase warning
| expected lex_preamble compile phase warning
Fatal problem(s) in <LONG_WHERE>
2 Warning(s)
Warning(s) treated as fatal problem
Last warning occurred in this code:
2: # this should be a compile phase warning
3: my $x = 0;
*4: my $x = 1;
*5: my $x = 2;
6: $x++;
7: 1;
======
Warning #0 in <WHERE>:
"my" variable $x masks earlier declaration in same scope at (eval <LINE_NO>) line 4, <DATA> line 1.
======
Warning #1 in <WHERE>:
"my" variable $x masks earlier declaration in same scope at (eval <LINE_NO>) line 5, <DATA> line 1.
======
__END__

| expected e_op_action compile phase warning
| expected default_action compile phase warning
Fatal problem(s) in <LONG_WHERE>
2 Warning(s)
Warning(s) treated as fatal problem
Last warning occurred in this code:
3: # this should be a compile phase warning
4: my $x = 0;
*5: my $x = 1;
*6: my $x = 2;
7: $x++;
8: 1;
9: }
======
Warning #0 in <WHERE>:
"my" variable $x masks earlier declaration in same scope at (eval <LINE_NO>) line 5, <DATA> line 1.
======
Warning #1 in <WHERE>:
"my" variable $x masks earlier declaration in same scope at (eval <LINE_NO>) line 6, <DATA> line 1.
======
__END__

| bad code compile phase fatal
# this should be a compile phase error
my $x = 0;
$x=;
$x++;
1;
__END__

| expected preamble compile phase fatal
| expected lex_preamble compile phase fatal
Fatal problem(s) in <LONG_WHERE>
Fatal Error
Problem code begins:
1: package Parse::Marpa::<PACKAGE>;
2: # this should be a compile phase error
3: my $x = 0;
4: $x=;
5: $x++;
6: 1;
======
Error in <WHERE>:
syntax error at (eval <LINE_NO>) line 4, at EOF
======
__END__

| expected e_op_action compile phase fatal
| expected default_action compile phase fatal
Fatal problem(s) in <LONG_WHERE>
Fatal Error
Problem code begins:
1: sub {
2:     package Parse::Marpa::<PACKAGE>;
3: # this should be a compile phase error
4: my $x = 0;
5: $x=;
6: $x++;
7: 1;
======
Error in <WHERE>:
syntax error at (eval <LINE_NO>) line 5, at EOF
======
__END__

| bad code run phase warning
# this should be a run phase warning
my $x = 0;
warn "Test Warning 1";
warn "Test Warning 2";
$x++;
1;
__END__

| expected preamble run phase warning
| expected lex_preamble run phase warning
Fatal problem(s) in <LONG_WHERE>
2 Warning(s)
Warning(s) treated as fatal problem
Last warning occurred in this code:
2: # this should be a run phase warning
3: my $x = 0;
*4: warn "Test Warning 1";
*5: warn "Test Warning 2";
6: $x++;
7: 1;
======
Warning #0 in <WHERE>:
Test Warning 1 at (eval <LINE_NO>) line 4, <DATA> line <LINE_NO>.
======
Warning #1 in <WHERE>:
Test Warning 2 at (eval <LINE_NO>) line 5, <DATA> line <LINE_NO>.
======
__END__

| expected e_op_action run phase warning
Fatal problem(s) in computing value for rule: 1: E -> E Op E
2 Warning(s)
Warning(s) treated as fatal problem
Last warning occurred in this code:
3: # this should be a run phase warning
4: my $x = 0;
*5: warn "Test Warning 1";
*6: warn "Test Warning 2";
7: $x++;
8: 1;
9: }
======
Warning #0 in computing value:
Test Warning 1 at (eval <LINE_NO>) line 5, <DATA> line <LINE_NO>.
======
Warning #1 in computing value:
Test Warning 2 at (eval <LINE_NO>) line 6, <DATA> line <LINE_NO>.
======
__END__

| expected default_action run phase warning
Fatal problem(s) in computing value for rule: 5: trailer -> Text
2 Warning(s)
Warning(s) treated as fatal problem
Last warning occurred in this code:
3: # this should be a run phase warning
4: my $x = 0;
*5: warn "Test Warning 1";
*6: warn "Test Warning 2";
7: $x++;
8: 1;
9: }
======
Warning #0 in computing value:
Test Warning 1 at (eval <LINE_NO>) line 5, <DATA> line <LINE_NO>.
======
Warning #1 in computing value:
Test Warning 2 at (eval <LINE_NO>) line 6, <DATA> line <LINE_NO>.
======
__END__

| bad code run phase error
# this should be a run phase error
my $x = 0;
$x = 711/0;
$x++;
1;
__END__

| expected preamble run phase error
| expected lex_preamble run phase error
Fatal problem(s) in <LONG_WHERE>
Fatal Error
Problem code begins:
1: package Parse::Marpa::<PACKAGE>;
2: # this should be a run phase error
3: my $x = 0;
4: $x = 711/0;
5: $x++;
6: 1;
======
Error in <WHERE>:
Illegal division by zero at (eval <LINE_NO>) line 4, <DATA> line <LINE_NO>.
======
__END__

| expected e_op_action run phase error
Fatal problem(s) in computing value for rule: 1: E -> E Op E
Fatal Error
Problem code begins:
1: sub {
2:     package Parse::Marpa::<PACKAGE>;
3: # this should be a run phase error
4: my $x = 0;
5: $x = 711/0;
6: $x++;
7: 1;
======
Error in computing value:
Illegal division by zero at (eval <LINE_NO>) line 5, <DATA> line <LINE_NO>.
======
__END__

| expected default_action run phase error
Fatal problem(s) in computing value for rule: 5: trailer -> Text
Fatal Error
Problem code begins:
1: sub {
2:     package Parse::Marpa::<PACKAGE>;
3: # this should be a run phase error
4: my $x = 0;
5: $x = 711/0;
6: $x++;
7: 1;
======
Error in computing value:
Illegal division by zero at (eval <LINE_NO>) line 5, <DATA> line <LINE_NO>.
======
__END__

| bad code run phase die
# this is a call to die()
my $x = 0;
die('test call to die');
$x++;
1;
__END__

| expected preamble run phase die
| expected lex_preamble run phase die
Fatal problem(s) in <LONG_WHERE>
Fatal Error
Problem code begins:
1: package Parse::Marpa::<PACKAGE>;
2: # this is a call to die()
3: my $x = 0;
4: die('test call to die');
5: $x++;
6: 1;
======
Error in <WHERE>:
test call to die at (eval <LINE_NO>) line 4, <DATA> line <LINE_NO>.
======
__END__

| expected e_op_action run phase die
Fatal problem(s) in computing value for rule: 1: E -> E Op E
Fatal Error
Problem code begins:
1: sub {
2:     package Parse::Marpa::<PACKAGE>;
3: # this is a call to die()
4: my $x = 0;
5: die('test call to die');
6: $x++;
7: 1;
======
Error in computing value:
test call to die at (eval <LINE_NO>) line 5, <DATA> line <LINE_NO>.
======
__END__

| expected default_action run phase die
Fatal problem(s) in computing value for rule: 5: trailer -> Text
Fatal Error
Problem code begins:
1: sub {
2:     package Parse::Marpa::<PACKAGE>;
3: # this is a call to die()
4: my $x = 0;
5: die('test call to die');
6: $x++;
7: 1;
======
Error in computing value:
test call to die at (eval <LINE_NO>) line 5, <DATA> line <LINE_NO>.
======
__END__


| good code e_op_action
my ($right_string, $right_value)
    = ($_[2] =~ /^(.*)==(.*)$/);
my ($left_string, $left_value)
    = ($_[0] =~ /^(.*)==(.*)$/);
my $op = $_[1];
my $value;
if ($op eq '+') {
   $value = $left_value + $right_value;
} elsif ($op eq '*') {
   $value = $left_value * $right_value;
} elsif ($op eq '-') {
   $value = $left_value - $right_value;
} else {
   croak("Unknown op: $op");
}
'(' . $left_string . $op . $right_string . ')==' . $value;
__END__

| good code e_number_action
my $v0 = pop @_;
$v0 . q{==} . $v0;
__END__

| good code default_action
my $v_count = scalar @_;
return q{} if $v_count <= 0;
return $_[0] if $v_count == 1;
'(' . join(q{;}, (map { $_ // 'undef' } @_)) . ')';
__END__

