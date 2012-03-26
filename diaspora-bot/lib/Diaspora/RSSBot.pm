package Diaspora::RSSBot;

use strict;
use warnings;
use vars qw($VERSION @ISA);
use Diaspora::Client;
use Carp;
use Switch;
use DBI;
use XML::Feed;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use List::MoreUtils 'any';
use HTML::Entities;
use Encode;
use utf8;

our $VERSION = '0.01';
our %flags   = qw(pod 1 user 1 passwd 1);

# Constants
use constant PATTERN_HREF => "<a.+?href=\"([^\"]+?)\".+?</a>";
use constant HELP_MESSAGE => "The rss-bot can be controlled with certain commands which are sent as private message. The command is always placed in the subject field of the message, while possible parameters are placed in the body. If a command has no parameters, you can put an arbitrary message into the body, as empty messages cannot be send. The rss-bot periodically processes commands at a certain frequency, so be patient as the response may take a few minutes.\n\nThe following commands a currently supported:\n\n**help**\nShows this help message which explains the usage. This command has no parameters.\n\n**subscribe**\nSubscribes you to the url(s) that are provided. Just paste one or more urls to RSS/Atom feeds into the message body, and rss-bot will subscribe you to those feeds right away.\n\n**unsubscribe**\nUnsubscribes you from the url(s) that are provided. Just paste one or more urls to RSS/Atom feeds that you no longer want to receive into the message body, and rss-bot will remove you from said feeds.\n\n**list**\nSends you a list of all feeds you are currently subscribed to.";

sub new
{
  my $this = shift;
  my $class = ref($this) || $this;
  my $self  = {};
  bless ($self, $class);
  return $self->init( @_ );
} 

sub init
{
  my $self = shift;
  my %args = @_;

  if( !exists $args{pod}       )  { croak "Parameter 'pod' is missing";       }
  if( !exists $args{user}      )  { croak "Parameter 'user' is missing";      }
  if( !exists $args{passwd}    )  { croak "Parameter 'passwd' is missing";    }
  if( !exists $args{db_path}   )  { croak "Parameter 'db_path' is missing";   }
  if( !exists $args{failcount} )  { croak "Parameter 'failcount' is missing"; }
  $self->{db}         = undef;
  $self->{db_path}    = $args{db_path};
  $self->{failcount}  = $args{failcount};
  $self->{diaspora}   = Diaspora::Client->new( pod => $args{pod}, user => $args{user}, passwd => $args{passwd} );
  $self->{aspect_all} = undef;
  $self->_db_prepare();

  $self->login();
  my @aspects = $self->{diaspora}->get_aspects();
  foreach( @aspects )
  {
    if( $_->{name} eq "all" )
    {
      $self->{aspect_all} = $_;
      last;
    }
  }
  $self->logout();
  die "No aspect 'all' defined" if !$self->{aspect_all};

  return $self;
}

sub login
{
  my $self = shift;
  $self->{diaspora}->login();
}

sub logout
{
  my $self = shift;
  $self->{diaspora}->logout();
}

sub process_requests
{
  my $self = shift;
  my @contacts = $self->{diaspora}->get_contacts();
  my @requests = sort cmp_requests $self->{diaspora}->get_conversations(); 

  foreach( @contacts )
  {
    if( $_->{only_sharing} )
    {
      $self->{diaspora}->add_user_to_aspect( $_->{user_id}, $self->{aspect_all}->{aspect_id} );
    }
  }

  foreach( @requests )
  {
    switch( $_->{subject} )
    {
      case "help"         { $self->_handle_help( $_ );        }
      case "subscribe"    { $self->_handle_subscribe( $_ );   }
      case "unsubscribe"  { $self->_handle_unsubscribe( $_ ); }
      case "list"         { $self->_handle_list( $_ );        }      
      else                { $self->_handle_invalid( $_ );     }
    }
  }
}

