package FBP::TopLevelWindow;

use Mouse::Role;

our $VERSION = '0.34';

has title => (
	is  => 'ro',
	isa => 'Str',
);

has center => (
	is  => 'ro',
	isa => 'Str',
);

has OnActivate => (
	is  => 'ro',
	isa => 'Str',
);

has OnActivateApp => (
	is  => 'ro',
	isa => 'Str',
);

has OnClose => (
	is  => 'ro',
	isa => 'Str',
);

has OnHibernate => (
	is  => 'ro',
	isa => 'Str',
);

has OnIconize => (
	is  => 'ro',
	isa => 'Str',
);

has OnIdle => (
	is  => 'ro',
	isa => 'Str',
);

no Mouse::Role;
__PACKAGE__->meta->make_immutable;

1;
