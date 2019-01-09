package Mojo::Recache;
use Mojo::Base 'Mojo::EventEmitter';

use Minion;
use Mojo::Home;
use Mojo::JSON 'j';
use Mojo::Log;
use Mojo::Util qw/b64_decode b64_encode md5_sum/;
use Mojolicious::Commands;

use B::Deparse;
use Data::Structure::Util 'unbless';
use Scalar::Util qw/blessed reftype/;
use Storable ();

use constant DEBUG => $ENV{MOJO_RECACHE_DEBUG} || 0;

has app => sub { scalar caller }, weak => 1;
has as => undef;
has cachedir => 'cache';
has cron => 0; # MED: Is it possible to detect run by cron?
has expires => 86_400 * 30;
has home => sub { Mojo::Home->new->detect(shift->app) };
has log => sub { Mojo::Log->new };
has minion => undef;
has options => sub {
  my $cron = shift->cron;
  {attempts => 3, delay => $cron ? 0 : 3_600, queue => $cron ? 'cron' : 'recache'}
};

our $VERSION = '0.01';

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);
  # LOW: Do something nice like the above for the $method in app

  $self->enqueue($method => @_);
  my $data = $self->retrieve($self->name($method => @_));
  return $data if $data;
  return $self->store($method => @_);
}

sub enqueue {
  my $self = shift;
  my $minion = $self->minion or return;
  my $name = $self->name(@_);
  $self->enqueued($name) or
    $self->emit(enqueued => $minion->enqueue(recache => [shift() => $name => @_] => $self->options));
  return $name;
}

# HIGH: Doesn't re-enqueue because the job to re-enqueue is still active
sub enqueued {
  my ($self, $name) = (shift, shift);
  my $minion = $self->minion or return;
  my $jobs;
  my $limit = 1;
  do {
    # LOW: Is offset and limit required?
    #      If not, remove the loop.
    $jobs = $minion->backend->list_jobs(0, $minion->backoff->($limit), {tasks => ['recache'], $self->cron ? () : (states => ['active', 'inactive', 'failed'], queues => [$self->options->{queue}])})->{jobs};
  } while ( @$jobs >= $minion->backoff->($limit++) );
  return scalar grep { $_->{args}->[1] eq $name && ($self->cron ? $_->{queue} ne 'recache' : 1) } @$jobs;
}

sub file {
  my $self = shift;
  return $self->home->child($self->cachedir)->make_path->child(shift);
}

sub merge_options {
  my $self = shift;
  $self->options({%{$self->options}, @_});
}

sub name {
  my ($self, $method) = (shift, shift);
  my $deparse = B::Deparse->new("-p", "-sC");
  my $serialized = j([map { ref eq 'CODE' ? $deparse->coderef2text($_) : unbless($_) } $method, @_]);
  my $name = md5_sum(b64_encode($serialized));
  warn sprintf "-- %s => %s (%s)\n", $method, $self->file($name), $serialized if DEBUG;
  return $name;
}

sub retrieve {
  my ($self, $name) = @_;
  my $file = $self->file($name);
  return unless -e $file;
  return if $self->expires && time - $file->stat->mtime > $self->expires;
  my $data;
  eval {
    local $Storable::Eval = 1 || $Storable::Eval;
    $data = Storable::retrieve($file);
  };
  return if $@;
  $self->emit(retrieved => $name);
  return $self->_as($data);
}

sub short { substr($_[1], 0, 6) }

sub start {
  my $self = shift;

  my $minion = $self->minion or return;

  $minion->add_task(recache => sub {
    my ($job, $method, $name) = (shift, shift, shift);
    return $job->finish('Previous job is still active')
      unless my $guard = $minion->guard($name, 7200);
    $self->store($method => @_);
    $self->enqueue($method => @_);
  });

  return $self unless @_;
  Mojolicious::Commands->new(app => $self, namespaces => ['Minion::Command'])->run(@_);

  # LOW: exit with an appropriate exit code
  exit;
}

sub store {
  my ($self, $method) = (shift, shift);
  my $data = $self->app->$method(@_);
  my $name = $self->name($method => @_);
  eval {
    local $Storable::Deparse = 1 || $Storable::Deparse;
    Storable::store(ref $data ? $data : \$data, $self->file($name));
  };
  return if $@;
  $self->emit(stored => $name);
  return $self->_as($data);
}

sub use_options {
  my $self = shift;
  $self->new(options => {%{$self->options}, @_});
}

sub _as {
  my ($self, $data) = @_;
  return ref $data eq 'SCALAR' ? $$data : $data unless $self->as;
  if ( reftype $self->as eq reftype $data ) {
    if ( reftype $data eq 'ARRAY' ) {
      return $self->as->new(@$data);
    } elsif ( reftype $data eq 'HASH' ) {
      return $self->as->new(%$data);
    } elsif ( reftype $data eq 'SCALAR' ) {
      return $self->as->new($$data);
    } else {
      die "Unsupported type";
    }
  }
  die "Type mismatch";
}

sub _isa { blessed $_[0] && $_[0]->isa($_[1]) ? $_[0] : undef }

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

=head1 ATTRIBUTES

L<Mojo::Recache> implements the following attributes.

=head2 app

  my $app = $cache->app;
  $cache  = $cache->app(__PACKAGE__);

Package, class, or object to provide caching for. Note that this attribute is
weakened.

=head2 as

  my $as = $cache->as;
  $cache = $cache->as(sub {...});

Return cached data as an instance of an object.

  $cache->as(sub { Mojo::Collection->new });
  $cache->cacheable_thing->each(sub { say $_ });

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

=head2 home

  my $home = $cache->home;
  $cache   = $cache->home(Mojo::Home->new);

The parent of the directory where cache files are stored. Defaults to the same
location as the main app.

=head2 log

  my $log = $cache->log;
  $cache  = $cache->log(Mojo::Log->new);

L<Mojo::Log> object used for logging.

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
L</"expires"> seconds.

=head2 short

  $short = $cache->short($name);

Return a shortened version of the cache name: the first 6 characters.

=head2 start

  $short = $cache->short($name);

Return a shortened version of the cache name: the first 6 characters.

=head2 store

  $data = $cache->store($sub_name => @args);

Run the specified subroutine from L</"app"> and stores it in L</"file"> after
making sure that the return value is a reference.

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
