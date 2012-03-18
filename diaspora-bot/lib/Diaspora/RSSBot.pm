package Diaspora::RSSBot;

use strict;
use warnings;
use vars qw($VERSION @ISA);
use Diaspora::Client;
use Carp;
use JSON;
use Switch;
use DBI;
use List::MoreUtils 'any';


our $VERSION = '0.01';
our %flags   = qw(pod 1 user 1 passwd 1);

# Constants
use constant PATTERN_HREF => "<a.+?href=\"([^\"]+?)\".+?</a>";
use constant HELP_MESSAGE => "The rss-bot can be controlled with certain commands which are sent as private message. The command is always placed in the subject field of the message, while possible parameters are placed in the body. If a command has no parameters, you can put an arbitrary message into the body, as empty messages cannot be send. The rss-bot periodically processes commands at a certain frequency, so be patient as the response may take a few minutes.\n\nThe following commands a currently supported:\n\n**help**\nShows this help message which explains the usage. This command has no parameters.\n\n**subscribe**\nSubscribes you to the url(s) that are provided. Just paste one or more urls to RSS/Atom feeds into the message body, and rss-bot will subscribe you to those feeds right away.\n\n**unsubscribe**\nUnsubscribes you from the url(s) that are provided. Just paste one or more urls to RSS/Atom feeds that you no longer want to receive into the message body, and rss-bot will remove you from said feeds.";


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

  if( !exists $args{pod}    ) { croak "Parameter 'pod' is missing";   }
  if( !exists $args{user}   ) { croak "Parameter 'user' is missing";  }
  if( !exists $args{passwd} ) { croak "Parameter 'passwd' is missing";}
  if( !exists $args{db}     ) { croak "Parameter 'db' is missing";    }
  $self->{dbh}      = undef;
  $self->{db}       = $args{db};
  $self->{diaspora} = Diaspora::Client->new( pod => $args{pod}, user => $args{user}, passwd => $args{passwd} );
  $self->_db_prepare();
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

sub process_user_tasks
{
  my $self = shift;
  my @conversations = $self->{diaspora}->get_conversations();

  foreach (@conversations)
  {
    switch( $_->{subject} )
    {
      case "help"         { $self->_handle_help( $_ );        }
      case "subscribe"    { $self->_handle_subscribe( $_ );   }
      case "unsubscribe"  { $self->_handle_unsubscribe( $_ ); }
#      case "list"         { $self->_handle_list( $_ );        }      
      else                { $self->_handle_invalid( $_ );     }
    }
  }
}

sub process_feeds
{
  my $self = shift;
  my $pm = shift;

  print "Processing feeds ...\n";
}

sub _handle_help
{
  my $self = shift;
  my $pm = shift;

  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, HELP_MESSAGE );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
}

sub _handle_subscribe
{
  my $self = shift;
  my $pm = shift;
  my $params = @{$pm->{messages}}[0]->{content};
  my @feeds;
  my @added;

  my $regex = qr/${\(PATTERN_HREF)}/;
  push @feeds, $1 while $params =~ /$regex/g;

  my $st_add = $self->{dbh}->prepare( "INSERT INTO feeds VALUES( NULL, ? );" );
  my $st_get = $self->{dbh}->prepare( "SELECT * FROM feeds WHERE url=?;" );

  foreach ( @feeds )
  {
    $_ =~ s/\/$//;  # Cut off possible trailing / in order to avoid false duplicates
   
    $st_get->execute( $_ );
    if( !$st_get->fetchrow_array() )
    {
      $st_add->execute( $_ );
      $st_get->execute( $_ );
      my $row = $st_get->fetchrow_hashref();
      if( $row )
      {
        my $aspect_id = $self->{diaspora}->create_aspect( $row->{guid} );
        $self->{diaspora}->add_user_to_aspect( $pm->{from_user_id}, $aspect_id );
        push @added, $_;
#       print "### Added feed to db, created aspect and added user to aspect\n";
      }
    }
    else
    {
      $st_get->execute( $_ );
      my $row = $st_get->fetchrow_hashref();
      if( $row )
      {
        my $aspect;
        my @aspects = $self->{diaspora}->get_aspects();
        foreach ( @aspects )
        {
          if( $_->{name} eq $row->{guid} )
          {
            $aspect = $_;
            last;
          }
        }
        
        $self->{diaspora}->add_user_to_aspect( $pm->{from_user_id}, $aspect->{aspect_id} );
        push @added, $_;
#       print "### Added user to existing aspect\n";
      }
    }
  }
  
  my $response = "Request processed, you have been added to the following feeds:\n\n";
  foreach ( @added )
  {
    $response = $response."+ $_\n";
  }
  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, $response );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
}

