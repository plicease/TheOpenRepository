package t::lib::Test3;

use strict;
use Perl::Dist ();

use vars qw{$VERSION @ISA};
BEGIN {
	$VERSION = '1.05';
	@ISA     = 'Perl::Dist';
}





#####################################################################
# Configuration

sub app_name             { 'Test Perl'                }
sub app_ver_name         { 'Test Perl 1 alpha 1'      }
sub app_publisher        { 'Vanilla Perl Project'     }
sub app_publisher_url    { 'http://vanillaperl.org'   }
sub app_id               { 'testperl'                 }
sub output_base_filename { 'test-perl-5.10.0-alpha-1' }





#####################################################################
# Constructor

sub new {
	my $class = shift;
	my $self  = $class->SUPER::new(@_);

	# Add links
	

	return $self;
}





#####################################################################
# Main Methods

sub run {
	my $self = shift;

	# Install the core binaries
	$self->install_c_toolchain;

	# Install the extra libraries
	$self->install_c_libraries;

	# Install Perl 5.10.0
	$self->install_perl_5100;

	# Install a test distro
	$self->install_distribution(
		name => 'ADAMK/Config-Tiny-2.12.tar.gz',
	);
}

sub trace { Test::More::diag($_[1]) }

sub install_binary {
	return shift->SUPER::install_binary( @_, trace => sub { 1 } );
}

sub install_library {
	return shift->SUPER::install_library( @_, trace => sub { 1 } );
}

sub install_distribution {
	return shift->SUPER::install_distribution( @_, trace => sub { 1 } );
}

sub install_perl_5100_bin {
	return shift->SUPER::install_perl_5100_bin( @_, trace => sub { 1 } );
}

sub install_perl_5100_toolchain {
	my $perl = Probe::Perl->find_perl_interpreter;
	local @Perl::Dist::Util::Toolchain::DELEGATE = (
		$perl, '-Mblib',
	);
	return shift->SUPER::install_perl_5100_toolchain( @_, trace => sub { 1 } );
}

1;
