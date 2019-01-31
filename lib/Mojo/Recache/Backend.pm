package Mojo::Recache::Backend;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::Home;
use Mojo::Recache::Cache;

use Carp 'croak';
use Scalar::Util 'blessed';
use Time::Seconds;

use constant DEBUG    => $ENV{MOJO_RECACHE_DEBUG}   || 0;
use constant REFRESH  => $ENV{MOJO_RECACHE_REFRESH} || 'session';
use constant EXPIRES  => $ENV{MOJO_RECACHE_EXPIRES} || undef;

# This attribute exists solely for the purpose of Mojo::Recache
has app        => sub { scalar caller }, weak => 1;

has cache      => sub { die };
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

sub expire { shift->remove }

sub expired {
  my $self = shift;
  return 1 if ! -e $self->file->to_string;
  my $expires = $self->expires->{$self->refresh || REFRESH} || EXPIRES;
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
