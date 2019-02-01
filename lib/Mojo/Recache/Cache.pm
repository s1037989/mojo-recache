package Mojo::Recache::Cache;
use Mojo::Base -base;

use Mojo::JSON 'j';
use Mojo::Util qw(b64_encode md5_sum);

use B::Deparse;
use Data::Structure::Util 'unbless';
use Scalar::Util 'blessed';

use constant DEBUG => $ENV{MOJO_RECACHE_DEBUG} || 0;

has args    => sub { [] };
has recache => sub { die }, weak => 1;
has cached  => 0;
has data    => undef;
has method  => sub { die };
has name    => sub { md5_sum(b64_encode(shift->serialize)) };
has options => sub { [] };
has roles   => sub { [] };

sub new {
  my $self = shift->SUPER::new(@_);
  $self->$_ for qw/args data method name roles/;
  DEBUG and warn sprintf '-- new cache %s', $self->name;
  return $self;
}

sub reftype { Scalar::Util::reftype(shift->data) }

sub serialize {
  my $self = shift;
  my $deparse = B::Deparse->new("-p", "-sC");
  return j([
    map {
      ref eq 'CODE' ? $deparse->coderef2text($_) : unbless($_)
    } $self->method, $self->args, $self->options
  ]);
}

sub short { substr(shift->name, 0, 6) }

sub restore_roles {
  my $self = shift;
  return $self unless blessed $self->data && @{$self->roles};
  $self->data->with_roles(@{$self->roles}) if $self->data->can('with_roles');
  return $self;
}

sub remove_roles {
  my $self = shift;
  return $self unless blessed $self->data && $self->data->can('with_roles');
  my $class = ref $self->data;
  my ($base_class, $roles) = split /__WITH__/, $class;
  return $self unless $roles;
  $self->roles([split /__AND__/, $roles]);
  if ( $self->reftype eq 'ARRAY' ) {
    $self->data($base_class->new(@{$self->data}));
  } elsif ( $self->reftype eq 'HASH' ) {
    $self->data($base_class->new(%{$self->data}));
  } elsif ( $self->reftype eq 'SCALAR' ) {
    $self->data($base_class->new(${$self->data}));
  } else {
    die "Unsupported type";
  }
  return $self;
}

1;

=encoding utf8

=head1 NAME 

Mojo::Recache - Provide caching and automatic refreshing for your app

=head1 SYNOPSIS

Used in a module:

  package Abc;
  use Mojo::Base -base;
  use Mojo::Recache;
  has cache => sub { Mojo::Recache->new };
  sub cacheable_thing {
    sleep 5;
    return time;
  }

  package main;
  use Abc;
  my $abc = Abc->new;
  warn $abc->cache->cacheable_thing;
  warn $abc->cache->cacheable_thing;

Used in a main app:

  use Mojo::Recache;
  sub cacheable_thing {
    sleep 5;
    return time;
  }
  my $cache = Mojo::Recache->new;
  warn $cache->cacheable_thing;
  warn $cache->cacheable_thing;

Used in a Mojolicious::Lite app:

  use Mojolicious::Lite;
  helper cache => sub { Mojo::Recache->new(expires => 3600, app => shift) };
  helper cacheable_think => sub { sleep 5; return time; };
  get '/' => sub { $_[0]->render(text => $_[0]->cache->cacheable_thing) };
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

=head1 EVENTS

L<Mojo::Recache> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 enqueued

  $cache->on(enqueued => sub {
    my ($cache, $id) = @_;
    ...
  });

Emitted after a cache auto-refresh job has been enqueued, in the process that
enqueued it.

  $cache->on(enqueued => sub {
    my ($cache, $id) = @_;
    say "Job $id has been enqueued.";
  });

=head2 retreived

  $cache->on(retreived => sub {
    my ($cache, $name) = @_;
    ...
  });

Emitted after retrieving data from a stored cache file.

  $cache->on(retreived => sub {
    my ($cache, $name) = @_;
    say "Data from $name has been retreived.";
  });

