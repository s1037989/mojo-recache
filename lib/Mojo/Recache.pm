package Mojo::Recache;
use Mojo::Base 'Mojo::EventEmitter';

use overload
  bool => sub {1},
  fallback => 1;

use Mojo::Home;
use Mojo::Loader 'load_class';
use Mojo::Recache::Cache;

use Carp;
use Scalar::Util 'blessed';
use Time::Seconds;

use constant BACKEND => $ENV{MOJO_RECACHE_BACKEND} || 'Storable';
use constant DEBUG   => $ENV{MOJO_RECACHE_DEBUG}   || 0;
use constant HOME    => $ENV{MOJO_RECACHE_HOME}    || 'recache';
use constant REFRESH => $ENV{MOJO_RECACHE_REFRESH} || 'session';

has app      => undef;
has backend  => BACKEND;
has cache    => undef;
has delay    => 60;
has expires  => sub {
  {
    session => undef,
    never   => 0,
    hourly  => ONE_HOUR,
    daily   => ONE_DAY,
    weekly  => ONE_WEEK,
    monthly => ONE_MONTH,
    yearly  => ONE_YEAR,
  }
};
has home     => sub { Mojo::Home->new->detect(shift->app)->child(HOME) };
has minion   => undef;
has options  => sub { {attempts => 3} };
has overload => 0;
has refresh  => REFRESH;

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  $self->_cache_method($method => [@_], sub {
    $_->retrieve or $_->store;
  });
}

# Set a good default in the attribute
sub new { shift->SUPER::new(app => scalar caller, @_)->_add_task }

sub _add_task {
  my $self = shift;
  return $self unless my $minion = $self->minion;
  #$minion->app($self);
  $minion->add_task(HOME => sub {
    my ($job, $method) = (shift, shift);
    #my $self = $job->app;
    $self->_cache_method($method => [@_], sub {
      $_->store
    });
  }) unless grep { $_ eq HOME } @{$minion->tasks};
  return $self;
}

sub _backend {
  my $class = 'Mojo::Recache::Backend::' . (shift || BACKEND);
  my $e     = load_class $class;
  Carp::croak ref $e ? $e : qq{Backend "$class" missing} if $e;
  return $class;
}

sub _cache_method {
  my ($self, $method, $args, $cb) = @_;
  my $cache = Mojo::Recache::Cache->new(method => $method, args => $args);
  $_ = _backend($self->backend)->new(recache => $self, cache => $cache);
  $_->$cb if ref $cb eq 'CODE';
  return $self->overload ? Mojo::Recache::overload->new($_) : $_;
}

package Mojo::Recache::overload;
use overload
  '@{}'    => sub { ${$_[0]}->cache ? ${$_[0]}->cache->data : [] },
  '%{}'    => sub { ${$_[0]}->cache ? ${$_[0]}->cache->data : {} },
  bool     => sub {1},
  '""'     => sub { ${$_[0]}->cache ? ${$_[0]}->cache->data : '' },
  fallback => 1;

sub new { bless \$_[1], $_[0] }

1;

=encoding utf8

=head1 NAME 

Mojo::Recache - Provide caching and automatic refreshing for your app

=head1 SYNOPSIS

Used in a module:

  package Slow;
  use Mojo::Base -base;
  use Mojo::Recache;
  has recache => sub { Mojo::Recache->new(app => shift) };
  sub cacheable_thing { sleep shift->cached + shift }

  package main;
  use Slow;
  my $slow = Slow->new->recache;
  $slow->cacheable_thing(1);
  warn $slow->[0];
  warn $slow->cacheable_thing(1)->data->[0];

