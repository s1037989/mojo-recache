package Mojo::Recache::Backend;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::Home;
use Mojo::Recache::Cache;

use Carp 'croak';
use Scalar::Util 'blessed';
use Time::Seconds;

use constant DEBUG    => $ENV{MOJO_RECACHE_DEBUG}   || 0;
use constant EXPIRES  => $ENV{MOJO_RECACHE_EXPIRES} || undef;
use constant REFRESH  => $ENV{MOJO_RECACHE_REFRESH} || 'session';

# This attribute exists solely for the purpose of Mojo::Recache
has app        => sub { scalar caller }, weak => 0;

has cache      => undef;
has delay      => 60;
has expires    => sub {
  {
    session => undef,
    once    => 0,
    hourly  => ONE_HOUR,
    daily   => ONE_DAY,
    weekly  => ONE_WEEK,
    monthly => ONE_MONTH,
    yearly  => ONE_YEAR,
  }
};
has minion     => undef, weak => 1;
has options    => sub { {attempts => 3} };
has recachedir => sub { die };
has refresh    => REFRESH;

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  $self->cache->data->$method(@_);
}

sub data { shift->cache->data }

sub DESTROY {
  my $self = shift;
  return unless defined $self->expires->{$self->refresh};
  DEBUG and warn sprintf '-- removing cache %s', $self->file;
}

sub enqueue {
  my $self = shift;
  $self->emit('enqueue');
  return $self;
}

sub enqueued {
  my $self = shift;
  return 0;
}

sub expire { shift->remove }

sub expired {
  my $self = shift;
  return 1 if ! -e $self->file->to_string;
  my $expires = $self->expires->{$self->refresh || REFRESH} || EXPIRES;
  return $expires && time - $self->file->stat->mtime > $expires;
}

sub file {
  my $self = shift;
  $self->recachedir->make_path->child($self->cache->name);
}

sub remove {
  my $self = shift;
  $self->file->remove;
  $self->emit('removed');
}

sub retrieve { croak 'Method "retrieve" not implemented by subclass' }

sub store { croak 'Method "store" not implemented by subclass' }

sub touch {
  my $self = shift;
  $self->file->touch;
  $self->emit('touched');
}

1;

=encoding utf8

=head1 NAME 

Mojo::Recache::Backend - Backend base class

=head1 SYNOPSIS

  package Mojo::Recache::Backend::MyBackend;
  use Mojo::Base 'Mojo::Recache::Backend';

  sub retrieve {...}
  sub store    {...}

=head1 DESCRIPTION

L<Mojo::Recache::Backend> is an abstract base class for L<Mojo::Recache>
backends, like L<Mojo::Recache::Backend::Storable>.

=head1 EVENTS

L<Mojo::Recache> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 removed

  $backend->on(removed => sub {
    my $backend = shift;
    ...
  });

Emitted after a cache deposit has been removed.

  $backend->on(removed => sub {
    my $name = shift->cache->name;
    say "Cache $name has been removed.";
  });

=head2 touched

  $backend->on(touched => sub {
    my $backend = shift;
    ...
  });

Emitted after a cache deposit has been artifically refreshed.

  $backend->on(touched => sub {
    my $name = shift->cache->name;
    say "Cache $name has been touched.";
  });

=head1 ENVIRONMENT

The behavior of L<Mojo::Recache::Backend> can be controlled through the use of
the following environment variables.

=head2 MOJO_RECACHE_DEBUG

Write warnings to STDERR when true. Defaults to false.

=head2 MOJO_RECACHE_EXPIRES

Write warnings to STDERR when true. Defaults to false.

=head2 MOJO_RECACHE_REFRESH

Write warnings to STDERR when true. Defaults to false.

=head1 ATTRIBUTES

L<Mojo::Recache> implements the following attributes.

=head2 app

  my $app = $cache->app;
  $cache  = $cache->app(__PACKAGE__);

Package, class, or object to provide caching for. Note that this attribute is
weakened.

=head2 cache

  my $cachedir = $cache->cachedir;
  $cache       = $cache->cachedir($dirname);

