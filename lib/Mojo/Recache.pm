package Mojo::Recache;
use Mojo::Base -base;

use Mojo::DynamicMethods -dispatch;
use Mojo::Home;
use Mojo::Loader 'load_class';
use Mojo::Recache::Cache;
use Mojo::Util;

use Carp;
use Time::Seconds;

use constant BACKEND => $ENV{MOJO_RECACHE_BACKEND} || 'Storable';
use constant DEBUG   => $ENV{MOJO_RECACHE_DEBUG}   || 0;
use constant HOME    => $ENV{MOJO_RECACHE_HOME}    || 'recache';
use constant QUEUE   => $ENV{MOJO_RECACHE_QUEUE}   || 'session';

has app      => sub { scalar caller }, weak => 1;
has 'backend';
has delay    => 60;
has home     => sub { Mojo::Home->new->detect(shift->app)->child(HOME) };
has 'minion';
has queues   => sub {
  {
    daily  => ONE_DAY,
    weekly => ONE_WEEK,
  }
};
has overload => 0;

sub add_methods {
  my $self = shift;
  $self->add_method(@$_ ) for @_;
  return $self;
}

sub add_method {
  my ($self, $method, $queue, $options) = @_;
  for my $method ( ref $method eq 'ARRAY' ? @$method : $method ) {
    my $cb = sub {
      my $self = shift;
      $self->_overload(
        Mojo::Recache::Cache->new(
          args    => [@_],
          cached  => 0,
          method  => $method,
          options => $options,
          queue   => $queue || QUEUE,
          recache => $self,
          roles   => [],
        )->update
      );
    };
    Mojo::DynamicMethods::register 'Mojo::Recache', $self, $method, $cb;
  }
  return $self;
}

sub BUILD_DYNAMIC {
  my ($class, $method, $dyn_methods) = @_;
  return sub {
    my ($self, @args) = @_;
    my $dynamic = $dyn_methods->{$self}{$method};
    return $self->$dynamic(@args) if $dynamic;
    my $package = ref $self;
    Carp::croak qq{Can't locate object method "$method" via package "$package"};
  };
}

sub cache {
  my $self = shift;
  my $file = $self->home->child(@_);
  $self->_overload($self->backend->retrieve($file)->recache($self));
}

sub new {
  my $self = shift->SUPER::new;

  # How to set this as a default in the attribute?
  $self->app(scalar caller);

  my $class = 'Mojo::Recache::Backend::' . (shift || BACKEND);
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "$class" missing} if $e;

  return $self->backend($class->new(@_)->recache($self));
}

sub _overload {
  delete $_[0]->{overload} ? Mojo::Recache::Cache::overload->new($_[1]) : $_[1]
}

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

=head2 MOJO_RECACHE_QUEUE

The default policy to use to expire the cache. Defaults to 'session'.

=head1 ATTRIBUTES

L<Mojo::Recache> implements the following methods.

=head2 app

  my $app  = $recache->app;
  $recache = $recache->app(MyApp->new);

Application to cache, defaults to the caller's package. Note that this atrribute
is weakened.

=head2 backend

  my $backend = $recache->backend;
  $recache    = $recache->backend(Mojo::Recache::Backend::Storable->new);

Backend, usually a L<Mojo::Recache::Backend::Storable> object.

=head2 delay

  my $seconds = $recache->delay;
  $recache    = $recache->delay($seconds);

The number of seconds to delay processing a job after it has been enqueued,
defaults to 60 seconds.

=head2 home

  my $home = $recache->home;
  $recache = $recache->home(Mojo::Home->new);

Path to store cache files. Defaults to the same location as the main app.

=head2 minion

  my $minion = $recache->minion;
  $recache   = $recache->minion(Minion->new);

L<Minion> object this backend belongs to. Note that this attribute is weakened.

=head2 queues

  my $queues = $recache->queues;
  $recache   = $recache->queues($hash);

A hash reference of named refresh policies and the amount of seconds after last
modified in which the cache expires. The default policies are session, once,
hourly, daily, weekly, monthly, and yearly.

An undefined refresh policy (session) removes the cache when the
L<Mojo::Recache::Backend> instance is destroyed.

A refresh policy of 0 seconds is never expired.

=head2 overload

  my $bool = $recache->overload;
  $recache = $recache->overload($bool);

Overload the L<Mojo::Recache::Cache> object for array, hash, and stringify.

=head1 METHODS

L<Mojo::Recache> implements the following methods.

=head2 add_method

  my $recache = $recache->add_method(method => $queue => $options);
  my $recache = $recache->add_method([qw/method1 method2/] => $queue);

Add method from L</"app"> to be cached, using a refresh policy from L</"queues>.

=head2 add_methods

  my $recache = $recache->add_method([method1 => $q1], [method2 => $q2]);

=head2 cache

  my $cache = $recache->cache($file);

Get L<Mojo::Recache::Cache> object or return C<undef> if job does not exist.

=head2 new

  my $minion = Minion->new;
  my $minion = Minion->new('Storable');

Construct a new L<Mojo::Recache> object.

=head1 DEPENDENCIES

L<Mojolicious>

=head Optional

L<Minion>

=head1 DEBUGGING

You can set the C<MOJO_RECACHE_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_RECACHE_DEBUG=1

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/s1037989/mojo-recache>

=cut
