package Mojo::Recache::Cache;
use Mojo::Base -base;

use Mojo::JSON 'j';
use Mojo::Util qw(b64_encode md5_sum);

use Data::Structure::Util 'unbless';
use Scalar::Util 'blessed';

has [qw(args cached data method options queue recache roles)];

sub app { shift->recache->app }

sub enqueue {}

sub enqueued {}

sub expire { shift->remove }

sub expired { shift->expires < time }

sub expires {
  my $self = shift;
  return 0 unless -e $self->file;
  my $mtime = $self->file->stat->mtime;
  my $ttl = $self->recache->queues->{$self->queue} || 0;
  return $mtime + $ttl;
}

sub file {
  my $self = shift;
  $self->recache->home->child($self->queue)->make_path->child($self->name);
}

sub name { md5_sum(b64_encode(shift->serialize)) }

sub remove { $_[0]->recache->backend->remove($_[0]->file) }

sub retrieve {
  my $self = shift;
  return if $self->expired;
  return $self->cache(1) if $self->data;
  my $cache = $self->recache->backend->retrieve($self->file) or return;
  $cache->recache($self->recache)->restore_roles;
  return $cache;
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
    } $self->method, $self->args, ref $self->recache->app, $self->queue, $self->options
  ]);
}

sub short { substr(shift->name, 0, 6) }

sub store {
  my $self = shift;
  my $app    = $self->app;
  my $method = $self->method;
  $app->cached(1) if blessed $app && $app->can('cached');
  if ( blessed $app ) {
    $self->data($app->$method(@{$self->args}));
  } else {
    my $code = \&{$app.'::'.$method};
    $self->data($code->(@{$self->args}));
  }
  $app->cached(0) if blessed $app && $app->can('cached');
  my $cache = $self->recache->backend->store($self->remove_roles) or return;
  $cache->recache($self->recache)->restore_roles;
  return $cache;
}

sub touch { $_[0]->recache->backend->touch($_[0]->file) }

sub update {
  my ($self, $force) = @_;
  return $self->store if $force;
  $self->retrieve or $self->store;
}

package Mojo::Recache::Cache::overload;
use Mojo::Base 'Mojo::Recache::Cache';
use overload
  '@{}'    => sub { ${$_[0]}->data || [] },
  '%{}'    => sub { ${$_[0]}->data || {} },
  bool     => sub {1},
  '""'     => sub { ${$_[0]}->data || "" },
  fallback => 1;

sub new { bless \$_[1], $_[0] }

1;

=encoding utf8

=head1 NAME

Mojo::Recache::Backend - Backend base class

=head1 SYNOPSIS

  package Mojo::Recache::Backend::MyBackend;
  use Mojo::Base 'Mojo::Recache::Backend';

  sub broadcast         {...}
  sub dequeue           {...}

=head1 DESCRIPTION

L<Mojo::Recache::Backend> is an abstract base class for L<Mojo::Recache> backends, like
L<Mojo::Recache::Backend::Pg>.

=head1 ATTRIBUTES

L<Mojo::Recache::Backend> implements the following attributes.

=head2 args

  my $args = $cache->args;
  $cache   = $cache->args([]);

=head2 cached

=head2 data

=head2 method

=head2 options

=head2 queue

=head2 recache

=head2 roles

=head1 METHODS

L<Mojo::Recache::Backend> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 app

  my $app = $cache->app;

Alias for L</"recache">C<->>L<Mojo::Recache/"app">.

=head2 expire

=head2 expired

=head2 expires

=head2 file

=head2 name

=head2 remove

=head2 retrieve

=head2 reftype

=head2 remove_roles

=head2 restore_roles

=head2 serialize

=head2 short

=head2 store

=head2 touch

=head2 update

=head1 OPERATORS

The constructor for L<Mojo::Recache::Cache::overload> returns a blessed
reference to the L<Mojo::Recache::Cache> object and overloads the following
operators.

=head2 array

  my @data = @$cache;

Alias for L</"data">.

=head2 bool

  my $bool = !!$cache;

Always true.

=head2 hash

  my %data = %$cache;

Alias for L</"data">.

=head2 stringify

  my $data = "$cache";

Alias for L</"data">.

=head1 SEE ALSO

L<Mojo::Recache>

=cut