package XML::WiX3::Classes::Fragment;

#<<<
use 5.006;
use Moose;
use vars              qw( $VERSION );

use version; $VERSION = version->new('0.003')->numify;
#>>>

with 'XML::WiX3::Classes::Role::Fragment';
with 'XML::WiX3::Classes::Role::Tag';

#####################################################################
# Main Methods

# Append the id parameter to 'Fr_' to indicate a fragment.
sub BUILDARGS {
	my $class = shift;
	
	if ( @_ == 1 && ! ref $_[0] ) {
		return { id => 'Fr_' . $_[0] };
	} elsif ( @_ == 1 && 'HASH' eq ref $_[0] ) {
		if (exists $_[0]->{id}) {
			$_[0]->{id} = 'Fr_' . $_[0]->{'id'};
			return $_[0];
		} else {
			XWC::Exception::Parameter::Missing->throw('id');
		}
	} else {
		my %hash = @_;
		if (exists $hash{id}) {
			$hash{id} = 'Fr_' . $hash{'id'};
			return \%hash;
		} else {
			XWC::Exception::Parameter::Missing->throw('id');
		}		
	}
}

sub as_string {
	my $self = shift;

	my @namespaces   = $self->get_namespaces();
	my $namespaces   = join q{ }, @namespaces;
	my $id           = $self->get_id();
	my $child_string = q{};
	$child_string = $self->indent(2, $self->as_string_children()) if $self->has_child_tags();
	chomp $child_string;
	
	return <<"EOF";
<?xml version='1.0' encoding='windows-1252'?>
<Wix $namespaces>
  <Fragment Id='$id'>
$child_string
  </Fragment>
</Wix>
EOF

} ## end sub as_string

sub get_namespace {
	return q{xmlns='http://schemas.microsoft.com/wix/2006/wi'};
}

1;

__END__

=head1 NAME

XML::WiX3::Classes::CreateFolderFragment - "Shortcut Fragment" containing only a CreateFolder entry.

=head1 VERSION

This document describes XML::WiX3::Classes::CreateFolderFragment version 0.003

=head1 SYNOPSIS

	my $fragment = XML::WiX3::Classes::CreateFolderFragment(
		id => $id,
		directory_id = $directory_id
	);
  
=head1 DESCRIPTION

This module defines a fragment that contains only a CreateFolder tag and 
the parent tags required to implement it.

=head1 INTERFACE 

=head2 new()



Parameter exceptions will always print a stack trace.

=head3 $fragment->parameter()

The name of the parameter with the error.

=head3 $e->info()

Information about how the parameter was bad.

=head3 $e->where()

Information about what routine had the bad parameter.

=back

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

This module provides the error diagnostics for the XML::WiX3::Objects 
distribution.  It has no diagnostics of its own.

=head1 CONFIGURATION AND ENVIRONMENT
  
XML::WiX3::Classes::Exceptions requires no configuration files or environment variables.

=head1 DEPENDENCIES

L<Exception::Class> version 1.22 or later.

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-xml-wix3-classes@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 AUTHOR

Curtis Jewell  C<< <csjewell@cpan.org> >>

=head1 SEE ALSO

L<Exception::Class>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2009, Curtis Jewell C<< <csjewell@cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

