package CPAN::Mini::Visit;

=pod

=head1 NAME

CPAN::Mini::Visit - A generalised API version of David Golden's visitcpan

=head1 SYNOPSIS

  CPAN::Mini::Visit->new(
      minicpan => '/minicpan',
      acme     => 0,
      author   => 'ADAMK',
      warnings => 1,
      random   => 1,
      callback => sub {
          print "# counter: $_[0]->{counter}\n";
          print "# archive: $_[0]->{archive}\n";
          print "# tempdir: $_[0]->{tempdir}\n";
          print "# dist:    $_[0]->{dist}\n";
          print "# author:  $_[0]->{author}\n";
      }
  )->run;

  # counter: 1234
  # archive: /minicpan/authors/id/A/AD/ADAMK/Config-Tiny-1.00.tar.gz
  # tempdir: /tmp/1a4YRmFAJ3/Config-Tiny-1.00
  # dist:    ADAMK/Config-Tiny-1.00.tar.gz
  # author:  ADAMK

=head1 DESCRIPTION

L<CPAN::Mini::Extract> has been relatively successful at allowing processes
to run across the contents (or a subset of the contents) of an entire
L<minicpan> checkout.

However it has become evident that while it is useful (and theoretically
optimal from a processing point of view) to maintain an expanded minicpan
checkout the sheer size of an expanded minicpan is such that it becomes
an undo burdon to manage, move, copy or even delete a directory tree with
hundreds of thousands of file totalling in the high single gigabytes in size.

Annoyed by this, David Golden created L<visitcpan> which takes an alternative
approach of sequentially expanding the tarball of each distribution into a
temporary directory, do the processing on that distribution, and then delete
the temporary directory before moving on to the next directory.

This method results in a longer computation time, but with the benefit of
dramatically reduced system overhead, greater adaptability, and allow for
easy ad-hoc computations.

This improvement in flexibility turns out to be worth the extra computation
time in almost all cases.

B<CPAN::Mini::Visit> is a simplified and generalised API-based version of 
David Golden's L<visitcpan> script.

It implements only the process of discovering, iterating and expanding
archives, before handing off control to an arbitrary callback function
provided to the constructor.

=cut

use 5.008;
use strict;
use warnings;
use Carp                   'croak';
use File::Spec        0.80 ();
use File::Temp        0.21 ();
use File::pushd       1.00 ();
use File::chmod       0.31 ();
use File::Find::Rule  0.27 ();
use Archive::Extract  0.32 ();
use CPAN::Mini       0.576 ();
use Params::Util      1.00 qw{
	_HASH _STRING _ARRAYLIKE _CODELIKE _REGEX
};

our $VERSION = '0.11_02';

use Object::Tiny 1.06 qw{
	minicpan
	authors
	callback
	skip
	acme
	author
	ignore
	random
	warnings
	prefer_bin
};

=pod

=head2 new

Takes a variety of parameters and creates a new visitor object.

The C<minicpan> param should be the root directory of a L<CPAN::Mini>
download.

The C<callback> param should be a C<CODE> reference that will be called
for each visit. The first parameter passed to the callback will be a C<HASH>
reference containing the tarball location in the C<archive> key, the location
of the temporary directory in the C<tempdir> key, the canonical CPAN
distribution name in the C<dist> key, and the author id in the C<author> key.

The optional C<skip> param should be a C<CODE> reference
that will be called for each visit before extracting dist. The first
parameter passed to the callback will be a C<HASH> reference with C<archive>,
C<dist> and C<author> keys. Callback should return 1 if dist should be skipped
and 0 otherwise.

The C<acme> param (true by default) can be set to false to exclude any
distributions that contain the string "Acme", allowing the visit to ignore
any of the joke modules.

The C<author> param can be provided to limit the visit to only the modules
owned by a specific author.

The C<random> param will cause the archives to be processed in random order
if enabled. If not, the archives will be processed in alphabetical order.

The C<warnings> param will turn on L<Archive::Extract> warnings if enabled,
or disable warnings otherwise.

The C<prefer_bin> param will tell L<Archive::Extract> to use binary extract
instead of CPAN module extract wherever possible. By default, it will use
module-based extract.

Returns a B<CPAN::Mini::Visit> object, or throws an exception on error.

=cut

sub new {
	my $class = shift;
	my $self  = bless { @_ }, $class;

	# Normalise
	$self->{random}     = $self->random     ? 1 : 0;
	$self->{prefer_bin} = $self->prefer_bin ? 1 : 0;
	$self->{warnings}   = 0 unless $self->{warnings};

	# Check params
	unless (
		_HASH($self->minicpan)
		or (
			defined _STRING($self->minicpan)
			and
			-d $self->minicpan
		)
	) {
		croak("Missing or invalid 'minicpan' param");
	}
	unless ( _CODELIKE($self->callback) ) {
		croak("Missing or invalid 'callback' param");
	}
	unless ( defined $self->ignore ) {
		$self->{ignore} = [];
	}
	unless ( _ARRAYLIKE($self->ignore) ) {
		croak("Invalid 'ignore' param");
	}

	# Derive the authors directory
	$self->{authors} = File::Spec->catdir( $self->_minicpan, 'authors', 'id' );
	unless ( -d $self->authors ) {
		croak("Authors directory '$self->{authors}' does not exist");
	}

	return $self;
}

