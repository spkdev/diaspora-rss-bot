package HTML::WikiConverter::Diaspora;
use base 'HTML::WikiConverter';
our $VERSION = '0.01';

sub rules
{
  return
  {
    b => { start => '**', end => '**' },
    i => { start => '*', end => '*' },
    strong => { alias => 'b' },
    em => { alias => 'i' },
    a => { replace => \&_a_replace },
    img => { replace => \&_img_replace }
  };
}

sub postprocess_output
{
  my( $self, $outref ) = @_;
  # Convert a regular image link to a 'clickable' image link. Image links that are already 'clickable' are left as is.
  $$outref =~ s/([^[]\s*)!\[[^]]*]\(([^)]*)\)/$1\[!\[$2\]\($2\)\]\($2\)/g;
  $$outref =~ s/^!\[[^]]*]\(([^)]*)\)/\[!\[$1\]\($1\)\]\($1\)/g;

  # Append linebreaks after image, so subsequent text starts on new paragraph 
  $$outref =~ s/(\[!\[[^]]*\]\([^]]*\)\]\([^]]*\))/$1\n\n/g;
}

sub _a_replace
{
  my( $self, $node, $rules ) = @_;
  my @text = $node->content_list();

  my $txt = (exists $text[0]) ? (defined $text[0]->attr('text') ? $text[0]->attr('text') : $self->get_elem_contents( $node ) ) : 'link';
  my $ref = (defined $node->attr('href') ? $node->attr('href') : '');
  my $link = "[".htmlEscape( $txt )."](".$ref.")";
  return $link;
}

sub _img_replace
{
  my( $self, $node, $rules ) = @_;
  my $img = "![".$node->attr('src')."](".$node->attr('src').")";
  return $img;
}

###############################################################################
### Helper functions
###############################################################################
sub htmlEscape
{
  my( $string ) = @_;
  $string =~ s/^#/&#35;/g;        # Escape "#" -> "&#35;" (at beginning)
  $string =~ s/([^&])#/$1&#35;/g; # Escape "#" -> "&#35;"
  return $string;
}

