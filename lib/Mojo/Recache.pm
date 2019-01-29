package Mojo::Recache;
use Mojo::Base 'Mojo::EventEmitter';

use Minion;
use Mojo::Home;
use Mojo::JSON 'j';
use Mojo::Util qw/b64_decode b64_encode md5_sum/;
use Mojolicious::Commands;

use B::Deparse;
use Data::Structure::Util 'unbless';
use Scalar::Util qw/blessed reftype/;
use Storable ();

use constant CRON    => $ENV{MOJO_RECACHE_CRON} || 0;
use constant DEBUG   => $ENV{MOJO_RECACHE_DEBUG} || 0;
use constant DELAY   => 60;
use constant EXPIRES => 86_400;
use constant QUEUE   => 'default';
use constant TASK    => 'recache';

has app => sub { scalar caller }, weak => 1;
has cachedir => sub { Mojo::Home->new->detect(shift->app)->child(TASK) };
has delay => 60;
has minion => undef;
has queues => sub {
  {
    once    => 0,
    hourly  => 3_600,
    daily   => 86_400,
    weekly  => 86_400 * 7,
    monthly => 86_400 * 30,
    yearly  => 86_400 * 365,
  }
};
has options => sub { {attempts => 3} };

has _queue => QUEUE;

our $VERSION = '0.01';

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);
  # LOW: Do something nice like the above for the $method in app

  $self->enqueue($method => @_);
  my $data = $self->retrieve([$method => @_]);
  return $data if $data;
  return $self->store($method => @_);
}

sub clone {
  my $self  = shift;
  return $self->SUPER::new({%$self, @_});
}

sub enqueue {
  my $self = shift;
  my $minion = $self->minion or return;
  my $job = shift if ref $_[0];

  return if $self->enqueued([@_]);

  my $options = {
    %{$self->options},
    queue => $self->_queue || QUEUE,
    delay => CRON ? 0 : $self->delay || DELAY,
    map { $_ => $job->info->{$_} } $job ? qw/priority notes attempts parents/ : ()
  };

  return $self->emit(enqueued => $minion->enqueue(TASK, [@_], $options));
}

# HIGH: Doesn't re-enqueue because the job to re-enqueue is still active
sub enqueued {
  my $self = shift;
  my $name = $self->_want_name(@_);
  my $minion = $self->minion or return;
  my $jobs;
  my $limit = 1;
  do {
    # LOW: Is offset and limit required?
    #      If not, remove the loop.
    my $enqueued = {
      tasks => [TASK],
      states => ['active', 'inactive', 'failed'],
      queues => [$self->queue],
    };
    $jobs = $minion->backend->list_jobs(
      0, $minion->backoff->($limit), $enqueued
    )->{jobs};
  } while ( @$jobs >= $minion->backoff->($limit++) );
  return scalar grep { $self->name($_->{args}) eq $name } @$jobs;
}

sub expired {
  my $self = shift;
  my $file = $self->_want_file(@_);
  return 1 if ! -e "$file";
  return $self->expires && time - $file->stat->mtime > $self->expires;
}

sub expires { $_[0]->queues->{$_[0]->_queue} || EXPIRES }

sub file {
  my $self = shift;
  my $name = $self->_want_name(@_);
  return $self->cachedir->child($self->_queue)->make_path->child($name);
}

sub name { md5_sum(b64_encode(shift->serialize(shift))) }

sub queue {
  my ($self, $queue) = @_;
  return $self->_queue unless $queue && $self->queues->{$queue};
  $self->clone(_queue => $queue);
}

sub remove {
  my $self = shift;
  return @_
       ? $self->_want_file(@_)->remove
       : $self->cachedir->child($self->_queue)->remove_tree;
}

sub retrieve {
  my $self = shift;
  my $file = $self->_want_file(@_);
  return if $self->expired($file);
  my ($data, @roles, $name, $method, @args);
  eval {
    local $Storable::Eval = 1 || $Storable::Eval;
    ($data, @roles, $name, $method, @args) = @{Storable::retrieve($file)};
    blessed $data && @roles and $data = $data->with_roles(@roles);
  };
  warn $@ if $@ && DEBUG;
  return if $@;
  $self->emit(retrieved => $name, $method, @args);
  DEBUG and warn sprintf "-- retrieved %s => %s (%s %s) => %s\n",
         $method, $self->file($name),
         $self->expired($name) ? 'expired, >' : 'cached, <',
         $self->expires,
         $self->serialized($method => @args);
  return $data;
}

sub serialize {
  my ($self, $method, @args) = (shift, ref $_[0] ? @{shift()} : @_);

  # If the app has an extra_args attribute, call it so that data can influence
  # the name of the cache file
  my @extra_args = $self->app->can('extra_args')
                 ? $self->app->extra_args->($self->app)
                 : ();

  my $deparse = B::Deparse->new("-p", "-sC");
  return j([
    map {
      ref eq 'CODE' ? $deparse->coderef2text($_) : unbless($_)
    } $method, @args, @extra_args
  ]);
}

sub short { substr($_[1], 0, 6) }

