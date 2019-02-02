package Mojo::Recache::Cache;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::JSON 'j';
use Mojo::Util qw(b64_encode md5_sum);

use B::Deparse;
use Data::Structure::Util 'unbless';
use Scalar::Util 'blessed';

use constant DEBUG => $ENV{MOJO_RECACHE_DEBUG} || 0;

has args    => sub { [] };
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
  $self->emit('new');
  return $self;
}

sub reftype { Scalar::Util::reftype(shift->data) }

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

sub restore_roles {
  my $self = shift;
  return $self unless blessed $self->data && @{$self->roles};
  $self->data->with_roles(@{$self->roles}) if $self->data->can('with_roles');
  return $self;
}

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

1;

=encoding utf8

=head1 NAME 

Mojo::Recache::Cache - Object class for cached instances

=head1 SYNOPSIS

  my $cache = Mojo::Recache::Cache->new(method => 'cacheable_thing');
  warn $cache->name;

=head1 DESCRIPTION

L<Mojo::Recache::Cache> provides caching and automatic refreshing for your app. It

=head1 EVENTS

L<Mojo::Recache> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 new

  $cache->on(new => sub {
    my $cache = shift;
    ...
  });

Emitted after a new cache instance and its attributes is created.

  $cache->on(new => sub {
    my $name = shift->name;
    say "Cache $name has been created.";
  });

=head1 ENVIRONMENT

The behavior of L<Mojo::Recache::Backend::Storable> can be controlled through
the use of the following environment variables.

=head2 MOJO_RECACHE_DEBUG

Write warnings to STDERR when true. Defaults to false.

=head1 ATTRIBUTES

L<Mojo::Recache::Cache> inherits the attributes from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 args

  my $app = $cache->app;
  $cache  = $cache->app(__PACKAGE__);

Package, class, or object to provide caching for. Note that this attribute is
weakened.

=head2 cached

  my $cached = $cache->cached;
  $cache     = $cache->cached($bool);

Child directory of L</"home"> where cache files are stored and retrieved.
Defaults to 'cache'.

=head2 data

  my $data = $cache->data;
  $cache   = $cache->data($data);

Instead of refreshing caches with a L<Minion> worker, use cron.

=head2 method

  my $method = $cache->method;
  $cache     = $cache->method($string);

When to consider a cachefile to be too old and force refreshing. Defaults to 30
days.

=head2 name

  my $name = $cache->name;
  $cache   = $cache->name($string);

The name of the cache instance. Defaults to the L<Mojo::Util/"md5_sum"> of the
L<Mojo::Util/"b64_encode"> of L</"serialize">.

=head2 options

  my $options = $cache->options;
  $cache      = $cache->options($array);

Extra arguments for L</"serialize"> to generate a random name.

=head2 roles

  my $roles = $cache->roles;
  $cache    = $cache->roles($array);

The roles that should be applied to the data for this cache when retrieved.

Roles cannot be stored in the default L<Mojo::Recache::Backend::Storable> cache
and therefore must be removed.

=head1 METHODS

=head2 new

  package main;
  sub cacheable_thing { sleep 5; return time; }
  my $cache = Mojo::Recache->new;
  warn $cache->cacheable_thing;

Cache the return value from the L</"app">'s subroutine. Return cached data
without refreshing if the cache exists and has not expired. Enqueue a
refreshing job if L<Minion> is enabled.

=head2 reftype

  my $cache = $cache->enqueue($method => @args);

If L<Minion> is enabled, use L<Minion> to enqueue a new job for task "$method".

=head2 short

  my $file = $cache->file($name);

Return a L<Mojo::File> object for the specified cache file. The location is a
child of L</"cachedir">, itself a child of L</"home">. The full directory path
is created if it does not already exist.

=head2 remove_roles

  my $name = $cache->name($sub_name => @args);

Generate a unique name for a cache using all of the specified arguments as
factors.

=head2 restore_roles

  $cache = $cache->set_options(option => 'value');
  $cache = $cache->set_options(queue => 'monthly', delay => 0);

Merge the specified arguments into </"options">.

=head2 serialize

  my $bool = $cache->enqueued($name);

If L<Minion> is enabled, check if a task "cache" for the provided cache name is
enqueued.

=head2 short

  $short = $cache->short($name);

Return a shortened version of the cache name: the first 6 characters.

=head1 DEPENDENCIES

L<Mojolicious>, L<B::Deparse>, L<Data::Structure::Util>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/s1037989/mojo-recache>

=cut