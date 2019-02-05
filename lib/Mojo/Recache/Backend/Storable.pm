package Mojo::Recache::Backend::Storable;
use Mojo::Base 'Mojo::Recache::Backend';

use Storable ();

use constant DEBUG => $ENV{MOJO_RECACHE_DEBUG} || 0;

sub retrieve {
  my $self = shift;
  return if $self->expired;
  return $self->data if $self->data;
  eval {
    local $Storable::Eval = 1 || $Storable::Eval;
    $self->cache(Storable::retrieve($self->file));
    $self->cache->cached(1)->restore_roles;
  };
  warn $@ if $@ && DEBUG;
  return if $@;
  $self->emit('retrieved');
  return $self;
}

sub store {
  my $self = shift;
  return $self unless defined $self->app;
  $self->cache_method;
  eval {
    local $Storable::Deparse = 1 || $Storable::Deparse;
    Storable::store($self->cache, $self->file);
    $self->cache->cached(0)->restore_roles;
  };
  warn $@ if $@ && DEBUG;
  return if $@;
  $self->emit('stored');
  $self->enqueue;
  return $self;
}

1;

=encoding utf8

=head1 NAME 

Mojo::Recache::Backend::Storable - Storable backend

=head1 SYNOPSIS

  use Mojo::Recache::Backend::Storable;

  my $backend = Mojo::Recache::Backend::Storable->new;
  $backend->cache(Mojo::Recache::Cache->new(method => 'method'));
  $backend->retrieve or $backend->store;
  say $backend->cache->data;

=head1 DESCRIPTION

L<Mojo::Recache::Backend::Storable> is a backend for L<Mojo::Recache> based on
L<Storable>.

=head1 EVENTS

L<Mojo::Recache> inherits all events from L<Mojo::Recache::Backend> and can emit the
following new ones.

=head2 retreived

  $recache->on(retreived => sub {
    my $recache = shift;
    my $cache = $recache->cache;
    ...
  });

Emitted after retrieving data from a stored cache file.

  $recache->on(retreived => sub {
    my $recache = shift;
    my $cache = $recache->cache;
    printf 'Data from %s has been retreived.', $cache->name;
  });

=head2 stored

  $cache->on(stored => sub {
    my $recache = shift;
    my $cache = $recache->cache;
    ...
  });

Emitted after executing the named subroutine from L</"app"> and storing in a
local cache file.

  $cache->on(stored => sub {
    my $recache = shift;
    my $cache = $recache->cache;
    printf 'Data for %s has been stored.', $cache->name;
  });

=head1 ENVIRONMENT

The behavior of L<Mojo::Recache::Backend::Storable> can be controlled through
the use of the following environment variables.

=head2 MOJO_RECACHE_DEBUG

Write warnings to STDERR when true. Defaults to false.

=head1 ATTRIBUTES

L<Mojo::Recache::Backend::Storable> inherits all attributes from
L<Mojo::Recache::Backend>.

=head1 METHODS

L<Mojo::Recache::Backend::Storable> inherits all methods from
L<Mojo::Recache::Backend> and implements the following new ones.

=head2 retrieve

  $backend = $backend->retrieve;

Return the data from a cache file if it exists and is not expired according to
L<Mojo::Recache::Backend/"expires">.

Set the L<Mojo::Recache::Cache/"cached"> attribute to true to indicate that
this L<Mojo::Recache::Cache/"data"> is cached.

=head2 store

  $backend = $backend->store;

Provide persistence for the Perl data structure returned by the specified
L<Mojo::Recache::Backend/"app"> class method.

If available, set the app's "cached" attribute to true, allowing the method
to have knowledge regarding the context in which it is called.

Set the L<Mojo::Recache::Cache/"cached"> attribute to false to indicate that
this L<Mojo::Recache::Cache/"data"> is not cached.

  $backend = $backend->store;
  say "This data is cached" if $backend->cache->cached;

=head1 DEPENDENCIES

L<Mojolicious>, L<Storable>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Stefan Adams and others.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/s1037989/mojo-recache>

=cut