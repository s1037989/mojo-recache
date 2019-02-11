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

=encoding utf8

=head1 NAME

Mojo::Recache::Backend::Storable - Storable backend

=head1 SYNOPSIS

  use Mojo::Recache::Backend::Storable;

  my $backend = Mojo::Recache::Backend::Storable->new;

=head1 DESCRIPTION

L<Mojo::Recache::Backend::Storable> is a backend for L<Mojo::Recache> based on
L<Storable>.

=head1 ATTRIBUTES

L<Mojo::Recache::Backend::Storable> inherits all attributes from
L<Mojo::Recache::Backend>.

=head1 METHODS

L<Mojo::Recache::Backend::Storable> inherits all methods from
L<Mojo::Recache::Backend> and implements the following new ones.

=head2 retrieve

  my $cache = $backend->retrieve(Mojo::File->new);

Retrieve a persistent L<Mojo::Recache::Cache> object. Meant to be overloaded
in a subclass.

=head2 store

  my $cache = $backend->store(Mojo::Recache::Cache->new);

Store a persistent L<Mojo::Recache::Cache> object. Meant to be overloaded
in a subclass.

=head1 SEE ALSO

L<Mojo::Recache>

=cut