sub _handle_unsubscribe
{
  my $self = shift;
  my $pm = shift;
  my $params = @{$pm->{messages}}[0]->{content};
  my @feeds;
  my @removed;
  my @error;

  my $regex = qr/${\(PATTERN_HREF)}/;
  push @feeds, $1 while $params =~ /$regex/g;

  my $st_get = $self->{dbh}->prepare( "SELECT * FROM feeds WHERE url=?;" );
  my $st_del = $self->{dbh}->prepare( "DELETE FROM feeds WHERE guid=?;" );

  foreach ( @feeds )
  {
    $_ =~ s/\/$//;  # Cut off possible trailing / in order to avoid false duplicates
   
    $st_get->execute( $_ );
    my $row = $st_get->fetchrow_hashref();
    if( $row )
    {
      my $aspect;
      my @aspects = $self->{diaspora}->get_aspects();
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
#        print "MATCH FOUND\n";
        $self->{diaspora}->remove_user_from_aspect( $pm->{from_user_id}, $aspect->{aspect_id} );
 
        if( ($#users_in_aspect + 1) == 1 )
        {
          if( $users_in_aspect[0] == $pm->{from_user_id} )
          {
            $self->{diaspora}->delete_aspect( $aspect->{aspect_id} );
            $st_del->execute( $row->{guid} );
          }
        }
        push @removed, $_;
      }
      else
      {
#        print "NO MATCH FOUND\n";
        push @error, $_;
      }
    }
    else
    {
#      print "NO MATCH FOUND, no db entry\n";
      push @error, $_;
    }
  }
  
  my $response = "Request processed.";
  if( ($#removed + 1) > 0 )
  {
    $response = $response."\n\nYou have been removed from the following feeds:\n\n";
    foreach ( @removed ) { $response = $response."+ $_\n"; }
  }
  if( ($#error + 1) > 0 )
  {
    $response = $response."\n\nYou are not subscribed to the following feeds, but attempted to be removed:\n\n";
    foreach ( @error ) { $response = $response."+ $_\n"; }
  }

  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, $response );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
}

sub _handle_invalid
{
  my $self = shift;
  my $pm = shift;

  my $message = "**Your request is invalid, please refer to the help to see what commands are currently supported:**\n\n".HELP_MESSAGE;

  $self->{diaspora}->reply_conversation( $pm->{conversation_id}, $message );
  $self->{diaspora}->delete_conversation( $pm->{conversation_id} );
}


#######################


sub postfeed {
  my $self = shift;
  my %arg  = @_;

  $self->{diaspora}->post( message => $self->_feed2message(%arg),
               uri     => '/status_messages' );
}

sub _feed2message {
  my $self = shift;
  my %arg  = @_;

  my $text = $self->_link(%arg)."\r\n".$self->_tags(%arg)."\r\n\r\n".$self->{diaspora}->wc->html2wiki( html => $arg{body} );

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
  return sprintf "### [%s](%s)\r\n", $self->_escape($self->_strip($arg{title})), $self->_escape($arg{link}); 
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

sub _escape {
  my $self = shift;
  my $string = shift;
	for($string)
	{
		s/^#/&#35;/g;        # Escape "#" -> "&#35;" (at beginning)
  	s/([^&])#/$1&#35;/g; # Escape "#" -> "&#35;"
	}
  return $string;
}

sub _strip {
  my $self = shift;
  my $string = shift;
  $string =~ tr/\x00-\x1F//d;
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


####################################



sub _db_prepare
{
  my $self = shift;
  $self->{dbh} = DBI->connect( "dbi:SQLite:$self->{db}" ) or die "Could not connect to sqlite db $self->{db}: $!\n";
  
  # Create table 'feeds'
  my $sth = $self->{dbh}->prepare( "CREATE TABLE IF NOT EXISTS feeds (guid INTEGER PRIMARY KEY, url varchar(255) NOT NULL UNIQUE);" );
  $sth->execute() or die "Could not create table 'feeds' for sqlite db $self->{db}: $!\n";

  # Create table 'processed'
  $sth = $self->{dbh}->prepare( "CREATE TABLE IF NOT EXISTS processed (feed INTEGER, guid varchar(255) NOT NULL, timestamp DATETIME);" );
  $sth->execute() or die "Could not create table 'processed' for sqlite db $self->{db}: $!\n";
}

sub _db_add_feed
{
  my $self  = shift;
  my $feed  = shift;
  my $sth   = $self->{dbh}->prepare( "INSERT INTO feeds VALUES( NULL, ? );" );
  $sth->execute( $feed ) or die "Could not insert ( NULL, $feed ) in table 'feeds': $!\n";
}

sub _db_del_feed
{
  my $self  = shift;
  my $feed  = shift;
  my $sth   = $self->{dbh}->prepare( "DELETE FROM feeds WHERE url=$feed;" );
  $sth->execute() or die "Could not delete $feed from table 'feeds': $!\n";
}

sub _db_get_feed_guid
{
  my $self  = shift;
  my $feed  = shift;
  my $sth   = $self->{dbh}->prepare( "INSERT INTO feeds VALUES( NULL, ? );" );
  $sth->execute( $feed ) or die "Could not insert ( NULL, $feed ) in table 'feeds': $!\n";
}

sub _db_add_processed
{
  my $self  = shift;
  my $feed  = shift;
  my $guid  = shift;
  my $sth   = $self->{dbh}->prepare( "INSERT INTO processed VALUES( ?, ? );" );
  $sth->execute( $feed, $guid ) or die "Could not insert ( $feed, $guid ) in table 'processed': $!\n";
}

sub _db_feeds_exists
{
  my $self  = shift;
  my $url   = shift;

  my $sth   = $self->{dbh}->prepare( "SELECT * FROM feeds WHERE url = ?;" );
  $sth->execute( $url ) or die "Could not find $url in table 'feeds': $!\n";
  my $row = $sth->fetchrow_hashref;
  if( $row )
  {
    if( exists $row->{url} )
    {
      return 1;
    }
  }
  return 0;
}

sub _db_processed_exists
{
  my $self  = shift;
  my $feed  = shift;
  my $guid  = shift;

  my $sth   = $self->{dbh}->prepare( "SELECT * FROM processed WHERE feed = ? AND guid = ?;" );
  $sth->execute( $feed, $guid ) or die "Could not find ($feed, $guid) in table 'processed': $!\n";
  my $row = $sth->fetchrow_hashref;
  if( $row )
  {
    if( exists $row->{url} )
    {
      return 1;
    }
  }
  return 0;
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
