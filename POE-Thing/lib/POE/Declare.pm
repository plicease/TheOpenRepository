package POE::Declare;

=pod

=head1 NAME

POE::Thing - A POE abstraction layer for conciseness and simplicity

=head1 DESCRIPTION

L<POE> is a very powerful and flexible system for doing asynchronous
programming.

But personally, I find it confusing and tricky to use at times.

(to be continued)

=cut

use 5.005;
use strict;
use Carp                 qw{ croak };
use Exporter             ();
use List::Util           qw{ first };
use Params::Util         qw{ _IDENTIFIER _CLASS };
use Class::Inspector     ();
use POE                  qw{ Session };
use POE::Declare::Object ();
use POE::Declare::Meta   ();

# Provide the SELF constant
use constant SELF => HEAP;

use vars qw{$VERSION @ISA @EXPORT %ATTR %META};
BEGIN {
	$VERSION = '0.01';
	@ISA     = 'Exporter';
	@EXPORT  = qw{ SELF declare compile };

	# Metadata Storage
	%ATTR    = ();
	%META    = ();
}





#####################################################################
# Declaration Functions

sub import {
	my $pkg     = shift;
	my $callpkg = caller($Exporter::ExportLevel);

	# POE::Declare should only be loaded on empty classes.
	# We only use the simple case here of checking for $VERSION or @ISA
	no strict 'refs';
	if ( defined ${"$callpkg\::VERSION"} ) {
		Carp::croak("$callpkg already exists, cannot use POE::Declare");
	}
	if ( defined @{"$callpkg\::ISA"} ) {
		# Are we a subclass of an existing POE::Declare class
		if ( $callpkg->isa('POE::Declare::Object') ) {
			# Yes, don't set up anything, just do the exports
			return $pkg->SUPER::import(@_);
		}

		# This isn't a POE::Declare class
		Carp::croak("$callpkg already exists, cannot use POE::Declare");
	}

	# Set @ISA for the package, which does most of the work.
	@{"$callpkg\::ISA"} = qw{ POE::Declare::Object };

	# Export the symbols
	local $Exporter::ExportLevel += 1;
	$pkg->SUPER::import(@_);	
}

sub declare (@) {
	my $pkg = caller();
	if ( $META{$pkg} ) {
		croak("Too late to declare additions to $pkg");
	}

	# What is the name of the attribute
	my $name = shift;
	unless ( _IDENTIFIER($name) ) {
		croak("Did not provide a valid attribute name");
	}

	# Has the attribute already been defined
	if ( $ATTR{$pkg}->{$name} ) {
		croak("Attribute $name already defined in class $pkg");
	}

	# Resolve the attribute type
	my $type = shift;
	if ( _IDENTIFIER($type) ) {
		$type = "POE::Declare::Meta::$type";
	} elsif ( _CLASS($type) ) {
		$type = $type;
	} else {
		croak("Invalid attribute type");
	}

	# Try to load the attribute class
	my $file = $type . '.pm';
	$file =~ s{::}{/}g;
	eval { require $file };
	if ( $@ ) {
		local $Carp::CarpLevel += 1;
		my $quotefile = quotemeta $file;
		if ( $@ =~ /^Can\'t locate $quotefile/ ) {
			croak("The attribute class $type does not exist");
		} else {
			croak($@);
		}
	}

	# Is the class an attribute class?
	unless ( $type->isa('POE::Declare::Meta::Attribute') ) {
		croak("The class $type is not a POE::Declare::Atribute");
	}

	# Create and save the attribute
	my $attribute = $type->new( name => $name, @_ );
	$ATTR{$pkg}->{$name} = $attribute;

	return 1;
}

# Compile a named class
sub compile {
	my $pkg = @_ ? shift : caller();

	# Shortcut if already compiled
	return 1 if $META{$pkg};

	# Create the meta object
	my $meta  = $META{$pkg} = POE::Declare::Meta->new($pkg);
	my @super = reverse $meta->super_path;

	# Make sure any parent POE::Declare classes are compiled
	foreach my $parent ( @super ) {
		next if $META{$parent};
		croak("Cannot compile $pkg, parent class $parent not compiled");
	}

	# Are any attributes already defined in our parents?
	foreach my $name ( sort keys %{$ATTR{$pkg}} ) {
		my $found = first { $ATTR{$_}->{attr}->{$name} } @super;
		if ( $found ) {
			croak("Duplicate attribute '$name' already defined in " . $found->name );
		}
		$meta->{attr}->{$name} = $ATTR{$pkg}->{$name};
	}

	# Compile the individual parts
	$meta->compile;
}

# Get the meta-object for a class.
# Primarily used for testing purposes.
sub meta {
	$META{$_[0]};
}

1;

=pod

=head1 SUPPORT

Bugs should be always be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=POE-Declare>

For other issues, or commercial enhancement or support, contact the author.

=head1 AUTHORS

Adam Kennedy E<lt>adamk@cpan.orgE<lt>

=head1 SEE ALSO

L<POE>, L<http://ali.as/>

=head1 COPYRIGHT

Copyright 2006 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