sub process_feeds
{
  my $self      = shift;
  my $pm        = shift;
  my $aspect    = undef;

  my $st_get_feed = $self->{db}->prepare( "SELECT * FROM feeds;" );
  my $st_set_failcount = $self->{db}->prepare( "UPDATE feeds SET failcount=? WHERE guid=?;" );
  my $st_get_processed = $self->{db}->prepare( "SELECT * FROM processed WHERE guid=?;" );
  my $st_ins_processed = $self->{db}->prepare( "INSERT INTO processed VALUES( ?, ?, ? );" );
  my @aspects = $self->{diaspora}->get_aspects();

  $st_get_feed->execute();
  while( my $fi = $st_get_feed->fetchrow_hashref() )
  {
    # Find corresponding aspect
    foreach ( @aspects )
    {
      if( $_->{name} eq $fi->{guid} )
      {
        $aspect = $_;
        last;
      }
    }

    if( $aspect )
    {
      eval
      {
        my $feed = XML::Feed->parse( URI->new( $fi->{url} ) );

        if( $fi->{failcount} > 0 )
        {
          $st_set_failcount->execute( 0, $fi->{guid} );
        }

        foreach ( $feed->entries )
        {
          my $content   = (defined $_->content->body) ? $_->content->body : (defined $_->summary->body) ? $_->summary->body : "";
          my $feed_url  = utf8::is_utf8($fi->{url}) ? encode('utf8', $fi->{url}) : $fi->{url};
          my $link      = utf8::is_utf8($_->link)   ? encode('utf8', $_->link)   : $_->link;
          my $title     = utf8::is_utf8($_->title)  ? encode('utf8', $_->title)  : $_->title;
          $content      = utf8::is_utf8($content)   ? encode('utf8', $content)   : $content;

          my $guid = md5_hex( $title.$content ); # This to get _every_ update of the post, or use url to only get it once?!
          $st_get_processed->execute( $guid );
          if( !$st_get_processed->fetchrow_hashref() )
          {
            print "NEW ITEM [$fi->{url} -> \"$title\" aspects: \"$aspect->{name}\", $aspect->{aspect_id}]\n";

            my $message = $self->_format_message( $feed_url, $link, $title, $content );
            $self->{diaspora}->post_message( $message, [$aspect->{aspect_id}] );
            $st_ins_processed->execute( $fi->{guid}, $guid, time );
          }
        }
        1;
      }
      or do
      {
        $fi->{failcount} = $fi->{failcount} + 1;
        if( $fi->{failcount} > $self->{failcount} )
        {
          # Limit reached -> delete feed and corresponding aspect
          $self->{db}->do( "DELETE FROM feeds where guid=$fi->{guid};" );

          my @contacts = $self->{diaspora}->get_contacts();
          my @contact_ids;
          foreach my $user ( @{$aspect->{user_ids}} )
          {
            foreach( @contacts )
            {
              if( $user eq $_->{user_id} )
              {
                push( @contact_ids, $_->{contact_id} ) if $_->{contact_id} ne "";
              }
            }
          }
          
          my $message = "The following feed seems to be broken and has been purged from the system:\n\n+ $fi->{url}";
          my $conversation_id = $self->{diaspora}->send_conversation( @contact_ids, "removed feed", $message );
          $self->{diaspora}->delete_conversation( $conversation_id );
          $self->{diaspora}->delete_aspect( $aspect->{aspect_id} );
          print "ERROR while processing $fi->{url}. Failcount limit reached, feed removed -> Processing next feed\n";
        }
        else
        {
          # Increase failcount
          $self->{db}->do( "UPDATE feeds SET failcount=$fi->{failcount} where guid=$fi->{guid};" );
          $st_set_failcount->execute( $fi->{failcount}, $fi->{guid} );
          print "ERROR while processing $fi->{url}. Failcount is now: $fi->{failcount} -> Processing next feed\n";
        }
        next;
      }
    }  
  }
}

sub purge_feeds
{
  my $self = shift;
  my $days = shift;
  my $t = time - ($days * 86400);
  $self->{db}->do( "DELETE FROM processed WHERE timestamp < $t" );
}

sub _handle_help
{
  my $self = shift;
  my $pm = shift;
  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, HELP_MESSAGE );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
  print "HELP command handled\n";
}

