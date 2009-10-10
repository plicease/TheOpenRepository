package Marpa::Evaluator;

use 5.010;
use warnings;
no warnings qw(recursion qw);
use strict;
use integer;

# The bocage is Marpa's structure for keeping multiple parses.
# A parse bocage is a list of or-nodes, whose child
# and-nodes must be (at most) binary.

# "Parse forests" are the structures used to keep multiple
# parses in many parsers, but Marpa
# can't use them because
# Marpa allows cyclical parses, and
# it breaks the RHS of productions into
# and-nodes of a most two symbols.
# And-nodes start in binary form
# in the Aycock-Horspool Earley items, and because
# binary and-nodes store the parses
# compactly, and allow easier tree
# traversals, I keep them that way.

# Bocage is a special type of forest,
# consisting of hedgerows deliberately cultivated
# as obstacles to cattle and armies.

# Saplings which become or-nodes when they grow up.

use Marpa::Offset qw(

    :package=Marpa::Internal::Or_Sapling

    NAME ITEM RULE
    POSITION CHILD_LHS_SYMBOL

);

use Marpa::Offset qw(

    :package=Marpa::Internal::And_Node

    TAG ID
    PREDECESSOR CAUSE
    TOKEN VALUE_REF
    EVALUATOR_DATA
    START_EARLEME END_EARLEME
    RULE_ID

    POSITION { Position in an and-node is not the same as
    position in a rule.  Rule positions are locations BETWEEN
    symbols, and start from 0 (before the first symbol).
    And-node positions are zero-based locations OF symbols.
    An and-node position of -1 means the and-node is for a
    rule with an empty RHS. }

    PARENT_ID
    PARENT_CHOICE
    DELETED
    CLASS { Equivalence class, for pruning duplicates }

    =LAST_GENERAL_EVALUATOR_FIELD

    SORT_ELEMENT

    =LAST_PER_METHOD_EVALUATOR_FIELD
    =LAST_FIELD

);

use Marpa::Offset qw(

    :package=Marpa::Internal::And_Iteration

    SORT_KEY
    OR_MAP
    CURRENT_CHILD

    =LAST_FIELD

);

use Marpa::Offset qw(

    :package=Marpa::Internal::Or_Node

    TAG ID CHILD_IDS
    START_EARLEME END_EARLEME
    PARENT_IDS
    DELETED
    CLASS { Equivalence class, for pruning duplicates }

    =LAST_GENERAL_EVALUATOR_FIELD
    =LAST_FIELD
);

use Marpa::Offset qw(

    :package=Marpa::Internal::Or_Iteration

    AND_CHOICE0
    AND_CHOICE1
    { And so on ... }

);

use Marpa::Offset qw(
    :package=Marpa::Internal::And_Choice
    ID
    SORT_KEY
    OR_MAP
    FROZEN_ITERATION
    =LAST_FIELD
);

use Marpa::Offset qw(

    :package=Marpa::Internal::Evaluator

    RECOGNIZER
    PARSE_COUNT :{ number of parses in an ambiguous parse :}
    AND_NODES
    OR_NODES
    RULE_DATA
    NULL_VALUES
    AND_ITERATIONS
    OR_ITERATIONS

);

use Marpa::Offset qw(

    :package=Marpa::Internal::Evaluator_Op
    ARGC
    CALL
    CONSTANT_RESULT
    VIRTUAL_HEAD
    VIRTUAL_HEAD_NO_SEP
    VIRTUAL_KERNEL
    VIRTUAL_TAIL

);

use Marpa::Offset qw(

    :package=Marpa::Internal::Evaluator_Rule
    CODE
    OPS

);

package Marpa::Internal::Evaluator;

use Smart::Comments '-ENV';

### Using smart comments <where>...

use Scalar::Util;
use List::Util;
use English qw( -no_match_vars );
use Data::Dumper;
use Storable;
use Marpa::Internal;
our @CARP_NOT = @Marpa::Internal::CARP_NOT;

# Perl critic at present is not smart about underscores
# in hex numbers
## no critic (ValuesAndExpressions::RequireNumberSeparators)
use constant N_FORMAT_MASK     => 0xffff_ffff;
use constant N_FORMAT_HIGH_BIT => 0x8000_0000;
## use critic
use constant N_FORMAT_WIDTH               => 4;
use constant NULL_SORT_ELEMENT_FILL_WIDTH => ( N_FORMAT_WIDTH * 2 );

# Also used as mask, so must be 2**n-1
# Perl critic at present is not smart about underscores
# in hex numbers
use constant N_FORMAT_MAX => 0x7fff_ffff;

sub set_null_values {
    my ($evaler) = @_;
    my $recce   = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar = $recce->[Marpa::Internal::Recognizer::GRAMMAR];

    my ( $rules, $symbols, $tracing, $default_null_value ) = @{$grammar}[
        Marpa::Internal::Grammar::RULES,
        Marpa::Internal::Grammar::SYMBOLS,
        Marpa::Internal::Grammar::TRACING,
        Marpa::Internal::Grammar::DEFAULT_NULL_VALUE,
    ];
    my $actions_package = $grammar->[Marpa::Internal::Grammar::ACTIONS];

    my $null_values;
    $#{$null_values} = $#{$symbols};

    my $trace_fh;
    my $trace_actions;
    if ($tracing) {
        $trace_fh = $grammar->[Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
        $trace_actions = $grammar->[Marpa::Internal::Grammar::TRACE_ACTIONS];
    }

    SYMBOL: for my $symbol ( @{$symbols} ) {
        my $id = $symbol->[Marpa::Internal::Symbol::ID];
        $null_values->[$id] = $default_null_value;
    }

    # Set null values specified in
    # empty rules.
    RULE: for my $rule ( @{$rules} ) {

        my $action = $rule->[Marpa::Internal::Rule::ACTION];

        # Set the null value of symbols from the action for their
        # empty rules
        my $rhs = $rule->[Marpa::Internal::Rule::RHS];

        # Empty rule with action?
        if ( defined $action and @{$rhs} <= 0 ) {

            my $closure = Marpa::Internal::Evaluator::resolve_semantics($evaler, $action);
            Marpa::exception(
                "Action closure '$action' not found")
                if not defined $closure;

            my $lhs            = $rule->[Marpa::Internal::Rule::LHS];
            my $nulling_symbol = $lhs->[Marpa::Internal::Symbol::NULL_ALIAS]
                // $lhs;

            my $null_value;

            my @warnings;
            my $eval_ok;
            DO_EVAL: {
                local $SIG{__WARN__} =
                    sub { push @warnings, [ $_[0], ( caller 0 ) ]; };
                $eval_ok = eval { $null_value = $closure->(); 1; };
            }

            if ( not $eval_ok or @warnings ) {
                my $fatal_error = $EVAL_ERROR;
                Marpa::Internal::code_problems(
                    {   eval_ok     => $eval_ok,
                        fatal_error => $fatal_error,
                        grammar     => $grammar,
                        warnings    => \@warnings,
                        where       => 'evaluating null value',
                        long_where  => 'evaluating null value for '
                            . $nulling_symbol
                            ->[Marpa::Internal::Symbol::NAME],
                    }
                );
            } ## end if ( not $eval_ok or @warnings )
            my $nulling_symbol_id =
                $nulling_symbol->[Marpa::Internal::Symbol::ID];
            $null_values->[$nulling_symbol_id] = $null_value;

            if ($trace_actions) {
                print {$trace_fh} 'Setting null value for symbol ',
                    $nulling_symbol->[Marpa::Internal::Symbol::NAME],
                    ' to ',
                    Data::Dumper->new( [ \$null_value ] )->Terse(1)->Dump,
                    "\n"
                    or Marpa::exception('Could not print to trace file');
            } ## end if ($trace_actions)

            next RULE;

        } ## end if ( defined $action and @{$rhs} <= 0 )

    }    # RULE

    if ($trace_actions) {
        SYMBOL: for my $symbol ( @{$symbols} ) {
            my ( $name, $id ) = @{$symbol}[
                Marpa::Internal::Symbol::NAME, Marpa::Internal::Symbol::ID,
            ];
            print {$trace_fh}
                'Setting null value for CHAF symbol ',
                $name, ' to ',
                Data::Dumper->new( [ $null_values->[$id] ] )->Terse(1)->Dump,
                or Marpa::exception('Could not print to trace file');
        } ## end for my $symbol ( @{$symbols} )
    } ## end if ($trace_actions)

    return $null_values;

}    # set_null_values

# Given the grammar and an action name, resolve it to a closure,
# or return undef
sub resolve_semantics {
    my ( $evaler, $closure_name ) = @_;
    my $recce   = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar = $recce->[Marpa::Internal::Recognizer::GRAMMAR];

    ### closure name: $closure_name
    return if not defined $closure_name;

    my $fully_qualified_name;
    DETERMINE_FULLY_QUALIFIED_NAME: {
        if ( $closure_name =~ /([:][:])|[']/xms ) {
            $fully_qualified_name = $closure_name;
            ### direct fully qualified name: $fully_qualified_name
            last DETERMINE_FULLY_QUALIFIED_NAME;
        }
        if (defined(
                my $actions_package =
                    $grammar->[Marpa::Internal::Grammar::ACTIONS]
            )
            )
        {
            $fully_qualified_name =
                $actions_package . q{::} . $closure_name;
            last DETERMINE_FULLY_QUALIFIED_NAME;
        } ## end if ( defined( my $actions_package = $grammar->[...]))

        if (defined(
                my $action_object =
                    $grammar->[Marpa::Internal::Grammar::ACTION_OBJECT]
            )
            )
        {
            $fully_qualified_name =
                $action_object . q{::} . $closure_name;
        } ## end if ( defined( my $action_object = $grammar->[...]))
    } ## end DETERMINE_FULLY_QUALIFIED_NAME:

    ### fully qualified name: $fully_qualified_name

    return if not defined $fully_qualified_name;

    no strict 'refs';
    my $closure = *{$fully_qualified_name}{CODE};
    use strict 'refs';

    if ( $grammar->[Marpa::Internal::Grammar::TRACE_ACTIONS] ) {
        my $trace_fh =
            $grammar->[Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
        print {$trace_fh} ( $closure ? 'Successful' : 'Failed' )
            . ' resolution of "$closure_name" ',
            ' to ', $fully_qualified_name, "\n"
            or Marpa::exception('Could not print to trace file');
    } ## end if ( $grammar->[Marpa::Internal::Grammar::TRACE_ACTION...])

    return $closure;

} ## end sub resolve_semantics

sub set_actions {
    my ($evaler) = @_;
    my $recce   = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar = $recce->[Marpa::Internal::Recognizer::GRAMMAR];

    my ( $rules, $tracing, $default_action, ) = @{$grammar}[
        Marpa::Internal::Grammar::RULES,
        Marpa::Internal::Grammar::TRACING,
        Marpa::Internal::Grammar::DEFAULT_ACTION,
    ];

    my $evaluator_rules = [];

    my $default_action_closure =
        Marpa::Internal::Evaluator::resolve_semantics( $evaler, $default_action );

    RULE: for my $rule ( @{$rules} ) {

        next RULE if not $rule->[Marpa::Internal::Rule::USEFUL];

        my $rule_id = $rule->[Marpa::Internal::Rule::ID];
        my $rule_data = $evaluator_rules->[$rule_id] = [];
        my $ops = $rule_data->[Marpa::Internal::Evaluator_Rule::OPS] = [];

        my $virtual_rhs = $rule->[Marpa::Internal::Rule::VIRTUAL_RHS];
        my $virtual_lhs = $rule->[Marpa::Internal::Rule::VIRTUAL_LHS];

        if ($virtual_lhs) {
            push @{$ops},
                (
                $virtual_rhs
                ? Marpa::Internal::Evaluator_Op::VIRTUAL_KERNEL
                : Marpa::Internal::Evaluator_Op::VIRTUAL_TAIL
                ),
                $rule->[Marpa::Internal::Rule::REAL_SYMBOL_COUNT];
            next RULE;
        } ## end if ($virtual_lhs)

        # If we are here the LHS is real, not virtual

        if ($virtual_rhs) {
            push @{$ops},
                (
                $rule->[Marpa::Internal::Rule::DISCARD_SEPARATION]
                ? Marpa::Internal::Evaluator_Op::VIRTUAL_HEAD_NO_SEP
                : Marpa::Internal::Evaluator_Op::VIRTUAL_HEAD
                ),
                $rule->[Marpa::Internal::Rule::REAL_SYMBOL_COUNT];

        } ## end if ($virtual_rhs)
            # assignment instead of comparison is deliberate
        elsif ( my $argc = scalar @{ $rule->[Marpa::Internal::Rule::RHS] } ) {
            push @{$ops}, Marpa::Internal::Evaluator_Op::ARGC, $argc;
        }

        my $action = $rule->[Marpa::Internal::Rule::ACTION]
            // $rule->[Marpa::Internal::Rule::LHS]
            ->[Marpa::Internal::Symbol::NAME];
        my $closure = Marpa::Internal::Evaluator::resolve_semantics(
                    $evaler, $action);
        $closure //= $default_action_closure;
        if (defined $closure) {
            $rule_data->[Marpa::Internal::Evaluator_Rule::CODE] =
                "$action->()";
            push @{$ops}, Marpa::Internal::Evaluator_Op::CALL, $closure;
            next RULE;
        } ## end if ( defined( my $closure = ...))

        # If there is no default action specified, the fallback
        # is to return an undef
        $rule_data->[Marpa::Internal::Evaluator_Rule::CODE] =
            'default to undef';
        push @{$ops},
            Marpa::Internal::Evaluator_Op::CONSTANT_RESULT,
            \undef;
        next RULE;

    } ## end for my $rule ( @{$rules} )

    return $evaluator_rules;

}    # set_actions

sub audit_or_node {
    my ( $evaler, $or_node ) = @_;
    my $or_nodes  = $evaler->[Marpa::Internal::Evaluator::OR_NODES];
    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];

    my $id = $or_node->[Marpa::Internal::Or_Node::ID];

    if ( not defined $id ) {
        Marpa::exception('ID not defined in or-node');
    }
    my $or_nodes_entry = $or_nodes->[$id];
    if ( $or_node != $or_nodes_entry ) {
        Marpa::exception("or_node #$id does not match its or-nodes entry");
    }
    if ( $#{$or_node} != Marpa::Internal::Or_Node::LAST_FIELD ) {
        Marpa::exception(
            "Bad field count in or-node #$id: want ",
            Marpa::Internal::Or_Node::LAST_FIELD,
            ', got ', $#{$or_node}
        );
    } ## end if ( $#{$or_node} != Marpa::Internal::Or_Node::LAST_FIELD)

    my $deleted = $or_node->[Marpa::Internal::Or_Node::DELETED];

    my $parent_ids = $or_node->[Marpa::Internal::Or_Node::PARENT_IDS];

    # No parents for top or-node, or-node 0
    if ( $id != 0 ) {
        my $has_parents = ( defined $parent_ids and scalar @{$parent_ids} );
        if ( not $deleted and not $has_parents ) {
            Marpa::exception("or-node #$id has no parents");
        }
        if ( $deleted and $has_parents ) {
            Marpa::exception("Deleted or-node #$id has parents");
        }
    } ## end if ( $id != 0 )

    {
        my %parent_id_seen;
        PARENT_ID: for my $parent_id ( @{$parent_ids} ) {
            next PARENT_ID if not $parent_id_seen{$parent_id}++;
            Marpa::exception(
                "or-node #$id has duplicate parent, #$parent_id");
        }
    }

    PARENT_ID: for my $parent_id ( @{$parent_ids} ) {
        my $parent = $and_nodes->[$parent_id];
        my $cause  = $parent->[Marpa::Internal::And_Node::CAUSE];
        next PARENT_ID if defined $cause and $or_node == $cause;

        my $predecessor = $parent->[Marpa::Internal::And_Node::PREDECESSOR];
        next PARENT_ID if defined $predecessor and $or_node == $predecessor;

        Marpa::exception(
            "or_node #$id is not the cause or predecessor of parent and-node #$parent_id"
        );

    } ## end for my $parent_id ( @{$parent_ids} )

    my $child_ids = $or_node->[Marpa::Internal::Or_Node::CHILD_IDS];
    my $has_children = ( defined $child_ids and scalar @{$child_ids} );
    if ( not $deleted and not $has_children ) {
        Marpa::exception("or-node #$id has no children");
    }
    if ( $deleted and $has_children ) {
        Marpa::exception("Deleted or-node #$id has children");
    }

    {
        my %child_id_seen;
        CHILD_ID: for my $child_id ( @{$child_ids} ) {
            next CHILD_ID if not $child_id_seen{$child_id}++;
            Marpa::exception("or-node #$id has duplicate child, #$child_id");
        }
    }

    for my $child_id ( @{$child_ids} ) {
        my $child        = $and_nodes->[$child_id];
        my $child_parent = $child->[Marpa::Internal::And_Node::PARENT_ID];
        if ( not defined $child_parent or $id != $child_parent ) {
            Marpa::exception(
                "or_node #$id is not the parent of child and-node #$child_id"
            );
        }
    } ## end for my $child_id ( @{$child_ids} )

    return;
} ## end sub audit_or_node

sub audit_and_node {
    my ( $evaler, $audit_and_node ) = @_;
    my $or_nodes  = $evaler->[Marpa::Internal::Evaluator::OR_NODES];
    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];

    my $audit_and_node_id = $audit_and_node->[Marpa::Internal::And_Node::ID];

    if ( not defined $audit_and_node_id ) {
        Marpa::exception('ID not defined in and-node');
    }
    my $and_nodes_entry = $and_nodes->[$audit_and_node_id];
    if ( $audit_and_node != $and_nodes_entry ) {
        Marpa::exception(
            "and_node #$audit_and_node_id does not match its and-nodes entry"
        );
    }
    if ( $#{$audit_and_node} != Marpa::Internal::And_Node::LAST_FIELD ) {
        Marpa::exception(
            "Bad field count in and-node #$audit_and_node_id: want ",
            Marpa::Internal::And_Node::LAST_FIELD,
            ', got ', $#{$audit_and_node}
        );
    } ## end if ( $#{$audit_and_node} != ...)

    my $deleted = $audit_and_node->[Marpa::Internal::And_Node::DELETED];

    my $parent_id = $audit_and_node->[Marpa::Internal::And_Node::PARENT_ID];
    my $parent_choice =
        $audit_and_node->[Marpa::Internal::And_Node::PARENT_CHOICE];
    if ( not $deleted ) {
        my $parent_or_node = $or_nodes->[$parent_id];
        my $parent_idea_of_child_id =
            $parent_or_node->[Marpa::Internal::Or_Node::CHILD_IDS]
            ->[$parent_choice];
        if ( $audit_and_node_id != $parent_idea_of_child_id ) {
            Marpa::exception(
                "and_node #$audit_and_node_id does not match its CHILD_IDS entry in its parent"
            );
        }
    } ## end if ( not $deleted )
    else {
        if ( defined $parent_id ) {
            Marpa::exception(
                "deleted and_node $audit_and_node_id has defined PARENT_ID: #$parent_id"
            );
        }
        if ( defined $parent_choice ) {
            Marpa::exception(
                "deleted and_node $audit_and_node_id has defined PARENT_CHOICE: #$parent_choice"
            );
        }
    } ## end else [ if ( not $deleted ) ]

    FIELD:
    for my $field (
        Marpa::Internal::And_Node::PREDECESSOR,
        Marpa::Internal::And_Node::CAUSE,
        )
    {
        my $child_or_node = $audit_and_node->[$field];
        next FIELD if not defined $child_or_node;
        my $child_or_node_id = $child_or_node->[Marpa::Internal::Or_Node::ID];
        if ( $deleted and defined $child_or_node_id ) {
            Marpa::exception(
                "deleted and-node $audit_and_node_id has defined child: #$parent_id"
            );
        }
        my $child_idea_of_parent_ids =
            $child_or_node->[Marpa::Internal::Or_Node::PARENT_IDS];
        if ( $deleted and scalar @{$child_idea_of_parent_ids} ) {
            Marpa::exception(
                "deleted and-node $audit_and_node_id has parents: ",
                ( join q{, }, @{$child_idea_of_parent_ids} )
            );
        } ## end if ( $deleted and scalar @{$child_idea_of_parent_ids...})
        next FIELD if $deleted;
        my $audit_and_node_index = List::Util::first {
            $child_idea_of_parent_ids->[$_] == $audit_and_node_id;
        }
        ( 0 .. $#{$child_idea_of_parent_ids} );
        if ( not defined $audit_and_node_index ) {
            Marpa::exception(
                "child of and-node (or-node $child_or_node_id) does not have and-node $audit_and_node_id as parent"
            );
        }

    } ## end for my $field ( Marpa::Internal::And_Node::PREDECESSOR...)

    return;
} ## end sub audit_and_node

sub Marpa::Evaluator::audit {
    my ($evaler) = @_;
    my $or_nodes = $evaler->[Marpa::Internal::Evaluator::OR_NODES];
    for my $or_node ( @{$or_nodes} ) {
        audit_or_node( $evaler, $or_node );
    }
    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];
    for my $and_node ( @{$and_nodes} ) {
        audit_and_node( $evaler, $and_node );
    }

    ### Bocage passed audit ...

    return;
} ## end sub Marpa::Evaluator::audit

# Internal routine to clone an and-node
sub clone_and_node {
    my ( $evaler, $and_node ) = @_;
    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];
    my $new_and_node;
    $#{$new_and_node} = Marpa::Internal::And_Node::LAST_FIELD;
    my $new_and_node_id = $new_and_node->[Marpa::Internal::And_Node::ID] =
        scalar @{$and_nodes};

    push @{$and_nodes}, $new_and_node;

    for my $field (
        Marpa::Internal::And_Node::TAG,
        Marpa::Internal::And_Node::VALUE_REF,
        Marpa::Internal::And_Node::TOKEN,
        Marpa::Internal::And_Node::EVALUATOR_DATA,
        Marpa::Internal::And_Node::START_EARLEME,
        Marpa::Internal::And_Node::END_EARLEME,
        Marpa::Internal::And_Node::RULE_ID,
        Marpa::Internal::And_Node::POSITION,
        )
    {
        $new_and_node->[$field] = $and_node->[$field];
    } ## end for my $field ( Marpa::Internal::And_Node::TAG, ...)
    $new_and_node->[Marpa::Internal::And_Node::TAG] =~ s{
        [a] \d* \z
    }{a$new_and_node_id}xms;

    return $new_and_node;
} ## end sub clone_and_node

