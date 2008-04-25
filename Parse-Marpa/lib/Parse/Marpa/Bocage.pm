package Parse::Marpa::Internal::Bocage;
use 5.010_000;

use warnings;
## no critic
no warnings "recursion";
## use critic
use strict;
use integer;

package Parse::Marpa::Internal::Sapling;

use constant NAME     => 0;
use constant ITEM     => 1;
use constant RULE     => 2;
use constant POSITION => 3;
use constant SYMBOL   => 4;

package Parse::Marpa::Internal::Branch;

use constant PREDECESSOR => 0;
use constant CAUSE       => 1;
use constant VALUE       => 2;
use constant CLOSURE     => 3;

package Parse::Marpa::Internal::Shrub;

use constant NAME => 0;
use constant BRANCHES => 1;

package Parse::Marpa::Internal::Bocage;

use constant RECOGNIZER  => 0;
use constant PARSE_COUNT => 1;    # number of parses in an ambiguous parse
use constant SHRUBS      => 2;

use Scalar::Util qw(weaken);
use Data::Dumper;
use Carp;

sub Parse::Marpa::Bocage::new {
    my $class         = shift;
    my $recognizer    = shift;
    my $parse_set_arg = shift;
    my $self          = bless [], $class;

    my $recognizer_class = ref $recognizer;
    my $right_class      = 'Parse::Marpa::Recognizer';
    croak(
        "Don't parse argument is class: $recognizer_class; should be: $right_class"
    ) unless $recognizer_class eq $right_class;

    # croak("Recognizer already in use by bocage")
    # if
    # defined $recognizer->[Parse::Marpa::Internal::Recognizer::BOCAGE];

    # weaken( $recognizer->[Parse::Marpa::Internal::Recognizer::BOCAGE] =
    # $self );

    my ( $grammar, $earley_sets, ) = @{$recognizer}[
        Parse::Marpa::Internal::Recognizer::GRAMMAR,
        Parse::Marpa::Internal::Recognizer::EARLEY_SETS,
    ];

    ## no critic ( Variables::ProhibitPackageVars )
    local ($Parse::Marpa::Internal::This::grammar) = $grammar;
    ## use critic

    my $tracing = $grammar->[Parse::Marpa::Internal::Grammar::TRACING];
    my $trace_fh;
    my $trace_iteration_changes;

    if ($tracing) {
        $trace_fh =
            $grammar->[Parse::Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
        $trace_iteration_changes = $grammar
            ->[Parse::Marpa::Internal::Grammar::TRACE_ITERATION_CHANGES];
    }

    local ($Data::Dumper::Terse) = 1;

    my $online = $grammar->[Parse::Marpa::Internal::Grammar::ONLINE];
    if ( not $online ) {
        Parse::Marpa::Recognizer::end_input($recognizer);
    }
    my $default_parse_set =
        $recognizer->[Parse::Marpa::Internal::Recognizer::DEFAULT_PARSE_SET];

    $self->[Parse::Marpa::Internal::Bocage::PARSE_COUNT] = 0;
    $self->[Parse::Marpa::Internal::Bocage::SHRUBS] = [];

    my $current_parse_set = $parse_set_arg // $default_parse_set;

    # Look for the start item and start rule
    my $earley_set = $earley_sets->[$current_parse_set];

    my $start_item;
    my $start_rule;
    my $start_state;

    EARLEY_ITEM: for my $item ( @{$earley_set} ) {
        $start_state =
            $item->[Parse::Marpa::Internal::Earley_item::STATE];
        $start_rule =
            $start_state->[Parse::Marpa::Internal::QDFA::START_RULE];
        next EARLEY_ITEM unless $start_rule;
	$start_item = $item;
        last EARLEY_ITEM;
    }

    return unless $start_rule;

    @{$recognizer}[
        Parse::Marpa::Internal::Recognizer::START_ITEM,
        Parse::Marpa::Internal::Recognizer::CURRENT_PARSE_SET,
        ]
        = ( $start_item, $current_parse_set );

    $self->[Parse::Marpa::Internal::Bocage::RECOGNIZER] = $recognizer;

    my $start_symbol = $start_rule->[Parse::Marpa::Internal::Rule::LHS];
    my ( $nulling, $null_value ) = @{$start_symbol}[
        Parse::Marpa::Internal::Symbol::NULLING,
        Parse::Marpa::Internal::Symbol::NULL_VALUE
    ];

    # deal with a null parse as a special case
    if ($nulling) {
        my $branch = [];
        $branch->[Parse::Marpa::Internal::Branch::VALUE] =
            $start_symbol->[Parse::Marpa::Internal::Symbol::NULL_VALUE];
        $branch->[Parse::Marpa::Internal::Branch::CLOSURE] =
            $start_symbol->[Parse::Marpa::Internal::Rule::CLOSURE];

        my $shrub = [];
	$shrub->[Parse::Marpa::Internal::Shrub::NAME] =
            $start_item->[Parse::Marpa::Internal::Earley_item::NAME];
        $shrub->[Parse::Marpa::Internal::Shrub::BRANCHES] = [$branch];

        $self->[SHRUBS] = [$shrub];

        return $self;

    }    # if $nulling

    my @saplings;
    my %sapling_by_name;
    my $start_sapling = [];
    {
	my $name = $start_item->[Parse::Marpa::Internal::Earley_item::NAME];
	my $symbol_id = $start_symbol->[Parse::Marpa::Internal::Symbol::ID];
	$name .= 'L' . $symbol_id;
	$start_sapling->[Parse::Marpa::Internal::Sapling::NAME]   = $name;
    }
    $start_sapling->[Parse::Marpa::Internal::Sapling::ITEM]   = $start_item;
    $start_sapling->[Parse::Marpa::Internal::Sapling::SYMBOL] = $start_symbol;
    push @saplings, $start_sapling;

    my $i = 0;
    SAPLING: while (1) {

        my (
	    $sapling_name,
	    $item, $symbol, $rule, $position
	) = @{ $saplings[ $i++ ] }[
            Parse::Marpa::Internal::Sapling::NAME,
            Parse::Marpa::Internal::Sapling::ITEM,
            Parse::Marpa::Internal::Sapling::SYMBOL,
            Parse::Marpa::Internal::Sapling::RULE,
            Parse::Marpa::Internal::Sapling::POSITION,
        ];

        last SAPLING unless defined $item;

	# If we don't have a current rule, we need to get one or
	# more rules, and deduce the position and a new symbol from
	# them.
        my @rule_data;

        # If we have a rule and a position, get the current symbol
        if ( defined $position ) {

            my $symbol =
                $rule->[Parse::Marpa::Internal::Rule::RHS]->[$position];
            push @rule_data, [ $rule, $position, $symbol ];

        }
        else { # if not defined $position

            my $lhs_id = $symbol->[Parse::Marpa::Internal::Symbol::ID];
	    my $state = $item->[Parse::Marpa::Internal::Earley_item::STATE];
            for my $rule (
                @{  $state->[Parse::Marpa::Internal::QDFA::COMPLETE_RULES]
                        ->[$lhs_id];
                }
                )
            {

                my $rhs     = $rule->[Parse::Marpa::Internal::Rule::RHS];
                my $closure = $rule->[Parse::Marpa::Internal::Rule::CLOSURE];
                my $last_position = $#{$rhs};
                push @rule_data,
		    [ $rule, $last_position, $rhs->[$last_position], $closure ];

            }    # for my $rule

        } # not defined $position

        my @branches;

        my $item_name = $item->[Parse::Marpa::Internal::Earley_item::NAME];

        RULE: for my $rule_data (@rule_data) {

            my ( $rule, $position, $symbol, $closure ) = @{$rule_data};

            my $rule_id = $rule->[Parse::Marpa::Internal::Rule::ID];

            my @work_list;
            if ( $symbol->[Parse::Marpa::Internal::Symbol::NULLING] ) {
                @work_list = (
                    [   $item,
                        undef,
                        $symbol->[Parse::Marpa::Internal::Symbol::NULL_VALUE]
                    ]
                );
            }
            else {
                @work_list = (
                    (map { [ $_->[0], undef, $_->[1] ] } @{
			$item
			    ->[Parse::Marpa::Internal::Earley_item::TOKENS
			    ]
			}
                    ),
		    (map { [ $_->[0], $_->[1] ] } @{
			    $item ->[Parse::Marpa::Internal::Earley_item::LINKS]
			}
		    )
		);
            }

            for my $work_item (@work_list) {

                my ( $predecessor, $cause, $value ) = @{$work_item};

                my $predecessor_name;

                if ( $position > 0 ) {

                    $predecessor_name =
                        $item_name . 'R' . $rule_id . q{:} . ( $position - 1 );

                    unless ( $predecessor_name ~~ %sapling_by_name ) {

                        $sapling_by_name{$predecessor_name} = [];

                        my $sapling = [];
                        @{$sapling}[
                            Parse::Marpa::Internal::Sapling::NAME,
                            Parse::Marpa::Internal::Sapling::RULE,
                            Parse::Marpa::Internal::Sapling::POSITION,
                            Parse::Marpa::Internal::Sapling::ITEM,
                            ]
                            = (
				$predecessor_name,
				$rule, $position - 1, $item,
			    );

                        push @saplings, $sapling;

                    }    # $predecessor_name ~~ %sapling_by_name

                }    # if position > 0

                my $cause_name;

                if ( defined $cause ) {

                    my $symbol_id =
                        $symbol->[Parse::Marpa::Internal::Symbol::ID];

                    $cause_name = $item_name . 'L' . $symbol_id;

                    unless ( $cause_name ~~ %sapling_by_name ) {

                        $sapling_by_name{$cause_name} = [];

                        my $sapling = [];
                        @{$sapling}[
                            Parse::Marpa::Internal::Sapling::NAME,
                            Parse::Marpa::Internal::Sapling::SYMBOL,
                            Parse::Marpa::Internal::Sapling::ITEM,
                            ]
                            = ( $cause_name, $symbol, $item );

                        push @saplings, $sapling;

                    }    # $cause_name ~~ %sapling_by_name

                }    # if cause

                my $branch = [];
                @{$branch}[
                    Parse::Marpa::Internal::Branch::PREDECESSOR,
                    Parse::Marpa::Internal::Branch::CAUSE,
                    Parse::Marpa::Internal::Branch::VALUE,
                    Parse::Marpa::Internal::Branch::CLOSURE,
                    ]
                    = ( $predecessor_name, $cause_name, $value, $closure );

                push @branches, $branch;

            }    # for work_item

        }    # RULE

	my $shrub = [];
	$shrub->[Parse::Marpa::Internal::Shrub::NAME] = $sapling_name;
	$shrub->[Parse::Marpa::Internal::Shrub::BRANCHES] = \@branches;
	push @{$self->[SHRUBS]}, $shrub;
	$sapling_by_name{$sapling_name} = $shrub;

    }    # SAPLING

    # resolve links in the bocage
    for my $branch (
        map { @{ $_->[Parse::Marpa::Internal::Shrub::BRANCHES] } }
        @{$self->[SHRUBS]} )
    {
        FIELD: for my $field (
            Parse::Marpa::Internal::Branch::PREDECESSOR,
            Parse::Marpa::Internal::Branch::CAUSE,
            )
        {
            my $name = $branch->[$field];
            next FIELD unless defined $name;
            $branch->[$field] = $sapling_by_name{$name};
        }

    }

    return $self;

}

sub Parse::Marpa::Bocage::show_bocage {
     my $bocage = shift;
     my $text = q{};

     for my $shrub (@{$bocage->[SHRUBS]}) {

	 my $lhs = $shrub->[Parse::Marpa::Internal::Shrub::NAME];

         for my $branch (@{$shrub->[Parse::Marpa::Internal::Shrub::BRANCHES]}) {

	     my @rhs = ();

	     my $predecessor = $branch->[Parse::Marpa::Internal::Branch::PREDECESSOR];
	     if ($predecessor) {
	         push @rhs, $predecessor->[Parse::Marpa::Internal::Shrub::NAME];
	     } # predecessor

	     my $cause = $branch->[Parse::Marpa::Internal::Branch::CAUSE];
	     if ($cause) {
	         push @rhs, $cause->[Parse::Marpa::Internal::Shrub::NAME];
	     } # cause

	     my $value = $branch->[Parse::Marpa::Internal::Branch::VALUE];
	     if ($value) {
	         push @rhs, Dumper($value);
	     } # value

	     $text .= $lhs . ' ::= ' . join(q{ }, @rhs) . "\n";

	 } # for my $branch;

     } # for my $shrub

     return $text;
}

# Undocumented.  It's main purpose was to allow the user to differentiate
# between an unevaluated node and a node whose value was a Perl 5 undefined.
sub Parse::Marpa::Bocage::value {
    my $evaler     = shift;
    my $recognizer = $evaler->[Parse::Marpa::Internal::Bocage::RECOGNIZER];

    croak('Not yet converted');
    my $start_item =
        $recognizer->[Parse::Marpa::Internal::Recognizer::START_ITEM];
    return unless defined $start_item;
    my $value_ref = $start_item->[Parse::Marpa::Internal::Earley_item::VALUE];

    # croak("No value defined") unless defined $value_ref;
    return $value_ref;
}

sub Parse::Marpa::Bocage::next {
    my $evaler     = shift;
    my $recognizer = $evaler->[Parse::Marpa::Internal::Bocage::RECOGNIZER];

    croak('No parse supplied') unless defined $evaler;
    my $evaler_class = ref $evaler;
    my $right_class  = 'Parse::Marpa::Bocage';
    croak(
        "Don't parse argument is class: $evaler_class; should be: $right_class"
    ) unless $evaler_class eq $right_class;

    my ( $grammar, $start_item, $current_parse_set, ) = @{$recognizer}[
        Parse::Marpa::Internal::Recognizer::GRAMMAR,
        Parse::Marpa::Internal::Recognizer::START_ITEM,
        Parse::Marpa::Internal::Recognizer::CURRENT_PARSE_SET,
    ];

    # TODO: Is this check enough be sure that this is an evaluated parse?
    croak('Parse not initialized: no start item') unless defined $start_item;

    my $max_parses = $grammar->[Parse::Marpa::Internal::Grammar::MAX_PARSES];
    my $parse_count =
        $evaler->[Parse::Marpa::Internal::Bocage::PARSE_COUNT];
    if ( $max_parses > 0 && $parse_count > $max_parses ) {
        croak("Maximum parse count ($max_parses) exceeded");
    }

    if ( $parse_count <= 0 ) {
        $evaler->[Parse::Marpa::Internal::Bocage::PARSE_COUNT] = 1;

        # Allow semipredication
        my $start_value =
            $start_item->[Parse::Marpa::Internal::Earley_item::VALUE];
        return \(undef) if not defined $start_value;
        return $start_value;
    }

    $evaler->[Parse::Marpa::Internal::Bocage::PARSE_COUNT]++;

    ## no critic ( Variables::ProhibitPackageVars )
    local ($Parse::Marpa::Internal::This::grammar) = $grammar;
    ## use critic

    my $tracing = $grammar->[Parse::Marpa::Internal::Grammar::TRACING];
    my $trace_fh;
    my $trace_iteration_changes;
    my $trace_iteration_searches;
    if ($tracing) {
        $trace_fh =
            $grammar->[Parse::Marpa::Internal::Grammar::TRACE_FILE_HANDLE];
        $trace_iteration_changes = $grammar
            ->[Parse::Marpa::Internal::Grammar::TRACE_ITERATION_CHANGES];
        $trace_iteration_searches = $grammar
            ->[Parse::Marpa::Internal::Grammar::TRACE_ITERATION_SEARCHES];
    }

    local ($Data::Dumper::Terse) = 1;

}

1;

__END__

=pod

=head1 NAME

Parse::Marpa::Bocage - Marpa Parse Bocage Objects

=head1 SYNOPSIS

    my $grammar = new Parse::Marpa::Grammar({ mdl_source => \$mdl });
    my $recce = new Parse::Marpa::Recognizer({ grammar => $grammar });
    my $fail_offset = $recce->text(\("2-0*3+1"));
    croak("Parse failed at offset $fail_offset") if $fail_offset >= 0;

    my $evaler = new Parse::Marpa::Bocage($recce);

    for (my $i = 0; defined(my $value = $evaler->tree()); $i++) {
        croak("Ambiguous parse has extra value: ", $$value, "\n")
	    if $i > $expected;
	say "Ambiguous Equation Value $i: ", $$value;
    }

=head1 DESCRIPTION

=head1 SUPPORT

See the L<support section|Parse::Marpa/SUPPORT> in the main module.

=head1 AUTHOR

Jeffrey Kegler

=head1 LICENSE AND COPYRIGHT

Copyright 2007 - 2008 Jeffrey Kegler

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

=cut