sub _handle_subscribe
{
  my $self = shift;
  my $pm = shift;
  my $params = @{$pm->{messages}}[0]->{content};
  my @aspects = $self->{diaspora}->get_aspects();
  my @feeds;
  my @added;

  my $regex = qr/${\(PATTERN_HREF)}/;
  push @feeds, decode_entities( $1 ) while $params =~ /$regex/g;

  my $st_add = $self->{db}->prepare( "INSERT INTO feeds (url) VALUES( ? );" );
  my $st_get = $self->{db}->prepare( "SELECT * FROM feeds WHERE url=?;" );

  foreach ( @feeds )
  {
    $_ =~ s/\/$//;  # Cut off possible trailing / in order to reduce false duplicates
   
    $st_get->execute( $_ );
    my $row = $st_get->fetchrow_hashref();
    if( !$row )
    {
      $st_add->execute( $_ );
      $st_get->execute( $_ );
      $row = $st_get->fetchrow_hashref();
      if( $row )
      {
        my $aspect_id = $self->{diaspora}->create_aspect( $row->{guid} );
        $self->{diaspora}->add_user_to_aspect( $pm->{from_user_id}, $aspect_id );
        push @added, $_;
        @aspects = $self->{diaspora}->get_aspects();  # Update to reflect changes
      }
    }
    else
    {
      my $aspect;
      foreach( @aspects )
      {
        if( $_->{name} eq $row->{guid} )
        {
          $aspect = $_;
          last;
        }
      }
      $self->{diaspora}->add_user_to_aspect( $pm->{from_user_id}, $aspect->{aspect_id} );
      push @added, $_;
    }
    print "SUBSCRIBE: Added user to feed \"$_\"\n";
  }
  
  my $response = "Request processed, you have been added to the following feeds:\n\n";
  foreach ( @added )
  {
    $response = $response."+ $_\n";
  }
  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, $response );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
  print "SUBSCRIBE command handled\n";
}

