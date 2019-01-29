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
  $self->enqueue;
  my $app = $self->app->can('cached') ? $self->app->cached(1) : $self->app;
  my $method = $self->cache->method;
  $self->cache->data($app->$method(@{$self->cache->args}))->remove_roles;
  eval {
    local $Storable::Deparse = 1 || $Storable::Deparse;
    Storable::store($self->cache, $self->file);
    $self->cache->cached(0)->restore_roles;
  };
  warn $@ if $@ && DEBUG;
  return if $@;
  $self->emit('stored');
  return $self;
}

1;
