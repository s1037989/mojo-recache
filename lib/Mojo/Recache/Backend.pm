package Mojo::Recache::Backend;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';

has 'recache' => sub { die }, weak => 1;

sub retrieve { croak 'Method "retrieve" not implemented by subclass' }

sub store    { croak 'Method "store" not implemented by subclass' }

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

=head1 ATTRIBUTES

L<Mojo::Recache::Backend> implements the following attributes.

=head2 recache

  my $recache = $backend->recache;
  $backend    = $backend->recache(Mojo::Recache->new);

L<Mojo::Recache> object this backend belongs to. Note that this attribute is
weakened.

=head1 METHODS

L<Mojo::Recache::Backend> inherits all methods from L<Mojo::Base> and
implements the following new ones.

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