Used in a main app:

  use Mojo::Recache;
  sub cacheable_thing { sleep // 1 }
  my $r = Mojo::Recache->new;
  $r->cacheable_thing(1);
  warn $r->[0];
  warn $r->cacheable_thing(1)->data->[0];

Used in a Mojolicious::Lite app:

  use Mojolicious::Lite;
  helper cache => sub { Mojo::Recache->new(app => shift) };
  helper cacheable_thing => sub { sleep shift->cached + shift }
  get '/' => sub { $_[0]->render(text => $_[0]->cacheable_thing(1)->data->[0]) };
  app->start;

Refreshed with a minion worker (takes the same arguments as
L<Minion::Command::worker>:

  $cache->start('worker', '-q', 'cache');

Refreshed with a cron job (takes the same arguments as
L<Minion::Command::job>:

  $cache->start('job', '-q', 'monthly');

=head1 DESCRIPTION

L<Mojo::Recache> provides caching and automatic refreshing for your app. It
caches return values from subroutines and stores them with L<Storable>. Stored
data is automatically refreshed using a L<Minion> worker or through a cron job.

Tasks that are not yet cached will be executed in real-time and a copy of the
task's return value will be stored in a local file for fast retrieval the next
time.

Refreshing can be handled by any job scheduler such as cron, but also includes
built-in support for L<Minion>. If no job scheduling is configured, refreshing
will occur automatically on demand, and this might slow down your application
periodically when refresh is necessary. With a typical job scheduler, such as
cron, caches can be scheduled to be refreshed at specific times of day. With
L<Minion>, caches are refreshed at the time that the cache expires.

Remove the cache deposit for the undefined refresh policy, if applicable, when
the object instance is destroyed.

=head1 ENVIRONMENT

The behavior of L<Mojo::Recache::Backend> can be controlled through the use of
the following environment variables.

=head2 MOJO_RECACHE_BACKEND

Write warnings to STDERR when true. Defaults to Storable.

=head2 MOJO_RECACHE_DEBUG

Write warnings to STDERR when true. Defaults to false.

=head2 MOJO_RECACHE_HOME

Write warnings to STDERR when true. Defaults to false.

=head2 MOJO_RECACHE_REFRESH

The default policy to use to expire the cache. Defaults to 'session'.

=head1 ATTRIBUTES

L<Mojo::Recache> implements the following methods.

=head2 app

  my $app  = $backend->app;
  $backend = $backend->app(MyApp->new);

Application to cache, defaults to the caller's package.

=head2 cache

  my $cache = $backend->cache;
  $backend  = $backend->cache(Mojo::Recache::Cache->new);

A single cache instance for one unique call to a method in the application.

=head2 delay

  my $seconds = $backend->delay;
  $backend    = $backend->delay($seconds);

The number of seconds to delay processing a job after it has been enqueued,
defaults to 60 seconds.

=head2 expires

  my $expires = $cache->expires;
  $cache      = $cache->expires($hash);

A hash reference of named L</"refresh"> policies and the amount of seconds
after last modified in which the cache expires. The default policies are
session, once, hourly, daily, weekly, monthly, and yearly.

An undefined refresh policy (session) removes the cache when the
L<Mojo::Recache::Backend> instance is destroyed.

A refresh policy of 0 seconds is never expired.

=head2 home

  my $home = $cache->home;
  $cache   = $cache->home(Mojo::Home->new);

The parent of the directory where cache files are stored. Defaults to the same
location as the main app.

=head2 minion

  my $minion = $backend->minion;
  $backend   = $backend->minion(Minion->new);

L<Minion> object to handle automatic refreshing; disabled by default. Note that
this attribute is weakened.

=head2 options

  my $hash = $backend->options;
  $backend = $backend->options($hash);

Hashref of options to be used by L<Minion> when auto-refreshing cache data.

These options are currently set by default:

=over 2

=item attempts

Defaults to 3.

=item delay

If cron is disabled, defaults to 1 minute.
If cron is enabled, defaults to no delay.

=item queue

If cron is disabled, defaults to "recache".
If cron is enabled, defaults to "cron".

=back

=head2 refresh

  my $bool = $cache->cron;
  $cache   = $cache->cron($bool);

The refresh policy to use. Defaults to 'session'.

=head1 METHODS

L<Mojo::Recache> implements the following methods.

=head2 AUTOLOAD

  package main;
  sub cacheable_thing { sleep shift // 1 }
  my $r = Mojo::Recache->new->recache;
  warn $r->cacheable_thing->data;
  warn $rr->cache->data;

Cache the return value from the L</"app">'s subroutine using
L<Mojo::Recache::Backend>.

Any public method called on a L<Mojo::Recache> instance is called

=head2 new

  package main;
  sub cacheable_thing { sleep shift // 1 }
  my $r = Mojo::Recache->new;
  warn $r->cacheable_thing->data;
  warn $rr->cache->data;

Construct a new L<Mojo::Recache> object for caching methods for the application
in L<Mojo::Recache::Backend/"app">. All options are passed to the
L<Mojo::Recache::Backend> instance

These options are currently available:

=over

=item app

  app => MyApp->new

Application to cache, defaults to the class name of the caller.

=item backend

  backend => Mojo::Recache::Backend::Storable->new

Backend, usually a L<Mojo::Recache::Backend::Storable> object.

=item recachedir

  recachedir => 'recache'
  recachedir => '/tmp/recache'
  recachedir => Mojo::File->new

The recache directory of your application, defaults to a child directory named
"recache" of a L<Mojo::File> object relative to your application's home.

The default child directory can be overridden by the MOJO_RECACHE_DIR
environment variable.

=back

=head1 OPERATORS

=head2 array

  my @data = @$recache;

Alias for L<Mojo::Recache::Cache/"data">.

  $recache->cache->data([1..2]);
  # 1
  $recache->[0];

=head2 bool

  my $bool = !!$recache;

Always true.

=head2 hash

  my %data = %$recache;

Alias for L<Mojo::Recache::Cache/"data">.

  $recache->cache->data({id => 1});
  # 1
  $recache->{id};

=head2 stringify

  my $str = "$recache";

Alias for L<Mojo::Recache::Cache/"data">.

  $recache->cache->data(1);
  # 1
  "$recache";

=head1 DEPENDENCIES

L<Mojolicious>

=head1 DEBUGGING

You can set the C<MOJO_WEBSOCKET_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_RECACHE_DEBUG=1

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/s1037989/mojo-recache>, L<Minion>

=cut