Child directory of L</"home"> where cache files are stored and retrieved.
Defaults to 'cache'.

=head2 delay

  my $bool = $cache->cron;
  $cache   = $cache->cron($bool);

Instead of refreshing caches with a L<Minion> worker, use cron.

=head2 expires

  my $expires = $cache->expires;
  $cache      = $cache->expires($hash);

A hash reference of named L</"refresh"> policies and the amount of seconds
after last modified in which the cache expires. The default policies are
session, once, hourly, daily, weekly, monthly, and yearly.

An undefined refresh policy (session) removes the cache when the
L<Mojo::Recache::Backend> instance is destroyed.

A refresh policy of 0 seconds is never expired.

=head2 minion

  my $minion = $cache->minion;
  $cache     = $cache->minion(Minion->new);

L<Minion> object to handle automatic refreshing; disabled by default.

=head2 options

  my $options = $cache->options;
  $cache      = $cache->options({%options});

Hashref of options to be used by L<Minion> when auto-refreshing cache data.

These options are currently set by default:

=over 2

=item attempts

Defaults to 3.

=item delay

If cron is disabled, defaults to 1 hour.
If cron is enabled, defaults to no delay.

=item queue

If cron is disabled, defaults to "recache".
If cron is enabled, defaults to "cron".

=back

=head2 recachedir

  my $home = $cache->home;
  $cache   = $cache->home(Mojo::Home->new);

The parent of the directory where cache files are stored. Defaults to the same
location as the main app.

=head2 refresh

  my $bool = $cache->cron;
  $cache   = $cache->cron($bool);

The refresh policy to use. Defaults to 'session'.

=head1 METHODS

=head2 AUTOLOAD

  package main;
  sub cacheable_thing { sleep 5; return time; }
  my $cache = Mojo::Recache->new;
  warn $cache->cacheable_thing;

Cache the return value from the L</"app">'s subroutine. Return cached data
without refreshing if the cache exists and has not expired. Enqueue a
refreshing job if L<Minion> is enabled.

=head2 data

  my $data = $backend->data;

L<Mojo::Recache::Backend> shortcut to L<Mojo::Recache::Cache/"data">.

=head2 enqueue

  my $cache = $cache->enqueue($method => @args);

If L<Minion> is enabled, use L<Minion> to enqueue a new job for task "$method".

=head2 enqueued

  my $bool = $cache->enqueued($name);

If L<Minion> is enabled, check if a task "cache" for the provided cache name is
enqueued.

=head2 expire

  my $file = $cache->file($name);

Return a L<Mojo::File> object for the specified cache file. The location is a
child of L</"cachedir">, itself a child of L</"home">. The full directory path
is created if it does not already exist.

=head2 expired

  my $file = $cache->file($name);

Return a L<Mojo::File> object for the specified cache file. The location is a
child of L</"cachedir">, itself a child of L</"home">. The full directory path
is created if it does not already exist.

=head2 file

  $cache = $cache->set_options(option => 'value');
  $cache = $cache->set_options(queue => 'monthly', delay => 0);

Merge the specified arguments into </"options">.

=head2 remove

  my $name = $cache->name($sub_name => @args);

Generate a unique name for a cache using all of the specified arguments as
factors.

=head2 retrieve

  my $data = $cache->retrieve($name);

Return the data from a cache file if it exists and has been modified within
L</"expires"> seconds. Reapply any roles to the recreated object instance.

=head2 store

  $data = $cache->store($sub_name => @args);

Run the specified subroutine from L</"app"> and store it in L</"file">,
carefully retaining any applied roles to the object instance for
reconstructing the data upon retrieval.

=head2 touch

  $cache = $cache->use_options(option => 'value');
  $cache = $cache->use_options(queue => 'monthly', delay => 0);

Create a new cache and merge the specified arguments into </"options">.

=head1 DEPENDENCIES

L<Mojolicious>

=head2 optional

L<Minion>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/s1037989/mojo-recache>, L<Minion>

=cut