=head2 stored

  $cache->on(stored => sub {
    my ($cache, $name) = @_;
    ...
  });

Emitted after executing the named subroutine from L</"app"> and storing in a
local cache file.

  $cache->on(stored => sub {
    my ($cache, $name) = @_;
    say "Data for $name has been stored.";
  });

=head1 ENVIRONMENT

The behavior of L<Mojo::Recache::Backend::Storable> can be controlled through
the use of the following environment variables.

=head2 MOJO_RECACHE_DEBUG

Write warnings to STDERR when true. Defaults to false.

=head1 ATTRIBUTES

L<Mojo::Recache> implements the following attributes.

=head2 app

  my $app = $cache->app;
  $cache  = $cache->app(__PACKAGE__);

Package, class, or object to provide caching for. Note that this attribute is
weakened.

=head2 cachedir

  my $cachedir = $cache->cachedir;
  $cache       = $cache->cachedir($dirname);

Child directory of L</"home"> where cache files are stored and retrieved.
Defaults to 'cache'.

=head2 cron

  my $bool = $cache->cron;
  $cache   = $cache->cron($bool);

Instead of refreshing caches with a L<Minion> worker, use cron.

=head2 expires

  my $expires = $cache->expires;
  $cache      = $cache->expires($seconds);

When to consider a cachefile to be too old and force refreshing. Defaults to 30
days.

=head2 extra_args

  my $array = $cache->extra_args;
  $cache    = $cache->extra_args([]);

Extra arguments for L</"name"> to generate a random filename.

=head2 home

  my $home = $cache->home;
  $cache   = $cache->home(Mojo::Home->new);

The parent of the directory where cache files are stored. Defaults to the same
location as the main app.

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

=head1 METHODS

=head2 AUTOLOAD

  package main;
  sub cacheable_thing { sleep 5; return time; }
  my $cache = Mojo::Recache->new;
  warn $cache->cacheable_thing;

Cache the return value from the L</"app">'s subroutine. Return cached data
without refreshing if the cache exists and has not expired. Enqueue a
refreshing job if L<Minion> is enabled.

=head2 enqueue

  my $cache = $cache->enqueue($method => @args);

If L<Minion> is enabled, use L<Minion> to enqueue a new job for task "$method".

=head2 enqueued

  my $bool = $cache->enqueued($name);

If L<Minion> is enabled, check if a task "cache" for the provided cache name is
enqueued.

=head2 file

  my $file = $cache->file($name);

Return a L<Mojo::File> object for the specified cache file. The location is a
child of L</"cachedir">, itself a child of L</"home">. The full directory path
is created if it does not already exist.

=head2 merge_options

  $cache = $cache->set_options(option => 'value');
  $cache = $cache->set_options(queue => 'monthly', delay => 0);

Merge the specified arguments into </"options">.

=head2 name

  my $name = $cache->name($sub_name => @args);

Generate a unique name for a cache using all of the specified arguments as
factors.

=head2 retrieve

  my $data = $cache->retrieve($name);

Return the data from a cache file if it exists and has been modified within
L</"expires"> seconds. Reapply any roles to the recreated object instance.

=head2 short

  $short = $cache->short($name);

Return a shortened version of the cache name: the first 6 characters.

=head2 start

  $short = $cache->short($name);

Return a shortened version of the cache name: the first 6 characters.

=head2 store

  $data = $cache->store($sub_name => @args);

Run the specified subroutine from L</"app"> and store it in L</"file">,
carefully retaining any applied roles to the object instance for
reconstructing the data upon retrieval.

=head2 use_options

  $cache = $cache->use_options(option => 'value');
  $cache = $cache->use_options(queue => 'monthly', delay => 0);

Create a new cache and merge the specified arguments into </"options">.

=head1 DEPENDENCIES

L<Mojolicious>, L<B::Deparse>, L<Storable>

=head2 optional

L<Minion>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/s1037989/mojo-recache>, L<Minion>

=cut