package Marpa::Internal::Tie;

use 5.010;
use warnings;
no warnings qw(qw);
use strict;
use integer;

# use Smart::Comments '-ENV';

### Using smart comments <where>...

use English qw( -no_match_vars );

use Marpa::Evaluator;
our @CARP_NOT = @Marpa::Internal::CARP_NOT;

## no critic (Subroutines::RequireArgUnpacking)

package Marpa::Internal::Tie::Location;

sub TIESCALAR {
   my ($class) = @_;
   my $instance; # not used for anything
   bless \$instance => $class;
}

sub FETCH {
    Marpa::exception('No context for location tie')
        if not my $context = $Marpa::Internal::CONTEXT;
    given ( $context->[0] ) {
        when ('setup and-node') {
            my $and_node = $context->[1];
            my $predecessor_id =
                $and_node->[Marpa::Internal::And_Node::PREDECESSOR_ID];
            return $and_node->[Marpa::Internal::And_Node::START_EARLEME]
                if not defined $predecessor_id;
            my $eval_instance = $Marpa::Internal::EVAL_INSTANCE;
            my $or_nodes = $eval_instance->[Marpa::Internal::Evaluator::OR_NODES];
            return $or_nodes->[$predecessor_id]
                ->[Marpa::Internal::Or_Node::START_EARLEME]
        } ## end when ('setup token')
        when ('rank and-node') {
            my $and_node = $context->[1];
            return $and_node->[Marpa::Internal::And_Node::START_EARLEME];
        }
        default {
            Marpa::exception(qq{Internal error: Unknown context type "$_" for location tie})
        }
    } ## end given
} ## end sub FETCH

sub STORE {
    Marpa::exception('Location tie is not writeable');
}

tie $Marpa::LOCATION, __PACKAGE__;

1;
