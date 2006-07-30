package Kepher::Show;
$VERSION = '0.11';

use strict;
use Cwd;

# open file will full absolut path
sub _of{
	my $file_path = shift;
	my $file_name = shift;
	Kepher::Document::Internal::add( $file_path.$file_name );#getcwd().'/'.
}
# config file
sub _cf { _of($Kepher::internal{path}{config}, shift) }
#
sub localisation_file  { _cf "localisation/$_[0].conf"}
sub syntaxmode_file    { _cf "syntaxhighlighter/$_[0].pm"}
sub interface_file     {
	my $item = shift;
	return unless exists $Kepher::config{'app'}{$item};
	my $file = $Kepher::config{'app'}{$item}{'file'};
	$file = $Kepher::config{'app'}{$item}{'defaultfile'} if $item eq 'contextmenu';
	$file = $Kepher::config{'app'}{'toolbar'}{'defaultfile'} if $item eq 'toolbar';
	_cf $file;
}

# help file
sub _hf { _of($Kepher::internal{path}{help}, shift)}
#
sub history              { _hf "english/internals/history.txt"}
sub thoughts_mission     { _hf "english/thoughts/mission.txt"}
sub thoughts_manifest    { _hf "deutsch/interna/manifest.txt"}
sub thoughts_gpl         { _hf "english/thoughts/gpl.txt"}
sub thoughts_perlrules   { _hf "deutsch/interna/perlrules.txt"}
sub thoughts_modulenames { _hf "deutsch/interna/modulnamen.txt"}
sub licence_art          { _hf "english/license/artistic.txt"}
sub licence_acl          { _hf "english/license/acl.txt"}
sub licence_wxwl         { _hf "english/license/wx.txt"}
sub licence_lgpl         { _hf "english/license/lgpl.txt"}
sub licence_sci          { _hf "english/license/scintilla.txt"}
sub welcome              { _hf $Kepher::config{'texts'}{'welcome'}}
sub version_text         { _hf $Kepher::config{'texts'}{'version'}}
sub licence_gpl          { _hf $Kepher::config{'texts'}{'license'}}
sub feature_tour         { _hf $Kepher::config{'texts'}{'feature'}}
sub navigation_guide     { _hf $Kepher::config{'texts'}{'navigation'}}
sub credits              { _hf $Kepher::config{'texts'}{'credits'}}
sub keyboard_map         { _hf $Kepher::config{'texts'}{'keymap'}}

1;