# Returns the number of nodes actually deleted
sub delete_nodes {
    my ( $evaler, $delete_work_list ) = @_;

    # Should be deletion-consistent at this point
    ### assert: Marpa'Evaluator'audit($evaler) or 1

    my $deleted_count = 0;

    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];
    my $or_nodes  = $evaler->[Marpa::Internal::Evaluator::OR_NODES];
    DELETE_WORK_ITEM:
    while ( my $delete_work_item = pop @{$delete_work_list} ) {
        my ( $node_type, $delete_node_id ) = @{$delete_work_item};

        if ( $node_type eq 'a' ) {

            my $delete_and_node = $and_nodes->[$delete_node_id];

            next DELETE_WORK_ITEM
                if $delete_and_node->[Marpa::Internal::And_Node::DELETED];

            my $parent_id =
                $delete_and_node->[Marpa::Internal::And_Node::PARENT_ID];
            my $parent_or_node = $or_nodes->[$parent_id];

            if ( not $parent_or_node->[Marpa::Internal::Or_Node::DELETED] ) {
                push @{$delete_work_list}, [ 'o', $parent_id ];
                my $parent_choice = $delete_and_node
                    ->[Marpa::Internal::And_Node::PARENT_CHOICE];

                my $parent_child_ids =
                    $parent_or_node->[Marpa::Internal::Or_Node::CHILD_IDS];

                splice @{$parent_child_ids}, $parent_choice, 1;

                # Eliminating one of the choices means all subsequent ones
                # are renumbered -- adjust accordingly.
                for my $choice ( $parent_choice .. $#{$parent_child_ids} ) {
                    my $sibling_and_node_id = $parent_child_ids->[$choice];
                    my $sibling_and_node = $and_nodes->[$sibling_and_node_id];
                    $sibling_and_node
                        ->[Marpa::Internal::And_Node::PARENT_CHOICE] =
                        $choice;

                } ## end for my $choice ( $parent_choice .. $#{...})

            } ## end if ( not $parent_or_node->[...])

            FIELD:
            for my $field (
                Marpa::Internal::And_Node::PREDECESSOR,
                Marpa::Internal::And_Node::CAUSE,
                )
            {
                my $child_or_node = $delete_and_node->[$field];
                next FIELD if not defined $child_or_node;
                next FIELD
                    if $child_or_node->[Marpa::Internal::Or_Node::DELETED];
                my $id = $child_or_node->[Marpa::Internal::Or_Node::ID];

                push @{$delete_work_list}, [ 'o', $id ];

                # Splice out the reference to this or-node in the PARENT_IDS
                # field of the or-node child
                my $parent_ids =
                    $child_or_node->[Marpa::Internal::Or_Node::PARENT_IDS];

                my $delete_node_index =
                    List::Util::first { $parent_ids->[$_] == $delete_node_id }
                ( 0 .. $#{$parent_ids} );

                splice @{$parent_ids}, $delete_node_index, 1;
            }    # FIELD

            FIELD:
            for my $field (
                Marpa::Internal::And_Node::PARENT_ID,
                Marpa::Internal::And_Node::PARENT_CHOICE,
                Marpa::Internal::And_Node::CAUSE,
                Marpa::Internal::And_Node::PREDECESSOR,
                Marpa::Internal::And_Node::VALUE_REF,
                Marpa::Internal::And_Node::TOKEN,
                Marpa::Internal::And_Node::CLASS,
                )
            {
                $delete_and_node->[$field] = undef;
            } ## end for my $field ( Marpa::Internal::And_Node::PARENT_ID,...)

            $delete_and_node->[Marpa::Internal::And_Node::DELETED] = 1;
            $deleted_count++;

            next DELETE_WORK_ITEM;
        } ## end if ( $node_type eq 'a' )

        if ( $node_type eq 'o' ) {

            my $or_node = $or_nodes->[$delete_node_id];
            next DELETE_WORK_ITEM
                if $or_node->[Marpa::Internal::Or_Node::DELETED];
            my $parent_ids = $or_node->[Marpa::Internal::Or_Node::PARENT_IDS];
            my $child_ids  = $or_node->[Marpa::Internal::Or_Node::CHILD_IDS];

            # Do not delete unless no children, or no parents and not the
            # start or-node.
            # Start or-node is always ID 0.

            next DELETE_WORK_ITEM
                if ( scalar @{$parent_ids} or $delete_node_id == 0 )
                and scalar @{$child_ids};

            $or_node->[Marpa::Internal::Or_Node::DELETED] = 1;
            $deleted_count++;

            push @{$delete_work_list},
                map { [ 'a', $_ ] } @{$parent_ids}, @{$child_ids};
            for my $field (
                Marpa::Internal::Or_Node::PARENT_IDS,
                Marpa::Internal::Or_Node::CHILD_IDS,
                )
            {
                $or_node->[$field] = [];
            } ## end for my $field ( Marpa::Internal::Or_Node::PARENT_IDS,...)
            $or_node->[Marpa::Internal::Or_Node::CLASS] = undef;

            next DELETE_WORK_ITEM;
        } ## end if ( $node_type eq 'o' )

        Marpa::exception("Unknown delete-work-list node-type: $node_type");
    } ## end while ( my $delete_work_item = pop @{$delete_work_list})
    return $deleted_count;
} ## end sub delete_nodes

## no critic (ControlStructures::ProhibitDeepNests)

