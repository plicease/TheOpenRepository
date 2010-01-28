#!/usr/bin/perl

use 5.010;
use strict;
use warnings;

use lib 'lib';
use Fatal qw(open close);
use Encode;

use Carp;
use Data::Dumper;
use English qw( -no_match_vars );
use Fatal qw(open);
use JSON::XS;
use Storable;
use Fatal qw(open close);

my $tag = shift;
Carp::croak("usage $0 gua") if not $tag;

my $i;
{
    local $RS = undef;
    open my $fh, q{<}, 'i.json';
    my $json_i = <$fh>;
    $i      = JSON::XS::decode_json $json_i;
    close $fh;
}
binmode STDOUT, ':utf8';

{
    Carp::croak("Misformed tag: $tag")
        if $tag !~ / \A [0-9]{1,2} [.] [1-6] \z /xms;
    my ( $hex, $line ) =
        split /[.]/xms, $tag;
    $tag = sprintf '%02d.%1d', $hex, $line;
}
my $rtext = $i->{$tag};
Carp::croak(qq{unknown text: "$tag"}) if not $rtext;
my $xc_text = $i->{$tag . 'x'};

my %codepoint_in_text = ();
my @received_text = ();
RECEIVED_TEXT: for my $codepoint (@{$rtext}) {
    push @received_text, $codepoint;
    $codepoint_in_text{lc $codepoint}++;
}
my $received_text = join q{ }, map { sprintf '%c', hex(substr($_, 2)) } @received_text;

my @xiang_zhuan = ();
XIANG_ZHUAN: for my $codepoint (@{$xc_text}) {
    push @xiang_zhuan, $codepoint;
    $codepoint_in_text{lc $codepoint}++;
}

my $xiang_zhuan = join q{ }, map { sprintf '%c', hex(substr($_, 2)) } @xiang_zhuan;

my $codepoints = Storable::retrieve('glossary.storable');

my @sorted_codepoints =
    map  { $_->[1] }
    sort { $b->[0] <=> $a->[0] }
    map  { [ $codepoints->{$_}->{occurrence_count}, $_ ] }
    keys %codepoint_in_text;

my @long_fields = qw(
occurrences
    shrift_notes
    laozi
cedict_definition
    unihan_definition
);

print <<'EOF';
<HTML>
<HEAD>
<STYLE type="text/css">
   .title { border-width: 1; border: solid; text-align: center}
   .content {white-space: pre-wrap; }
   .inline_chinese { font-size:200%; line-height:150% }
   .subsection_label { font-weight:bold }
   .glyph { float: left; vertical-align: text-top; font-size: 400%; margin-right: 1.5em }
   .codepoint { margin-bottom: 3ex; margin-top: 3ex }
   .unicode_value { font-weight: bold; }
   .codepoint_datum_label { font-weight: bold }
</STYLE>
</HEAD>
<BODY>
EOF

say qq{<div class="inline_chinese">};
say $received_text;
say qq{</div>};
say qq{<div class="inline_chinese">};
say $xiang_zhuan;
say qq{</div>};

for my $codepoint (@sorted_codepoints) {
    say qq{<div class="codepoint" title="$codepoint">};
    say qq{<table>};
    say qq{<td>};
    say $codepoints->{$codepoint}->{glyph};
    say qq{</td>};
    say qq{<td>};
    for my $field (qw( unicode_value krskangxi krsunicode )) {
        if ( my $text_ref = $codepoints->{$codepoint}->{$field} ) {
            say $text_ref;
        }
    }
    say qq{</td>};
    say qq{<td>};
    for my $field (qw( kfrequency kgradelevel ktotalstrokes)) {
        if ( my $text_ref = $codepoints->{$codepoint}->{$field} ) {
            say $text_ref;
        }
    }
    say qq{</td>};
    say qq{<td>};
    for my $field (qw( kmandarin kmatthews)) {
        if ( my $text_ref = $codepoints->{$codepoint}->{$field} ) {
            say $text_ref;
        }
    }
    say qq{</td>};
    say qq{</table>};
    for my $field (@long_fields) {
        if ( my $text_ref = $codepoints->{$codepoint}->{$field} ) {
            say $text_ref;
        }
    }
    say qq{</div>};
} ## end for my $codepoint (@sorted_codepoints)

say '</BODY>';
say '</HTML>';
