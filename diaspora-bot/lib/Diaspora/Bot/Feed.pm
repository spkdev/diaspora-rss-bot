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



=head1 NAME

Diaspora::Bot::Feed - A module to post RSS feeds to Diaspora*.

=head1 SYNOPSIS

 use Diaspora::Bot::Feed;
 my $d = Diaspora::Bot->new(
                             pod    => 'https://foo.bar',
                             user   => 'yourbot',
                             passwd => 'secret',
                           );
 $d->postfeed(
               tags   => [ $feed_tag ] ,
               aspect => 'public',
               link   => $feed_link,
               title  => $feed_title,
               body   => $html_or_txt_feed_description
               uri    => '/status_messages'
             );

=head1 DESCRIPTION

B<This document describes Diaspora::Bot::Feed version 0.01.>

This is a submodule of L<Diaspora::Bot>. Read its documentation
for more details about how to use it.

=head1 POST A FEED

The B<postfeed()> method posts a single rss feed item to
the stream of a diaspora bot user. The body (description
of the rss feed item) has to be unformatted, it will be
automatically converted to Diaspora* wiki syntax.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012 FIXME

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 BUGS AND LIMITATIONS

See L<http://rt.cpan.org> or L<https://github.com/spkdev/diaspora-rss-bot/issues>
for current bugs, if any.

=head1 INCOMPATIBILITIES

None known.

=head1 DIAGNOSTICS

To debug Diaspora::Bot::Feed use the Perl debugger, see L<perldebug>.

=head1 DEPENDENCIES

Diaspora::Bot::Feed depends on the following modules:

=over

=item Diaspora::Bot

=back

=head1 AUTHOR

FIXME

=head1 VERSION

0.01

=cut



1;
