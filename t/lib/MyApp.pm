package MyApp;
use Mojo::Base -base;

has cached => 0;
has cache => sub { [qw/array slow/] };
has recache => sub { Mojo::Recache->new(app => shift) };

sub new {
  my $self = shift->SUPER::new(@_);
  return $self unless $self->recache;
  $self->recache->cache_this($_) for @{$self->cache};
  return $self;
}

sub array { shift; [@_] }
sub slow { warn 'SLOW: '.$_[0]->cached; sleep @_>1 ? pop : 1 }

1;
