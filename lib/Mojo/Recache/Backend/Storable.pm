package Mojo::Recache::Backend::Storable;
use Mojo::Base 'Mojo::Recache::Backend';

use B::Deparse;
use Storable ();

use constant DEBUG => $ENV{MOJO_RECACHE_DEBUG} || 0;

sub retrieve {
  my ($self, $file) = @_;
  my $cache;
  eval {
    local $Storable::Eval = 1 || $Storable::Eval;
    $cache = Storable::retrieve($file);
  };
  warn $@ if $@ && DEBUG;
  return if $@;
  $self->emit(retrieved => $file);
  return $cache->cached(1);
}

sub store {
  my ($self, $cache) = @_;
  my $file = $cache->file;
  eval {
    local $Storable::Deparse = 1 || $Storable::Deparse;
    my $recache = $cache->recache;
    Storable::store($cache->recache(undef), $file);
    $cache->recache($recache);
  };
  warn $@ if $@ && DEBUG;
  return if $@;
  $self->emit(stored => $cache);
  return $cache->cached(0);
}

1;
