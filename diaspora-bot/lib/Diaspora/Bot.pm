package Diaspora::Bot;

use strict;
use warnings;
use vars qw($VERSION @ISA);
use Carp;

use LWP::UserAgent;
use HTML::Entities;
use URI::Escape;
use HTML::WikiConverter;
use JSON;
use utf8;

our $VERSION = '0.01';
our %flags   = qw(pod 1 user 1 passwd 1 csrftoken 0 loggedin 0 ua 0 wc 0);


foreach my $flag (keys %flags) {
  my $pkg = __PACKAGE__;
  my $fun = "${pkg}::${flag}";
  eval qq(
    *$fun = sub {
      my \$self = shift;
      my \$val  = shift;
      if (\$val) {
        \$self->{$flag} = \$val;
      }
      return \$self->{$flag};
    }
  );#)
}

sub new {
  my $class = shift;
  my $self = bless {}, $class;
  return $self->init(@_);
}

sub init {
  my $self = shift;
  my %arg  = @_;
  my $pkg  = __PACKAGE__;

  foreach my $flag (keys %arg) {
    if (! exists $flags{$flag}) {
      croak "$flag is no valid param for $pkg!";
    }
    else {
      $self->$flag($arg{$flag});
    }
  }
  foreach my $flag (keys %flags) {
    if ($flags{$flag} && ! exists $arg{$flag}) {
      croak "missing required $flag param!";
    }
  }

  $self->ua(LWP::UserAgent->new( keep_alive => 1 ));
  $self->wc(HTML::WikiConverter->new( dialect => 'Diaspora' ));

  return $self;
}


sub _login {
  my $self = shift;

  return if $self->loggedin;

  my $csrf_param;

  $self->ua->cookie_jar({});
  
  my $sign_in_page = $self->ua->get( $self->pod.'/users/sign_in' )->decoded_content()
    or croak "Could not connect to " . $self->pod . ": $!";

  $sign_in_page =~ m/"csrf-param" content="([^"]+)"/ or croak "Could not find csrf-param on loginpage of " . $self->pod;
  $csrf_param = decode_entities($1);
  $sign_in_page =~ m/"csrf-token" content="([^"]+)"/ or croak "Could not find csrf-token on loginpage of " . $self->pod;
  $self->csrftoken(decode_entities($1));

  my $request = HTTP::Request->new( 'POST', $self->pod.'/users/sign_in' );
  $request->header( 'Connection' => 'keep-alive' );
  $request->header( 'Content-Type' => 'application/x-www-form-urlencoded' );

  my %plist = (
	       utf8                    => '%E2%9C%93',
	       uri_escape($csrf_param) => uri_escape($self->csrftoken),
	       'user%5Busername%5D'    => $self->user,
	       'user%5Bpassword%5D'    => uri_escape($self->passwd),
	       'user%5Bremember_me%5D' => 0,
	       commit                  => 'Sign in'
	      );

  my $post = join '&', map { join '=', ($_, $plist{$_}) } keys %plist;

  $request->content( $post );
  my $res = $self->ua->request( $request ) or croak "Could not login to " . $self->pod . ": $!" ;
  if(! $res->is_success) {
    croak "Could not login to " . $self->pod . ": " . $res->status_line ;
  }
  $self->loggedin(1);
}

sub _logout {
  my $self = shift;
  my $request = HTTP::Request->new( 'GET', $self->pod.'/users/sign_out' );
  $request->header( 'Connection' => 'keep-alive' );
  my $res = $self->ua->request( $request ) or croak "Could not logout from " . $self->pod . ": $!" ;  
  if(! $res->is_success) {
    croak "Could not logout from " . $self->pod . ": " . $res->status_line ;
  }
  $self->loggedin(0);
}

sub logout {
  my $self = shift;

  if ($self->loggedin) {
    return $self->_logout;
  }
  else {
    return;
  }
}

sub post {
  my $self = shift;
  my %arg  = @_;

  $self->_login();

  my $json = JSON->new->allow_nonref;
  if(! utf8::is_utf8($arg{message})) {
    $json = $json->utf8(0);
  }

  my $json_message = $json->encode($arg{message});

  my $request = HTTP::Request->new( 'POST', $self->pod . $arg{uri} );
  $request->header( 'Content-Type' => 'application/json; charset=UTF-8' );
  $request->header( 'Connection'   => 'keep-alive' );
  $request->header( 'X-CSRF-Token' => $self->csrftoken );
  $request->content( $json_message );
  $self->ua->request( $request ) or die "Could not post message to " . $self->pod . "$arg{uri}: $!";
}

sub get {
  my $self = shift;
  my %arg  = @_;

  $self->_login();

  my $request = HTTP::Request->new( 'GET', $self->pod . $arg{uri} );
  $request->header( 'Content-Type' => 'application/json; charset=UTF-8' );
  $request->header( 'Connection'   => 'keep-alive' );
  $request->header( 'X-CSRF-Token' => $self->csrftoken );
  my $res = $self->ua->request( $request ) or die "Could not post message to " . $self->pod . "$arg{uri}: $!";
   
  if(! $res->is_success) {
    croak "Could not get $arg{uri} from " . $self->pod . ": " . $res->status_line ;
  }

  my $json = JSON->new->allow_nonref;

  return $json->decode( $res->content );
}

sub _escapeString {
  my $self   = shift;
  my $string = shift;
 
  $string =~ s/\\/\\\\/g; # Replace '\' with '\\'
  $string =~ s/\"/\\\"/g; # Replace '"' with '\"'
  return $string;
}

sub _escapeMarkup {
  my $self   = shift;
  my $string = shift;

  $string =~ s/([^&])#/$1&#35;/g; # Escape "#" -> "&#35;"
  return $string;
}



1;
