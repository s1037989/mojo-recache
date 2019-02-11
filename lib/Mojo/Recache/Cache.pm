package Mojo::Recache::Cache;
use Mojo::Base -base;

use Mojo::JSON 'j';
use Mojo::Util qw(b64_encode md5_sum);

use Data::Structure::Util 'unbless';
use Scalar::Util 'blessed';

has [qw(args cached data method options queue recache roles)];

sub update {
  my ($self, $force) = @_;
  return $self->store if $force;
  $self->retrieve or $self->store;
}

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