sub _sort {
	my $self = shift;
	my $files = shift;

	# Randomise if needed
	if ( $self->random ) {
		@$files = sort { rand() <=> rand() } @$files;
	}

}

=pod

=head2 run

The C<run> method executes the visit process, taking no parameters and
returning true.

Because the object contains no state information, you may call the C<run>
method multiple times for a single visit object with no ill effects.

=cut

sub run {
	my $self = shift;

	# If we've been passed a HASH minicpan param,
	# do an update_mirror first, before the regular run.
	if ( _HASH($self->minicpan) ) {
		CPAN::Mini->update_mirror(%{$self->minicpan});
	}

	# Search for the files
	my $find  = File::Find::Rule->name('*.tar.gz', '*.tgz', '*.zip', '*.bz2')->file->relative;
	my @files = sort $find->in( $self->authors );
	unless ( $self->acme ) {
		@files = grep { ! /\bAcme\b/ } @files;
	}
	foreach my $filter ( @{$self->ignore} ) {
		if ( defined _STRING($filter) ) {
			$filter = quotemeta $filter;
			$filter = qr/$filter/;
		}
		if ( _REGEX($filter) ) {
			@files = grep { ! /$filter/ } @files;
		} elsif ( _CODELIKE($filter) ) {
			@files = grep { ! $filter->($_) } @files;
		} else {
			die("Missing or invalid filter");
		}
	}

	$self->_sort(\@files);

	# Extract the archive
	my $counter = 0;
	foreach my $file ( @files ) {
		# Derive the main file properties
		my $path = File::Spec->catfile( $self->authors, $file );
		my $dist = $file;
		$dist =~ s|^[A-Z]/[A-Z][A-Z]/|| or die "Bad distpath for $file";
		unless ( $dist =~ /^([A-Z]+)/ ) {
			die "Bad author for $file";
		}
		my $author = "$1";
		if ( $self->author and $self->author ne $author ) {
			next;
		}

		# Explicitly ignore some damaging distributions
		# if we are using Perl extraction
		unless ( $self->prefer_bin ) {
			next if $path =~ /\bHarvey-\d/;
			next if $path =~ /\bText-SenseClusters\b/;
			next if $path =~ /\bBio-Affymetrix\b/;
			next if $path =~ /\bAlien-MeCab\b/;
		}

		my $skip = 0;
		if ($self->skip) {
			# Invoke the callback
			$skip = $self->skip->( {
				archive => $path,
				dist    => $dist,
				author  => $author,
			} );
		}
		next if $skip;

		# Extract the archive
		local $Archive::Extract::WARN       = !! ($self->warnings > 1);
		local $Archive::Extract::PREFER_BIN = $self->prefer_bin;
		my $archive = Archive::Extract->new( archive => $path );
		my $tmpdir  = File::Temp->newdir;
		my $ok      = 0;
		SCOPE: {
			my $pushd1 = File::pushd::pushd( File::Spec->curdir );
			$ok = eval {
				$archive->extract( to => $tmpdir );
			};
		}
		if ( $@ or not $ok ) {
			if ( $self->warnings > 1 ) {
				warn("Failed to extract '$path': $@");
			} elsif ( $self->warnings ) {
				print "  Failed: $dist\n";
			}
			next;
		}

		# If using bin tools, do an additional check for
		# damaged tarballs with non-executable directories (on unix)
		my $extract = $archive->extract_path;
		unless ( -r $extract and -x $extract ) {
			# Handle special case where we have screwed up
			# permissions on the extract directory.
			# Just assume we have permissions for that.
			File::chmod::chmod( 0755, $extract );
		}

		# Change into the directory
		my $pushd2 = File::pushd::pushd( $extract );

		# Invoke the callback
		$self->callback->( {
			tempdir => $extract,
			archive => $path,
			dist    => $dist,
			author  => $author,
			counter => ++$counter,
		} );
	}

	return 1;
}





######################################################################
# Support Methods

sub _minicpan {
	my $self = shift;
	return _HASH($self->minicpan)
		? $self->minicpan->{local}
		: $self->minicpan;
}

1;

=pod

=head1 SUPPORT

Bugs should be reported via the CPAN bug tracker at

L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=CPAN-Mini-Visit>

For other issues, contact the author.

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2009 Adam Kennedy.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
