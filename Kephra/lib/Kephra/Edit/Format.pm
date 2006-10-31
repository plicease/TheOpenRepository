package Kephra::Edit::Format;
$VERSION = '0.22';

use strict;
use Wx qw(
	wxSTC_CMD_NEWLINE wxSTC_CMD_DELETEBACK wxSTC_CMD_LINEEND
	wxSTC_CMD_WORDLEFT wxSTC_CMD_WORDRIGHT
);

# indention
sub _indent {
	my $width = shift;
	my $ep    = Kephra::App::EditPanel::_get();
	$width ||= 0;
	$ep->BeginUndoAction;
	$ep->SetLineIndentation( $_, $ep->GetLineIndentation($_) + $width ) 
		for $ep->LineFromPosition($ep->GetSelectionStart)
		 .. $ep->LineFromPosition($ep->GetSelectionEnd);
	$ep->EndUndoAction;
}

sub _dedent {
	my $width = shift;
	my $ep   = Kephra::App::EditPanel::_get();
	$ep->BeginUndoAction;
	$ep->SetLineIndentation( $_, $ep->GetLineIndentation($_) - $width )
		for $ep->LineFromPosition($ep->GetSelectionStart)
		 .. $ep->LineFromPosition($ep->GetSelectionEnd);
	$ep->EndUndoAction;
}

sub indent_space { _indent(1) }
sub dedent_space { _dedent(1) }
sub indent_tab   { _indent($Kephra::document{'current'}{'tab_size'}) }
sub dedent_tab   { _dedent($Kephra::document{'current'}{'tab_size'}) }

#
sub align_indent {
	my $ep = Kephra::App::EditPanel::_get();
	my $firstline = $ep->LineFromPosition( $ep->GetSelectionStart );
	my $align = $ep->GetLineIndentation($firstline);
	$ep->BeginUndoAction();
	$ep->SetLineIndentation($_ ,$align)
		for $firstline + 1 .. $ep->LineFromPosition($ep->GetSelectionEnd);
	$ep->EndUndoAction();
}

# deleting trailing spaces on line ends
sub del_trailing_spaces {
	&Kephra::Edit::_save_positions;
	my $ep = Kephra::App::EditPanel::_get();
	my $text = Kephra::Edit::_select_all_if_none();
	$text =~ s/[ \t]+(\r|\n|\Z)/$1/g;
	$ep->BeginUndoAction;
	$ep->ReplaceSelection($text);
	$ep->EndUndoAction;
	Kephra::Edit::_restore_positions();
}

#
sub join_lines {
 my $ep = Kephra::App::EditPanel::_get();
 my $text = $ep->GetSelectedText();
	$text =~ tr/\r\n//d; # delete end of line marker
	$ep->BeginUndoAction;
	$ep->ReplaceSelection($text);
	$ep->EndUndoAction;
}

sub blockformat{
}

sub blockformat_LLI{
	blockformat( $Kephra::config{editpanel}{indicator}{right_margin}{position} );
}

sub blockformat_custom{
	my $width = Kephra::Dialog::get_text( Kephra::App::Window::_get(),
			$Kephra::localisation{dialog}{edit}{wrap_width_input},
			$Kephra::localisation{dialog}{edit}{wrap_custom_headline}
	);
	blockformat( $width ) if defined $width and $width;}


# breaking too long lines into smaller one
sub line_break {
	my $width = shift;
	my $ep    = &Kephra::App::EditPanel::_get;
	my $autoindent = $Kephra::config{'editpanel'}{'auto'}{'indention'};
	my $eol_width  = $Kephra::temp{'current_doc'}{'EOL_length'};
	my ($begin_pos, $end_pos) = ( $ep->GetSelectionStart, $ep->GetSelectionEnd );
	($begin_pos, $end_pos) = ($end_pos, $begin_pos) if $begin_pos > $end_pos;
	my $line = $ep->LineFromPosition( $begin_pos );
	my ($pos, $col, $indent, $line_end);

	$ep->BeginUndoAction();
	$ep->GotoPos($begin_pos);

	#while () {
		# position where this line will be broken
		$line_end = $ep->PositionFromLine($line) + $width;
#
		# last when end of selection is reached
		#last unless $pos < $end_pos;
#
		# skip and not brake short lines
		$ep->CmdKeyExecute(wxSTC_CMD_LINEEND);
		$col = $ep->GetColumn($ep->GetCurrentPos());
		if ($col > $line_end) {
			#$pos += $width - $col
			Kephra::Dialog::msg_box( undef,);
		} else {
			$ep->GotoLine(++$line);
			#next; 
		}
#
		# brake always on and of the last word that fit into the line
		#if ( not ($pos == $ep->WordEndPosition($pos, 1)  )
		     #and ($pos == $ep->WordStartPosition($pos, 1))  ) {
			#$pos = $ep->WordStartPosition($pos, 1);
			#$pos = $ep->WordStartPosition($pos, 0);
		#}
#
		#$ep->GotoPos( $pos );
		#$ep->CmdKeyExecute(wxSTC_CMD_NEWLINE);
		#$line++;
		#$indent = $ep->GetLineIndentation($line);
		#$end_pos += $eol_width - $indent;
		#if ($autoindent){
			#$indent = $ep->GetLineIndentation($line-1);
			#$ep->SetLineIndentation($line, $indent);
			#$end_pos += $indent;#length ($ep->GetTextRange());
		#} else { $ep->SetLineIndentation($line, 0) }
	#}

#$ep->WordStartPosition( $begin, 1 );
	$ep->GotoPos($end_pos);
	$ep->EndUndoAction();

	#Kephra::Dialog::msg_box( undef, $ep->GetColumn($ep->GetCurrentPos()).$width,     '' );
	# GetLineEndPosition                                                  LineLength
	# $ep->CmdKeyExecute(wxSTC_CMD_WORDLEFT);#wxSTC_CMD_WORDRIGHT
	
#$ep->CmdKeyExecute(); #GetCharAt(position)   
#$Kephra::temp{'edit'}{'wordchars'}WordEndPosition(pos, onlyWordCharacters) WordStartPosition(pos, onlyWordCharacters)
}

sub linebreak_custom {
	my $l10n = $Kephra::localisation{dialog}{edit};
	my $width = Kephra::Dialog::get_text( Kephra::App::Window::_get(),
			$l10n->{wrap_width_input}, $l10n->{wrap_custom_headline} );
	line_break( $width ) if defined $width and $width;
}

sub linebreak_LLI {
	line_break( $Kephra::config{editpanel}{indicator}{right_margin}{position} );
}

sub linebreak_window {
	my $app     = Kephra::App::Window::_get();
	my $ep = Kephra::App::EditPanel::_get();
	my ($width) = $app->GetSizeWH();
	my $pos = $ep->GetColumn($ep->PositionFromPointClose(100, 67));
	Kephra::Dialog::msg_box( $app, $pos, '' );
	#line_break($width);
}

1;
