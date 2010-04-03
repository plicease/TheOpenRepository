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
use Test::More tests => 24;

# =begin testing string 3
{
my $Document = PPI::Document->new( \"print 'foo';" );
isa_ok( $Document, 'PPI::Document' );
my $Single = $Document->find_first('Token::Quote::Single');
isa_ok( $Single, 'PPI::Token::Quote::Single' );
is( $Single->string, 'foo', '->string returns as expected' );
}



# =begin testing literal 21
{
my @pairs = (
	"''",          '',
	"'f'",         'f',
	"'f\\'b'",     "f\'b",
	"'f\\nb'",     "f\\nb",
	"'f\\\\b'",    "f\\b",
	"'f\\\\\\b'", "f\\\\b",
	"'f\\\\\\\''", "f\\'",
);
while ( @pairs ) {
	my $from  = shift @pairs;
	my $to    = shift @pairs;
	my $doc   = PPI::Document->new( \"print $from;" );
	isa_ok( $doc, 'PPI::Document' );
	my $quote = $doc->find_first('Token::Quote::Single');
	isa_ok( $quote, 'PPI::Token::Quote::Single' );
	is( $quote->literal, $to, "The source $from becomes $to ok" );
}
}


1;