package Mojo::Recache::Cache;
use Mojo::Base -base;

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
  return $self;
}

sub reftype { Scalar::Util::reftype(shift->data) }

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

sub restore_roles {
  my $self = shift;
  return $self unless blessed $self->data && @{$self->roles};
  $self->data->with_roles(@{$self->roles}) if $self->data->can('with_roles');
  return $self;
}

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

1;
