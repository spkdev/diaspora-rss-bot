package HTML::WikiConverter::Diaspora;
use base 'HTML::WikiConverter';

sub rules
{
  return
  {
    b => { start => '**', end => '**' },
    i => { start => '*', end => '*' },
    strong => { alias => 'b' },
    em => { alias => 'i' },
    a => { replace => \&_a_replace },
    img => { replace => \&_img_clickable_replace }
  };
}

sub _a_replace
{
  my( $self, $node, $rules ) = @_;
  my @text = $node->content_list();
  my $txt = (exists $text[0]) ? (defined $text[0]->attr('text') ? $text[0]->attr('text') : '') : "";
  my $ref = (defined $node->attr('href') ? $node->attr('href') : '');
  my $link = "[".htmlEscape( $txt )."](".$ref.")";
  return $link;
}

# Currently unused, as I use "_img_clickable_replace" function to generate clickable images for Diaspora*
sub _img_replace
{
  my( $self, $node, $rules ) = @_;
  my $img = "![".$node->attr('src')."](".$node->attr('src').")";
  return $img;
}

sub _img_clickable_replace
{
  my( $self, $node, $rules ) = @_;
  my $img = "[![".$node->attr('src')."](".$node->attr('src').")](".$node->attr('src').")";
  return $img;
}


###############################################################################
### Helper functions
###############################################################################
sub htmlEscape
{
  my( $string ) = @_;
  $string =~ s/([^&])#/$1&#35;/g; # Escape "#" -> "&#35;"
  return $string;
}
