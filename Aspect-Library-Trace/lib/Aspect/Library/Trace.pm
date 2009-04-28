package Aspect::Library::Trace;

use 5.006;
use strict;
use warnings;
use Aspect     0.14 ();
use Aspect::Modular ();

use vars qw{$VERSION @ISA};
BEGIN {
	$VERSION = '0.01';
	@ISA     = 'Aspect::Modular';
}

sub new {
	my $self = shift->SUPER::new(@_);

	# Track our depth
	$self->{depth} = 0;

	return $self;
}

sub get_advice {
	my $self   = shift;
	my $cut    = shift;
	my $before = Aspect::before { print STDERR '  ' x $self->{depth}++ . $_[0]->sub_name . "\n" } $cut;
	my $after  = Aspect::after  { $self->{depth}-- } $cut;
	return ( $before, $after );
}

1;

__END__

=pod

=head1 NAME

Aspect::Library::Trace - Aspect-oriented function call tracing

=head1 SYNOPSIS

  use Aspect;
  use Aspect::Library::Trace;
  
  aspect Trace => call qr/^Foo::/;
  
  Foo::foo1
    Foo::foo2
      Foo::foo3
  Foo::foo2
    Foo::foo3
  Foo::foo2
    Foo::foo3

=head1 DESCRIPTION

B<L<Aspect> Oriented Programming> is a programming paradigm that increases
modularity by enabling improved separation of concerns.

It is most useful when dealing with cross-cutting concerns that would
otherwise require code to be scattered around in many places.

B<Aspect::Library::Trace> is an L<Aspect> library that implements nested
functional call tracing, in the style formerly offered by the C<dprofpp -T>
command provided by L<Devel::DProf> (before that module became unusable).

The basic usage is very simple, just create an C<Trace> aspect as shown
in the L</SYNOPSIS>.

Any calls to functions described in the pointcut will be printed to
C<STDERR>. Nesting is indicated via indenting.

Because the depth is tracked at a per-Aspect level, you should avoid
creating more than one trace Aspect or the indenting levels will be
mixed up and the output will become largely meaningless.

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Aspect-Library-Trace>

For other issues, contact the author.

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 SEE ALSO

L<Aspect>

=head1 COPYRIGHT

Copyright 2009 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
