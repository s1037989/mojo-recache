package Mojo::Recache;
use Mojo::Base -base;

use Mojo::DynamicMethods -dispatch;
use Mojo::Home;
use Mojo::Loader 'load_class';
use Mojo::Recache::Cache;
use Mojo::Util;

use Carp;
use Time::Seconds;

use constant BACKEND => $ENV{MOJO_RECACHE_BACKEND} || 'Storable';
use constant DEBUG   => $ENV{MOJO_RECACHE_DEBUG}   || 0;
use constant HOME    => $ENV{MOJO_RECACHE_HOME}    || 'recache';
use constant QUEUE   => $ENV{MOJO_RECACHE_QUEUE}   || 'session';

has app      => sub { scalar caller }, weak => 1;
has 'backend';
has delay    => 60;
has home     => sub { Mojo::Home->new->detect(shift->app)->child(HOME) };
has 'minion';
has queues   => sub {
  {
    daily  => ONE_DAY,
    weekly => ONE_WEEK,
  }
};
has overload => 0;

sub add_methods {
  my $self = shift;
  $self->add_method(@$_ ) for @_;
  return $self;
}

sub add_method {
  my ($self, $method, $queue, $options) = @_;
  for my $method ( ref $method eq 'ARRAY' ? @$method : $method ) {
    my $cb = sub {
      my $self = shift;
      $self->_overload(
        Mojo::Recache::Cache->new(
          args    => [@_],
          cached  => 0,
          method  => $method,
          options => $options,
          queue   => $queue || QUEUE,
          recache => $self,
          roles   => [],
        )->update
      );
    };
    Mojo::DynamicMethods::register 'Mojo::Recache', $self, $method, $cb;
  }
  return $self;
}

sub BUILD_DYNAMIC {
  my ($class, $method, $dyn_methods) = @_;
  return sub {
    my ($self, @args) = @_;
    my $dynamic = $dyn_methods->{$self}{$method};
    return $self->$dynamic(@args) if $dynamic;
    my $package = ref $self;
    Carp::croak qq{Can't locate object method "$method" via package "$package"};
  };
}

sub cache {
  my $self = shift;
  my $file = $self->home->child(@_);
  $self->_overload($self->backend->retrieve($file)->recache($self));
}

sub new {
  my $self = shift->SUPER::new;

  # How to set this as a default in the attribute?
  $self->app(scalar caller);

  my $class = 'Mojo::Recache::Backend::' . (shift || BACKEND);
  my $e     = load_class $class;
  croak ref $e ? $e : qq{Backend "$class" missing} if $e;

  return $self->backend($class->new(@_)->recache($self));
}

sub _overload {
  delete $_[0]->{overload} ? Mojo::Recache::Cache::overload->new($_[1]) : $_[1]
}

1;
