package Mojo::Recache;
use Mojo::Base -strict;

use overload
  '@{}' => sub { ${$_[0]}->cache->data },
  '%{}' => sub { ${$_[0]}->cache->data },
  '${}' => sub { ((caller)[2]) == __LINE__ ? ${$_[0]}->cache->data : $_[0] },# if ((caller)[2]) == __LINE__; ${$_[0]}->cache->data },
  '""'  => sub { ${$_[0]}->cache->data },
  fallback => 1;

use Mojo::Home;
use Mojo::Recache::Cache;
use Mojo::Loader 'load_class';

use Carp 'croak';
use Scalar::Util 'blessed';

use constant BACKEND    => $ENV{BACKEND}            || 'Storable';
use constant CRON       => $ENV{CRON}               || 0;
use constant DEBUG      => $ENV{MOJO_RECACHE_DEBUG} || 0;
use constant RECACHEDIR => $ENV{MOJO_RECACHE_DIR}   || 'recache';

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  $$self->cache(Mojo::Recache::Cache->new(method => $method, args => [@_]));
  $$self->retrieve or $$self->store;
  return $$self;
}

sub DESTROY {
  my $self = shift;
  return unless $$self->refresh eq 'session';
  DEBUG and warn sprintf '-- removing recachedir %s', $$self->recachedir;
}

sub new {
  my $class = shift;
  local %_ = @_%2==0 ? @_ : (app => @_);
  $_{app} ||= scalar caller;
  $_{backend} = $_{backend};
  my $recachedir = Mojo::File->new(delete $_{recachedir} || RECACHEDIR);
  $_{recachedir} = $recachedir->is_abs ? $recachedir : _recachedir($_{app})->child($recachedir);
  my $self = bless \_backend($_{backend})->new(%_), ref $class || $class;
  $self->_add_task;
  return $self;
}

sub _add_task {
  my $self = shift;
  return $self unless my $minion = $$self->minion;
  $minion->add_task(RECACHEDIR => sub {
    my $job = shift;
    $$self->cache(Mojo::Recache::Cache->new(method => shift, args => [@_]));
    $$self->store;
  }) unless grep { $_ eq RECACHEDIR } @{$minion->tasks};
  return $self;
}

sub _backend {
  my $class = 'Mojo::Recache::Backend::' . (shift || BACKEND);
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "$class" missing} if $e;
  return $class;
}

sub _recachedir {
  my $app = shift;
  return unless scalar caller eq __PACKAGE__;
  return $app && blessed $app && $app->can('home')
    ? $app->home
    : Mojo::Home->new->detect($app||scalar caller);
}

1;
