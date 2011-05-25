package Aspect::Point::Around;
=pod

=head1 NAME

Aspect::Point - The Join Point context for "around" advice code

=head1 SYNOPSIS

=head1 METHODS

=cut

use strict;
use warnings;
use Aspect::Point ();

our $VERSION = '0.981';
our @ISA     = 'Aspect::Point';

use constant type => 'around';





######################################################################
# Aspect::Point Methods

sub exception {
	Carp::croak("Cannot call exception in around advice");
}

sub proceed {
	my $self = shift;

	local $_ = ${$self->{topic}};

	if ( $self->{wantarray} ) {
		$self->return_value(
			Sub::Uplevel::uplevel(
				2,
				$self->{original},
				@{$self->{args}},
			)
		);

	} elsif ( defined $self->{wantarray} ) {
		$self->return_value(
			scalar Sub::Uplevel::uplevel(
				2,
				$self->{original},
				@{$self->{args}},
			)
		);

	} else {
		Sub::Uplevel::uplevel(
			2,
			$self->{original},
			@{$self->{args}},
		);
	}

	${$self->{topic}} = $_;

	return;
}

BEGIN {
	*run_original = *proceed;
}

1;

=pod

=head1 AUTHORS

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

Marcel GrE<uuml>nauer E<lt>marcel@cpan.orgE<gt>

Ran Eilam E<lt>eilara@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2001 by Marcel GrE<uuml>nauer

Some parts copyright 2009 - 2011 Adam Kennedy.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
