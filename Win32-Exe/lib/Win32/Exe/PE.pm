package Win32::Exe::PE;

use strict;
use base 'Win32::Exe';
use constant SUBFORMAT => (
    Machine	    => 'v',
    NumSections	    => 'v',
    TimeStamp	    => 'V',
    SymbolTable	    => 'V',
    _		    => 'a4',
    OptHeaderSize   => 'v',
    Characteristics => 'v',
    Data	    => 'a*',
);
use constant DISPATCH_FIELD => 'OptHeaderSize';
use constant DISPATCH_TABLE => (
    '0' => '',
    '*' => 'PE::Header',
);

our $VERSION = '0.11_01';
$VERSION =~ s/_//ms;

1;
