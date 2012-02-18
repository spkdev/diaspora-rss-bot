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

our $VERSION = '0.03';
our %flags   = qw(pod 1 user 1 passwd 1 csrftoken 0 ua 0 wc 0 loggedin 0);

foreach my $flag (keys %flags) {
  my $pkg = __PACKAGE__;
  my $fun = "${pkg}::${flag}";
  eval qq(
    *$fun = sub {
      my \$self = shift;
      my \$val  = shift;
      if (defined(\$val)) {
        \$self->{\$flag} = \$val;
      }
      return \$self->{\$flag};
    }
  );
}


sub new {
  my $class = shift;
  my $self = bless { }, $class;
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
    elsif(! exists $arg{$flag}) {
      $self->{$flag} = $flags{$flag};
    }
  }

  $self->ua(LWP::UserAgent->new( keep_alive => 1 ));
  $self->ua->cookie_jar({});
  $self->wc(HTML::WikiConverter->new( dialect => 'Diaspora' ));
  $self->loggedin(0);
  return $self;
}


sub _login {
  my $self = shift;

  if (!$self->loggedin) {
    my $csrf_param;
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
    if(! $res->code == 302) {
      croak "Could not login to " . $self->pod . ": " . $res->status_line ;
    }
    $self->loggedin(1);
  }
}

sub _logout {
  my $self = shift;
  my $request = HTTP::Request->new( 'GET', $self->pod.'/users/sign_out' );
  $request->header( 'Connection' => 'keep-alive' );
  my $res = $self->ua->request( $request ) or croak "Could not logout from " . $self->pod . ": $!" ;
  if(! $res->code == 302) {
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
  $self->ua->request( $request ) or die "POST request failed: " . $self->pod . "$arg{uri}: $!";
}

sub get {
  my $self = shift;
  my %arg  = @_;

  $self->_login();

  my $request = HTTP::Request->new( 'GET', $self->pod . $arg{uri} );
  $request->header( 'Accept'        => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' );
  $request->header( 'Connection'    => 'keep-alive' );
  $request->header( 'Pragma'        => 'no-cache' );
  $request->header( 'Cache-Control' => 'no-cache' );
  my $response = $self->ua->request( $request ) or die "GET request failed: " . $self->pod . "$arg{uri}: $!";

  if( $response->is_success )
  {
    return $response->decoded_content;
  }
  else
  {
    return "";
  }
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


=head1 NAME

Diaspora::Bot - A perl interface to the diaspora social network.

=head1 SYNOPSIS

 use Diaspora::Bot;
 my $d = Diaspora::Bot->new(
                             pod    => 'https://foo.bar',
                             user   => 'yourbot',
                             passwd => 'secret'
                           );
 $d->post(
           uri     => '/status_messages',
           message => {
                        status_message => { text => 'blah..' },
                        aspect_ids     => 'public'
                      }
         );

 my $hashref = $d->get(uri => '/conversations');

=head1 DESCRIPTION

B<This document describes Diaspora::Bot version 0.01.>

Diaspora* is a federated social network. This module
provides an API to access diaspora by using perl using
its json HTTP interface.

In order to use it, you'll have to create an account
for your bot first on your pod.

The module doesn't "know" the API urls of Diaspora*, you
have to provide them when calling L<post()> or L<get()>.
Once the API gets official and stable a more abstract
interface might be added to the module. However, the
lowlevel methods  L<post()> or L<get()> will remain
anyway.

=head1 LOGIN

The module does automatically login to Diaspora* if
required. As long as you don't call L<post()> or L<get()>
nothing will happen.

=head1 METHODS

=head2 post()

 $d->post(
           uri     => '/status_messages',
           message => {
                        status_message => { text => 'blah..' },
                        aspect_ids     => 'public'
                      }
         );

The B<post()> method posts a JSON encoded message to
Diaspora*. The message will be automatically converted
to JSON, all you have to do is to provide a perl hash
reference.

If you use the B<post()> method to send a posting, then
you are responsible to format it using the Diaspora*
wiki syntax. You might use the method L<wc()> for this
which is in fact an L<HTML::WikiConverter> object loaded
with the required syntax submodule.

The B<post()> method automatically logs into Diaspora*
if not already done so and the module remains logged in,
until the program ends or you call the L<logout()> method.

=head2 get()

 my $hashref = $d->get(uri => '/conversations');

The B<get()> method fetches something from Diaspora*.
Like with L<post()>, you have to provide the url for
this yourself.

It also logs in automatically and returns a hashref
of what Diaspora* returned.

See L<https://github.com/diaspora/diaspora/wiki/API-v1>
for details how the structure will look like.

=head2 logout()

 $d->logout();

You can call B<logout()> if you want/need, but it's
optional. The session will be stored in memory only,
so if you just finish the program, the session is lost.

=head2 wc()

 my $wifified = $d->wc( html => '<a href="/blah">blubb</a>');

returns:

 [blubb](/blah)

This is just an L<HTML::WikiConverter> object which
can be used to convert HTML to Diaspora* wiki syntax.

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

To debug Diaspora::Bot use the Perl debugger, see L<perldebug>.

=head1 DEPENDENCIES

Diaspora::Bot depends on the following modules:

=over

=item File::Pid

=item XML::FeedPP

=item Getopt::Long

=item Config::Tiny

=item Digest::MD5

=item DBD::SQLite

=item LWP::UserAgent

=item HTML::Entities

=item URI::Escape

=item HTML::WikiConverter

=item HTML::WikiConverter::Diaspora

=back

=head1 AUTHOR

FIXME

=head1 VERSION

0.01

=cut

1;
