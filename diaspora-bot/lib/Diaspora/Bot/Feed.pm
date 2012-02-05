package Diaspora::Bot::Feed;
use Diaspora::Bot;
use base 'Diaspora::Bot';

use strict;
use warnings;
use vars qw($VERSION @ISA);
use Carp;
use JSON;

our $VERSION = '0.01';

sub postfeed {
  my $self = shift;
  my %arg  = @_;

  $self->post( message => $self->_feed2message(%arg),
               uri     => '/status_messages' );
}


sub _feed2message {
  my $self = shift;
  my %arg  = @_;

  my $text = $self->_link(%arg)."\r\n".$self->_tags(%arg)."\r\n\r\n".$self->wc->html2wiki( html => $arg{body} );

  return {
		status_message => {
			text => $text,
		},
		aspect_ids => $arg{aspect}
  };
}

sub _link {
  my $self = shift;
  my %arg  = @_;

  return sprintf "### [%s](%s)\r\n", $self->_escape($arg{title}), $self->_escape($arg{link}); 
}

sub _tags {
  my $self = shift;
  my %arg  = @_;

  my $tags;

  if( $arg{tags} ) {
    $tags = join ' ', map { "#$_" } @{$arg{tags}};   
  }
  else {
    $tags = $self->_tagfromuri(%arg);    
  }

  return $tags;
}

sub _escape{
  my $self = shift;
  my $string = shift;
  $string =~ s/^#/&#35;/g;        # Escape "#" -> "&#35;" (at beginning)
  $string =~ s/([^&])#/$1&#35;/g; # Escape "#" -> "&#35;"
  $string =~ s/\\/\\\\/g;         # Replace '\' with '\\'
  $string =~ s/\"/\\\"/g;         # Replace '"' with '\"'

  return $string;
}


sub _tagfromuri {
  my $self = shift;
  my %arg  = @_;

  my $hashtag = $arg{uri};
  
  for($hashtag)
  {
    s/https?:\/\/(.*)\/?$/$1/g; # Cut off protocol
    s/\/$//;                    # Cut off possible trailing /
    s/[^a-zA-Z0-9_]/-/g;        # Replace special chars with '-'
  }
 
  return sprintf "#rss-%s #rss-all", $hashtag;
}

1;
