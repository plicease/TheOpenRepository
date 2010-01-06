#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 7;
use Aspect;

# Convert Foo into a Memoized class that emulates a kind of Singleton
aspect Memoize => call 'Foo::new';

SCOPE: {
	# No param case should return the same object twice
	my $foo1 = Foo->new;
	my $foo2 = Foo->new;
	is( ref($foo1), ref($foo2), 'null: There can only be one' );

	# Since param case should also return the same object twice
	my $foo3 = Foo->new('foo');
	my $foo4 = Foo->new('foo');
	is( ref($foo3), ref($foo4), 'foo: There can only be one' );

	# But they shouldn't be the same as the null ones
	is( ref($foo1), ref($foo3), 'null and foo do not match' );
}

# Repeat as a lexical to ensure it handles global vs lexical properly
SCOPE: {
	my $aspect = aspect Memoize => call 'Bar::new';
	isa_ok( $aspect, 'Aspect::Library::Memoize' );

	# No param case should return the same object twice
	my $bar1 = Bar->new;
	my $bar2 = Bar->new;
	is( ref($bar1), ref($bar2), 'null: There can only be one' );

	# Since param case should also return the same object twice
	my $bar3 = Bar->new('foo');
	my $bar4 = Bar->new('foo');
	is( ref($bar3), ref($bar4), 'foo: There can only be one' );

	# But they shouldn't be the same as the null ones
	is( ref($bar1), ref($bar3), 'null and foo do not match' );
}





######################################################################
# Test Class

package Foo;

sub new {
	bless {}, shift;
};

package Bar;

sub new {
	bless {}, shift;
}