# Rewrite to eliminate cycles.
sub rewrite_cycles {
    my ($evaler) = @_;

    my $or_nodes  = $evaler->[Marpa::Internal::Evaluator::OR_NODES];
    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];

    my $trace_fh;
    my $trace_evaluation;

    my $recce   = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar = $recce->[Marpa::Internal::Recognizer::GRAMMAR];
    my $warn_on_cycle =
        $grammar->[Marpa::Internal::Grammar::CYCLE_ACTION] ne 'quiet';
    my $tracing = $warn_on_cycle
        || $grammar->[Marpa::Internal::Grammar::TRACING];
    if ($tracing) {
        $trace_fh = $grammar->[Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
        $trace_evaluation =
            $grammar->[Marpa::Internal::Grammar::TRACE_EVALUATION];
    }

    # Group or-nodes by span.  Only or-nodes with the same
    # span can be in a cycle.
    my %or_nodes_by_span;
    for my $or_node ( @{$or_nodes} ) {
        push @{
            $or_nodes_by_span{
                join q{,},
                @{$or_node}[
                    Marpa::Internal::Or_Node::START_EARLEME,
                Marpa::Internal::Or_Node::END_EARLEME
                ]
                }
            },
            $or_node;
    } ## end for my $or_node ( @{$or_nodes} )

    # Initialize the span sets
    my @span_sets = values %or_nodes_by_span;

    SPAN_SET: while ( my $span_set = pop @span_sets ) {
        @{$span_set} =
            grep { not $_->[Marpa::Internal::Or_Node::DELETED] } @{$span_set};
        next SPAN_SET if not @{$span_set};

        my %in_span_set = ();
        for my $or_node_ix ( 0 .. $#{$span_set} ) {
            my $or_node_id =
                $span_set->[$or_node_ix]->[Marpa::Internal::Or_Node::ID];

            $in_span_set{$or_node_id} = $or_node_ix;
        } ## end for my $or_node_ix ( 0 .. $#{$span_set} )

        # Set up matrix of or-node to or-node transitions.
        my @transition;
        my @work_list;
        for my $or_parent_ix ( 0 .. $#{$span_set} ) {
            my @or_child_ixes =
                grep { defined $_ }
                map  { $in_span_set{ $_->[Marpa::Internal::Or_Node::ID] } }
                grep { defined $_ }
                map {
                @{$_}[
                    Marpa::Internal::And_Node::CAUSE,
                    Marpa::Internal::And_Node::PREDECESSOR
                    ]
                } @{$and_nodes}[
                @{ $span_set->[$or_parent_ix]
                        ->[Marpa::Internal::Or_Node::CHILD_IDS] }
                ];
            for my $or_child_ix (@or_child_ixes) {
                $transition[$or_parent_ix][$or_child_ix]++;
                push @work_list, [ $or_parent_ix, $or_child_ix ];
            }
        } ## end for my $or_parent_ix ( 0 .. $#{$span_set} )

        # Compute transitive closure of matrix of or-node transitions.
        while ( my $work_item = pop @work_list ) {
            my ( $parent_ix, $child_ix ) = @{$work_item};
            GRAND_CHILD:
            for my $grandchild_ix ( grep { $transition[$child_ix][$_] }
                ( 0 .. $#{$span_set} ) )
            {
                my $transition_row = $transition[$parent_ix];
                next GRAND_CHILD if $transition_row->[$grandchild_ix];
                $transition_row->[$grandchild_ix]++;
                push @work_list, [ $parent_ix, $grandchild_ix ];
            } ## end for my $grandchild_ix ( grep { $transition[$child_ix]...})
        } ## end while ( my $work_item = pop @work_list )

        # Use the transitions to find the cycles in the span set
        my @cycle;
        {
            my $span_set_index =
                List::Util::first { $transition[$_][$_] }
            ( 0 .. $#{$span_set} );
            next SPAN_SET if not defined $span_set_index;
            @cycle = map { $span_set->[$_] } (
                $span_set_index,
                grep {
                            $transition[$span_set_index][$_]
                        and $transition[$_][$span_set_index]
                    } ( $span_set_index + 1 .. $#{$span_set} )
            );
        }

        if ($trace_evaluation) {
            say {$trace_fh} 'Found cycle of length ', ( scalar @cycle );
            for my $ix ( 0 .. $#cycle ) {
                my $or_node = $cycle[$ix];
                print {$trace_fh} "Node $ix in cycle: ",
                    Marpa::Evaluator::show_or_node( $evaler, $or_node,
                    $trace_evaluation )
                    or Marpa::exception('print to trace handle failed');
            } ## end for my $ix ( 0 .. $#cycle )
        } ## end if ($trace_evaluation)

        # If we found any cycles in the span set, put the
        # whole span set back
        # on the work list for another pass
        push @span_sets, $span_set;

        # determine which in the original cycle set are
        # internal and-nodes
        my %internal_and_nodes = ();
        for my $or_node (@cycle) {
            for my $and_node_id (
                @{ $or_node->[Marpa::Internal::Or_Node::CHILD_IDS] } )
            {
                $internal_and_nodes{$and_node_id} = 1;
            }
        } ## end for my $or_node (@cycle)

        # determine which in the original span set are the
        # root or-nodes
        my @root_or_nodes = grep {
            defined List::Util::first { not defined $internal_and_nodes{$_} }
            @{ $_->[Marpa::Internal::Or_Node::PARENT_IDS] }
        } @cycle;

        ## deletion-consistent at this point
        ### assert: Marpa'Evaluator'audit($evaler) or 1

        my @delete_work_list = ();

        ## now make the copies
        for my $copy ( 1 .. $#root_or_nodes ) {

            my $original_root_or_node = $root_or_nodes[$copy];
            my $original_root_or_node_id =
                $original_root_or_node->[Marpa::Internal::Or_Node::ID];

            # Copy non-link dependent fields
            # Make translation tables
            # Create interior and-node to or-node links
            my %translate_or_node_id;
            my %translate_and_node_id;

            # store our new cycle set here, so we can add it
            # to the span set work list
            my @copied_cycle;

            # Copy the or- and and-nodes and build the translation
            # tables.
            for my $or_node (@cycle) {
                my $new_or_node;
                $#{$new_or_node} = Marpa::Internal::Or_Node::LAST_FIELD;
                for my $field (
                    Marpa::Internal::Or_Node::START_EARLEME,
                    Marpa::Internal::Or_Node::END_EARLEME,
                    Marpa::Internal::Or_Node::TAG,
                    )
                {
                    $new_or_node->[$field] = $or_node->[$field];
                } ## end for my $field ( ...)

                my $new_or_node_id = @{$or_nodes};

                $new_or_node->[Marpa::Internal::Or_Node::TAG] =~ s{
                        [o] \d* \z
                    }{o$new_or_node_id}xms;

                $new_or_node->[Marpa::Internal::Or_Node::ID] =
                    $new_or_node_id;
                push @{$or_nodes}, $new_or_node;
                push @copied_cycle, $new_or_node;
                $translate_or_node_id{ $or_node
                        ->[Marpa::Internal::Or_Node::ID] } = $new_or_node_id;

                my $child_ids =
                    $or_node->[Marpa::Internal::Or_Node::CHILD_IDS];
                for my $choice ( 0 .. $#{$child_ids} ) {
                    my $and_node_id  = $child_ids->[$choice];
                    my $and_node     = $and_nodes->[$and_node_id];
                    my $new_and_node = clone_and_node( $evaler, $and_node );
                    my $new_and_node_id =
                        $new_and_node->[Marpa::Internal::And_Node::ID];
                    push @{$and_nodes}, $new_and_node;
                    $translate_and_node_id{$and_node_id} = $new_and_node_id;

                    $new_or_node->[Marpa::Internal::Or_Node::CHILD_IDS]
                        ->[$choice] = $new_and_node_id;
                    $new_and_node->[Marpa::Internal::And_Node::PARENT_ID] =
                        $new_or_node_id;
                    $new_and_node->[Marpa::Internal::And_Node::PARENT_CHOICE]
                        = $choice;
                } ## end for my $choice ( 0 .. $#{$child_ids} )

            } ## end for my $or_node (@cycle)

            # Translate the cycle-internal links
            # and duplicate the outgoing external links (which
            # will be from the and-nodes)

            for my $original_or_node (@cycle) {

                my $original_or_node_id =
                    $original_or_node->[Marpa::Internal::Or_Node::ID];
                my $new_or_node_id =
                    $translate_or_node_id{$original_or_node_id};
                my $new_or_node = $or_nodes->[$new_or_node_id];

                # This throws away all external links to the or-nodes,
                # for the moment.  Below, I'll re-add the ones for the
                # root node.
                $new_or_node->[Marpa::Internal::Or_Node::PARENT_IDS] = [
                    grep    { defined $_ }
                        map { $translate_and_node_id{$_} } @{
                        $original_or_node
                            ->[Marpa::Internal::Or_Node::PARENT_IDS]
                        }
                ];

                for my $original_and_node_id (
                    @{  $original_or_node
                            ->[Marpa::Internal::Or_Node::CHILD_IDS]
                    }
                    )
                {
                    my $original_and_node =
                        $and_nodes->[$original_and_node_id];
                    my $new_and_node_id =
                        $translate_and_node_id{$original_and_node_id};
                    my $new_and_node = $and_nodes->[$new_and_node_id];

                    FIELD:
                    for my $field (
                        Marpa::Internal::And_Node::CAUSE,
                        Marpa::Internal::And_Node::PREDECESSOR
                        )
                    {
                        my $original_or_child = $original_and_node->[$field];
                        next FIELD if not defined $original_or_child;
                        my $original_or_child_id = $original_or_child
                            ->[Marpa::Internal::Or_Node::ID];
                        my $new_or_child_id =
                            $translate_or_node_id{$original_or_child_id};

                        my $new_or_child;
                        if ( defined $new_or_child_id ) {

                            $new_or_child = $or_nodes->[$new_or_child_id];
                            $new_and_node->[$field] = $new_or_child;

                            next FIELD;

                        } ## end if ( defined $new_or_child_id )

                        # If here, the or-child is external.

                        $new_or_child = $new_and_node->[$field] =
                            $original_or_child;

                        # Since the or-child is external,
                        # we need to duplicate the link.
                        push @{ $new_or_child
                                ->[Marpa::Internal::Or_Node::PARENT_IDS] },
                            $new_and_node_id;

                    } ## end for my $field ( Marpa::Internal::And_Node::CAUSE, ...)
                } ## end for my $original_and_node_id ( @{ $original_or_node...})

            } ## end for my $original_or_node (@cycle)

            # It remains now to duplicate the external links to the cycle
            # and to mark internal links to the root node for deletion.
            # External links are allowed only to the root node of the cycle.

            my $new_root_or_node_id =
                $translate_or_node_id{ $original_root_or_node
                    ->[Marpa::Internal::Or_Node::ID] };

            my $new_root_or_node = $or_nodes->[$new_root_or_node_id];

            PARENT_AND_NODE:
            for my $original_parent_and_node_id (
                @{  $original_root_or_node
                        ->[Marpa::Internal::Or_Node::PARENT_IDS]
                }
                )
            {

                # Internal nodes need to be put on the list to be deleted
                if (defined(
                        my $new_parent_and_node_id =
                            $translate_and_node_id{
                            $original_parent_and_node_id}
                    )
                    )
                {
                    push @delete_work_list, [ 'a', $new_parent_and_node_id ];
                    next PARENT_AND_NODE;
                } ## end if ( defined( my $new_parent_and_node_id = ...))

                # If we are here, the parent node is cycle-external.

                # Clone the external parent node
                my $original_parent_and_node =
                    $and_nodes->[$original_parent_and_node_id];
                my $new_parent_and_node =
                    clone_and_node( $evaler, $original_parent_and_node );
                my $new_parent_and_node_id =
                    $new_parent_and_node->[Marpa::Internal::And_Node::ID];

                # Now tell the cloned and-node about its children, one
                # of which is the new root or-node
                FIELD:
                for my $field (
                    Marpa::Internal::And_Node::CAUSE,
                    Marpa::Internal::And_Node::PREDECESSOR
                    )
                {
                    my $original_root_or_node_sibling =
                        $original_parent_and_node->[$field];
                    next FIELD if not defined $original_root_or_node_sibling;

                    # If this field was the root or node in the old
                    # parent and-node, make it the case that the
                    # new root or-node is this same field in the
                    # new parent and-node.
                    # Uses a referent address comparison.
                    my $new_root_or_node_sibling;
                    if ( $original_root_or_node_sibling
                        == $original_root_or_node )
                    {
                        $new_root_or_node_sibling =
                            $new_parent_and_node->[$field] =
                            $new_root_or_node;

                    } ## end if ( $original_root_or_node_sibling == ...)
                    else {
                        $new_root_or_node_sibling =
                            $new_parent_and_node->[$field] =
                            $original_root_or_node_sibling;
                    }

                    push @{ $new_root_or_node_sibling
                            ->[Marpa::Internal::Or_Node::PARENT_IDS] },
                        $new_parent_and_node_id;

                    # We assume that a field is either
                    # a clone of the root, or cycle-external.
                    # We can do this because:
                    #
                    #   1. All or-nodes in a cycle must have the same
                    #      span.
                    #   2. For both children of an and-node to have
                    #      the same span, both must have a zero-width
                    #      span.
                    #   3. If more than one zero-width span occurred
                    #      in an and-node,
                    #      the parent or-node and and-node would have
                    #      zero-width as well.
                    #   4. Zero-width and-nodes do not have children,
                    #      because of Marpa's assignment of constant
                    #      "null values" to null symbols.
                } ## end for my $field ( Marpa::Internal::And_Node::CAUSE, ...)

                # Tell the parent of the newly cloned and-node
                # about its new child
                my $grandparent_or_node_id = $original_parent_and_node
                    ->[Marpa::Internal::And_Node::PARENT_ID];
                my $grandparent_or_node =
                    $or_nodes->[$grandparent_or_node_id];
                my $child_ids_of_grandparent = $grandparent_or_node
                    ->[Marpa::Internal::Or_Node::CHILD_IDS];
                my $choice = @{$child_ids_of_grandparent};
                push @{$child_ids_of_grandparent}, $new_parent_and_node_id;

                # Tell the new cloned and-node about its parent
                $new_parent_and_node->[Marpa::Internal::And_Node::PARENT_ID] =
                    $grandparent_or_node_id;
                $new_parent_and_node
                    ->[Marpa::Internal::And_Node::PARENT_CHOICE] = $choice;

            } ## end for my $original_parent_and_node_id ( @{ ...})

            push @span_sets, \@copied_cycle;

            # Should be deletion-consistent at this point
            ### assert: Marpa'Evaluator'audit($evaler) or 1

        } ## end for my $copy ( 1 .. $#root_or_nodes )

        ## DELETE non-root external link on original
        ## DELETE root internal links on original
        my $original_root_or_node = $root_or_nodes[0];
        for my $original_or_node (@cycle) {
            my $is_root = $original_or_node == $original_root_or_node;
            PARENT_AND_NODE:
            for my $original_parent_and_node_id (
                @{ $original_or_node->[Marpa::Internal::Or_Node::PARENT_IDS] }
                )
            {

                next PARENT_AND_NODE
                    if $is_root
                        xor $internal_and_nodes{$original_parent_and_node_id};

                push @delete_work_list, [ 'a', $original_parent_and_node_id ];
            } ## end for my $original_parent_and_node_id ( @{ ...})
        } ## end for my $original_or_node (@cycle)

        # we should be deletion-consistent at this point

        # Now actually do the deletions
        delete_nodes( $evaler, \@delete_work_list );

        # Should be deletion-consistent at this point
        ### assert: Marpa'Evaluator'audit($evaler) or 1

        # Have we deleted the top or-node?
        # If so, there will be no parses.
        if ( $or_nodes->[0]->[Marpa::Internal::Or_Node::DELETED] ) {
            if ($warn_on_cycle) {
                print {$trace_fh} "Cycles found, but no parses\n"
                    or Marpa::exception('print to trace handle failed');
            }
            return;
        } ## end if ( $or_nodes->[0]->[Marpa::Internal::Or_Node::DELETED...])

    } ## end while ( my $span_set = pop @span_sets )

    ### assert: Marpa'Evaluator'audit($evaler) or 1

    return;
} ## end sub rewrite_cycles

# Make sure and-nodes are unique.
sub delete_duplicate_nodes {

    my ($evaler) = @_;

    my $recce   = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar = $recce->[Marpa::Internal::Recognizer::GRAMMAR];

    my $tracing = $grammar->[Marpa::Internal::Grammar::TRACING];
    my $trace_fh;
    my $trace_evaluation;

    if ($tracing) {
        $trace_fh = $grammar->[Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
        $trace_evaluation =
            $grammar->[Marpa::Internal::Grammar::TRACE_EVALUATION];
    }

    my $or_nodes  = $evaler->[Marpa::Internal::Evaluator::OR_NODES];
    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];

    # Deleting nodes can change the equivalence classes (EC),
    # so we need multiple passes.
    # In practice two passes should suffice
    # in almost all cases.

    # Deleting nodes combines ECs; never splits them.
    # You can prove this by induction on the node levels,
    # where a level 0 node has no children,
    # and a level n+1 node has
    # children of level n or less.
    #
    # Level 0 nodes (always terminal and-nodes) will
    # always have the same signature regardless of node
    # deletions.  So if two level 0 nodes are in the same
    # EC before a set of deletions, they
    # will be after.
    #
    # Induction hypothesis: any two nodes of level n in
    # a common EC before a set of deletions, will be in
    # a common EC after the set of deletions.
    #
    # Two level n+1 or-nodes in the same EC:
    # The EC's of their children must have been
    # the same.
    # Since deletions are based on the EC of the
    # children on a per or-node basis, the same
    # deletions will be made in both level n+1
    # or-nodes.
    # And by the induction hypothesis, any node
    # in an EC with one of the children before
    # the set of deletions, also shares and EC
    # afterwards.
    # So the signature of the two level n+1
    # or-nodes will remain identical.
    #
    # Two level n+1 and-nodes:
    # If either child is deleted, the level
    # n+1 and-node is also deleted and becomes
    # irrelevant.
    # By the induction hypothesis, and following
    # the same argument as for level n+1 or-node
    # children, the signatures of the two level
    # n+1 and-nodes will remain the same, and
    # they will remain together in an EC.

    # Initialize the work list with the terminal and-nodes
    my @terminal_nodes =
        grep {
                not $_->[Marpa::Internal::And_Node::DELETED]
            and not $_->[Marpa::Internal::And_Node::PREDECESSOR]
            and not $_->[Marpa::Internal::And_Node::CAUSE]
        } @{$and_nodes};

    DELETE_DUPLICATE_PASS: while (1) {

        # Initialize the work list
        my @work_list =
            map { [ 'a', $_->[Marpa::Internal::And_Node::ID] ] }
            @terminal_nodes;

        my %and_class_signature;
        my %or_class_signature;
        my %full_signature;
        my @delete_work_list = ();

        WORK_LIST_ENTRY: while ( my $work_list_entry = pop @work_list ) {

            my ( $node_type, $node_id ) = @{$work_list_entry};

            if ( $node_type eq 'a' ) {
                my $and_node = $and_nodes->[$node_id];

                next WORK_LIST_ENTRY
                    if $and_node->[Marpa::Internal::And_Node::DELETED]
                        or
                        defined $and_node->[Marpa::Internal::And_Node::CLASS];

                # No check whether there is already a class -- an undeleted
                # and-node with a class will not be on the work list.

                my @classes;
                FIELD:
                for my $field ( Marpa::Internal::And_Node::CAUSE,
                    Marpa::Internal::And_Node::PREDECESSOR
                    )
                {
                    my $or_child = $and_node->[$field];
                    my $class =
                        defined $or_child
                        ? $or_child->[Marpa::Internal::Or_Node::CLASS]
                        : -1;

                    # If we don't have an equivalence class for a child,
                    # nothing we can do.
                    next WORK_LIST_ENTRY if not defined $class;

                    push @classes, $class;

                } ## end for my $field ( Marpa::Internal::And_Node::CAUSE, ...)

                my $and_class_signature = join q{,},
                    $and_node->[Marpa::Internal::And_Node::RULE_ID] + 0,
                    $and_node->[Marpa::Internal::And_Node::POSITION] + 0,
                    $and_node->[Marpa::Internal::And_Node::START_EARLEME] + 0,
                    $and_node->[Marpa::Internal::And_Node::END_EARLEME] + 0,
                    @classes,
                    ( $and_node->[Marpa::Internal::And_Node::VALUE_REF] // 0 )
                    + 0,
                    ;

                my $parent_id =
                    $and_node->[Marpa::Internal::And_Node::PARENT_ID];

                push @work_list, [ 'o', $parent_id ];

                my $class = $and_class_signature{$and_class_signature};
                if ( not defined $class ) {
                    $class = $and_class_signature{$and_class_signature} =
                        $node_id;
                }
                $and_node->[Marpa::Internal::And_Node::CLASS] = $class;

                if ( $full_signature{"$parent_id,$and_class_signature"}++ ) {

                    if ($trace_evaluation) {
                        print {$trace_fh} "Deleting duplicate and-node:\n",
                            $and_node->[Marpa::Internal::And_Node::TAG], "\n"
                            or
                            Marpa::exception('print to trace handle failed');
                    } ## end if ($trace_evaluation)

                    push @delete_work_list, [ 'a', $node_id ];

                    next WORK_LIST_ENTRY;

                } ## end if ( $full_signature{...})

                next WORK_LIST_ENTRY;

            } ## end if ( $node_type eq 'a' )

            if ( $node_type eq 'o' ) {
                my $or_node = $or_nodes->[$node_id];

                next WORK_LIST_ENTRY
                    if $or_node->[Marpa::Internal::Or_Node::DELETED]
                        or
                        defined $or_node->[Marpa::Internal::Or_Node::CLASS];

                my @classes = map {
                    $and_nodes->[$_]->[Marpa::Internal::And_Node::CLASS]
                } @{ $or_node->[Marpa::Internal::Or_Node::CHILD_IDS] };

                # If one of the classes is undefined, nothing we can do
                next WORK_LIST_ENTRY
                    if grep { not defined $_ } @classes;

                my $or_class_signature = join q{,}, ( sort @classes );
                my $class = $or_class_signature{$or_class_signature};
                if ( not defined $class ) {
                    $class = $or_class_signature{$or_class_signature} =
                        $node_id;
                }
                $or_node->[Marpa::Internal::Or_Node::CLASS] = $class;

                push @work_list,
                    map { [ 'a', $_ ] }
                    @{ $or_node->[Marpa::Internal::Or_Node::PARENT_IDS] };

                next WORK_LIST_ENTRY;

            } ## end if ( $node_type eq 'o' )

            Marpa::exception("Internal error, unknown node type: $node_type");

        } ## end while ( my $work_list_entry = pop @work_list )

        # If no nodes are deleted, we are finished
        last DELETE_DUPLICATE_PASS
            if not scalar @delete_work_list
                or delete_nodes( $evaler, \@delete_work_list ) <= 0;

        # Remove any deleted nodes from the terminal nodes
        # before looping
        @terminal_nodes =
            grep { not $_->[Marpa::Internal::And_Node::DELETED] }
            @terminal_nodes;

    } ## end while (1)

    return;

} ## end sub delete_duplicate_nodes

# Returns false if no parse
sub Marpa::Evaluator::new {
    my $class = shift;
    my $args  = shift;

    my $self = bless [], $class;

    ### Constructing new evaluator

    my $recce;
    RECCE_ARG_NAME: for my $recce_arg_name (qw(recognizer recce)) {
        my $arg_value = $args->{$recce_arg_name};
        delete $args->{$recce_arg_name};
        next RECCE_ARG_NAME if not defined $arg_value;
        Marpa::exception('recognizer specified twice') if defined $recce;
        $recce = $arg_value;
    } ## end for my $recce_arg_name (qw(recognizer recce))
    Marpa::exception('No recognizer specified') if not defined $recce;

    my $recce_class = ref $recce;
    Marpa::exception(
        "${class}::new() recognizer arg has wrong class: $recce_class")
        if $recce_class ne 'Marpa::Recognizer';

    my $parse_set_arg = $args->{end};
    delete $args->{end};

    my $clone_arg = $args->{clone};
    delete $args->{clone};
    my $clone = $clone_arg // 1;

    if ($clone) {
        $recce = $recce->clone();
    }

    my ( $grammar, $earley_sets, ) = @{$recce}[
        Marpa::Internal::Recognizer::GRAMMAR,
        Marpa::Internal::Recognizer::EARLEY_SETS,
    ];

    my $phase = $grammar->[Marpa::Internal::Grammar::PHASE];

    # Marpa::exception('Recognizer already in use by Evaluator')
    # if $phase == Marpa::Internal::Phase::EVALUATING;
    Marpa::exception(
        'Attempt to evaluate grammar in wrong phase: ',
        Marpa::Internal::Phase::description($phase)
    ) if $phase < Marpa::Internal::Phase::RECOGNIZED;

    $self->[Marpa::Internal::Evaluator::RECOGNIZER] = $recce;

    $self->set($args);

    $grammar->[Marpa::Internal::Grammar::PHASE] =
        Marpa::Internal::Phase::EVALUATING;

    my $tracing = $grammar->[Marpa::Internal::Grammar::TRACING];

    my $trace_fh;
    my $trace_iterations;
    my $trace_evaluation;

    if ($tracing) {
        $trace_fh = $grammar->[Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
        $trace_evaluation =
            $grammar->[Marpa::Internal::Grammar::TRACE_EVALUATION];
        $trace_iterations =
            $grammar->[Marpa::Internal::Grammar::TRACE_ITERATIONS];
    } ## end if ($tracing)

    $self->[Marpa::Internal::Evaluator::PARSE_COUNT] = 0;
    my $or_nodes  = $self->[Marpa::Internal::Evaluator::OR_NODES]  = [];
    my $and_nodes = $self->[Marpa::Internal::Evaluator::AND_NODES] = [];

    my $current_parse_set = $parse_set_arg
        // $recce->[Marpa::Internal::Recognizer::FURTHEST_EARLEME];

    # Look for the start item and start rule
    my $earley_set = $earley_sets->[$current_parse_set];

    my $start_item;
    my $start_rule;
    my $start_state;

    EARLEY_ITEM: for my $item ( @{$earley_set} ) {
        $start_state = $item->[Marpa::Internal::Earley_Item::STATE];
        $start_rule  = $start_state->[Marpa::Internal::QDFA::START_RULE];
        next EARLEY_ITEM if not $start_rule;
        $start_item = $item;
        last EARLEY_ITEM;
    } ## end for my $item ( @{$earley_set} )

    return if not $start_rule;

    my $start_rule_id = $start_rule->[Marpa::Internal::Rule::ID];

    state $parse_number = 0;
    my $null_values = $self->[Marpa::Internal::Evaluator::NULL_VALUES] =
        set_null_values($self);
    my $evaluator_rules = $self->[Marpa::Internal::Evaluator::RULE_DATA] =
        set_actions($self);

    my $start_symbol = $start_rule->[Marpa::Internal::Rule::LHS];
    my ( $nulling, $symbol_id ) =
        @{$start_symbol}[ Marpa::Internal::Symbol::NULLING,
        Marpa::Internal::Symbol::ID, ];
    my $start_null_value = $null_values->[$symbol_id];

    # deal with a null parse as a special case
    if ($nulling) {

        my $evaluator_data = $evaluator_rules->[$start_rule_id];

        my $or_node = [];
        $#{$or_node} = Marpa::Internal::Or_Node::LAST_FIELD;

        my $and_node = [];
        $#{$and_node} = Marpa::Internal::And_Node::LAST_FIELD;

        $or_node->[Marpa::Internal::Or_Node::CHILD_IDS]     = [0];
        $or_node->[Marpa::Internal::Or_Node::START_EARLEME] = 0;
        $or_node->[Marpa::Internal::Or_Node::END_EARLEME]   = 0;
        my $or_node_id = $or_node->[Marpa::Internal::Or_Node::ID] = 0;
        my $or_node_tag = $or_node->[Marpa::Internal::Or_Node::TAG] =
            $start_item->[Marpa::Internal::Earley_Item::NAME]
            . "o$or_node_id";

        $and_node->[Marpa::Internal::And_Node::VALUE_REF] =
            \$start_null_value;
        $and_node->[Marpa::Internal::And_Node::EVALUATOR_DATA] =
            $evaluator_data;
        $and_node->[Marpa::Internal::And_Node::RULE_ID]  = $start_rule_id;
        $and_node->[Marpa::Internal::And_Node::POSITION] = -1;
        $and_node->[Marpa::Internal::And_Node::START_EARLEME] = 0;
        $and_node->[Marpa::Internal::And_Node::END_EARLEME]   = 0;
        $and_node->[Marpa::Internal::And_Node::PARENT_ID]     = 0;
        $and_node->[Marpa::Internal::And_Node::PARENT_CHOICE] = 0;
        my $and_node_id = $and_node->[Marpa::Internal::And_Node::ID] = 0;
        $and_node->[Marpa::Internal::And_Node::TAG] =
            $or_node_tag . "a$and_node_id";

        push @{$or_nodes},  $or_node;
        push @{$and_nodes}, $and_node;

        return $self;

    }    # if $nulling

    my @or_saplings;
    my %or_node_by_name;
    my $start_sapling = [];
    {
        my $start_name = $start_item->[Marpa::Internal::Earley_Item::NAME];
        my $start_symbol_id = $start_symbol->[Marpa::Internal::Symbol::ID];
        $start_name .= 'L' . $start_symbol_id;
        $start_sapling->[Marpa::Internal::Or_Sapling::NAME] = $start_name;
    }
    $start_sapling->[Marpa::Internal::Or_Sapling::ITEM] = $start_item;
    $start_sapling->[Marpa::Internal::Or_Sapling::CHILD_LHS_SYMBOL] =
        $start_symbol;
    push @or_saplings, $start_sapling;

    my $i = 0;
    OR_SAPLING: while (1) {

        my ( $sapling_name, $item, $child_lhs_symbol, $rule, $position ) =
            @{ $or_saplings[ $i++ ] }[
            Marpa::Internal::Or_Sapling::NAME,
            Marpa::Internal::Or_Sapling::ITEM,
            Marpa::Internal::Or_Sapling::CHILD_LHS_SYMBOL,
            Marpa::Internal::Or_Sapling::RULE,
            Marpa::Internal::Or_Sapling::POSITION,
            ];

        last OR_SAPLING if not defined $item;

        # If we don't have a current rule, we need to get one or
        # more rules, and deduce the position and a new symbol from
        # them.
        my @and_saplings;

        my $is_kernel_or_node = defined $position;

        if ($is_kernel_or_node) {

            # Kernel or-node: We have a rule and a position.
            # get the current symbol

            $position--;
            my $symbol = $rule->[Marpa::Internal::Rule::RHS]->[$position];
            push @and_saplings, [ $rule, $position, $symbol ];

        } ## end if ($is_kernel_or_node)
        else {

            # Closure or-node.

            my $child_lhs_id =
                $child_lhs_symbol->[Marpa::Internal::Symbol::ID];
            my $state = $item->[Marpa::Internal::Earley_Item::STATE];
            for my $rule (
                @{  $state->[Marpa::Internal::QDFA::COMPLETE_RULES]
                        ->[$child_lhs_id];
                }
                )
            {

                my $rhs = $rule->[Marpa::Internal::Rule::RHS];
                my $evaluator_data =
                    $evaluator_rules->[ $rule->[Marpa::Internal::Rule::ID] ];

                my $last_position = @{$rhs} - 1;
                push @and_saplings,
                    [
                    $rule,                  $last_position,
                    $rhs->[$last_position], $evaluator_data
                    ];

            }    # for my $rule

        }    # closure or-node

        my $start_earleme = $item->[Marpa::Internal::Earley_Item::PARENT];
        my $end_earleme   = $item->[Marpa::Internal::Earley_Item::SET];

        my @child_and_nodes;

        my $item_name = $item->[Marpa::Internal::Earley_Item::NAME];

        for my $and_sapling (@and_saplings) {

            my ( $sapling_rule, $sapling_position, $symbol, $evaluator_data )
                = @{$and_sapling};

            my ( $rule_id, $rhs ) =
                @{$sapling_rule}[ Marpa::Internal::Rule::ID,
                Marpa::Internal::Rule::RHS ];
            my $rule_length = @{$rhs};

            my @or_bud_list;
            if ( $symbol->[Marpa::Internal::Symbol::NULLING] ) {
                my $nulling_symbol_id =
                    $symbol->[Marpa::Internal::Symbol::ID];
                my $null_value = $null_values->[$nulling_symbol_id];
                @or_bud_list = ( [ $item, undef, $symbol, \$null_value, ] );
            } ## end if ( $symbol->[Marpa::Internal::Symbol::NULLING] )
            else {
                @or_bud_list = (
                    (   map { [ $_->[0], undef, @{$_}[ 1, 2 ] ] }
                            @{ $item->[Marpa::Internal::Earley_Item::TOKENS] }
                    ),
                    (   map { [ $_->[0], $_->[1] ] }
                            @{ $item->[Marpa::Internal::Earley_Item::LINKS] }
                    )
                );
            } ## end else [ if ( $symbol->[Marpa::Internal::Symbol::NULLING] ) ]

            for my $or_bud (@or_bud_list) {

                my ( $predecessor, $cause, $token, $value_ref ) = @{$or_bud};

                my $predecessor_name;

                if ( $sapling_position > 0 ) {

                    $predecessor_name =
                        $predecessor->[Marpa::Internal::Earley_Item::NAME]
                        . "R$rule_id:$sapling_position";

                    if ( not $predecessor_name ~~ %or_node_by_name ) {

                        $or_node_by_name{$predecessor_name} = [];

                        my $sapling = [];
                        @{$sapling}[
                            Marpa::Internal::Or_Sapling::NAME,
                            Marpa::Internal::Or_Sapling::RULE,
                            Marpa::Internal::Or_Sapling::POSITION,
                            Marpa::Internal::Or_Sapling::ITEM,
                            ]
                            = (
                            $predecessor_name, $sapling_rule,
                            $sapling_position, $predecessor,
                            );

                        push @or_saplings, $sapling;

                    }    # $predecessor_name ~~ %or_node_by_name

                }    # if sapling_position > 0

                my $cause_name;

                if ( defined $cause ) {

                    my $cause_symbol_id =
                        $symbol->[Marpa::Internal::Symbol::ID];

                    $cause_name =
                          $cause->[Marpa::Internal::Earley_Item::NAME] . 'L'
                        . $cause_symbol_id;

                    if ( not $cause_name ~~ %or_node_by_name ) {

                        $or_node_by_name{$cause_name} = [];

                        my $sapling = [];
                        @{$sapling}[
                            Marpa::Internal::Or_Sapling::NAME,
                            Marpa::Internal::Or_Sapling::CHILD_LHS_SYMBOL,
                            Marpa::Internal::Or_Sapling::ITEM,
                            ]
                            = ( $cause_name, $symbol, $cause, );

                        push @or_saplings, $sapling;

                    }    # $cause_name ~~ %or_node_by_name

                }    # if cause

                my $and_node = [];
                $#{$and_node} = Marpa::Internal::And_Node::LAST_FIELD;

                $and_node->[Marpa::Internal::And_Node::PREDECESSOR] =
                    $predecessor_name;
                $and_node->[Marpa::Internal::And_Node::CAUSE] = $cause_name;
                $and_node->[Marpa::Internal::And_Node::TOKEN] = $token;
                $and_node->[Marpa::Internal::And_Node::VALUE_REF] =
                    $value_ref;
                $and_node->[Marpa::Internal::And_Node::EVALUATOR_DATA] =
                    $evaluator_data;
                $and_node->[Marpa::Internal::And_Node::RULE_ID] =
                    $sapling_rule->[Marpa::Internal::Rule::ID];
                $and_node->[Marpa::Internal::And_Node::POSITION] =
                    $sapling_position;
                $and_node->[Marpa::Internal::And_Node::START_EARLEME] =
                    $start_earleme;
                $and_node->[Marpa::Internal::And_Node::END_EARLEME] =
                    $end_earleme;
                my $id = $and_node->[Marpa::Internal::And_Node::ID] =
                    @{$and_nodes};
                Marpa::exception("Too many and-nodes for evaluator: $id")
                    if $id & ~(N_FORMAT_MAX);
                push @{$and_nodes}, $and_node;

                push @child_and_nodes, $and_node;

            }    # for my $or_bud

        }    # for my $and_sapling

        my $or_node = [];
        $#{$or_node} = Marpa::Internal::Or_Node::LAST_FIELD;
        my $or_node_id = $or_node->[Marpa::Internal::Or_Node::ID] =
            @{$or_nodes};
        my $or_node_tag = $or_node->[Marpa::Internal::Or_Node::TAG] =
            $sapling_name . "o$or_node_id";
        $or_node->[Marpa::Internal::Or_Node::CHILD_IDS] =
            [ map { $_->[Marpa::Internal::And_Node::ID] } @child_and_nodes ];
        for my $and_node_choice ( 0 .. $#child_and_nodes ) {
            my $and_node    = $child_and_nodes[$and_node_choice];
            my $and_node_id = $and_node->[Marpa::Internal::And_Node::ID];
            $and_node->[Marpa::Internal::And_Node::TAG] =
                $or_node_tag . "a$and_node_id";
            $and_node->[Marpa::Internal::And_Node::PARENT_ID] = $or_node_id;
            $and_node->[Marpa::Internal::And_Node::PARENT_CHOICE] =
                $and_node_choice;
        } ## end for my $and_node_choice ( 0 .. $#child_and_nodes )
        $or_node->[Marpa::Internal::Or_Node::START_EARLEME] = $start_earleme;
        $or_node->[Marpa::Internal::Or_Node::END_EARLEME]   = $end_earleme;
        $or_node->[Marpa::Internal::Or_Node::PARENT_IDS]    = [];
        push @{$or_nodes}, $or_node;
        $or_node_by_name{$sapling_name} = $or_node;

    }    # OR_SAPLING

    my $and_node_counter = 0;

    # resolve links in the bocage
    for my $and_node ( @{$and_nodes} ) {
        my $and_node_id = $and_node->[Marpa::Internal::And_Node::ID];

        FIELD:
        for my $field (
            Marpa::Internal::And_Node::PREDECESSOR,
            Marpa::Internal::And_Node::CAUSE,
            )
        {
            my $name = $and_node->[$field];
            next FIELD if not defined $name;
            my $child_or_node = $or_node_by_name{$name};
            $and_node->[$field] = $child_or_node;
            my $parent_ids =
                $child_or_node->[Marpa::Internal::Or_Node::PARENT_IDS];
            push @{$parent_ids}, $and_node_id;
        } ## end for my $field ( Marpa::Internal::And_Node::PREDECESSOR...)

    } ## end for my $and_node ( @{$and_nodes} )

    # We don't allow zero-length or-nodes to have more than one
    # and-node parent.
    # We do that to prevent two and-nodes in a
    # parse from overlapping.
    # For non-zero-length or-nodes preventing overlap is
    # easy -- if no and-nodes have overlapping spans
    # as determined by start and end earleme,
    # they won't have overlapping non-zero-length or-nodes.
    # But with zero-length or-nodes, an or-node can
    # be a trailing or-node and a lead or-node at the same
    # earleme location.
    # That means that two adjacent and-nodes can share
    # the same child or-node -- one which has it as a trailing
    # or-node, the other which has it as a leading or-node.
    #
    # So in the below, we make sure every zero-length or-node
    # has only one parent.
    OR_NODE: for my $or_node ( @{$or_nodes} ) {

        # Don't need to deal with deleted ndoes
        # There aren't any at this point
        next OR_NODE
            if $or_node->[Marpa::Internal::Or_Node::START_EARLEME]
                != $or_node->[Marpa::Internal::Or_Node::END_EARLEME];

        my $parent_and_node_ids =
            $or_node->[Marpa::Internal::Or_Node::PARENT_IDS];
        next OR_NODE if scalar @{$parent_and_node_ids} <= 1;

        # Remove the other parents from the original (uncloned)
        # or-node.
        $or_node->[Marpa::Internal::Or_Node::PARENT_IDS] =
            [ $parent_and_node_ids->[0] ];

        # This or-node needs to be cloned, so that it will be
        # unique to its parent and-node
        for my $parent_and_node_id (
            @{$parent_and_node_ids}[ 1 .. $#{$parent_and_node_ids} ] )
        {
            my @cloned_and_nodes =
                map { clone_and_node( $self, $and_nodes->[$_] ) }
                @{ $or_node->[Marpa::Internal::Or_Node::CHILD_IDS] };

            my $cloned_or_node = [];
            $#{$cloned_or_node} = Marpa::Internal::Or_Node::LAST_FIELD;
            my $cloned_or_node_id =
                $cloned_or_node->[Marpa::Internal::Or_Node::ID] =
                @{$or_nodes};
            my $cloned_or_node_tag =
                $or_node->[Marpa::Internal::Or_Node::TAG];
            $cloned_or_node_tag =~ s/ (o\d+) \z /o$cloned_or_node_id/xms;
            $cloned_or_node->[Marpa::Internal::Or_Node::TAG] =
                $cloned_or_node_tag;
            $cloned_or_node->[Marpa::Internal::Or_Node::CHILD_IDS] =
                [ map { $_->[Marpa::Internal::And_Node::ID] }
                    @cloned_and_nodes ];

            for my $cloned_and_node_choice ( 0 .. $#cloned_and_nodes ) {
                my $cloned_and_node =
                    $cloned_and_nodes[$cloned_and_node_choice];
                my $cloned_and_node_id =
                    $cloned_and_node->[Marpa::Internal::And_Node::ID];
                $cloned_and_node->[Marpa::Internal::And_Node::TAG] =
                    $cloned_or_node_tag . "a$cloned_and_node_id";
                $cloned_and_node->[Marpa::Internal::And_Node::PARENT_ID] =
                    $cloned_or_node_id;
                $cloned_and_node->[Marpa::Internal::And_Node::PARENT_CHOICE] =
                    $cloned_and_node_choice;
            } ## end for my $cloned_and_node_choice ( 0 .. $#cloned_and_nodes)
            for my $field (
                Marpa::Internal::Or_Node::START_EARLEME,
                Marpa::Internal::Or_Node::END_EARLEME,
                )
            {
                $cloned_or_node->[$field] = $or_node->[$field];
            } ## end for my $field ( Marpa::Internal::Or_Node::START_EARLEME...)

            $cloned_or_node->[Marpa::Internal::Or_Node::PARENT_IDS] =
                [$parent_and_node_id];

            my $parent_and_node = $and_nodes->[$parent_and_node_id];
            my $parent_and_node_cause =
                $parent_and_node->[Marpa::Internal::And_Node::CAUSE];
            if ( defined $parent_and_node_cause
                and $or_node == $parent_and_node_cause )
            {
                $parent_and_node->[Marpa::Internal::And_Node::CAUSE] =
                    $cloned_or_node;
            } ## end if ( defined $parent_and_node_cause and $or_node == ...)
            else {
                $parent_and_node->[Marpa::Internal::And_Node::PREDECESSOR] =
                    $cloned_or_node;
            }

            push @{$or_nodes}, $cloned_or_node;
        } ## end for my $parent_and_node_id ( @{$parent_and_node_ids}[...])

    } ## end for my $or_node ( @{$or_nodes} )

    # TODO: Add code to only attempt rewrite if grammar is cyclical
    rewrite_cycles($self);

    my $first_ambiguous_or_node = List::Util::first {
        @{ $_->[Marpa::Internal::Or_Node::CHILD_IDS] } > 1;
    }
    @{$or_nodes};

    ### assert: Marpa'Evaluator'audit($self) or 1

    return $self if not defined $first_ambiguous_or_node;

    # The rest of the processing only applies to ambiguous grammars.

    delete_duplicate_nodes($self);

    ### assert: Marpa'Evaluator'audit($self) or 1

    return $self;

}    # sub new

## use critic

sub Marpa::dump_sort_key {
    my ($sort_key) = @_;
    my @element_dumps = ();
    for my $sort_element (
        map { [ unpack 'N*', $_ ] }
        sort map { pack 'N*', @{$_} } @{$sort_key}
        )
    {
        push @element_dumps,
            (
            join q{ },
            map { ( $_ & N_FORMAT_HIGH_BIT ) ? ( q{~} . ~$_ ) : "$_" }
                @{$sort_element}
            );
    } ## end for my $sort_element ( map { [ unpack 'N*', $_ ] } sort...)
    return join q{; }, @element_dumps;
} ## end sub Marpa::dump_sort_key

sub Marpa::Evaluator::show_sort_keys {
    my ($evaler) = @_;
    my $or_iterations = $evaler->[Marpa::Internal::Evaluator::OR_ITERATIONS];
    my $top_or_iteration = $or_iterations->[0];
    Marpa::exception('show_sort_keys called on exhausted parse')
        if not $top_or_iteration;

    my $text = q{};
    for my $and_choice ( reverse @{$top_or_iteration} ) {
        $text
            .= Marpa::dump_sort_key(
            $and_choice->[Marpa::Internal::And_Choice::SORT_KEY] )
            . "\n";
    } ## end for my $and_choice ( reverse @{$top_or_iteration} )
    return $text;
} ## end sub Marpa::Evaluator::show_sort_keys

sub Marpa::Evaluator::show_and_node {
    my ( $evaler, $and_node, $verbose ) = @_;
    $verbose //= 0;

    return q{} if $and_node->[Marpa::Internal::And_Node::DELETED];

    my $return_value = q{};

    my $recce   = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar = $recce->[Marpa::Internal::Recognizer::GRAMMAR];
    my $rules   = $grammar->[Marpa::Internal::Grammar::RULES];

    my $name        = $and_node->[Marpa::Internal::And_Node::TAG];
    my $predecessor = $and_node->[Marpa::Internal::And_Node::PREDECESSOR];
    my $cause       = $and_node->[Marpa::Internal::And_Node::CAUSE];
    my $value_ref   = $and_node->[Marpa::Internal::And_Node::VALUE_REF];
    my $rule_id     = $and_node->[Marpa::Internal::And_Node::RULE_ID];
    my $position    = $and_node->[Marpa::Internal::And_Node::POSITION];

    my @rhs = ();

    my $rule          = $rules->[$rule_id];
    my $original_rule = $rule->[Marpa::Internal::Rule::ORIGINAL_RULE]
        // $rule;
    my $is_virtual_rule = $rule != $original_rule;

    if ($predecessor) {
        push @rhs, $predecessor->[Marpa::Internal::Or_Node::TAG];
    }    # predecessor

    if ($cause) {
        push @rhs, $cause->[Marpa::Internal::Or_Node::TAG];
    }    # cause

    if ( defined $value_ref ) {
        my $value_as_string =
            Data::Dumper->new( [ ${$value_ref} ] )->Terse(1)->Dump;
        chomp $value_as_string;
        push @rhs, $value_as_string;
    }    # value

    $return_value .= "$name -> " . join( q{ }, @rhs ) . "\n";

    SHOW_RULE: {
        if ( $is_virtual_rule and $verbose >= 2 ) {
            $return_value
                .= '    rule '
                . $rule->[Marpa::Internal::Rule::ID] . ': '
                . Marpa::show_dotted_rule( $rule, $position + 1 )
                . "\n    "
                . Marpa::brief_virtual_rule( $rule, $position + 1 ) . "\n";
            last SHOW_RULE;
        } ## end if ( $is_virtual_rule and $verbose >= 2 )

        last SHOW_RULE if not $verbose;
        $return_value
            .= '    rule '
            . $rule->[Marpa::Internal::Rule::ID] . ': '
            . Marpa::brief_virtual_rule( $rule, $position + 1 ) . "\n";

    } ## end SHOW_RULE:

    return $return_value;

} ## end sub Marpa::Evaluator::show_and_node

sub Marpa::Evaluator::show_or_node {
    my ( $evaler, $or_node, $verbose ) = @_;
    $verbose //= 0;

    return q{} if $or_node->[Marpa::Internal::Or_Node::DELETED];

    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];

    my $text = q{};

    my $or_node_tag  = $or_node->[Marpa::Internal::Or_Node::TAG];
    my $and_node_ids = $or_node->[Marpa::Internal::Or_Node::CHILD_IDS];

    for my $index ( 0 .. $#{$and_node_ids} ) {
        my $and_node_id = $and_node_ids->[$index];
        my $and_node    = $and_nodes->[$and_node_id];

        my $and_node_tag = $or_node_tag . "a$and_node_id";
        if ( $verbose >= 2 ) {
            $text .= "$or_node_tag -> $and_node_tag\n";
        }

        $text .= $evaler->show_and_node( $and_node, $verbose );

    } ## end for my $index ( 0 .. $#{$and_node_ids} )

    return $text;

} ## end sub Marpa::Evaluator::show_or_node

sub Marpa::Evaluator::show_bocage {
    my ( $evaler, $verbose ) = @_;
    $verbose //= 0;

    my $parse_count = $evaler->[Marpa::Internal::Evaluator::PARSE_COUNT];
    my $or_nodes    = $evaler->[Marpa::Internal::Evaluator::OR_NODES];

    my $text = 'parse count: ' . $parse_count . "\n";

    for my $or_node ( @{$or_nodes} ) {

        $text
            .= Marpa::Evaluator::show_or_node( $evaler, $or_node, $verbose );

    } ## end for my $or_node ( @{$or_nodes} )

    return $text;
} ## end sub Marpa::Evaluator::show_bocage

sub Marpa::Evaluator::set {
    my $evaler  = shift;
    my $args    = shift;
    my $recce   = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar = $recce->[Marpa::Internal::Recognizer::GRAMMAR];
    Marpa::Grammar::set( $grammar, $args );
    return 1;
} ## end sub Marpa::Evaluator::set

use Marpa::Offset qw(
    { tasks for use in Marpa::Evaluator::value }
    :package=Marpa::Internal::Task
    RESET_AND_NODE
    SETUP_AND_NODE
    ITERATE_AND_TREE
    ITERATE_AND_TREE_2
    ITERATE_AND_TREE_3
    RESET_AND_TREE
    RESET_OR_NODE
    RESET_OR_TREE
    ITERATE_OR_NODE
    ITERATE_OR_TREE
    FREEZE_TREE
    THAW_TREE
    EVALUATE
);

# This will replace the old value method
sub Marpa::Evaluator::value {
    my ($evaler) = @_;

    Marpa::exception('No parse supplied') if not defined $evaler;
    my $evaler_class = ref $evaler;
    my $right_class  = 'Marpa::Evaluator';
    Marpa::exception(
        "Don't parse argument is class: $evaler_class; should be: $right_class"
    ) if $evaler_class ne $right_class;

    my $recognizer = $evaler->[Marpa::Internal::Evaluator::RECOGNIZER];
    my $grammar    = $recognizer->[Marpa::Internal::Recognizer::GRAMMAR];
    my $rules      = $grammar->[Marpa::Internal::Grammar::RULES];

    my $evaluator_rules = $evaler->[Marpa::Internal::Evaluator::RULE_DATA];
    my $null_values     = $evaler->[Marpa::Internal::Evaluator::NULL_VALUES];
    my $parse_count = $evaler->[Marpa::Internal::Evaluator::PARSE_COUNT]++;

    my $and_nodes = $evaler->[Marpa::Internal::Evaluator::AND_NODES];
    my $or_nodes  = $evaler->[Marpa::Internal::Evaluator::OR_NODES];

    # If the arrays of iteration data
    # for the and-nodes and or-nodes are undefined,
    # this is the first pass through, and there is some
    # initialization that needs to be done.
    my $and_iterations =
        $evaler->[Marpa::Internal::Evaluator::AND_ITERATIONS];
    my $or_iterations = $evaler->[Marpa::Internal::Evaluator::OR_ITERATIONS];
    if ( not defined $and_iterations ) {
        $#{$and_iterations} = $#{$and_nodes};
        $#{$or_iterations}  = $#{$or_nodes};
        $evaler->[Marpa::Internal::Evaluator::AND_ITERATIONS] =
            $and_iterations;
        $evaler->[Marpa::Internal::Evaluator::OR_ITERATIONS] = $or_iterations;

        # This could be done in the ::new constructor, but intuitively
        # I feel it does not belong -- that someday it would get
        # factored out to here.
        for my $and_node ( @{$and_nodes} ) {

            my $rule_id  = $and_node->[Marpa::Internal::And_Node::RULE_ID];
            my $rule     = $rules->[$rule_id];
            my $maximal  = $rule->[Marpa::Internal::Rule::MAXIMAL];
            my $minimal  = $rule->[Marpa::Internal::Rule::MINIMAL];
            my $priority = $rule->[Marpa::Internal::Rule::PRIORITY];

            if ( $maximal or $minimal or $priority ) {

                my $and_node_start_earleme =
                    $and_node->[Marpa::Internal::And_Node::START_EARLEME];
                my $and_node_end_earleme =
                    $and_node->[Marpa::Internal::And_Node::END_EARLEME];

                # compute this and-nodes sort key element
                # insert it into the predecessor sort key elements
                my $location = $and_node_start_earleme;
                my $length =
                    $maximal
                    ? ~( ( $and_node_end_earleme - $and_node_start_earleme )
                    & N_FORMAT_MASK )
                    : $minimal
                    ? ( $and_node_end_earleme - $and_node_start_earleme )
                    : 0;
                $and_node->[Marpa::Internal::And_Node::SORT_ELEMENT] =
                    [ $location, ~( $priority & N_FORMAT_MASK ), $length ];

            } ## end if ( $maximal or $minimal or $priority )

        } ## end for my $and_node ( @{$and_nodes} )

    } ## end if ( not defined $and_iterations )

    my $tracing  = $grammar->[Marpa::Internal::Grammar::TRACING];
    my $trace_fh = $grammar->[Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
    my $trace_values     = 0;
    my $trace_iterations = 0;
    my $trace_tasks      = 0;
    if ($tracing) {
        $trace_values = $grammar->[Marpa::Internal::Grammar::TRACE_VALUES];
        $trace_iterations =
            $grammar->[Marpa::Internal::Grammar::TRACE_ITERATIONS];
        $trace_tasks = $trace_iterations >= 2;
    } ## end if ($tracing)

    my $max_parses = $grammar->[Marpa::Internal::Grammar::MAX_PARSES];
    if ( $max_parses > 0 && $parse_count >= $max_parses ) {
        Marpa::exception("Maximum parse count ($max_parses) exceeded");
    }

    my @tasks = (
        [Marpa::Internal::Task::EVALUATE],
        [   (   $parse_count
                ? Marpa::Internal::Task::ITERATE_OR_TREE
                : Marpa::Internal::Task::RESET_OR_TREE
            ),
            0
        ]
    );

    while (1) {

        my $task_entry = pop @tasks;
        my $task       = shift @{$task_entry};

        given ($task) {
            when (Marpa::Internal::Task::RESET_OR_NODE) {
                my ($or_node_id) = @{$task_entry};
                my $or_node = $or_nodes->[$or_node_id];

                if ($trace_tasks) {
                    print {$trace_fh} "Task: RESET_OR_NODE #$or_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                }

                # Set up the and-choices from the children
                my @and_choices;
                for my $child_and_node_id (
                    @{ $or_node->[Marpa::Internal::Or_Node::CHILD_IDS] } )
                {
                    my $and_choice;
                    $#{$and_choice} = Marpa::Internal::And_Choice::LAST_FIELD;
                    $and_choice->[Marpa::Internal::And_Choice::ID] =
                        $child_and_node_id;
                    my $and_iteration = $and_iterations->[$child_and_node_id];
                    $and_choice->[Marpa::Internal::And_Choice::SORT_KEY] =
                        $and_iteration
                        ->[Marpa::Internal::And_Iteration::SORT_KEY];

                    my $or_map =
                        $and_choice->[Marpa::Internal::And_Choice::OR_MAP] = [
                        @{  $and_iteration
                                ->[Marpa::Internal::And_Iteration::OR_MAP]
                            }
                        ];

                    push @and_choices, $and_choice;

                } ## end for my $child_and_node_id ( @{ $or_node->[...]})

                # Sort and-choices
                my $or_iteration = $or_iterations->[$or_node_id] = [
                    map      { $_->[1] }
                        sort { $a->[0] cmp $b->[0] }
                        map {
                        [   (   join q{},
                                map {
                                    length $_ == N_FORMAT_WIDTH
                                        ? ( ~$_ )
                                        . (
                                        "\0" x NULL_SORT_ELEMENT_FILL_WIDTH )
                                        : ~$_
                                    }
                                    sort map { pack 'N*', @{$_} } @{
                                    $_->[
                                        Marpa::Internal::And_Choice::SORT_KEY]
                                    }
                            ),
                            $_
                        ]
                        } @and_choices
                ];

                push @tasks,
                    map { [ Marpa::Internal::Task::FREEZE_TREE, $_ ] }
                    @{$or_iteration}[ 0 .. $#{$or_iteration} - 1 ];

            } ## end when (Marpa::Internal::Task::RESET_OR_NODE)

            when (Marpa::Internal::Task::RESET_AND_NODE) {

                my ($and_node_id) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh} "Task: RESET_AND_NODE #$and_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                }

                my $and_node = $and_nodes->[$and_node_id];

                my $and_node_iteration = $and_iterations->[$and_node_id] = [];

                $and_node_iteration
                    ->[Marpa::Internal::And_Iteration::CURRENT_CHILD] =
                    defined $and_node->[Marpa::Internal::And_Node::CAUSE]
                    ? Marpa::Internal::And_Node::CAUSE
                    : defined
                    $and_node->[Marpa::Internal::And_Node::PREDECESSOR]
                    ? Marpa::Internal::And_Node::PREDECESSOR
                    : undef;

                push @tasks,
                    [ Marpa::Internal::Task::SETUP_AND_NODE, $and_node_id ];

            } ## end when (Marpa::Internal::Task::RESET_AND_NODE)

            # Set up task for followup on both initialization and iteration
            # This is safe to call on exhausted nodes
            when (Marpa::Internal::Task::SETUP_AND_NODE) {

                my ($and_node_id) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh} "Task: SETUP_AND_NODE #$and_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                }

                my $and_node = $and_nodes->[$and_node_id];

                my $and_node_iteration = $and_iterations->[$and_node_id];
                break if not $and_node_iteration;

                my $sort_element =
                    $and_node->[Marpa::Internal::And_Node::SORT_ELEMENT];
                my @current_sort_elements =
                    $sort_element ? ($sort_element) : ();

                my $cause;
                my $cause_id;
                my $cause_or_node_iteration;
                my $cause_and_node_choice;
                my $cause_and_node_iteration;
                my $cause_sort_elements = [];

                # assignment instead of comparison intentional
                if ( $cause = $and_node->[Marpa::Internal::And_Node::CAUSE] )
                {
                    $cause_id = $cause->[Marpa::Internal::Or_Node::ID];
                    $cause_or_node_iteration = $or_iterations->[$cause_id];

                    # If there is a predecessor, but it is
                    # exhausted, this and-node is exhausted.
                    if ( not $cause_or_node_iteration ) {
                        $and_iterations->[$and_node_id] = undef;
                        break;
                    }

                    $cause_and_node_choice = $cause_or_node_iteration->[-1];
                    my $cause_and_node_id = $cause_and_node_choice
                        ->[Marpa::Internal::And_Choice::ID];
                    $cause_and_node_iteration =
                        $and_iterations->[$cause_and_node_id];
                    $cause_sort_elements = $cause_and_node_iteration
                        ->[Marpa::Internal::And_Iteration::SORT_KEY];

                } ## end if ( $cause = $and_node->[...])

                my $predecessor;
                my $predecessor_id;
                my $predecessor_or_node_iteration;
                my $predecessor_and_node_choice;
                my $predecessor_and_node_iteration;
                my $predecessor_sort_elements = [];
                my $predecessor_end_earleme;

                # assignment instead of comparison intentional
                if ( $predecessor =
                    $and_node->[Marpa::Internal::And_Node::PREDECESSOR] )
                {
                    $predecessor_id =
                        $predecessor->[Marpa::Internal::Or_Node::ID];
                    $predecessor_or_node_iteration =
                        $or_iterations->[$predecessor_id];
                    $predecessor_end_earleme =
                        $predecessor->[Marpa::Internal::Or_Node::END_EARLEME];

                    # If there is a predecessor, but it is
                    # exhausted, this and-node is exhausted.
                    if ( not $predecessor_or_node_iteration ) {
                        $and_iterations->[$and_node_id] = undef;
                        break;
                    }

                    $predecessor_and_node_choice =
                        $predecessor_or_node_iteration->[-1];
                    my $predecessor_and_node_id = $predecessor_and_node_choice
                        ->[Marpa::Internal::And_Choice::ID];
                    $predecessor_and_node_iteration =
                        $and_iterations->[$predecessor_and_node_id];
                    $predecessor_sort_elements =
                        $predecessor_and_node_iteration
                        ->[Marpa::Internal::And_Iteration::SORT_KEY];

                } ## end if ( $predecessor = $and_node->[...])

                # Compute trailing nulls
                if ( my $token =
                    $and_node->[Marpa::Internal::And_Node::TOKEN] )
                {

                    my $nullable = $token->[Marpa::Internal::Symbol::NULLABLE]
                        // 0;

                    # A null token must start at the end earleme
                    # This will not necessarily be the start earleme
                    # -- there may be a predecessor
                    push @current_sort_elements,
                        (
                        [   $and_node
                                ->[Marpa::Internal::And_Node::END_EARLEME]
                        ]
                        ) x $nullable;

                } ## end if ( my $token = $and_node->[...])

                $and_node_iteration
                    ->[Marpa::Internal::And_Iteration::SORT_KEY] = [
                    @current_sort_elements, @{$predecessor_sort_elements},
                    @{$cause_sort_elements}
                    ];

                my @or_map;
                if ( defined $predecessor ) {
                    push @or_map,
                        [
                        $predecessor_id,
                        $predecessor_and_node_choice
                            ->[Marpa::Internal::And_Choice::ID]
                        ],
                        @{ $predecessor_and_node_choice
                            ->[Marpa::Internal::And_Choice::OR_MAP] };
                } ## end if ( defined $predecessor )
                if ( defined $cause ) {
                    push @or_map,
                        [
                        $cause_id,
                        $cause_and_node_choice
                            ->[Marpa::Internal::And_Choice::ID]
                        ],
                        @{ $cause_and_node_choice
                            ->[Marpa::Internal::And_Choice::OR_MAP] };
                } ## end if ( defined $cause )
                $and_node_iteration->[Marpa::Internal::And_Iteration::OR_MAP]
                    = \@or_map;

                if (    defined $cause
                    and defined $predecessor )
                {
                    my ( $cause_sort_string, $predecessor_sort_string ) =
                        map {
                        join q{}, map {
                            length $_ == N_FORMAT_WIDTH
                                ? ( ~$_ )
                                . ( "\0" x NULL_SORT_ELEMENT_FILL_WIDTH )
                                : ~$_
                            }
                            sort map { pack 'N*', @{$_} }
                            @{$_}
                        } ( $cause_sort_elements,
                        $predecessor_sort_elements );
                    $and_node_iteration
                        ->[Marpa::Internal::And_Iteration::CURRENT_CHILD] =
                        $cause_sort_string ge $predecessor_sort_string
                        ? Marpa::Internal::And_Node::CAUSE
                        : Marpa::Internal::And_Node::PREDECESSOR;

                } ## end if ( defined $cause and defined $predecessor )

            } ## end when (Marpa::Internal::Task::SETUP_AND_NODE)

            when (Marpa::Internal::Task::RESET_OR_TREE) {
                my ( $or_node_id, $visited ) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh}
                        "Task: RESET_OR_TREE from #$or_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                my $or_node = $or_nodes->[$or_node_id];
                $visited //= {};
                my @unvisited_children =
                    grep { !( $visited->{$_}++ ) }
                    @{ $or_node->[Marpa::Internal::Or_Node::CHILD_IDS] };
                push @tasks,
                    [ Marpa::Internal::Task::RESET_OR_NODE, $or_node_id ],
                    map {
                    [ Marpa::Internal::Task::RESET_AND_TREE, $_, $visited ]
                    } @unvisited_children;
            } ## end when (Marpa::Internal::Task::RESET_OR_TREE)

            when (Marpa::Internal::Task::RESET_AND_TREE) {
                my ( $and_node_id, $visited ) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh}
                        "Task: RESET_AND_TREE from #$and_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                my $and_node = $and_nodes->[$and_node_id];

                push @tasks,
                    [ Marpa::Internal::Task::RESET_AND_NODE, $and_node_id ],
                    map {
                    [   Marpa::Internal::Task::RESET_OR_TREE,
                        $_->[Marpa::Internal::Or_Node::ID],
                        $visited
                    ]
                    }
                    grep { defined $_ } @{$and_node}[
                    Marpa::Internal::And_Node::CAUSE,
                    Marpa::Internal::And_Node::PREDECESSOR
                    ];

            } ## end when (Marpa::Internal::Task::RESET_AND_TREE)

            when (Marpa::Internal::Task::ITERATE_AND_TREE) {
                my ($and_node_id) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh}
                        "Task: ITERATE_AND_TREE from #$and_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                push @tasks,
                    [ Marpa::Internal::Task::SETUP_AND_NODE, $and_node_id ];

                # Iteration of and-node without child always results in
                # exhausted and-node
                my $current_child_field =
                    $and_iterations->[$and_node_id]
                    ->[Marpa::Internal::And_Iteration::CURRENT_CHILD];
                if ( not defined $current_child_field ) {
                    $and_iterations->[$and_node_id] = undef;
                    break;
                }

                my $and_node = $and_nodes->[$and_node_id];

                my $cause = $and_node->[Marpa::Internal::And_Node::CAUSE];
                my $predecessor =
                    $and_node->[Marpa::Internal::And_Node::PREDECESSOR];
                if ( defined $cause and defined $predecessor ) {
                    push @tasks,
                        [
                        Marpa::Internal::Task::ITERATE_AND_TREE_2,
                        $and_node_id
                        ];
                } ## end if ( defined $cause and defined $predecessor )

                push @tasks,
                    [
                    Marpa::Internal::Task::ITERATE_OR_TREE,
                    $and_node->[$current_child_field]
                        ->[Marpa::Internal::Or_Node::ID]
                    ];

            } ## end when (Marpa::Internal::Task::ITERATE_AND_TREE)

            when (Marpa::Internal::Task::ITERATE_AND_TREE_2) {

                # We always have both a cause and a predecessor if we are
                # in this task.

                my ($and_node_id) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh}
                        "Task: ITERATE_AND_TREE_2 from #$and_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                my $and_node = $and_nodes->[$and_node_id];

                # Iteration of and-node without child always results in
                # exhausted and-node
                my $current_child_field =
                    $and_iterations->[$and_node_id]
                    ->[Marpa::Internal::And_Iteration::CURRENT_CHILD];

                # if the current child is not exhausted, the last task
                # successfully iterated it.  So SETUP_AND_NODE
                # (which is already on the tasks stack) is all
                # that is needed.
                break
                    if defined $or_iterations->[
                        $and_node->[$current_child_field]
                        ->[Marpa::Internal::Or_Node::ID]
                    ];

                my $other_child_id = $and_node->[
                    $current_child_field == Marpa::Internal::And_Node::CAUSE
                    ? Marpa::Internal::And_Node::PREDECESSOR
                    : Marpa::Internal::And_Node::CAUSE
                ]->[Marpa::Internal::Or_Node::ID];

                push @tasks,
                    [
                    Marpa::Internal::Task::ITERATE_AND_TREE_3, $and_node_id
                    ],
                    [
                    Marpa::Internal::Task::ITERATE_OR_TREE,
                    $other_child_id
                    ];

            } ## end when (Marpa::Internal::Task::ITERATE_AND_TREE_2)

            when (Marpa::Internal::Task::ITERATE_AND_TREE_3) {

                # We always have both a cause and a predecessor if we are
                # in this task.

                my ($and_node_id) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh}
                        "Task: ITERATE_AND_TREE_3 from #$and_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                my $and_node = $and_nodes->[$and_node_id];

                my @exhausted_children = grep {
                    not defined
                        $or_iterations->[ $_->[Marpa::Internal::Or_Node::ID] ]
                    } @{$and_node}[
                    Marpa::Internal::And_Node::CAUSE,
                    Marpa::Internal::And_Node::PREDECESSOR
                    ];

                # If both children exhausted, this and node is exhausted
                # Let SETUP_AND_NODE (which is already on the tasks stack)
                # deal with that.
                break if @exhausted_children >= 2;

                push @tasks,
                    [
                    Marpa::Internal::Task::RESET_OR_TREE,
                    $exhausted_children[0]->[Marpa::Internal::Or_Node::ID]
                    ];

            } ## end when (Marpa::Internal::Task::ITERATE_AND_TREE_3)

            when (Marpa::Internal::Task::ITERATE_OR_NODE) {
                my ($or_node_id) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh} "Task: ITERATE_OR_NODE #$or_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                }

                my $and_choices = $or_iterations->[$or_node_id];

                my $current_and_choice = $and_choices->[-1];
                my $current_and_node_id =
                    $current_and_choice->[Marpa::Internal::And_Choice::ID];
                my $current_and_iteration =
                    $and_iterations->[$current_and_node_id];

                # If the current and-choice is exhausted ...
                if ( not defined $current_and_iteration ) {
                    pop @{$and_choices};

                    # If there are no more choices, the or-node is exhausted ...
                    if ( scalar @{$and_choices} == 0 ) {
                        $or_iterations->[$or_node_id] = undef;
                        break;
                    }

                    # Thaw out the current and-choice,
                    push @tasks,
                        [
                        Marpa::Internal::Task::THAW_TREE,
                        $and_choices->[-1]
                        ];

                    break

                } ## end if ( not defined $current_and_iteration )

                # If we are here the current and-choice is not exhausted,
                # but it may have been iterated to the point where it is
                # no longer the first in sort order.

                # Refresh and-choice's fields
                $current_and_choice->[Marpa::Internal::And_Choice::SORT_KEY] =
                    $current_and_iteration
                    ->[Marpa::Internal::And_Iteration::SORT_KEY];
                $current_and_choice->[Marpa::Internal::And_Choice::OR_MAP] =
                    $current_and_iteration
                    ->[Marpa::Internal::And_Iteration::OR_MAP];

                # If only one choice still active,
                # clearly no need to
                # worry about sorting alternatives.
                break if @{$and_choices} <= 1;

                my $current_sort_key = join q{}, map {
                    length $_ == N_FORMAT_WIDTH
                        ? ( ~$_ ) . ( "\0" x NULL_SORT_ELEMENT_FILL_WIDTH )
                        : ~$_
                    }
                    sort map { pack 'N*', @{$_} }
                    @{ $current_and_choice
                        ->[Marpa::Internal::And_Choice::SORT_KEY] };

                my $first_le_sort_key = (
                    List::Util::first {
                        (   join q{},
                            map {
                                length $_ == N_FORMAT_WIDTH
                                    ? ( ~$_ )
                                    . ( "\0" x NULL_SORT_ELEMENT_FILL_WIDTH )
                                    : ~$_
                                }
                                sort map { pack 'N*', @{$_} } @{
                                $current_and_choice
                                    ->[Marpa::Internal::And_Choice::SORT_KEY]
                                }
                        ) le $current_sort_key;
                    } ## end List::Util::first
                    reverse 0 .. ( $#{$and_choices} - 1 )
                );

                my $insert_point =
                    defined $first_le_sort_key ? $first_le_sort_key + 1 : 0;

                # If current choice would be inserted where it already
                # is now, we're done
                break if $insert_point == $#{$and_choices};

                my $former_current_choice = pop @{$and_choices};
                splice @{$and_choices}, $insert_point, 0,
                    $former_current_choice;

                push @tasks,
                    [ Marpa::Internal::Task::THAW_TREE, $and_choices->[1] ],
                    [
                    Marpa::Internal::Task::FREEZE_TREE,
                    $former_current_choice
                    ];

            } ## end when (Marpa::Internal::Task::ITERATE_OR_NODE)

            when (Marpa::Internal::Task::ITERATE_OR_TREE) {
                my ($or_node_id) = @{$task_entry};

                if ($trace_tasks) {
                    print {$trace_fh} "Task: ITERATE_OR_TREE #$or_node_id; ",
                        ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                }

                my $or_node = $or_nodes->[$or_node_id];

                my $current_and_node_id =
                    $or_iterations->[$or_node_id]->[-1]
                    ->[Marpa::Internal::And_Choice::ID];
                push @tasks,
                    [ Marpa::Internal::Task::ITERATE_OR_NODE, $or_node_id ],
                    [
                    Marpa::Internal::Task::ITERATE_AND_TREE,
                    $current_and_node_id
                    ];
            } ## end when (Marpa::Internal::Task::ITERATE_OR_TREE)

            when (Marpa::Internal::Task::FREEZE_TREE) {
                my ($and_choice) = @{$task_entry};

                my $and_node_id =
                    $and_choice->[Marpa::Internal::And_Choice::ID];
                if ($trace_tasks) {
                    printf {$trace_fh}
                        "Task: FREEZE_TREE; and-node-id: %d; %d tasks pending\n",
                        $and_node_id, ( scalar @tasks )
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                my $or_map =
                    $and_choice->[Marpa::Internal::And_Choice::OR_MAP];

                # Add frozen iteration
                my @or_slice = map { $_->[0] } @{$or_map};
                my @and_slice = ( $and_node_id, map { $_->[1] } @{$or_map} );

                my @or_values  = @{$or_iterations}[@or_slice];
                my @and_values = @{$and_iterations}[@and_slice];

                $and_choice->[Marpa::Internal::And_Choice::FROZEN_ITERATION] =
                    Storable::freeze(
                    [ \@and_slice, \@and_values, \@or_slice, \@or_values ] );

            } ## end when (Marpa::Internal::Task::FREEZE_TREE)

            when (Marpa::Internal::Task::THAW_TREE) {
                my ($and_choice) = @{$task_entry};

                my $and_node_id =
                    $and_choice->[Marpa::Internal::And_Choice::ID];

                if ($trace_tasks) {
                    printf {$trace_fh}
                        "Task: THAW_TREE; and-node-id: %d; %d tasks pending\n",
                        $and_node_id, ( scalar @tasks )
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                # If we are here, the current choice is new
                # It must be thawed and its frozen iteration thrown away
                my ( $and_slice, $and_values, $or_slice, $or_values ) = @{
                    Storable::thaw(
                        $and_choice
                            ->[Marpa::Internal::And_Choice::FROZEN_ITERATION]
                    )
                    };

                @{$and_iterations}[ @{$and_slice} ] = @{$and_values};
                @{$or_iterations}[ @{$or_slice} ]   = @{$or_values};

                # Refresh and-choice's fields
                my $current_and_iteration = $and_iterations->[$and_node_id];
                $and_choice->[Marpa::Internal::And_Choice::SORT_KEY] =
                    $current_and_iteration
                    ->[Marpa::Internal::And_Iteration::SORT_KEY];

                $and_choice->[Marpa::Internal::And_Choice::OR_MAP] =
                    $current_and_iteration
                    ->[Marpa::Internal::And_Iteration::OR_MAP];

                # Once it's unfrozen, it's subject to change, so the
                # the frozen version will become invalid.
                # We undef it.
                $and_choice->[Marpa::Internal::And_Choice::FROZEN_ITERATION] =
                    undef;

            } ## end when (Marpa::Internal::Task::THAW_TREE)

            when (Marpa::Internal::Task::EVALUATE) {

                if ($trace_tasks) {
                    print {
                        $trace_fh
                    }
                    'Task: EVALUATE; ', ( scalar @tasks ), " tasks pending\n"
                        or Marpa::exception('print to trace handle failed');
                } ## end if ($trace_tasks)

                # If the top or node is exhausted, we are done
                my $top_or_iteration = $or_iterations->[0];
                return if not $top_or_iteration;

                # Initialize with the top or-node's and-choice
                my $top_and_choice = $top_or_iteration->[-1];

                # Position 0 is top and-node id
                my @or_node_choices = (
                    $and_nodes->[
                        $top_and_choice->[Marpa::Internal::And_Choice::ID]
                    ]
                );
                $#or_node_choices = $#{$or_nodes};

                for my $or_mapping (
                    @{  $top_and_choice->[Marpa::Internal::And_Choice::OR_MAP]
                    }
                    )
                {
                    my ( $or_node_id, $and_node_id ) = @{$or_mapping};
                    $or_node_choices[$or_node_id] =
                        $and_nodes->[$and_node_id];
                } ## end for my $or_mapping ( @{ $top_and_choice->[...]})

                # Write the and-nodes out in preorder
                my @preorder = ();

                # Initialize the work list to the top and-node
                my @work_list = ( $or_node_choices[0] );

                AND_NODE: while ( scalar @work_list ) {
                    my $and_node = pop @work_list;
                    push @work_list, map {
                        $or_node_choices[ $_->[Marpa::Internal::Or_Node::ID] ]
                        } grep { defined $_ }
                        map    { $and_node->[$_] }
                        ( Marpa::Internal::And_Node::PREDECESSOR,
                        Marpa::Internal::And_Node::CAUSE
                        );
                    push @preorder, $and_node;
                } ## end while ( scalar @work_list )

                my @evaluation_stack   = ();
                my @virtual_rule_stack = ();

                TREE_NODE: for my $and_node ( reverse @preorder ) {

                    if ( $trace_values >= 3 ) {
                        for my $i ( reverse 0 .. $#evaluation_stack ) {
                            printf {$trace_fh} 'Stack position %3d:', $i
                                or Marpa::exception(
                                'print to trace handle failed');
                            print {$trace_fh} q{ },
                                Data::Dumper->new( [ $evaluation_stack[$i] ] )
                                ->Terse(1)->Dump
                                or Marpa::exception(
                                'print to trace handle failed');
                        } ## end for my $i ( reverse 0 .. $#evaluation_stack )
                    } ## end if ( $trace_values >= 3 )

                    my $value_ref =
                        $and_node->[Marpa::Internal::And_Node::VALUE_REF];

                    if ( defined $value_ref ) {

                        push @evaluation_stack, $value_ref;

                        if ($trace_values) {
                            print {$trace_fh}
                                'Pushed value from ',
                                $and_node->[Marpa::Internal::And_Node::TAG],
                                ': ',
                                Data::Dumper->new( [ ${$value_ref} ] )
                                ->Terse(1)->Dump
                                or Marpa::exception(
                                'print to trace handle failed');
                        } ## end if ($trace_values)

                    }    # defined $value_ref

                    my $evaluator_data = $and_node
                        ->[Marpa::Internal::And_Node::EVALUATOR_DATA];

                    next TREE_NODE if not defined $evaluator_data;

                    my $ops = $evaluator_data
                        ->[Marpa::Internal::Evaluator_Rule::OPS];
                    my $current_data = [];
                    my $op_ix        = 0;
                    while ( $op_ix < scalar @{$ops} ) {
                        given ( $ops->[ $op_ix++ ] ) {

                            when (Marpa::Internal::Evaluator_Op::ARGC) {
                                my $argc = $ops->[ $op_ix++ ];
                                $current_data =
                                    [ map { ${$_} }
                                        ( splice @evaluation_stack, -$argc )
                                    ];
                                if ($trace_values) {
                                    my $rule_id =
                                        $and_node
                                        ->[ Marpa::Internal::And_Node::RULE_ID
                                        ];
                                    my $rule = $rules->[$rule_id];
                                    say {$trace_fh}
                                        'Popping ',
                                        $argc,
                                        ' values to evaluate ',
                                        $and_node
                                        ->[Marpa::Internal::And_Node::TAG],
                                        ', rule: ', Marpa::brief_rule($rule)
                                        or Marpa::exception(
                                        'Could not print to trace file');
                                } ## end if ($trace_values)

                            } ## end when (Marpa::Internal::Evaluator_Op::ARGC)

                            when ( Marpa::Internal::Evaluator_Op::VIRTUAL_HEAD
                                )
                            {
                                my $real_symbol_count = $ops->[ $op_ix++ ];

                                if ($trace_values) {
                                    my $rule_id =
                                        $and_node
                                        ->[ Marpa::Internal::And_Node::RULE_ID
                                        ];
                                    my $rule = $rules->[$rule_id];
                                    say {$trace_fh}
                                        'Head of Virtual Rule: ',
                                        $and_node
                                        ->[Marpa::Internal::And_Node::TAG],
                                        ', rule: ', Marpa::brief_rule($rule),
                                        "\nAdding $real_symbol_count symbols; currently ",
                                        ( scalar @virtual_rule_stack ),
                                        ' rules; ',
                                        $virtual_rule_stack[-1], ' symbols'
                                        or Marpa::exception(
                                        'Could not print to trace file');
                                } ## end if ($trace_values)

                                ### assert: scalar @virtual_rule_stack

                                $real_symbol_count += pop @virtual_rule_stack;
                                $current_data = [
                                    map { ${$_} } (
                                        splice @evaluation_stack,
                                        -$real_symbol_count
                                    )
                                ];

                            } ## end when ( Marpa::Internal::Evaluator_Op::VIRTUAL_HEAD )

                            when
                                ( Marpa::Internal::Evaluator_Op::VIRTUAL_HEAD_NO_SEP
                                )
                            {
                                my $real_symbol_count = $ops->[ $op_ix++ ];

                                if ($trace_values) {
                                    my $rule_id =
                                        $and_node
                                        ->[ Marpa::Internal::And_Node::RULE_ID
                                        ];
                                    my $rule = $rules->[$rule_id];
                                    say {$trace_fh}
                                        'Head of Virtual Rule (discards separation): ',
                                        $and_node
                                        ->[Marpa::Internal::And_Node::TAG],
                                        ', rule: ', Marpa::brief_rule($rule),
                                        "\nAdding $real_symbol_count symbols; currently ",
                                        ( scalar @virtual_rule_stack ),
                                        ' rules; ',
                                        $virtual_rule_stack[-1], ' symbols'
                                        or Marpa::exception(
                                        'Could not print to trace file');
                                } ## end if ($trace_values)

                                $real_symbol_count += pop @virtual_rule_stack;
                                ### real symbol count: $real_symbol_count
                                my $base = ( scalar @evaluation_stack )
                                    - $real_symbol_count;
                                $current_data = [
                                    map { ${$_} } @evaluation_stack[
                                        map { $base + 2 * $_ } (
                                            0 .. ( $real_symbol_count + 1 )
                                                / 2 - 1
                                        )
                                    ]
                                ];

                                ### length of current data: (scalar @{$current_data})

                                # truncate the evaluation stack
                                $#evaluation_stack = $base - 1;

                            } ## end when ( ...)

                            when
                                ( Marpa::Internal::Evaluator_Op::VIRTUAL_KERNEL
                                )
                            {
                                my $real_symbol_count = $ops->[ $op_ix++ ];
                                $virtual_rule_stack[-1] += $real_symbol_count;

                                if ($trace_values) {
                                    my $rule_id =
                                        $and_node
                                        ->[ Marpa::Internal::And_Node::RULE_ID
                                        ];
                                    my $rule = $rules->[$rule_id];
                                    say {$trace_fh}
                                        'Virtual Rule: ',
                                        $and_node
                                        ->[Marpa::Internal::And_Node::TAG],
                                        ', rule: ', Marpa::brief_rule($rule),
                                        "\nAdding $real_symbol_count, now ",
                                        ( scalar @virtual_rule_stack ),
                                        ' rules; ',
                                        $virtual_rule_stack[-1], ' symbols'
                                        or Marpa::exception(
                                        'Could not print to trace file');
                                } ## end if ($trace_values)

                            } ## end when ( Marpa::Internal::Evaluator_Op::VIRTUAL_KERNEL )

                            when (Marpa::Internal::Evaluator_Op::VIRTUAL_TAIL)
                            {
                                my $real_symbol_count = $ops->[ $op_ix++ ];

                                if ($trace_values) {
                                    my $rule_id =
                                        $and_node
                                        ->[ Marpa::Internal::And_Node::RULE_ID
                                        ];
                                    my $rule = $rules->[$rule_id];
                                    say {$trace_fh}
                                        'New Virtual Rule: ',
                                        $and_node
                                        ->[Marpa::Internal::And_Node::TAG],
                                        ', rule: ', Marpa::brief_rule($rule),
                                        "\nSymbol count is $real_symbol_count, now ",
                                        ( scalar @virtual_rule_stack + 1 ),
                                        ' rules',
                                        or Marpa::exception(
                                        'Could not print to trace file');
                                } ## end if ($trace_values)

                                push @virtual_rule_stack, $real_symbol_count;

                            } ## end when (Marpa::Internal::Evaluator_Op::VIRTUAL_TAIL)

                            when
                                ( Marpa::Internal::Evaluator_Op::CONSTANT_RESULT
                                )
                            {
                                my $result = $ops->[ $op_ix++ ];
                                if ($trace_values) {
                                    print {$trace_fh}
                                        'Constant result: Pushing 1 value on stack: ',
                                        Data::Dumper->new( [$result] )
                                        ->Terse(1)->Dump
                                        or Marpa::exception(
                                        'Could not print to trace file');
                                } ## end if ($trace_values)
                                push @evaluation_stack, $result;
                            } ## end when ( Marpa::Internal::Evaluator_Op::CONSTANT_RESULT)

                            when (Marpa::Internal::Evaluator_Op::CALL) {
                                my $closure = $ops->[ $op_ix++ ];
                                my $result;

                                my @warnings;
                                my $eval_ok;
                                DO_EVAL: {
                                    local $SIG{__WARN__} = sub {
                                        push @warnings,
                                            [ $_[0], ( caller 0 ) ];
                                    };

                                    $eval_ok = eval {
                                        $result =
                                            $closure->( @{$current_data} );
                                        1;
                                    };
                                } ## end DO_EVAL:

                                if ( not $eval_ok or @warnings ) {
                                    my $rule_id =
                                        $and_node
                                        ->[ Marpa::Internal::And_Node::RULE_ID
                                        ];
                                    my $rule        = $rules->[$rule_id];
                                    my $fatal_error = $EVAL_ERROR;
                                    my $code =
                                        $evaluator_rules->[$rule_id]->[
                                        Marpa::Internal::Evaluator_Rule::CODE
                                        ];
                                    Marpa::Internal::code_problems(
                                        {   fatal_error => $fatal_error,
                                            grammar     => $grammar,
                                            eval_ok     => $eval_ok,
                                            warnings    => \@warnings,
                                            where       => 'computing value',
                                            long_where =>
                                                'computing value for rule: '
                                                . Marpa::brief_rule($rule),
                                        }
                                    );
                                } ## end if ( not $eval_ok or @warnings )

                                if ($trace_values) {
                                    print {$trace_fh}
                                        'Calculated and pushed value: ',
                                        Data::Dumper->new( [$result] )
                                        ->Terse(1)->Dump
                                        or Marpa::exception(
                                        'print to trace handle failed');
                                } ## end if ($trace_values)

                                push @evaluation_stack, \$result;

                            } ## end when (Marpa::Internal::Evaluator_Op::CALL)

                            default {
                                Marpa::Exception("Unknown evaluator Op: $_");
                            }

                        } ## end given
                    } ## end while ( $op_ix < scalar @{$ops} )

                }    # TREE_NODE

                ### sort_key: $evaler->show_sort_keys()

                return pop @evaluation_stack;

            } ## end when (Marpa::Internal::Task::EVALUATE)
            ## End EVALUATE

            default {
                Carp::confess("Internal error: Unknown task, number $task");
            }
        } ## end given

    } ## end while (1)

    Carp::confess('Internal error: Should not reach here');

} ## end sub Marpa::Evaluator::value

1;

__END__

=pod

=head1 NAME

Marpa::Evaluator - Marpa Evaluator Objects

=head1 SYNOPSIS

=begin Marpa::Test::Display:

## next 3 displays
in_file($_, 't/equation_s.t')

=end Marpa::Test::Display:

    my $fail_offset = $lexer->text('2-0*3+1');
    if ( $fail_offset >= 0 ) {
        Marpa::exception("Parse failed at offset $fail_offset");
    }

    my $evaler = Marpa::Evaluator->new( { recognizer => $recce } );
    Marpa::exception('Parse failed') if not $evaler;

    my $i = 0;
    while ( defined( my $value = $evaler->value() ) ) {
        my $value = ${$value};
        Test::More::ok( $expected_value{$value}, "Value $i (unspecified order)" );
        delete $expected_value{$value};
        $i++;
    } ## end while ( defined( my $value = $evaler->value() ) )

=head1 DESCRIPTION

Parses are found and evaluated by Marpa's evaluator objects.
Evaluators are created with the C<new> constructor,
which requires a Marpa recognizer object
as an argument.

Marpa allows ambiguous parses, so evaluator objects are iterators.
Iteration is performed with the C<value> method,
which returns a reference to the value of the next parse.
Often only the first parse is needed,
in which case the C<value> method can be called just once.

By default, the C<new> constructor clones the recognizer, so that
multiple evaluators do not interfere with each other.

=head2 Null Values

A "null value" is the value used for a symbol when it is nulled in a parse.
By default, the null value is a Perl undefined.
The default null value is a Marpa option (C<default_null_value>) and can be reset.

Each symbol can have its own null symbol value.
The null symbol value for any symbol is calculated using the null symbol action.
The B<null symbol action> for a symbol is the action
specified for the empty rule with that symbol on its left hand side.
The null symbol action is B<not> a rule action.
It's a property of the symbol, and applies whenever the symbol is nulled,
even when the symbol's empty rule is not involved.

For example, in MDL,
the following says that whenever the symbol C<A> is nulled,
its value should be a string that says it is missing.

=begin Marpa::Test::Commented_out_Display:

## next display
in_file($_, 'example/null_value.marpa');

=end Marpa::Test::Commented_out_Display:

=begin Marpa::Test::Display:

## skip display

=end Marpa::Test::Display:

    A: . q{'A is missing'}.

Null symbol actions are evaluated differently from rule actions.
Null symbol actions are run at evaluator creation time and the value of the result
at that point
becomes fixed as the null symbol value.
This is not the case with rule actions.
During the creation of the evaluator object,
rule actions are B<compiled into closures>.
During parse evaluation,
whenever a node for that rule needs its value recalculated,
the compiled rule closure is run.
A compiled rule closure
can produce a different value every time it runs.

I treat null symbol actions differently for efficiency.
They have no child values,
and a fixed value is usually what is wanted.
If you want to calculate a symbol's null value with a closure run at parse evaluation time,
the null symbol action can return a reference to a closure.
Rules with that nullable symbol in their right hand side
can then be set up to run that closure.

=head3 Evaluating Null Derivations

A null derivation may consist of many steps and may contain many symbols.
Marpa's rule is that the value of a null derivation is
the null symbol value of the B<highest null symbol> in that
derivation.
This section describes in detail how a parse is evaluated,
focusing on what happens when nulled symbols are involved.

The first step in evaluating a parse is to determine which nodes
B<count> for the purpose of evaluation, and which do not.
Marpa follows these principles:

=over 4

=item 1

The start node always counts.

=item 2

Nodes count if they derive a non-empty sentence.

=item 3

All other nodes do not count.

=item 4

In evaluating a parse, Marpa uses only nodes that count.

=back

These are all consequences of the principles above:

=over 4

=item 1

The value of null derivation is the value of the highest null symbol in it.

=item 2

A nulled node counts only if it is the start node.

=item 3

The value of a null parse is the null value of the start symbol.

=back

If you think some of the rules or symbols represented by nodes that don't count
are important in your grammar,
Marpa can probably accommodate your ideas.
First,
for every nullable symbol,
determine how to calculate the value which your semantics produces
when that nullable symbol is a "highest null symbol".
If it's a constant, write a null action for that symbol which returns that constant.
If your semantics do not produce a constant value by evaluator creation time,
write a null action which returns a reference to a closure
and arrange to have that closure run by the parent node.

=head3 Example

Suppose a grammar has these rules

=begin Marpa::Test::Commented_Out_Display:

## start display
## next display
in_file($_, 'example/null_value.marpa');

=end Marpa::Test::Commented_Out_Display:

=begin Marpa::Test::Display:

## start display
## skip display

=end Marpa::Test::Display:

    THIS NEEDS TO CHANGE SO THAT IT NO LONGER USES MDL.

    S: A, Y. q{ $_[0] . ", but " . $_[1] }. # Call me the start rule
    note: you can also call me Rule 0.

    A: . q{'A is missing'}. # Call me Rule 1

    A: B, C. q{"I'm sometimes null and sometimes not"}. # Call me Rule 2

    B: . q{'B is missing'}. # Call me Rule 3

    C: . q{'C is missing'}. # Call me Rule 4

    C: Y.  q{'C matches Y'}. # Call me Rule 5

    Y: /Z/. q{'Zorro was here'}. # Call me Rule 6

=begin Marpa::Test::Display:

## end display

=end Marpa::Test::Display:

In the above MDL, the Perl 5 regex "C</Z/>" occurs on the rhs of Rule 6.
Where a regex is on the rhs of a rule, MDL internally creates a terminal symbol
to match that regex in the input text.
In this example, the MDL internal terminal symbol that
matches input text using the regex
C</Z/> will be called C<Z>.

If the input text is the Perl 5 string "C<Z>",
the derivation is as follows:

=begin Marpa::Test::Display:

## skip 2 displays

=end Marpa::Test::Display:

    S -> A Y      (Rule 0)
      -> A "Z"    (Y produces "Z", by Rule 6)
      -> B C "Z"  (A produces B C, by Rule 2)
      -> B "Z"    (C produces the empty string, by Rule 4)
      -> "Z"      (B produces the empty string, by Rule 3)

The parse tree can be described as follows:

    Node 0 (root): S (2 children, nodes 1 and 4)
        Node 1: A (2 children, nodes 2 and 3)
	    Node 2: B (matches empty string)
	    Node 3: C (matches empty string)
	Node 4: Y (1 child, node 5)
	    Node 5: "Z" (terminal node)

Here's a table showing, for each node, its lhs symbol,
the sentence it derives, and
its value.

=begin Marpa::Test::Display:

## skip 2 displays

=end Marpa::Test::Display:

                        Symbol      Sentence     Value
                                    Derived

    Node 0:                S         "Z"         "A is missing, but Zorro is here"
        Node 1:            A         empty       "A is missing"
	    Node 2:        B         empty       No value
	    Node 3:        C         empty       No value
	Node 4:            Y         "Z"         "Zorro was here"
	    Node 5:        -         "Z"         "Z"

In this derivation,
nodes 1, 2 and 3 derive the empty sentence.
None of them are the start node so that none of them count.

Nodes 0, 4 and 5 all derive the same non-empty sentence, C<Z>,
so they all count.
Node 0 is the start node, so it would have counted in any case.

Since node 5 is a terminal node, it's value comes from the lexer.
Where the lexing is done with a Perl 5 regex,
the value will be the Perl 5 string that the regex matched.
In this case it's the string "C<Z>".

Node 4 is not nulled,
so it is evaluated normally, using the rule it represents.
That is rule 6.
The action for rule 6 returns "C<Zorro was here>", so that
is the value of node 4.
Node 4 has a child node, node 5, but rule 6's action pays no
attention to child values.
The action for each rule is free to use or not use child values.

Nodes 1, 2 and 3 don't count and will all remain unevaluated.
The only rule left to be evaluated
is node 0, the start node.
It is not nulled, so
its value is calculated using the action for the rule it
represents (rule 0).

Rule 0's action uses the values of its child nodes.
There are two child nodes and their values are
elements 0 and 1 in the C<@_> array of the action.
The child value represented by the symbol C<Y>,
C<< $_[1] >>, comes from node 4.
From the table above, we can see that that value was
"C<Zorro was here>".

The first child value is represented by the symbol C<A>,
which is nulled.
For nulled symbols, we must use the null symbol value.
Null symbol values for each symbol can be explicitly set
by specifying an rule action for an empty rule with that symbol
as its lhs.
For symbol C<A>,
this was done in Rule 1.
Rule 1's action evaluates to the Perl 5 string
"C<A is missing>".

Even though rule 1's action plays a role in calculating the value of this parse,
rule 1 is not actually used in the derivation.
No node in the derivation represents rule 1.
Rule 1's action is used because it is the null symbol action for
the symbol C<A>.

Now that we have both child values, we can use rule 0's action
to calculate the value of node 0.
That value is "C<A is missing, but Zorro was here>",
This becomes the value of C<S>, rule 0's left hand side symbol and
the start symbol of the grammar.
A parse has the value of its start symbol,
so "C<A is missing, but Zorro was here>" is also
the value of the parse.

=head2 Cloning

The C<new> constructor requires a recognizer object to be one of its arguments.
By default, the C<new> constructor clones the recognizer object.
This is done so that evaluators do not interfere with each other by
modifying the same data.
Cloning is the default behavior, and is always safe.

While safe, cloning does impose an overhead in memory and time.
This can be avoided by using the C<clone> option with the C<new>
constructor.
Not cloning is safe if you know that the recognizer object will not be shared by another evaluator.
You must also be sure that the
underlying grammar object is not being shared by multiple recognizers.

It is very common for a Marpa program to have a simple
structure, where no more than one recognizer is created from any grammar,
and no more than one evaluator is created from any recognizer.
When this is the case, cloning is unnecessary.

=head1 METHODS

=head2 new

=begin Marpa::Test::Display:

## next display
in_file($_, 't/equation_s.t');

=end Marpa::Test::Display:

    my $evaler = Marpa::Evaluator->new(
      { recognizer => $recce }
    );

Z<>

=begin Marpa::Test::Display:

## next display
in_file($_, 'author.t/misc.t');

=end Marpa::Test::Display:

    my $evaler = Marpa::Evaluator->new( {
        recce => $recce,
        end => $location,
        clone => 0,
    } );

The C<new> method's one, required, argument is a hash reference of named
arguments.
The C<new> method either returns a new evaluator object or throws an exception.
The C<recognizer> option is required,
Its value must be a recognizer object which has finished recognizing a text.
The C<recce> option is a synonym for the the C<recognizer> option.

By default,
parsing ends at the default end of parsing,
which was set in the recognizer.
If an C<end> option is specified, 
it will be used as the number of the earleme at which to end parsing.

If the C<clone> argument is set to 1,
C<new> clones the recognizer object, so that multiple
evaluators do not interfere with each other's data.
This is the default and is always safe.
If C<clone> is set to 0, the evaluator will work directly with
the recognizer object which was its argument.
See L<above|/"Cloning"> for more detail.

Marpa options can also
be named arguments to C<new>.
For these, see L<Marpa::Doc::Options>.

=head2 set

=begin Marpa::Test::Display:

## next display
is_file($_, 'author.t/misc.t', 'evaler set snippet')

=end Marpa::Test::Display:

    $evaler->set( { trace_values => 1 } );

The C<set> method takes as its one, required, argument a reference to a hash of named arguments.
It allows Marpa options
to be specified for an evaluator object.
Relatively few Marpa options are not available at
evaluation time.
The options which are available
are mainly those which control evaluation time tracing.
C<set> either returns true or throws an exception.

=head2 value

=begin Marpa::Test::Display:

## next display
in_file($_, 't/ah2.t');

=end Marpa::Test::Display:

    my $result = $evaler->value();

Iterates the evaluator object, returning a reference to the value of the next parse.
If there are no more parses, returns undefined.
Successful parses may evaluate to a Perl 5 undefined,
which the C<value> method will return as a reference to an undefined.
Failures are thrown as exceptions.

When the order of parses is important,
it may be manipulated by assigning priorities to the rules and
terminals.
If a symbol can both match a token and derive a rule,
the token match always takes priority.
Otherwise the parse order is implementation dependent.

A failed parse does not always show up as an exhausted parse in the recognizer.
Just because the recognizer was active when it was used to create
the evaluator, does not mean that the input matches the grammar.
If it does not match, there will be no parses and the C<value> method will
return undefined the first time it is called.

=head1 SUPPORT

See the L<support section|Marpa/SUPPORT> in the main module.

=head1 AUTHOR

Jeffrey Kegler

=head1 LICENSE AND COPYRIGHT

Copyright 2007 - 2009 Jeffrey Kegler

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl 5.10.0.

=cut