sub start {
  my $self = shift;
  my $minion = $self->minion or return $self;

  # HIGH: Can minion store just the name, and then get everything else it needs from Storable hash?
  $minion->add_task(recache => sub {
    my $job = shift;
    my $name = $self->name(@_);
    $job->info->{name} = $name;
    my $recache = $self->queue($job->info->{queue});
    return $job->finish('Previous job is still active')
      unless my $guard = $minion->guard($name, 7200);
    $recache->store(@_) if $recache->expired($name);
    $recache->enqueue($job, @_);
  });
  return $self unless CRON;

  # To Document:
  # Only retrieve honors "expires" -- retrieve will re-fetch of the content is expired
  # Expires is otherwised only used for setting the delay for non-cron re-freshing
  # If you want a job to run at an exact time, use cron
  # If you only want something to refresh periodically, a worker is great
  # Cron:
  #   env CRON=1 
  #   cron.weekly: ./myapp.pl minion worker -q weekly
  #   cron.monthly: ./myapp.pl minion worker -q monthly
  # Worker:
  #   ./myapp.pl minion worker -q weekly,monthly

  $self->emit('cron');
  Mojolicious::Commands
    ->new(app => $self, namespaces => ['Minion::Command'])
    ->run(@_);

  # LOW: exit with an appropriate exit code
  exit;
}

sub store {
  my $self = shift;
  my $name = $self->name(@_);
  my ($method, @args) = @_;
  my $app = $self->app->can('cached') ? $self->app->cached(1) : $self->app;
  my $data = $app->$method(@args);
  my $store = {
    name => $name,
    method => $method,
    args => [@args],
  };
  eval {
    local $Storable::Deparse = 1 || $Storable::Deparse;
    if ( blessed $data ) {
      my $class = ref $data;
      my ($base_class, $roles) = split /__WITH__/, $class;
      $store->{roles} = [split /__AND__/, $roles];
      my @store;
      if ( reftype $data eq 'ARRAY' ) {
        $store->{data} = $base_class->new(@$data);
      } elsif ( reftype $data eq 'HASH' ) {
        $store->{data} = $base_class->new(%$data);
      } elsif ( reftype $data eq 'SCALAR' ) {
        $store->{data} = $base_class->new($$data);
      } else {
        die "Unsupported type";
      }
    } else {
      $store->{data} = $data;
    }
    Storable::store($store, $self->file($name));
  };
  return if $@;
  $self->emit(stored => $name, $method, @args);
  DEBUG and warn sprintf "-- stored %s => %s (%s %s) => %s\n",
         $method, $self->file($name),
         $self->expired($name) ? 'expired, >' : 'cached, <',
         $self->expires,
         $self->serialized($method => @args);
  return $data;
}

sub touch {
  my $self = shift;
  return @_
       ? $self->_want_file(@_)->touch
       : $self->cachedir->child($self->_queue)->each(sub{$_->touch});
}

sub _want_args { shift->_want(1 => @_) }
sub _want_file { shift->_want(0 => @_) }
sub _want_name { shift->_want(1 => @_) }
sub _want {
  my ($self, $want) = (shift, shift);
  if ( !ref $_[0] ) {
    return $want ? @_ : $self->file(shift);
  } elsif ( ref $_[0] eq 'ARRAY' ) {
    return $want ? $self->name(@{shift()}) : $self->file(@{shift()});
  } elsif ( blessed $_[0] && $_[0]->isa('Mojo::File') ) {
    return $want ? shift->basename : shift;
  }
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
  has cached => 0;
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

L<Mojo::Recache> caches any function from your provided L</"app"> and if there
is an available attribute called "cached" it will set it to true so that
L</"app">'s methods can know that they are being called in a cached context.

=head1 EVENTS

L<Mojo::Recache> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 cron

  $cache->on(cron => sub {
    my ($cache) = @_;
    ...
  });

Emitted after started by cron.

  $cache->on(cron => sub {
    my ($cache) = @_;
    say "Recaching via cron";
  });

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

=head2 retrieved

  $cache->on(retrieved => sub {
    my ($cache, $name) = @_;
    ...
  });

Emitted after retrieving data from a stored cache file.

  $cache->on(retrieved => sub {
    my ($cache, $name) = @_;
    say "Data from $name has been retrieved.";
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

If L</"app"> has a "cached" boolean attribute, L</"store"> will set it to true
just before calling the app method. This is useful for allowing an app method
to handle it's own caching algorithm which is useful for updating the cache
with small incremental fetches from the original source.

If L</"app"> has an "extra_args" callback attribute, L</"name"> will pass the
L</"app"> instance to it in order to grab some extra criteria for computing
the name of the cache file. This is useful for allowing multiple separate
cache files on the same method without having to provide the extra criteria
on every call to the app method.

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

=head2 length

  my $lengths = $cache->lengths;
  $cache      = $cache->lengths({});

XXX

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

=head2 clone

  my $cache = $cache->clone(expires => $seconds);

Clone a L</"cache"> instance.

=head2 enqueue

  my $cache = $cache->enqueue($method => @args);

If L<Minion> is enabled, use L<Minion> to enqueue a new job for task "$method".

=head2 enqueued

  my $bool = $cache->enqueued($name);

If L<Minion> is enabled, check if a task "cache" for the provided cache name is
enqueued.

=head2 expired

  my $bool = $cache->expired($file);

Check if specified cache file is expired or not.

=head2 file

  my $file = $cache->file($name);

Return a L<Mojo::File> object for the specified cache file. The location is a
child of L</"cachedir">, itself a child of L</"home">. The full directory path
is created if it does not already exist.

=head2 length

  my $cache = $cache->length($name);

XXXX

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
