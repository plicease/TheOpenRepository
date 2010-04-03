#!/usr/bin/perl

# Unit testing for PPI, generated by Test::Inline

use strict;
use File::Spec::Functions ':ALL';
BEGIN {
	$|  = 1;
	$^W = 1;
	$PPI::XS_DISABLE = 1;
	$PPI::XS_DISABLE = 1; # Prevent warning
    no warnings 'once';
    $PPI::Lexer::X_TOKENIZER = "PPI::XS::Tokenizer";
}
use PPI;
use PPI::XS::Tokenizer;

# Execute the tests
use Test::More tests => 12;

# =begin testing literal 12
{
my $empty_list_document = PPI::Document->new(\<<'END_PERL');
qw//
qw/    /
END_PERL

isa_ok( $empty_list_document, 'PPI::Document' );
my $empty_list_tokens =
	$empty_list_document->find('PPI::Token::QuoteLike::Words');
is( scalar @{$empty_list_tokens}, 2, 'Found expected empty word lists.' );
foreach my $token ( @{$empty_list_tokens} ) {
	my @literal = $token->literal;
	is( scalar @literal, 0, qq<No elements for "$token"> );
}

my $non_empty_list_document = PPI::Document->new(\<<'END_PERL');
qw/foo bar baz/
qw/  foo bar baz  /
qw {foo bar baz}
END_PERL
my @expected = qw/ foo bar baz /;

isa_ok( $non_empty_list_document, 'PPI::Document' );
my $non_empty_list_tokens =
	$non_empty_list_document->find('PPI::Token::QuoteLike::Words');
is(
	scalar(@$non_empty_list_tokens),
	3,
	'Found expected non-empty word lists.',
);
foreach my $token ( @$non_empty_list_tokens ) {
	my $literal = $token->literal;
	is(
		$literal,
		scalar @expected,
		qq<Scalar context literal() returns the list for "$token">,
	);
	my @literal = $token->literal;
	is_deeply( [ $token->literal ], \@expected, '->literal matches expected' );
}
}


1;