sub _handle_unsubscribe
{
  my $self = shift;
  my $pm = shift;
  my $params = @{$pm->{messages}}[0]->{content};
  my @aspects = $self->{diaspora}->get_aspects();
  my @feeds;
  my @removed;
  my @error;

  my $regex = qr/${\(PATTERN_HREF)}/;
  push @feeds, decode_entities( $1 ) while $params =~ /$regex/g;

  my $st_get = $self->{db}->prepare( "SELECT * FROM feeds WHERE url=?;" );
  my $st_del = $self->{db}->prepare( "DELETE FROM feeds WHERE guid=?;" );

  foreach ( @feeds )
  {
    $_ =~ s/\/$//;  # Cut off possible trailing / in order to reduce false duplicates
   
    $st_get->execute( $_ );
    my $row = $st_get->fetchrow_hashref();
    if( $row )
    {
      my $aspect;
      foreach ( @aspects )
      {
        if( $_->{name} eq $row->{guid} )
        {
          $aspect = $_;
          last;
        }
      }
     
      my $user_found = undef;
      my @users_in_aspect = @{$aspect->{user_ids}};
      foreach ( @users_in_aspect )
      {
        if( $_ eq $pm->{from_user_id} )
        {
          $user_found = 1;
          last;
        }
      }

      if( $user_found )
      {
        $self->{diaspora}->remove_user_from_aspect( $pm->{from_user_id}, $aspect->{aspect_id} );
 
        if( ($#users_in_aspect + 1) == 1 )
        {
          if( $users_in_aspect[0] == $pm->{from_user_id} )
          {
            $self->{diaspora}->delete_aspect( $aspect->{aspect_id} );
            $st_del->execute( $row->{guid} );
            @aspects = $self->{diaspora}->get_aspects();  # Update to reflect changes
          }
        }
        push @removed, $_;
        print "UNSUBSCRIBE: Removed user from feed \"$_\"\n";
      }
      else
      {
        push @error, $_;
      }
    }
    else
    {
      push @error, $_;
    }
  }
  
  my $response = "Request processed.";
  if( ($#removed + 1) > 0 )
  {
    $response = $response."\n\nYou have been removed from the following feeds:\n\n";
    foreach( @removed ) { $response = $response."+ $_\n"; }
  }
  if( ($#error + 1) > 0 )
  {
    $response = $response."\n\nYou are not subscribed to the following feeds, but attempted to be removed:\n\n";
    foreach( @error ) { $response = $response."+ $_\n"; }
  }

  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, $response );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
  print "UNSUBSCRIBE command handled\n";
}

sub _handle_list
{
  my $self = shift;
  my $pm = shift;
 
  my @aspects = $self->{diaspora}->get_aspects();
  my @subscribed;


  my $st_get_feed = $self->{db}->prepare( "SELECT * FROM feeds WHERE guid=?;" );
  foreach( @aspects )
  {
    if( any { $_ eq $pm->{from_user_id} } @{$_->{user_ids}} )
    {
      $st_get_feed->execute( $_->{name} );
      my $feed = $st_get_feed->fetchrow_hashref();
      if( $feed )
      {
        push( @subscribed, $feed->{url} );
      }
    }
  }

  my $response;
  if( ($#subscribed + 1) > 0 )
  {
    $response = "You are subscribed to the following feeds:\n\n";
    foreach( @subscribed ) { $response = $response."+ $_\n"; }
  }
  else
  {
    $response = "You are not subscribed to any feed.";
  }

  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, $response );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
  print "LIST command handled\n";
}

sub _handle_invalid
{
  my $self = shift;
  my $pm = shift;
  
  my $message = "**Your request is invalid, please refer to the help to see what commands are currently supported:**\n\n".HELP_MESSAGE;
  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, $message );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
  print "INVALID command handled\n";
}

sub _format_message
{
  my $self    = shift;
  my $feed_url= shift;
  my $link    = shift;
  my $title   = shift;
  my $content = shift;

  my $message = sprintf( "### [%s](%s)\r\n", $self->_escape( $self->_strip( $title ) ), $self->_escape( $link ) );
  $message = $message.sprintf( "[%s](%s)\r\n\r\n", $self->_escape( $feed_url ), $self->_escape( $feed_url ) );
  $message = $message.$self->{diaspora}->wc->html2wiki( html => $content );
  return $message;
}

sub _link
{
  my $self = shift;
  my %arg  = @_;
  return sprintf "### [%s](%s)\r\n", $self->_escape($self->_strip($arg{title})), $self->_escape($arg{link}); 
}

sub _escape
{
  my $self = shift;
  my $string = shift;
	for($string)
	{
		s/^#/&#35;/g;        # Escape "#" -> "&#35;" (at beginning)
  	s/([^&])#/$1&#35;/g; # Escape "#" -> "&#35;"
	}
  return $string;
}

sub _strip
{
  my $self = shift;
  my $string = shift;
  $string =~ tr/\x00-\x1F//d;
  return $string;
}

sub cmp_requests
{
  # Sorts requests in the following order: subscribe -> unsubscribe -> list
  my $u = $a->{subject};
  my $v = $b->{subject};
  return  0 if $u eq $v;
  return -1 if $u eq "subscribe";
  return  1 if $v eq "subscribe";
  return -1 if $u eq "unsubscribe";
  return  1 if $v eq "unsubscribe";
  return  0;  # For all unsupported strings
}

sub _db_prepare
{
  my $self = shift;
  $self->{db} = DBI->connect( "dbi:SQLite:$self->{db_path}" ) or die "Could not connect to sqlite db $self->{db_path}: $!\n";
  
  # Create table 'feeds'
  my $sth = $self->{db}->prepare( "CREATE TABLE IF NOT EXISTS feeds (guid INTEGER PRIMARY KEY, url varchar(255) NOT NULL UNIQUE, failcount INTEGER NOT NULL DEFAULT 0);" );
  $sth->execute() or die "Could not create table 'feeds' for sqlite db $self->{db_path}: $!\n";

  # Create table 'processed'
  $sth = $self->{db}->prepare( "CREATE TABLE IF NOT EXISTS processed (feed INTEGER, guid varchar(255) NOT NULL, timestamp integer(32) NOT NULL);" );
  $sth->execute() or die "Could not create table 'processed' for sqlite db $self->{db_path}: $!\n";
}


=head1 NAME

Diaspora::Client::Feed - A module to post RSS feeds to Diaspora*.

=head1 SYNOPSIS

 use Diaspora::Client::Feed;
 my $d = Diaspora::Client->new(
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

B<This document describes Diaspora::Client::Feed version 0.01.>

This is a submodule of L<Diaspora::Client>. Read its documentation
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

To debug Diaspora::Client::Feed use the Perl debugger, see L<perldebug>.

=head1 DEPENDENCIES

Diaspora::Client::Feed depends on the following modules:

=over

=item Diaspora::Client

=back

=head1 AUTHOR

FIXME

=head1 VERSION

0.01

=cut



1;
