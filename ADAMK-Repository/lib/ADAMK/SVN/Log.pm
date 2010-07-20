package ADAMK::SVN::Log;

use 5.008;
use strict;
use warnings;

use vars qw{$VERSION};
BEGIN {
	$VERSION = '0.12';
}

use Object::Tiny::XS qw{
	author
	date
	message
	revision
};

1;
