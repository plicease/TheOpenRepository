package Module::Release::OpenRepository;

use strict;
use warnings;
use base qw(Exporter);
use vars qw($VERSION);

our @EXPORT = qw(open_upload);

$VERSION = '0.01';

=head1 NAME

Module::Release::OpenRepository - Import release into The Open Repository.

=head1 SYNOPSIS

The release2 script will automatically load this module if it thinks that you
want to upload to the Open Repository at http://svn.ali.as/.

=head1 DESCRIPTION

=over 4

=item ownsite_upload

Looks in local_name to get the name and version of the distribution file.

=cut

sub open_upload {
	my $self = shift;

	$self->_print( "Checking state of Subversion..." );

	my $local_file = $self->local_file;
	my $remote_file = "http://svn.ali.as/cpan/releases/$local_file";
	my $bot_name = $self->config->upload_bot_name || 'Module::Release::OpenRepository';
	my ($release, $version) = $self->local_file =~ m/([\w-]+)-([\d_\.]+).tar.gz/msx;
	$release =~ s/-/::/g;
    my $message = "[$bot_name] Importing upload file for $release $version"; 
	
	$self->_print("Committing release file to OpenRepository.\n");
	$self->_debug("Commit Message: $message\n");
	$self->run(qq(svn import $local_file $remote_file -m "$message" 2>&1));

}


=back

=head1 SEE ALSO

L<Module::Release>

=head1 SOURCE AVAILABILITY

This source is in Github:

	git://github.com/briandfoy/module-release.git

=head1 AUTHOR

brian d foy, C<< <bdfoy@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2007-2009, brian d foy, All Rights Reserved.

You may redistribute this under the same terms as Perl itself.

=cut

1;
