package Mojo::Recache;
use Mojo::Base -strict;

use overload
  '@{}'    => sub { ${$_[0]}->cache ? ${$_[0]}->cache->data : [] },
  '%{}'    => sub { ${$_[0]}->cache ? ${$_[0]}->cache->data : {} },
  #'${}'    => sub { ((caller)[2]) == __LINE__ ? ${$_[0]}->cache->data : $_[0] },# if ((caller)[2]) == __LINE__; ${$_[0]}->cache->data },
  bool     => sub {1},
  '""'     => sub { ${$_[0]}->cache ? ${$_[0]}->cache->data : '' },
  fallback => 1;

use Mojo::Home;
use Mojo::Recache::Cache;
use Mojo::Loader 'load_class';

use Carp 'croak';
use Scalar::Util 'blessed';

use constant BACKEND    => $ENV{MOJO_RECACHE_BACKEND} || 'Storable';
use constant CRON       => $ENV{CRON}                 || 0;
use constant DEBUG      => $ENV{MOJO_RECACHE_DEBUG}   || 0;
use constant RECACHEDIR => $ENV{MOJO_RECACHE_DIR}     || 'recache';

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  $$self->cache(Mojo::Recache::Cache->new(method => $method, args => [@_]));
  $$self->retrieve or $$self->store;
  return $$self;
}

sub DESTROY {
  my $self = shift;
  return unless ref $$self && $$self->refresh eq 'session';
  DEBUG and warn sprintf '-- removing recachedir %s', $$self->recachedir;
}

sub new {
  my $class = shift;
  local %_ = @_%2==0 ? @_ : (app => @_);
  $_{app} ||= scalar caller;
  $_{backend} = $_{backend};
  my $recachedir = Mojo::File->new(delete $_{recachedir} || RECACHEDIR);
  $_{recachedir} = $recachedir->is_abs ? $recachedir : _recachedir($_{app})->child($recachedir);
  my $self = bless \_backend($_{backend})->new(%_), ref $class || $class;
  $self->_add_task;
  return $self;
}

sub _add_task {
  my $self = shift;
  return $self unless my $minion = $$self->minion;
  $minion->add_task(RECACHEDIR => sub {
    my $job = shift;
    $$self->cache(Mojo::Recache::Cache->new(method => shift, args => [@_]));
    $$self->store;
  }) unless grep { $_ eq RECACHEDIR } @{$minion->tasks};
  return $self;
}

sub _backend {
  my $class = 'Mojo::Recache::Backend::' . (shift || BACKEND);
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "$class" missing} if $e;
  return $class;
}

sub _recachedir {
  my $app = shift;
  return unless scalar caller eq __PACKAGE__;
  return $app && blessed $app && $app->can('home')
    ? $app->home
    : Mojo::Home->new->detect($app||scalar caller);
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

=head1 METHODS

L<Mojo::Recache> implements the following methods.

=head2 AUTOLOAD

  package main;
  sub cacheable_thing { sleep 5; return time; }
  my $cache = Mojo::Recache->new;
  warn $cache->cacheable_thing;

Cache the return value from the L</"app">'s subroutine. Return cached data
without refreshing if the cache exists and has not expired. Enqueue a
refreshing job if L<Minion> is enabled.

=head2 DESTROY

When this L<Mojo::Recache> instance goes out of scope and the value of
L<Mojo::Recache::Backend/"refresh"> is "session", remove the "session"
L<Mojo::Recache::Backend/"recachedir">.

=head2 new

  package main;
  sub cacheable_thing { sleep 5; return time; }
  my $cache = Mojo::Recache->new;
  warn $cache->cacheable_thing;

Cache the return value from the L</"app">'s subroutine. Return cached data
without refreshing if the cache exists and has not expired. Enqueue a
refreshing job if L<Minion> is enabled.

=head1 OPERATORS

=head2 array

  my @data = @$recache;

Alias for L<Mojo::Recache::Cache/"data">.

  # 1
  $recache->cache->data([1..2])->[0];

=head2 bool

  my $bool = !!$recache;

Always true.

=head2 hash

  my %data = %$recache;

Alias for L<Mojo::Recache::Cache/"data">.

  # 1
  $recache->cache->data({id => 1})->{id};

=head2 stringify

  my $str = "$recache";

Alias for L<Mojo::Recache::Cache/"data">.

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