use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
	class => 'My::Builder',
	code  => <<'END_CODE',
sub ACTION_authortest {
    my ($self) = @_;

    $self->depends_on('build');

    $self->test_files( qw( t xt/author ) );
    $self->depends_on('test');

    return;
}



sub ACTION_releasetest {
    my ($self) = @_;

    $self->depends_on('build');

    $self->test_files( qw( t xt/author xt/release ) );
    $self->depends_on('test');

    return;
}



sub ACTION_manifest {
    my ($self, @arguments) = @_;

    if (-e 'MANIFEST') {
        unlink 'MANIFEST' or die "Can't unlink MANIFEST: $!";
    }

    return $self->SUPER::ACTION_manifest(@arguments);
}

sub ACTION_distmeta {
    my ($self) = @_;
	
    $self->depends_on('manifest');
	
    return $self->SUPER::ACTION_distmeta();
}
END_CODE
);


my $builder = $class->new(
    module_name              => 'Perl::Dist::Strawberry::BuildPerl::5120',
    license                  => 'perl',
    dist_author              => [ 'Curtis Jewell <CSJewell@cpan.org>' ],
    dist_version_from        => 'lib/Perl/Dist/Strawberry/BuildPerl/5120.pm',
	create_readme            => 1,
	create_license           => 1,
	create_makefile_pl       => 'small',
	configure_requires       => {
        'Module::Build'      => '0.33',
	},
    requires => {
        'perl'                => '5.008001',	
#        'parent'              => '0.221',
#        'Exception::Class'    => '1.29',
    },
	build_requires => {
        'Test::More'          => '0.88',
	},
    meta_merge     => {
        resources => {
            homepage    => 'http://csjewell.comyr.com/perl/',
            bugtracker  => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Perl-Dist-Strawberry-BuildPerl-5120',
            repository  => 'http://bitbucket.org/csjewell/perl-dist-strawberry-buildperl-5120'
        },
    },
    add_to_cleanup      => [ 'Perl-Dist-Strawberry-BuildPerl-5120-*', ],
);

$builder->create_build_script();
