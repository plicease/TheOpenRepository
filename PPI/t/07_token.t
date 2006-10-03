#!/usr/bin/perl -w

# Formal unit tests for specific PPI::Token classes

use strict;
use File::Spec::Functions ':ALL';
use List::MoreUtils qw();
BEGIN {
	$| = 1;
	$PPI::XS_DISABLE = 1;
	$PPI::XS_DISABLE = 1; # Prevent warning
}
use PPI;

# Execute the tests
use Test::More tests => 255;
use t::lib::PPI;

#####################################################################
# Code/Dump Testing
# ntests = 2 + 12 * nfiles

t::lib::PPI->run_testdir( catdir( 't', 'data', '07_token' ) );



#####################################################################
# PPI::Token::Symbol Unit Tests
# Note: braces and the symbol() method are tested in regression.t

{
	# Test both creation methods
	my $Token = PPI::Token::Symbol->new( '$foo' );
	isa_ok( $Token, 'PPI::Token::Symbol' );
	$Token = PPI::Token->new( 'Symbol', '$foo' );
	isa_ok( $Token, 'PPI::Token::Symbol' );
	
	# Check the creation of a number of different values
	my @symbols = (
		'$foo'       => '$foo',
		'@foo'       => '@foo',
		'$ foo'      => '$foo',
		'$::foo'     => '$main::foo',
		'@::foo'     => '@main::foo',
		'$foo::bar'  => '$foo::bar',
		'$ foo\'bar' => '$foo::bar',
		);
	while ( @symbols ) {
		my ($value, $canon) = ( shift(@symbols), shift(@symbols) );
		my $Symbol = PPI::Token::Symbol->new( $value );
		isa_ok( $Symbol, 'PPI::Token::Symbol' );
		is( $Symbol->content,   $value, "Symbol '$value' returns ->content   '$value'" );
		is( $Symbol->canonical, $canon, "Symbol '$value' returns ->canonical '$canon'" );
	}
}


#####################################################################
# PPI::Token::Number Unit Tests

SCOPE: {
	my @examples = (
		# code => base | '10f' | '10e'
		'0'       => 10,
		'1'       => 10,
		'10'      => 10,
		'1_0'     => 10,
		'.0'      => '10f',
		'.0_0'    => '10f',
		'-.0'     => '10f',
		'0.'      => '10f',
		'0.0'     => '10f',
		'0.0_0'   => '10f',
		'1_0.'    => '10f',
		'.0e0'    => '10e',
		'-.0e0'   => '10e',
		'0.e1'    => '10e',
		'0.0e-1'  => '10e',
		'0.0e+1'  => '10e',
		'0.0e-10' => '10e',
		'0.0e+10' => '10e',
		'0.0e100' => '10e',
		'1_0e1_0' => '10e',
		'0b'      => 2,
		'0b0'     => 2,
		'0b10'    => 2,
		'0b1_0'   => 2,
		'00'      => 8,
		'01'      => 8,
		'010'     => 8,
		'01_0'    => 8,
		'0x'      => 16,
		'0x0'     => 16,
		'0x10'    => 16,
		'0x1_0'   => 16,
		'0.0.0'       => 256,
		'.0.0'        => 256,
		'127.0.0.1'   => 256,
		'1.1.1.1.1.1' => 256,
	);

	my $iterator = List::MoreUtils::natatime(2, @examples);
	while (my ($code, $base) = $iterator->()) {
		my $exp = $base =~ s/e//;
		my $float = $exp || $base =~ s/f//;
		my $T = PPI::Tokenizer->new( \$code );
		my $token = $T->get_token();
		is("$token", $code, "'$code' is a single token");
		is($token->base(), $base, "base of '$code' is $base");
		if ($float) {
			ok($token->isa('PPI::Token::Number::Float'), "'$code' is ::Float");
		} else {
			ok(!$token->isa('PPI::Token::Number::Float'), "'$code' not ::Float");
		}
		if ($exp) {
			ok($token->isa('PPI::Token::Number::Exp'), "'$code' is ::Exp");
		} else {
			ok(!$token->isa('PPI::Token::Number::Exp'), "'$code' not ::Exp");
		}

		if ($base != 256) {
			no warnings;
			my $literal = eval $code;
			if ($@) {
				is($token->literal, undef, "literal('$code'), $@");
			} else {
				cmp_ok($token->literal, '==', $literal, "literal('$code')");
			}
		}
	}
}

foreach my $code ( '1.0._0', '1.0.0.0_0' ) {
	my $T = PPI::Tokenizer->new( \$code );
	my $token = $T->get_token();
	isnt("$token", $code, 'tokenize bad version');
}


foreach my $code ( '08', '09', '0778', '0779' ) {
	my $T = PPI::Tokenizer->new( \$code );
	my $token = $T->get_token();
	is("$token", $code, 'tokenize bad octal');
	ok($token->{_error} && $token->{_error} =~ m/octal/i,
	   'invalid octal number should trigger parse error');
}

foreach my $code ( '0b2', '0b012' ) {
	my $T = PPI::Tokenizer->new( \$code );
	my $token = $T->get_token();
	is("$token", $code, 'tokenize bad binary');
	ok($token->{_error} && $token->{_error} =~ m/binary/i,
	   'invalid binary number should trigger parse error');
}

foreach my $code ( '0xg', '0x0g' ) {
	my $T = PPI::Tokenizer->new( \$code );
	my $token = $T->get_token();
	isnt("$token", $code, 'tokenize bad hex');
	ok(!$token->{_error}, 'invalid hexadecimal digit triggers end of token');
}

1;
