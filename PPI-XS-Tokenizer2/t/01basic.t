use strict;
use warnings;

use Test::More tests => 2;
BEGIN { use_ok('PPI::XS::Tokenizer') };

SCOPE: {
  my $t = PPI::XS::Tokenizer->new();
  isa_ok($t, 'PPI::XS::Tokenizer');
}



