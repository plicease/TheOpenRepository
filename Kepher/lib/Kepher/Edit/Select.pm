package Kepher::Edit::Select;
$VERSION = '0.01';

# text selection

use strict;
use Wx qw( wxSTC_CMD_PARAUPEXTEND wxSTC_CMD_PARADOWNEXTEND );


sub all      { &document }
sub document { Kepher::App::STC::_get()->SelectAll }
sub all_if_non {
	my $ep = Kepher::App::STC::_get();
	$ep->SelectAll if $ep->GetSelectionStart == $ep->GetSelectionEnd;
	my ($start, $end) = $ep->GetSelection;
	return $ep->GetTextRange( $start, $end );
}

sub to_block_begin{ Kepher::App::STC::_get()->CmdKeyExecute(wxSTC_CMD_PARAUPEXTEND)}
sub to_block_end{Kepher::App::STC::_get()->CmdKeyExecute(wxSTC_CMD_PARADOWNEXTEND)}

1;