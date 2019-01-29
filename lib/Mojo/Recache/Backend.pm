package Mojo::Recache::Backend;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::Home;

use Carp 'croak';
use Scalar::Util 'blessed';
use Time::Seconds;

use constant CACHEDIR => $ENV{MOJO_RECACHE_PATH}    || 'recache';
use constant DEBUG    => $ENV{MOJO_RECACHE_DEBUG}   || 0;
use constant REFRESH  => $ENV{MOJO_RECACHE_REFRESH} || 'session';
use constant EXPIRES  => $ENV{MOJO_RECACHE_EXPIRES} || undef;

has app        => sub { scalar caller }, weak => 1;
has cache      => undef;
has delay      => 60;
has expires    => sub {
  {
    session => undef,
    once    => 0,
    hourly  => ONE_HOUR,
    daily   => ONE_DAY,
    weekly  => ONE_WEEK,
    monthly => ONE_MONTH,
    yearly  => ONE_YEAR,
  }
};
has minion     => undef, weak => 1;
has options    => sub { {attempts => 3} };
has recachedir => sub { die };
has refresh    => REFRESH;

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  $self->cache->data->$method(@_);
}

sub data { shift->cache->data }

sub DESTORY {
  my $self = shift;
  return unless $self->refresh eq 'session';
  DEBUG and warn sprintf '-- removing cache %s', $self->file;
}

sub enqueue {
}

sub enqueued {
}

sub expired {
  my $self = shift;
  my $expires = $self->expires->{$self->refresh || REFRESH} || EXPIRES;
  return 1 if ! -e $self->file->to_string;
  return $expires && time - $self->file->stat->mtime > $expires;
}

sub file {
  my $self = shift;
  $self->recachedir->make_path->child($self->cache->name);
}

sub remove { shift->file->remove }

sub retrieve { croak 'Method "retrieve" not implemented by subclass' }

sub store { croak 'Method "store" not implemented by subclass' }

sub touch { shift->file->touch }

1;
