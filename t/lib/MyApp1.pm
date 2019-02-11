package MyApp1;
use Mojo::Base -base;

use Mojo::Recache;

has cached  => 0;
has recache => sub {
  Mojo::Recache->new->app(shift)->add_methods([[qw/array array2/] => 'daily']);
};

sub array {
  my $self = shift;
  return [map { $self->cached ? abs($_)*-2 : $_ } @_]
}

sub array2 {
  my $self = shift;
  return [map { $self->cached ? abs($_)*-2 : $_ } @_]
}

1;
